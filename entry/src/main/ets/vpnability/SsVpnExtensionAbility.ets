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

import { VpnExtensionAbility, vpnExtension, socket } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import sslocal from 'libsslocal.so';
import { ProfileStore } from '../model/ProfileStore';
import { aclFileForRoute, ROUTE_ALL } from '../model/Routes';
import { TrafficStatsStore } from '../model/TrafficStats';
import { VpnStatusStore } from '../model/VpnStatus';

const TAG = 'SsVpnExtension';

const TUN_ADDRESS = '172.19.0.1';
/**
 * Tun prefix length. Together with TUN_ADDRESS this is handed to the core as
 * `tun_interface_address`, so the two must stay the same values the system VPN
 * is configured with below.
 */
const TUN_PREFIX_LENGTH = 30;
/**
 * Tun MTU.
 *
 * Deliberately below the 1500 of the underlying path. Every byte the client
 * sends is wrapped in a shadowsocks frame — salt, length and AEAD tags, call it
 * 50 bytes — and then in the tunnel's own IP and TCP headers, so a 1500-byte
 * client packet leaves as roughly 1550 and is dropped by the network. The
 * symptom is distinctive and easy to misread: handshakes and small responses
 * get through, so a connectivity check passes, while anything that moves real
 * data — a web page, a speed test — stalls with the core retransmitting frames
 * the client never acknowledged.
 *
 * The core's own smoltcp stack is fixed at 1500 and is not configurable from
 * here, but that is fine: TCP takes the smaller of the two MSS values, so
 * advertising 1360 to the client keeps both directions inside the path MTU.
 */
const TUN_MTU = 1400;

/** Loopback ports probed (in order) for the traffic-stat report endpoint. */
const STAT_PORTS: number[] = [65080, 65081, 65082, 65083, 65084];
/** Stat samples reach us every ~500 ms; persist at most one per second. */
const STAT_SAVE_INTERVAL_MS = 1000;
/** How long after a successful start to check the core is still alive. */
const CORE_LIVENESS_DELAY_MS = 3000;

/**
 * VPN extension ability that establishes the system VPN interface and routes
 * every packet through the embedded sslocal core in tun mode.
 *
 * The system hands us an already-configured tun file descriptor from
 * `VpnConnection.create()`; we pass it straight to the native core
 * (`sslocal.startTunFd`, built with the `local-tun` feature). The core's tun
 * stack (smoltcp) terminates TCP/UDP from the tun and re-establishes each flow
 * through the shadowsocks tunnel — the same role tun2socks plays in the
 * Android client.
 *
 * Policy routes: when the active profile's route is not `all`, the matching
 * ACL file (shipped as a rawfile resource, mirroring shadowsocks-android's
 * assets/acl) is deployed to the app files dir and injected into the core
 * config; the core then connects matching destinations directly instead of
 * through the tunnel.
 *
 * Traffic stats: the core (built with `local-flow-stat`) connects to a
 * loopback TCP endpoint every 500 ms and writes 16 bytes — two little-endian
 * u64 cumulative counters (tx, rx), the same wire format shadowsocks-android's
 * TrafficMonitor consumes. We host that endpoint and persist the latest
 * sample via TrafficStatsStore for the UI process to poll.
 *
 * The default route below sends all traffic into the tun, so the core's own
 * connections to the shadowsocks server must stay outside the tunnel or the
 * tunnel loops on itself. `VpnConnection.protectProcessNet()` (API 22+) marks
 * every socket this process creates afterwards as protected; since the native
 * core runs in this same process, its server connections bypass the VPN. On
 * older runtimes the API is absent — we log a warning and the tunnel will
 * loop unless the server is reachable through a more specific route.
 */
export default class SsVpnExtensionAbility extends VpnExtensionAbility {
  private connection: vpnExtension.VpnConnection | null = null;
  private statServer: socket.TCPSocketServer | null = null;
  private statConnections: socket.TCPSocketConnection[] = [];
  private lastStatSave: number = 0;
  /** Highest core log sequence number already written to hilog. */
  private lastLogSeq: number = -1;
  /**
   * Set when this start attempt failed, so `onDestroy` does not overwrite the
   * recorded failure with `stopped`. Without it the UI would see a clean stop
   * and could not tell a failed start from a user-initiated disconnect.
   */
  private failed: boolean = false;

  async onCreate(want: Want): Promise<void> {
    hilog.info(0x0000, TAG, 'onCreate, core version %{public}s', sslocal.version());
    const profile = await ProfileStore.getCurrent(this.context);
    if (profile === null || profile.host.length === 0) {
      hilog.error(0x0000, TAG, 'no profile configured, aborting');
      // report it: otherwise the UI sits on "Connecting…" until its own
      // timeout, which reads as a hang rather than as a configuration problem
      await VpnStatusStore.markFailed(this.context, '', '', 'No profile configured', '');
      return;
    }
    hilog.info(0x0000, TAG, 'starting profile %{public}s (route %{public}s)',
      profile.name, profile.route);
    await VpnStatusStore.markStarting(this.context, profile.id, profile.name);

    this.connection = vpnExtension.createVpnConnection(this.context);
    const config: vpnExtension.VpnConfig = {
      addresses: [{
        address: { address: TUN_ADDRESS, family: 1 },
        prefixLength: TUN_PREFIX_LENGTH,
      }],
      // default route: capture all IPv4 traffic into the tun
      routes: [{
        interface: 'vpn-tun',
        destination: {
          address: { address: '0.0.0.0', family: 1 },
          prefixLength: 0,
        },
        gateway: { address: '0.0.0.0', family: 1 },
        hasGateway: false,
        isDefaultRoute: true,
      }],
      dnsAddresses: ['1.1.1.1'],
      trustedApplications: [],
      blockedApplications: [],
      mtu: TUN_MTU,
      isIPv4Accepted: true,
    };
    try {
      const tunFd = await this.connection.create(config);
      hilog.info(0x0000, TAG, 'vpn interface created, tun fd %{public}d', tunFd);

      // Keep the core's own server connections out of the tunnel (see class
      // doc): protect every socket this process creates from now on. Only
      // available since API 22, so probe for it at runtime.
      if (typeof this.connection.protectProcessNet === 'function') {
        await this.connection.protectProcessNet();
        hilog.info(0x0000, TAG, 'process sockets protected from VPN routing');
      } else {
        hilog.warn(0x0000, TAG, 'protectProcessNet unavailable (API < 22); ' +
          'server connection may loop through the tunnel');
      }

      const aclPath = await this.deployAcl(profile.route);

      // Host the flow-stat report endpoint; stats are best-effort, so a
      // failure here must not block the VPN from starting.
      await TrafficStatsStore.clear(this.context);
      try {
        const statPort = await this.startStatServer();
        const code = sslocal.setStatAddress(`127.0.0.1:${statPort}`);
        if (code !== 0) {
          hilog.warn(0x0000, TAG, 'setStatAddress failed: %{public}d', code);
        }
      } catch (e) {
        hilog.warn(0x0000, TAG, 'traffic stats unavailable: %{public}s', JSON.stringify(e));
      }

      // Route the tun device through the shadowsocks tunnel. The address must
      // accompany the fd: the core's serving loop reads the interface address
      // and netmask before its packet loop and aborts without them, and on
      // OpenHarmony the device cannot report them from the fd alone.
      const tunAddress = `${TUN_ADDRESS}/${TUN_PREFIX_LENGTH}`;
      const code = sslocal.startTunFd(profile.toTunConfig(aclPath, tunAddress), tunFd);
      if (code !== 0) {
        // read lastError() in the same statement as the failing call: the
        // native side only guarantees the message until the next call
        const detail: string = sslocal.lastError() ?? `startTunFd returned ${code}`;
        hilog.error(0x0000, TAG, 'sslocal.startTunFd failed: %{public}d %{public}s',
          code, detail);
        this.failed = true;
        await VpnStatusStore.markFailed(this.context, profile.id, profile.name,
          'Could not start the tunnel', detail);
        await this.teardown();
      } else {
        hilog.info(0x0000, TAG, 'shadowsocks tun routing started');
        await VpnStatusStore.markRunning(this.context, profile.id, profile.name);
        this.watchCoreLiveness(profile.id, profile.name);
      }
    } catch (e) {
      const detail: string = (e as BusinessError).message ?? JSON.stringify(e);
      hilog.error(0x0000, TAG, 'failed to establish VPN: %{public}s', detail);
      this.failed = true;
      await VpnStatusStore.markFailed(this.context, profile.id, profile.name,
        'Could not establish the VPN interface', detail);
      await this.teardown();
    }
  }

  async onDestroy(): Promise<void> {
    hilog.info(0x0000, TAG, 'onDestroy');
    // a failed start has already recorded why; a clean stop must not mask it
    if (!this.failed) {
      await VpnStatusStore.markStopped(this.context);
    }
    await this.teardown();
  }

  /**
   * `startTunFd` returning 0 only means the core accepted the tun fd — it can
   * still fall over moments later, and when it does the only other signal is
   * that the traffic counters never start moving, which is indistinguishable
   * from a slow start. So look once shortly after startup, and if the core is
   * gone record why: `sslocal.lastError()` holds the reason the runtime
   * stopped, and this is the last moment it can be read from this process.
   */
  private watchCoreLiveness(profileId: string, profileName: string): void {
    setTimeout(() => {
      const alive = sslocal.isRunning();
      const error = sslocal.lastError() ?? '';
      hilog.info(0x0000, TAG, 'core liveness check: running=%{public}s lastError=%{public}s',
        alive ? 'true' : 'false', error);
      if (alive) {
        return;
      }
      this.failed = true;
      VpnStatusStore.markFailed(this.context, profileId, profileName,
        'The core stopped right after starting', error).catch(() => {
      });
    }, CORE_LIVENESS_DELAY_MS);
  }

  private async teardown(): Promise<void> {
    // `startTunFd` returns as soon as the tokio runtime has been spawned — it
    // does not wait for `run_local` to build the local server, so a core that
    // fell over immediately still reported success and the extension logged
    // "tun routing started". Its reason is still sitting in lastError() here,
    // and this is the last moment it can be read before `stop()` clears it.
    const coreRunning = sslocal.isRunning();
    const coreError = sslocal.lastError() ?? '';
    hilog.info(0x0000, TAG, 'teardown: coreRunning=%{public}s lastError=%{public}s',
      coreRunning ? 'true' : 'false', coreError);
    if (!coreRunning && coreError.length > 0 && !this.failed) {
      this.failed = true;
      await VpnStatusStore.markFailed(this.context, '', '',
        'The core stopped after starting', coreError).catch(() => {
      });
    }
    if (sslocal.isRunning()) {
      sslocal.stop();
    }
    // iterate a copy: closing a connection fires its 'close' handler, which
    // removes it from this.statConnections
    const connections = this.statConnections.slice();
    this.statConnections = [];
    for (const conn of connections) {
      try {
        await conn.close();
      } catch (e) {
        // already closed
      }
    }
    if (this.statServer !== null) {
      try {
        await this.statServer.close();
      } catch (e) {
        // already closed
      }
      this.statServer = null;
    }
    if (this.connection !== null) {
      await this.connection.destroy();
      this.connection = null;
    }
    await TrafficStatsStore.clear(this.context);
    // The *status* file is deliberately left alone here — see VpnStatusStore.
    // Clearing it would erase the failed/stopped/crashed distinction the UI
    // depends on. The traffic counters above are per-connection and do go.
  }

  /**
   * Deploys the ACL file for `route` from rawfile resources into the app
   * files dir and returns its path, or '' when the route needs no ACL.
   */
  private async deployAcl(route: string): Promise<string> {
    if (route === ROUTE_ALL) {
      return '';
    }
    const file = aclFileForRoute(route);
    if (file.length === 0) {
      hilog.warn(0x0000, TAG, 'unknown route %{public}s, no ACL applied', route);
      return '';
    }
    try {
      const dir = `${this.context.filesDir}/acl`;
      try {
        fs.mkdirSync(dir);
      } catch (e) {
        // directory already exists
      }
      const dest = `${dir}/${file}`;
      const content = await this.context.resourceManager.getRawFileContent(`acl/${file}`);
      const fd = fs.openSync(dest,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(fd.fd,
          content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength));
      } finally {
        fs.closeSync(fd);
      }
      hilog.info(0x0000, TAG, 'ACL deployed: %{public}s', dest);
      return dest;
    } catch (e) {
      hilog.error(0x0000, TAG, 'failed to deploy ACL for %{public}s: %{public}s',
        route, JSON.stringify(e));
      return '';
    }
  }

  /**
   * Binds the traffic-stat TCP endpoint to the first free loopback port from
   * STAT_PORTS and returns the bound port. Each accepted connection delivers
   * 16-byte little-endian (tx, rx) u64 cumulative counters.
   *
   * A fresh server instance is constructed per attempt: re-listening on an
   * instance whose bind already failed is not guaranteed to work.
   */
  private async startStatServer(): Promise<number> {
    for (const port of STAT_PORTS) {
      const server = socket.constructTCPSocketServerInstance();
      server.on('connect', (conn: socket.TCPSocketConnection) => {
        this.onStatConnection(conn);
      });
      try {
        await server.listen({ address: '127.0.0.1', port: port, family: 1 });
        this.statServer = server;
        hilog.info(0x0000, TAG, 'stat endpoint listening on 127.0.0.1:%{public}d', port);
        return port;
      } catch (e) {
        hilog.warn(0x0000, TAG, 'stat port %{public}d unavailable, trying next', port);
        try {
          await server.close();
        } catch (closeError) {
          // never bound
        }
      }
    }
    throw new Error('no stat port available');
  }

  /**
   * Forwards the core's own log records to hilog.
   *
   * The native core reports everything interesting about a broken tunnel — a
   * server it cannot reach, a cipher the peer rejects — through the `log`
   * facade, and a device has no console to attach to, so those records were
   * simply discarded; a tunnel that came up and carried nothing had no
   * explanation at all. The core posts a traffic sample here every ~500 ms, so
   * draining the records on that same tick gives near-live logging with no
   * extra timer. Records carry a sequence number because the ring wraps.
   */
  private flushCoreLogs(): void {
    const raw = sslocal.recentLogs();
    if (raw === null || raw.length === 0) {
      return;
    }
    for (const line of raw.split('\n')) {
      const split = line.indexOf(' ');
      if (split <= 0) {
        continue;
      }
      const seq = Number.parseInt(line.substring(0, split), 10);
      if (Number.isNaN(seq) || seq <= this.lastLogSeq) {
        continue;
      }
      this.lastLogSeq = seq;
      hilog.info(0x0000, TAG, 'core %{public}s', line.substring(split + 1));
    }
  }

  /**
   * Handles one flow-stat report. The core opens a **new** connection for
   * every 500 ms sample and closes it after the 16-byte write, so each
   * connection is dropped from the tracking list as soon as it ends —
   * otherwise the list would grow by two entries per second for as long as
   * the VPN is up.
   */
  private onStatConnection(conn: socket.TCPSocketConnection): void {
    this.statConnections.push(conn);
    // piggy-back on the core's ~500 ms report cadence to surface its own logs
    this.flushCoreLogs();
    const forget = () => {
      const index = this.statConnections.indexOf(conn);
      if (index >= 0) {
        this.statConnections.splice(index, 1);
      }
    };
    conn.on('close', () => forget());
    conn.on('error', () => forget());
    conn.on('message', (info: socket.SocketMessageInfo) => {
      const buf = info.message;
      if (buf.byteLength < 16) {
        return;
      }
      const view = new DataView(buf);
      // native-endian u64 on arm64 = little-endian; low word first
      const tx = view.getUint32(0, true) + view.getUint32(4, true) * 4294967296;
      const rx = view.getUint32(8, true) + view.getUint32(12, true) * 4294967296;
      const now = Date.now();
      if (now - this.lastStatSave >= STAT_SAVE_INTERVAL_MS) {
        this.lastStatSave = now;
        TrafficStatsStore.save(this.context, tx, rx).catch(() => {
        });
      }
    });
  }
}
