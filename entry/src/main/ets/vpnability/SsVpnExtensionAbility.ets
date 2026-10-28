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
import { BusinessError, power } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import sslocal from 'libsslocal.so';
import { ProfileStore } from '../model/ProfileStore';
import { aclFileForRoute, ROUTE_ALL, ROUTE_CUSTOM_RULES } from '../model/Routes';
import { cachedAcl, refreshAcl } from '../model/AclSync';
import { localDnsServer } from '../model/Network';
import { composeCustomRules, readUserRules } from '../model/CustomRules';
import {
  clear as clearNotification, showConnected, showStarting,
} from '../model/ConnectionNotification';
import { TrafficSample, TrafficUpdate, trafficUpdate } from '../model/NotificationContent';
import { TrafficStats, TrafficStatsStore, formatBytes, formatRate } from '../model/TrafficStats';
import { VpnStatusStore } from '../model/VpnStatus';
import { SettingsStore } from '../model/Settings';
import {
  AppSettings, DEFAULT_LOCAL_DNS_PORT, portNumber, VPN_STATE_STOPPED,
} from '../model/Diagnostics';
import {
  appMode, joinNames, MAX_APP_LIST, namesOf, vpnApplicationLists, VpnAppLists,
} from '../model/PerApp';
import { installedNames, InstalledNames, selfBundleName } from '../model/AppCatalog';

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
/**
 * Address clients are told to send DNS to: the *other* end of the tun's /30,
 * which nothing is configured to own.
 *
 * Deliberately not `TUN_ADDRESS`. A query to the tun's own address is delivered
 * to the local socket stack rather than out through the interface, so it never
 * reaches the core's tun stack, and the interception that answers DNS — see
 * `dns_gateway` in Profile.toTunConfig — would never see it. An address merely
 * *on* the tun's subnet is on-link and does go out the interface, which is what
 * puts the query in front of the core. shadowsocks-android uses the same trick
 * with the same address.
 */
const DNS_ADDRESS = '172.19.0.2';

/** Loopback ports probed (in order) for the traffic-stat report endpoint. */
const STAT_PORTS: number[] = [65080, 65081, 65082, 65083, 65084];
/** Stat samples reach us every ~500 ms; persist at most one per second. */
const STAT_SAVE_INTERVAL_MS = 1000;
/**
 * How often the notification's traffic line is rewritten. The core reports
 * twice a second and the saved sample follows it; a notification that changed
 * that fast would be unreadable.
 */
const NOTIFICATION_INTERVAL_MS = 2000;
/** How long after a successful start to check the core is still alive. */
const CORE_LIVENESS_DELAY_MS = 3000;
/**
 * How long the core has to prove that it is up by reporting its first traffic
 * sample. `sslocal.startTunFd` returns as soon as the tokio runtime has been
 * spawned (see the teardown comment). The first stat report is the earliest
 * proof that `run_local` built the local server. The core reports every
 * 500 ms, so this budget is many report periods.
 */
const CORE_READY_TIMEOUT_MS = 5000;
/**
 * How long to watch a core that has no stat endpoint. Without counters the
 * only evidence is that the process is alive and recorded no error. This is
 * long enough for an immediate `run_local` failure to surface.
 */
const CORE_READY_FALLBACK_MS = 1500;

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
 * TrafficMonitor consumes. We host that endpoint and persist one record per
 * second via TrafficStatsStore for the UI process to poll. The record names
 * the profile and a per-start session token, and the UI process settles it
 * into the profile counters once. The first report also proves that
 * `run_local` built its local server, so this extension does not record
 * `running` before it arrives.
 *
 * Per-app proxy: when the profile enables Apps VPN mode, the selected bundle
 * names go into the platform VPN config as `trustedApplications` in On mode or
 * as `blockedApplications` in Bypass mode. The two fields are mutually
 * exclusive. The client bundle never enters the tunnel. The core config is
 * unchanged, because the platform applies the lists.
 *
 * Notification: while the tunnel is up, the notification carries the profile
 * name, the live rates and the session totals. The body tap opens the main
 * screen. The Stop button starts `EntryAbility`, which stops this extension
 * and then settles the session counters. A screen that is off stops the
 * traffic updates.
 *
 * The default route below sends all traffic into the tun, so the core's own
 * connections to the shadowsocks server must stay outside the tunnel or the
 * tunnel loops on itself. `VpnConnection.protectProcessNet()` (API 22+) marks
 * every socket this process creates afterwards as protected; since the native
 * core runs in this same process, its server connections bypass the VPN. On
 * older runtimes the API is absent — we log a warning and the tunnel will
 * loop unless the server is reachable through a more specific route.
 */
/** The text of a rawfile, which arrives as bytes. */
function bufferToText(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}

/** Resolves after `ms` milliseconds. */
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

/** What the readiness wait learned about the core. */
interface CoreReadiness {
  ready: boolean;
  /** True when the core reports its traffic counters. */
  stats: boolean;
  /** The native error text, or '' when the core reported no error. */
  detail: string;
}

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
  /** Profile name, as the notification shows it. */
  private runningProfileName: string = '';
  /** Profile id this start runs. The traffic record and a failure both need it. */
  private runningProfileId: string = '';
  /**
   * Identifies this extension start in the traffic record. The settler adds a
   * record once and marks it settled under this token, which is what stops a
   * late write of the same counters from being counted twice.
   */
  private sessionToken: string = '';
  /** True when the core reports to a hosted stat endpoint. */
  private statsAvailable: boolean = false;
  /** Set before the first await in `onDestroy`: no stat write may follow. */
  private stopping: boolean = false;
  /** True once this session wrote its record. Only then may teardown rewrite it. */
  private wroteSample: boolean = false;
  /** Latest counters in memory, for the final record teardown writes. */
  private lastTx: number = 0;
  private lastRx: number = 0;
  /** Keeps a session record fresh when the core has no stat endpoint. */
  private heartbeatTimer: number = -1;
  /** Resolves when the core reports its first traffic sample. */
  private sampleWaiter: (() => void) | null = null;
  /** True once this session warned that an unsettled record blocks its writes. */
  private warnedForeignRecord: boolean = false;
  /** `lastError()` just before this start, to tell this session's error apart. */
  private lastErrorBaseline: string = '';
  /** Previous traffic sample, for the rate the notification shows. */
  private sample: TrafficSample = { tx: -1, rx: -1, at: 0 };
  private lastNotificationAt: number = 0;

  async onCreate(want: Want): Promise<void> {
    hilog.info(0x0000, TAG, 'onCreate, core version %{public}s', sslocal.version());
    // The platform may reuse this process after an earlier extension instance
    // that was stopped while its teardown was cut short. The core is a
    // single-instance native object, so a live one here would make this start
    // return ALREADY_RUNNING. Stopping it is safe: nothing on the page holds a
    // live session in a process that is being reused.
    if (sslocal.isRunning()) {
      hilog.warn(0x0000, TAG, 'an earlier core instance is still running, stopping it first');
      sslocal.stop();
    }
    const profile = await ProfileStore.getCurrent(this.context);
    if (profile === null || profile.host.length === 0) {
      hilog.error(0x0000, TAG, 'no profile configured, aborting');
      this.failed = true;
      // Post the notification first, then report the failure and take it away:
      // the user sees that a start was attempted, and the UI learns the reason
      // instead of waiting on the connecting state until its own timeout.
      await showStarting(this.context);
      await VpnStatusStore.markFailed(this.context, '', '', 'No profile configured', '');
      await clearNotification();
      return;
    }
    // Refuse a plugin the native core cannot run before the VPN interface
    // exists. The core would reject the config too, but a refused start reads
    // as a reason where a dead tunnel reads as a bug.
    const pluginError: string = profile.pluginError();
    if (pluginError.length > 0) {
      hilog.error(0x0000, TAG, 'refusing the profile: %{public}s', pluginError);
      this.failed = true;
      await VpnStatusStore.markFailed(this.context, profile.id, profile.name, pluginError, '');
      return;
    }
    // The local DNS port is a setting. This process reads the store and never
    // writes it, because the UI process owns the file.
    const settings: AppSettings = await SettingsStore.load(this.context);
    const dnsPort: number = portNumber(settings.localDnsPort, DEFAULT_LOCAL_DNS_PORT);
    hilog.info(0x0000, TAG, 'starting profile %{public}s (route %{public}s)',
      profile.name, profile.route);
    await VpnStatusStore.markStarting(this.context, profile.id, profile.name);
    // The tunnel outlives the app's window, so the way out of it has to exist
    // before the tun interface does.
    await showConnected(this.context, profile.name, $r('app.string.index_connecting'));

    // The per-app lists are platform VPN fields. The core config carries none.
    // The client bundle always stays outside the tunnel: the helper removes it
    // from the trusted list and puts it first in the blocked list.
    const clientBundle: string = selfBundleName(this.context);
    const wanted: string[] = namesOf(profile.proxyAppsList);
    let installed: InstalledNames = { names: [], reason: '' };
    if (profile.proxyAppsEnabled) {
      installed = await installedNames(wanted);
      if (installed.reason.length > 0) {
        // the list is applied but was not verified against the installed apps
        hilog.warn(0x0000, TAG, 'app list not verified (%{public}s); kept %{public}d names',
          installed.reason, installed.names.length);
      }
      for (const name of wanted) {
        if (installed.names.indexOf(name) < 0) {
          hilog.warn(0x0000, TAG, 'skipped bundle %{public}s', name);
        }
      }
    }
    const appLists: VpnAppLists = vpnApplicationLists(profile.proxyAppsEnabled,
      profile.proxyAppsBypass, joinNames(installed.names), clientBundle, MAX_APP_LIST);
    hilog.info(0x0000, TAG, 'per-app mode %{public}s: trusted %{public}d, blocked %{public}d',
      appMode(profile.proxyAppsEnabled, profile.proxyAppsBypass),
      appLists.trusted.length, appLists.blocked.length);

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
      // Clients resolve against DNS_ADDRESS; whatever they do with it, the
      // core answers (see toTunConfig). Pointing them at a public resolver
      // would not work: their queries would be relayed as UDP and dropped by a
      // server that does not relay UDP.
      dnsAddresses: [DNS_ADDRESS],
      mtu: TUN_MTU,
      isIPv4Accepted: true,
    };
    // The two list fields are mutually exclusive, and the code sets at most
    // one. An absent list means every application, which is the default.
    if (appLists.trusted.length > 0) {
      config.trustedApplications = appLists.trusted;
    }
    if (appLists.blocked.length > 0) {
      config.blockedApplications = appLists.blocked;
    }
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

      // This session's identity goes into every traffic record, so set it
      // before anything can write one, and before the first await that follows
      // the start below.
      this.sessionToken = `${Date.now()}-${Math.random().toString(36).substring(2, 10)}`;
      this.runningProfileId = profile.id;
      this.runningProfileName = profile.name;
      this.lastErrorBaseline = sslocal.lastError() ?? '';

      // A record an earlier session left unsettled is moved aside before this
      // session writes its own. The settler reads the pending record first, so
      // the crashed session's counters are not lost and do not block this one.
      try {
        await TrafficStatsStore.archivePending(this.context);
      } catch (e) {
        hilog.warn(0x0000, TAG, 'could not archive an unsettled traffic record: %{public}s',
          JSON.stringify(e));
      }

      // Host the flow-stat report endpoint; stats are best-effort, so a
      // failure here must not block the VPN from starting. The store is not
      // cleared: an unsettled record from an earlier session belongs to the
      // settler. A session without an endpoint is recorded with `stats` false,
      // so the page does not read the missing counters as a dead core.
      this.statsAvailable = false;
      try {
        const statPort = await this.startStatServer();
        const code = sslocal.setStatAddress(`127.0.0.1:${statPort}`);
        if (code !== 0) {
          hilog.warn(0x0000, TAG, 'setStatAddress failed: %{public}d', code);
        } else {
          this.statsAvailable = true;
        }
      } catch (e) {
        hilog.warn(0x0000, TAG, 'traffic stats unavailable: %{public}s', JSON.stringify(e));
      }

      // Route the tun device through the shadowsocks tunnel. The address must
      // accompany the fd: the core's serving loop reads the interface address
      // and netmask before its packet loop and aborts without them, and on
      // OpenHarmony the device cannot report them from the fd alone.
      const tunAddress = `${TUN_ADDRESS}/${TUN_PREFIX_LENGTH}`;
      const code = sslocal.startTunFd(
        profile.toTunConfig(aclPath, tunAddress, localDnsServer(), dnsPort), tunFd);
      if (code !== 0) {
        // read lastError() in the same statement as the failing call: the
        // native side only guarantees the message until the next call
        const detail: string = sslocal.lastError() ?? `startTunFd returned ${code}`;
        hilog.error(0x0000, TAG, 'sslocal.startTunFd failed: %{public}d %{public}s',
          code, detail);
        this.failed = true;
        // the page composes the final text from the reason and the detail
        await VpnStatusStore.markFailed(this.context, profile.id, profile.name,
          'Failed to connect the remote server', detail);
        await this.teardown();
      } else {
        // A 0 only means the tokio runtime was spawned. It does not mean
        // `run_local` built the local server, so wait for proof before this
        // start claims success: the first traffic report, or a liveness window
        // with no new native error when there is no report to wait for.
        const readiness = await this.awaitCoreReady();
        if (!readiness.ready) {
          hilog.error(0x0000, TAG, 'the core did not start: %{public}s', readiness.detail);
          this.failed = true;
          await VpnStatusStore.markFailed(this.context, profile.id, profile.name,
            'The core did not start', readiness.detail);
          await this.teardown();
          return;
        }
        if (!readiness.stats) {
          // The core is alive but its counters do not reach us. Record the
          // session with the heartbeat instead, so the page can still tell it
          // is alive and does not read the missing counters as a dead core.
          this.statsAvailable = false;
          this.startHeartbeat();
        }
        hilog.info(0x0000, TAG, 'shadowsocks tun routing started');
        await VpnStatusStore.markRunning(this.context, profile.id, profile.name);
        // the tunnel outlives this app's window, so the way out of it has to
        // outlive the window too
        await showConnected(this.context, profile.name);
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
    // Everything that must happen even when the platform tears this process
    // down at the first await runs first, without yielding:
    // - stop the stat writer, so no sample lands after the final record;
    // - write the session's final record, which is what the settler adds;
    // - stop the core, so a status that says `stopped` never leaves a core
    //   running for the next start to meet as ALREADY_RUNNING.
    // The store calls write their files synchronously, before they yield.
    this.stopping = true;
    this.stopHeartbeat();
    this.writeFinalSample();
    if (sslocal.isRunning()) {
      sslocal.stop();
    }
    // Only now is the status true. It is written synchronously by the store
    // call, so the UI can act on it even if the process dies at the await. A
    // failure recorded by a start must not be overwritten with a clean stop.
    if (!this.failed) {
      await VpnStatusStore.mark(this.context, VPN_STATE_STOPPED,
        this.runningProfileId, this.runningProfileName, '', '');
    }
    await clearNotification();
    await this.teardown();
  }

  /**
   * Waits until the core proves that it started, or until the budget expires.
   *
   * With a stat endpoint, the first traffic report is the strongest proof: the
   * core's report task runs only when `run_local` built its local server. A
   * report that never comes while the process lives and records no new error
   * still leaves a startable core, so that case returns ready without stats
   * and the caller switches to the heartbeat. Without an endpoint there is no
   * report signal at all, so the wait is a liveness window. `lastError()`
   * survives a successful start, so the baseline taken before the start tells
   * this session's error apart from an earlier one.
   */
  private async awaitCoreReady(): Promise<CoreReadiness> {
    if (this.statsAvailable) {
      const reported = await this.waitForFirstSample(CORE_READY_TIMEOUT_MS);
      if (reported) {
        return { ready: true, stats: true, detail: '' };
      }
      hilog.warn(0x0000, TAG,
        'the core reported no traffic sample in %{public}d ms, using the heartbeat',
        CORE_READY_TIMEOUT_MS);
    } else {
      await sleep(CORE_READY_FALLBACK_MS);
    }
    const error = sslocal.lastError() ?? '';
    if (!sslocal.isRunning()) {
      return { ready: false, stats: false, detail: error };
    }
    if (error.length > 0 && error !== this.lastErrorBaseline) {
      return { ready: false, stats: false, detail: error };
    }
    return { ready: true, stats: false, detail: '' };
  }

  /** Resolves true when the core sends its first traffic sample in time. */
  private waitForFirstSample(timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      let done = false;
      let timer = -1;
      const finish = (ready: boolean): void => {
        if (done) {
          return;
        }
        done = true;
        this.sampleWaiter = null;
        if (timer >= 0) {
          clearTimeout(timer);
        }
        resolve(ready);
      };
      timer = setTimeout(() => finish(false), timeoutMs);
      this.sampleWaiter = () => finish(true);
    });
  }

  /**
   * Writes a record once a second while the core has no stat endpoint, so the
   * page can tell a live session without counters from a dead core. The record
   * carries `stats` false, and the page keeps it away from the rates.
   */
  private startHeartbeat(): void {
    this.stopHeartbeat();
    const tick = (): void => {
      this.persistSample(this.lastTx, this.lastRx, false).catch(() => {
      });
    };
    tick();
    this.heartbeatTimer = setInterval(tick, STAT_SAVE_INTERVAL_MS);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer >= 0) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  /**
   * Writes one record for this session.
   *
   * The extension never overwrites an unsettled record of another session: its
   * counters are not in profiles.json yet, and it is the only copy. The record
   * of a session the settler already added is not written either, because a
   * late write would carry the same token and be counted again.
   */
  private async persistSample(tx: number, rx: number, closed: boolean): Promise<void> {
    if (this.stopping && !closed) {
      return;
    }
    const current = await TrafficStatsStore.load(this.context);
    // Teardown can start while the read above is in flight. Its final record
    // must be the last one, or the session would look open again.
    if (this.stopping && !closed) {
      return;
    }
    if (current !== null) {
      if (current.token === this.sessionToken && current.settled) {
        return;
      }
      if (current.token !== this.sessionToken && !current.settled) {
        if (!this.warnedForeignRecord) {
          this.warnedForeignRecord = true;
          hilog.warn(0x0000, TAG, 'traffic record of an unsettled session is kept');
        }
        return;
      }
    }
    await this.writeSample(tx, rx, closed);
  }

  /** The final record, written without yielding (see `onDestroy`). */
  private writeFinalSample(): void {
    if (!this.wroteSample) {
      return;
    }
    const current = TrafficStatsStore.loadSync(this.context);
    if (current !== null) {
      if (current.token === this.sessionToken && current.settled) {
        return;
      }
      if (current.token !== this.sessionToken && !current.settled) {
        return;
      }
    }
    // JsonStore.write performs the whole write before it yields, so the record
    // is on disk even if the process dies at the following await.
    this.writeSample(this.lastTx, this.lastRx, true).catch(() => {
    });
  }

  private async writeSample(tx: number, rx: number, closed: boolean): Promise<void> {
    const record: TrafficStats = {
      tx: tx,
      rx: rx,
      timestamp: Date.now(),
      profileId: this.runningProfileId,
      token: this.sessionToken,
      stats: this.statsAvailable,
      closed: closed,
      settled: false,
    };
    await TrafficStatsStore.save(this.context, record);
    this.wroteSample = true;
  }

  /**
   * Watches the core once more shortly after the start was confirmed alive.
   *
   * `startTunFd` returning 0 and the first stat report only prove the core got
   * going; it can still fall over moments later. `lastError()` holds the reason
   * the runtime stopped, and this is the last moment it can be read from this
   * process. A core whose instance is gone, or that recorded a new error, is
   * reported as failed with the profile that ran it, so the record stays
   * attributable.
   */
  private watchCoreLiveness(profileId: string, profileName: string): void {
    setTimeout(() => {
      const alive = !this.coreDied();
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
      // a dead core must not leave a notification behind
      clearNotification().catch(() => {
      });
    }, CORE_LIVENESS_DELAY_MS);
  }

  /**
   * True when the core is gone. The instance can outlive its task, so a new
   * native error is as much a death as a missing instance.
   */
  private coreDied(): boolean {
    if (!sslocal.isRunning()) {
      return true;
    }
    const error = sslocal.lastError() ?? '';
    return error.length > 0 && error !== this.lastErrorBaseline;
  }

  private async teardown(): Promise<void> {
    // The notification goes first: a tunnel that is being torn down has no
    // control left to offer, and a failed start must not leave one behind.
    await clearNotification();
    // `startTunFd` returns as soon as the tokio runtime has been spawned — it
    // does not wait for `run_local` to build the local server, so a core that
    // fell over immediately still reported success and the extension logged
    // "tun routing started". The readiness wait in `onCreate` closes that gap;
    // this check catches a core that died after it.
    const coreRunning = sslocal.isRunning();
    const coreError = sslocal.lastError() ?? '';
    hilog.info(0x0000, TAG, 'teardown: coreRunning=%{public}s lastError=%{public}s',
      coreRunning ? 'true' : 'false', coreError);
    if (!coreRunning && coreError.length > 0 && !this.failed) {
      this.failed = true;
      await VpnStatusStore.markFailed(this.context, this.runningProfileId,
        this.runningProfileName,
        'The core stopped after starting', coreError).catch(() => {
      });
    }
    this.stopping = true;
    this.stopHeartbeat();
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
    // The traffic record is deliberately left alone: only the settler marks it
    // settled, and deleting it here would race the settlement that reads it.
    // The *status* file is left alone for the same reason — see VpnStatusStore.
  }

  /**
   * Deploys the ACL file for `route` from rawfile resources into the app
   * files dir and returns its path, or '' when the route needs no ACL. While
   * doing that it refreshes whatever the file imports, for the next start.
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
      // the presets arrive as files; the custom route is composed from what the
      // user wrote, since nothing ships for it
      const rawText = route === ROUTE_CUSTOM_RULES
        ? composeCustomRules(readUserRules(this.context))
        : bufferToText(await this.context.resourceManager.getRawFileContent(`acl/${file}`));

      // A refreshed copy from an earlier start is used when there is one; the
      // list it came from may have moved on, but a start must not wait on the
      // network for that, so the refresh below is for the next one. The custom
      // route holds the user's own rules, composed above, so a cached copy
      // never applies to it.
      const cached = route === ROUTE_CUSTOM_RULES ? '' : await cachedAcl(this.context, file);
      const deployed = cached.length > 0 ? cached : rawText;

      const fd = fs.openSync(dest,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(fd.fd, deployed);
      } finally {
        fs.closeSync(fd);
      }
      const source = cached.length > 0
        ? 'refreshed copy'
        : (route === ROUTE_CUSTOM_RULES ? 'user rules' : 'shipped copy');
      hilog.info(0x0000, TAG, 'ACL deployed: %{public}s (%{public}s)', dest, source);

      // deliberately not awaited: connecting does not depend on it
      refreshAcl(this.context, file, rawText).then((written: boolean) => {
        if (written) {
          hilog.info(0x0000, TAG, 'ACL refreshed for the next start: %{public}s', file);
        }
      }).catch((e: Object) => {
        hilog.warn(0x0000, TAG, 'ACL refresh failed: %{public}s', JSON.stringify(e));
      });
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
   * Keeps the notification's traffic line current.
   *
   * The counters are cumulative, so a rate needs two samples and the time
   * between them. Updates are throttled well below the core's report rate: a
   * notification that rewrote itself twice a second would be noise, and the
   * platform would rather not be asked.
   *
   * A screen that is off stops the updates. The phone shows nothing while it
   * is off, and a wake-up every two seconds costs battery for no reader. The
   * first sample after the screen comes back is a baseline, so the line
   * resumes with a correct rate.
   */
  private updateNotification(tx: number, rx: number, now: number): void {
    let screenActive: boolean = true;
    try {
      screenActive = power.isActive();
    } catch (e) {
      // a failed screen-state read counts as screen on, so the line keeps
      // updating rather than freezing on a platform that refuses the call
      screenActive = true;
    }
    const update: TrafficUpdate = trafficUpdate(this.sample, tx, rx, now, screenActive);
    this.sample = update.sample;
    if (!update.publish) {
      return;
    }
    if (now - this.lastNotificationAt < NOTIFICATION_INTERVAL_MS) {
      return;
    }
    this.lastNotificationAt = now;
    showConnected(this.context, this.runningProfileName,
      $r('app.string.notification_traffic',
        formatRate(update.rates.up), formatRate(update.rates.down)),
      $r('app.string.notification_traffic', formatBytes(tx), formatBytes(rx)))
      .catch(() => {
      });
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
      // the first report is the proof that the core built its local server
      const waiter = this.sampleWaiter;
      if (waiter !== null) {
        this.sampleWaiter = null;
        waiter();
      }
      this.lastTx = tx;
      this.lastRx = rx;
      if (now - this.lastStatSave >= STAT_SAVE_INTERVAL_MS) {
        this.lastStatSave = now;
        this.persistSample(tx, rx, false).catch(() => {
        });
      }
      this.updateNotification(tx, rx, now);
    });
  }
}
