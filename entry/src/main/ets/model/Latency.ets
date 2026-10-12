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

import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LatencyEntry } from './Diagnostics';

/** Connect budget for one latency measurement. */
export const LATENCY_TIMEOUT_MS: number = 5000;

/**
 * Times a TCP connect to a profile's server, the same measurement
 * shadowsocks-android shows per profile.
 *
 * **Closing a `TCPSocket` whose `connect()` is still in flight kills the test
 * process outright, with no error** (AGENTS.md, and docs/hos-emulator-vpn.md
 * §2a). The rules that keep this safe, and that must not be "simplified":
 *
 *  1. `TCPConnectOptions.timeout` is the *only* timeout. Never race a
 *     `setTimeout` against the connect and close the socket from the timer —
 *     that hand-rolled race is exactly the crash above.
 *  2. `close()` is reached only after `await connect(...)` has settled, on both
 *     the success and the failure path, and never before.
 *  3. Each measurement uses a fresh socket; instances are not pooled.
 *
 * On when to call it: with the tunnel up and a default route, the UI process's
 * own traffic traverses the tun, so a connect here measures a round trip
 * *through the tunnel* rather than the server's own latency, and under some
 * routes it will simply fail. Treat the number as meaningful only while
 * disconnected. With a SIP003 plugin the connect also times the obfuscation
 * front rather than the shadowsocks handshake — inherent to a TCP-connect ping.
 */
export async function measureLatency(host: string, port: number,
  timeoutMs: number): Promise<LatencyEntry> {
  if (host.length === 0 || port <= 0) {
    const missing: LatencyEntry = { ok: false, ms: 0, detail: 'no server' };
    return missing;
  }

  const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
  const started = Date.now();

  try {
    // rule 1: the transport's own timeout, nothing hand-rolled
    await tcp.connect({
      address: { address: host, port: port, family: 1 },
      timeout: timeoutMs,
    });
  } catch (e) {
    // rule 2: connect() has settled, so closing is safe. A socket that never
    // bound may still reject close(), and that must not escape this function.
    try {
      await tcp.close();
    } catch (closeError) {
      // already gone
    }
    const failed: LatencyEntry = {
      ok: false, ms: 0, detail: (e as BusinessError).message ?? 'connect failed',
    };
    return failed;
  }

  // rule 2: reached only once connect() resolved
  const ms = Date.now() - started;
  try {
    await tcp.close();
  } catch (closeError) {
    // already closed
  }
  const entry: LatencyEntry = { ok: true, ms: ms, detail: '' };
  return entry;
}
