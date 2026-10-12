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
import { computeMbps } from './Diagnostics';

/** Wall-clock budget for the whole download. */
export const SPEED_TIMEOUT_MS: number = 30000;

/** Outcome of one throughput attempt. */
export interface SpeedResult {
  ok: boolean;
  /** Bytes actually received. */
  bytes: number;
  /** Wall-clock milliseconds for the whole request. */
  elapsedMs: number;
  /** Megabits per second over the transfer window; 0 unless `ok`. */
  mbps: number;
  /** Human-readable failure text, '' when ok. */
  reason: string;
}

/**
 * Downloads `url` and reports the throughput it achieved.
 *
 * `requestInStream` resolves only once the body has been fully delivered, so it
 * doubles as the completion signal and no `dataEnd` handler is needed — one
 * less listener to unhook, and no ordering hazard between the two. Bytes are
 * counted as they arrive via `dataReceive`.
 *
 * The rate is measured from the **first byte** to completion rather than from
 * the request start, so TLS setup and the server's think time do not deflate
 * the number; the full wall clock is still reported as `elapsedMs`. A watchdog
 * destroys the request on expiry, which is the only way to abort one in flight.
 *
 * This promise always resolves — failures come back as `ok: false` with a
 * `reason` — so callers need only a single path.
 */
export function measureThroughput(url: string, timeoutMs: number): Promise<SpeedResult> {
  return new Promise<SpeedResult>((resolve: (result: SpeedResult) => void) => {
    const request = http.createHttp();
    const started = Date.now();
    let firstByteAt = 0;
    let received = 0;
    let settled = false;
    let watchdog = -1;

    const onData = (chunk: ArrayBuffer): void => {
      received += chunk.byteLength;
      if (firstByteAt === 0) {
        firstByteAt = Date.now();
      }
    };

    // Idempotent: whichever of the stream promise, the watchdog or a rejection
    // gets here first owns the outcome, and the rest are dropped.
    const finish = (result: SpeedResult): void => {
      if (settled) {
        return;
      }
      settled = true;
      if (watchdog >= 0) {
        clearTimeout(watchdog);
      }
      try {
        request.off('dataReceive', onData);
      } catch (e) {
        // never attached
      }
      request.destroy();
      resolve(result);
    };

    // Registered before the request starts: a fast server can deliver its first
    // chunk before a later on() would have attached.
    request.on('dataReceive', onData);
    watchdog = setTimeout(() => {
      const timedOut: SpeedResult = {
        ok: false, bytes: received, elapsedMs: Date.now() - started, mbps: 0,
        reason: `timed out after ${timeoutMs} ms`,
      };
      finish(timedOut);
    }, timeoutMs);

    const stream: Promise<number> = request.requestInStream(url, {
      method: http.RequestMethod.GET,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      usingCache: false,
    });
    stream.then((code: number) => {
      const endAt = Date.now();
      const windowMs = firstByteAt > 0 ? (endAt - firstByteAt) : (endAt - started);
      if (code < 200 || code >= 300) {
        const bad: SpeedResult = {
          ok: false, bytes: received, elapsedMs: endAt - started, mbps: 0, reason: `HTTP ${code}`,
        };
        finish(bad);
        return;
      }
      const result: SpeedResult = {
        ok: received > 0,
        bytes: received,
        elapsedMs: endAt - started,
        mbps: computeMbps(received, windowMs),
        reason: received > 0 ? '' : 'no data received',
      };
      finish(result);
    }).catch((e: BusinessError) => {
      // reaches here when the watchdog destroyed the request mid-flight, in
      // which case finish() has already settled and this is ignored
      const message: string = (e as BusinessError).message ?? 'request failed';
      const failed: SpeedResult = {
        ok: false, bytes: received, elapsedMs: Date.now() - started, mbps: 0, reason: message,
      };
      finish(failed);
    });
  });
}
