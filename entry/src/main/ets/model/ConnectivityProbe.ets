/*******************************************************************************
 *                                                                             *
 *  Copyright (C) 2026 by Max Lv <max.c.lv@gmail.com>                          *
 *                                                                             *
 *  This program is free software: you can redistribute it and/or modify       *
 *  it under the terms of the GNU General Public License as published by       *
 *  the Free Software Foundation, either version 3 of the License, or          *
 *  (at your option) any later version.                                        *
 *                                                                             *
 *  This program is distributed in the hope that it will be useful,            *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 *  GNU General Public License for more details.                               *
 *                                                                             *
 *  You should have received a copy of the GNU General Public License          *
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.       *
 *                                                                             *
 *******************************************************************************/

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** Wall-clock budget for one probe. */
export const PROBE_TIMEOUT_MS: number = 8000;

/** What one probe attempt observed, before any interpretation. */
export interface ProbeOutcome {
  /** The transport succeeded and the server answered 2xx. */
  ok: boolean;
  /** HTTP status, 0 when no response arrived. */
  httpCode: number;
  /** Wall-clock milliseconds for the request; 0 when it failed. */
  rttMs: number;
  /** Human-readable failure text, '' when ok. */
  reason: string;
}

/**
 * Issues one GET through whatever path the device currently uses, and reports
 * what came back. It does **not** decide whether that proves the tunnel works —
 * that is Diagnostics.interpretProbe, which also weighs the core's byte
 * counters, because this function cannot tell a tunnelled fetch from a direct
 * one.
 *
 * `request()` rather than `requestInStream`: the response is an empty 204, so
 * there is nothing to stream and the streaming API would add event-handler
 * lifecycle for no benefit. The timeout is enforced twice — once by the
 * transport's own connect/read timeouts, once by a watchdog that rejects the
 * race — because a stalled DNS lookup can defeat the transport timeouts and
 * leave the UI waiting forever.
 */
export async function probeThroughTunnel(url: string, timeoutMs: number): Promise<ProbeOutcome> {
  const request = http.createHttp();
  const started = Date.now();
  let watchdog = -1;
  const headers: Record<string, string> = { 'Cache-Control': 'no-cache' };
  try {
    const call: Promise<http.HttpResponse> = request.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      usingCache: false,
      // The system proxy is used by default, and a device with one configured
      // (a Wi-Fi network set to a manual proxy, say) would then have every
      // probe answered — or, as observed, hung — by that proxy rather than by
      // the tunnel this is meant to measure. A connectivity test has to
      // describe the device's own path, so opt out.
      usingProxy: false,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
    });
    // The watchdog can win the race, leaving `call` to settle afterwards; this
    // handler keeps that late rejection from surfacing as unhandled.
    call.catch((e: BusinessError) => {
      return;
    });

    const timeout: Promise<http.HttpResponse> = new Promise<http.HttpResponse>(
      (resolve: (value: http.HttpResponse) => void, reject: (e: Error) => void) => {
        watchdog = setTimeout(() => {
          reject(new Error(`probe timed out after ${timeoutMs} ms`));
        }, timeoutMs);
      });

    const response: http.HttpResponse = await Promise.race([call, timeout]);
    const rttMs = Date.now() - started;
    const code = response.responseCode;
    if (code >= 200 && code < 300) {
      const ok: ProbeOutcome = { ok: true, httpCode: code, rttMs: rttMs, reason: '' };
      return ok;
    }
    const failed: ProbeOutcome = {
      ok: false, httpCode: code, rttMs: rttMs, reason: `HTTP ${code}`,
    };
    return failed;
  } catch (e) {
    const message: string = (e as BusinessError).message ?? JSON.stringify(e);
    const failed: ProbeOutcome = { ok: false, httpCode: 0, rttMs: 0, reason: message };
    return failed;
  } finally {
    if (watchdog >= 0) {
      clearTimeout(watchdog);
    }
    // every createHttp() must be paired with destroy(), per the d.ts
    request.destroy();
  }
}
