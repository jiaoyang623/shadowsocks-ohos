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

import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Profile } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import { applyImport, exportProfiles, parseProfilesText } from '../model/ProfilesFile';
import { EXPORT_FILE_NAME, pickTextFile, readClipboard, saveTextFile, writeClipboard } from '../model/Transfer';
import { abilityContext, takePendingImport } from '../model/AppContext';
import { MODE_PROXY } from '../model/Diagnostics';
import { ProxyService } from '../model/ProxyService';
import { formatBytes, formatRate, TrafficStats, TrafficStatsStore } from '../model/TrafficStats';
import { grantVpnAuthorization } from './VpnGrant';
import {
  AppSettings, CONNECT_TIMEOUT_MS, formatLatency, formatMbps, formatRtt, interpretProbe, isStale,
  LatencyEntry, PHASE_CONNECTED, PHASE_CONNECTING, PHASE_FAILED, PHASE_IDLE, PHASE_PROBE_FAILED,
  PHASE_VERIFYING, PROBE_OK, routeProxiesByDefault, STATS_SETTLE_MS, STATS_STALE_MS,
  summarizeStatus, VpnStatus, VPN_STATE_FAILED, VPN_STATE_RUNNING, VPN_STATE_STOPPED,
} from '../model/Diagnostics';
import { VpnStatusStore } from '../model/VpnStatus';
import { PROBE_TIMEOUT_MS, probeThroughTunnel } from '../model/ConnectivityProbe';
import { LATENCY_TIMEOUT_MS, measureLatency } from '../model/Latency';
import { measureThroughput, SPEED_TIMEOUT_MS } from '../model/Throughput';
import { SettingsStore } from '../model/Settings';

const TAG = 'Index';

const VPN_ABILITY: Want = {
  deviceId: '',
  bundleName: 'com.xbt.project',
  abilityName: 'SsVpnExtensionAbility',
};

const STATS_POLL_INTERVAL_MS = 1000;

/**
 * Main page: the profile list with the active profile highlighted, a bottom
 * bar with the connect toggle and live traffic stats — mirroring
 * shadowsocks-android's main screen.
 *
 * "Connected" here is not taken on faith. Starting the extension ability only
 * proves the ability was launched; its own setup can still fail afterwards, and
 * the tunnel can come up while the far end is unreachable. So the page follows
 * a phase machine driven by the extension's status file (VpnStatusStore) plus a
 * real fetch through the tunnel (ConnectivityProbe), and only reports
 * `connected` once that fetch has both succeeded and been seen traversing the
 * core.
 */
@Entry
@Component
struct Index {
  @State profiles: Profile[] = [];
  @State currentId: string = '';
  @State phase: string = PHASE_IDLE;
  @State failReason: string = '';
  @State probeRttMs: number = 0;
  @State txTotal: number = 0;
  @State rxTotal: number = 0;
  @State txRate: number = 0;
  @State rxRate: number = 0;
  @State mbps: number = 0;
  @State speedRunning: boolean = false;
  @State probeRunning: boolean = false;
  @State latencies: Map<string, LatencyEntry> = new Map<string, LatencyEntry>();
  @State measuringId: string = '';
  @State importUrl: string = '';

  private healthTimer: number = -1;
  private lastStats: TrafficStats | null = null;
  /** Guards against a slow tick overlapping the next one. */
  private polling: boolean = false;
  private lastStatus: VpnStatus | null = null;
  private connectingSince: number = 0;
  /** When the extension first reported `running` for this attempt; 0 = never. */
  private runningSince: number = 0;
  private probeInFlight: boolean = false;
  /** Bumped to abandon a probe whose result is no longer wanted. */
  private probeSeq: number = 0;
  private settings: AppSettings | null = null;
  /** Filter text for the list; empty shows everything. */
  @State search: string = '';
  /**
   * The profile the last delete removed, and where it was. Deleting is easy to
   * do by accident and the profile holds a password that is not recoverable
   * from anywhere else, so the removal is offered back until the next action.
   */
  private lastDeleted: Profile | null = null;
  private lastDeletedIndex: number = -1;
  /** Index a drag started from, so the drop knows what to move. */
  private dragFrom: number = -1;
  /**
   * Set while proxy mode is serving from this process. The VPN extension is not
   * involved in that mode, so its status file says nothing about it.
   */
  @State proxyUp: boolean = false;
  private importDialog: CustomDialogController = new CustomDialogController({
    builder: ImportDialog({
      onConfirm: (text: string) => this.importFromText(text, 'the text'),
    }),
    autoCancel: true,
  });
  // Replacing throws away every profile that is not in the file, so it asks
  // first. Importing does not, which is why only this one is confirmed.
  private replaceDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: 'Replace all profiles?',
      message: 'Every profile will be replaced by the ones in the file. Profiles with the same server keep their counters.',
      confirmLabel: 'Replace',
      onConfirm: () => this.importFromFile(true),
    }),
    autoCancel: true,
  });

  /**
   * A profile link the app was launched with. The page is already on screen by
   * the time a link opened from elsewhere arrives, so the value is watched
   * rather than read once.
   */
  @StorageLink('pending_import_uri') @Watch('onPendingImport') pendingImport: string = '';

  aboutToAppear(): void {
    this.reload();
    this.resumeStatus();
    // a cold start carries the link in the want, before this page existed
    this.onPendingImport();
  }

  private onPendingImport(): void {
    const uri = takePendingImport();
    if (uri.length === 0) {
      return;
    }
    this.importFromText(uri, 'the link');
  }

  aboutToDisappear(): void {
    // the poll timer outlives the page otherwise, and keeps reading the
    // stats file (and touching @State) after the component is gone
    this.stopHealthPolling();
  }

  onPageShow(): void {
    // returning from the edit/subscription/settings page may have changed the
    // list and the endpoints
    this.reload();
    // Re-check for a VPN that is already up. FAILED counts: the system consent
    // dialog can outlast this page's start timeout, and the extension comes up
    // afterwards — leaving the page showing a failure over a working tunnel
    // until something else re-syncs it.
    if (this.phase === PHASE_IDLE || this.phase === PHASE_FAILED) {
      this.resumeStatus();
    }
  }

  /** The profiles to render: the stored ones, less the search filter. */
  private shown(): Profile[] {
    const needle = this.search.trim().toLowerCase();
    if (needle.length === 0) {
      return this.profiles;
    }
    return this.profiles.filter((p) => p.name.toLowerCase().includes(needle) ||
      p.host.toLowerCase().includes(needle));
  }

  /**
   * Moves a dragged profile, which is the order the store keeps and the list
   * shows. Dragging is refused while a filter is on: the indices the list
   * reports are then positions in the filtered view, and moving by them would
   * put the profile somewhere the user did not point at.
   */
  private async dropProfile(insertIndex: number): Promise<void> {
    const from = this.dragFrom;
    this.dragFrom = -1;
    if (from < 0 || this.search.trim().length > 0 || from === insertIndex) {
      return;
    }
    try {
      await ProfileStore.move(abilityContext(), from, insertIndex);
    } catch (e) {
      this.reportFailure('Reorder', e as Object);
    }
    await this.reload();
  }

  private async reload(): Promise<void> {
    // what a subscription no longer lists is kept but not shown
    this.profiles = ProfileStore.visible(await ProfileStore.getAll(abilityContext()));
    this.currentId = await ProfileStore.getCurrentId(abilityContext());
    this.settings = await SettingsStore.load(abilityContext());
  }

  /**
   * Reconciles the page with a VPN that may already be running. The extension
   * outlives the UI, so after an app restart the file is the only record that
   * the tunnel is up.
   */
  private async resumeStatus(): Promise<void> {
    const context = abilityContext();
    const status = await VpnStatusStore.load(context);
    const summary = summarizeStatus(status);
    if (status === null || summary === PHASE_IDLE || summary === PHASE_FAILED) {
      return;
    }
    // A `running` record only means the extension started once — the process
    // may have died since without writing anything, and this file is never
    // cleared on teardown. Trust it only when it is recent, or when the traffic
    // counters are still being refreshed, which is the real liveness signal.
    const stats = await TrafficStatsStore.load(context);
    const recent = !isStale(status.timestamp, Date.now(),
      CONNECT_TIMEOUT_MS + STATS_STALE_MS);
    const countersLive = stats !== null &&
      !isStale(stats.timestamp, Date.now(), STATS_STALE_MS);
    if (!recent && !countersLive) {
      return;
    }
    this.lastStatus = status;
    this.startHealthPolling();
    if (summary === PHASE_CONNECTED) {
      // the extension is up, but this page has not verified anything yet
      this.runProbe(false);
    }
  }

  private currentProfile(): Profile | null {
    return this.profiles.find((p) => p.id === this.currentId) ??
      (this.profiles.length > 0 ? this.profiles[0] : null);
  }

  /** Reports a failed store operation instead of rejecting into a click handler. */
  private reportFailure(what: string, e: Object): void {
    hilog.error(0x0000, TAG, '%{public}s failed: %{public}s', what, JSON.stringify(e));
    promptAction.showToast({ message: `${what} failed` });
  }

  private async selectProfile(profile: Profile): Promise<void> {
    this.currentId = profile.id;
    try {
      await ProfileStore.setCurrentId(abilityContext(), profile.id);
    } catch (e) {
      this.reportFailure('Select profile', e as Object);
    }
  }

  private async removeProfile(profile: Profile): Promise<void> {
    const index = this.profiles.findIndex((p) => p.id === profile.id);
    try {
      await ProfileStore.remove(abilityContext(), profile.id);
      this.lastDeleted = profile;
      this.lastDeletedIndex = index;
    } catch (e) {
      this.reportFailure('Delete profile', e as Object);
      return;
    }
    await this.reload();
    // the profile is gone from the list, so the undo has to be offered here
    const answer = await promptAction.showDialog({
      title: `Deleted ${profile.name}`,
      message: 'Its password was only stored here.',
      buttons: [
        { text: 'Undo', color: $r('app.color.accent') },
        { text: 'OK', color: $r('app.color.text_body') },
      ],
    });
    if (answer.index === 0) {
      await this.undoDelete();
    }
  }

  /** Puts the last deleted profile back where it was. */
  private async undoDelete(): Promise<void> {
    const profile = this.lastDeleted;
    if (profile === null) {
      return;
    }
    const index = this.lastDeletedIndex;
    this.lastDeleted = null;
    this.lastDeletedIndex = -1;
    try {
      const context = abilityContext();
      const stored = await ProfileStore.getAll(context);
      stored.splice(index >= 0 && index <= stored.length ? index : stored.length, 0, profile);
      await ProfileStore.saveAll(context, stored);
    } catch (e) {
      this.reportFailure('Undo delete', e as Object);
    }
    await this.reload();
  }

  /**
   * Imports whatever the text holds: an exported file, a SIP008 document, a
   * list of `ss://` URLs, or a base64 blob of them. Appending rather than
   * replacing, which is what Android's own import does.
   */
  private async importText(text: string, source: string, replace: boolean = false): Promise<void> {
    const imported = parseProfilesText(text);
    if (imported.length === 0) {
      promptAction.showToast({ message: `Nothing to import from ${source}` });
      return;
    }
    const context = abilityContext();
    const existing = await ProfileStore.getAll(context);
    const profiles = applyImport(existing, imported, replace);
    await ProfileStore.saveAll(context, profiles);
    if ((await ProfileStore.getCurrentId(context)).length === 0 && profiles.length > 0) {
      await ProfileStore.setCurrentId(context, profiles[0].id);
    }
    await this.reload();
    const verb = replace ? 'Replaced with' : 'Imported';
    promptAction.showToast({ message: `${verb} ${imported.length} profile(s)` });
  }

  private async importFromText(text: string, source: string): Promise<void> {
    try {
      await this.importText(text, source);
    } catch (e) {
      this.reportFailure('Import', e as Object);
    }
  }

  private async importFromFile(replace: boolean): Promise<void> {
    try {
      const text = await pickTextFile(abilityContext());
      if (text.length === 0) {
        return; // the user cancelled
      }
      await this.importText(text, 'the file', replace);
    } catch (e) {
      this.reportFailure('Import', e as Object);
    }
  }

  private async importFromClipboard(): Promise<void> {
    try {
      const text = await readClipboard();
      if (text.trim().length === 0) {
        promptAction.showToast({ message: 'The clipboard is empty' });
        return;
      }
      await this.importText(text, 'the clipboard');
    } catch (e) {
      this.reportFailure('Import', e as Object);
    }
  }

  private async exportToFile(): Promise<void> {
    try {
      const text = exportProfiles(this.profiles);
      const uri = await saveTextFile(abilityContext(), EXPORT_FILE_NAME, text);
      if (uri.length === 0) {
        return; // the user cancelled
      }
      promptAction.showToast({ message: `Exported ${this.profiles.length} profile(s)` });
    } catch (e) {
      this.reportFailure('Export', e as Object);
    }
  }

  private async copyToClipboard(): Promise<void> {
    try {
      await writeClipboard(exportProfiles(this.profiles));
      promptAction.showToast({ message: `Copied ${this.profiles.length} profile(s)` });
    } catch (e) {
      this.reportFailure('Copy', e as Object);
    }
  }

  /** True while an extension is believed to exist, so the button reads Disconnect. */
  private isUp(): boolean {
    return this.proxyUp || this.phase === PHASE_CONNECTING || this.phase === PHASE_VERIFYING ||
      this.phase === PHASE_CONNECTED || this.phase === PHASE_PROBE_FAILED;
  }

  private async connect(): Promise<void> {
    const profile = this.currentProfile();
    if (profile === null || profile.host.length === 0 || profile.password.length === 0) {
      promptAction.showToast({ message: 'Please add and select a profile first' });
      return;
    }
    if ((this.settings?.serviceMode ?? '') === MODE_PROXY) {
      await this.connectProxy(profile);
      return;
    }
    // Enter the connecting phase *before* awaiting: starting the extension can
    // block on the system consent dialog for as long as the user takes to
    // answer, and the page must not look idle meanwhile. Note that this says
    // nothing about whether the tunnel will actually come up — that is decided
    // by the status file and the probe below.
    this.phase = PHASE_CONNECTING;
    this.failReason = '';
    this.probeRttMs = 0;
    this.mbps = 0;
    this.probeSeq += 1;
    this.connectingSince = Date.now();
    this.startHealthPolling();

    // The public emulator image ships no system consent app
    // (com.huawei.hmos.vpndialog), so startVpnExtensionAbility cannot obtain
    // authorization the usual way there. Grant it up front through the
    // module's own updateVpnAuthorizedState (the same settingsdata write the
    // consent app performs). On retail devices the write is either ignored or
    // rejected and the normal consent dialog still shows; the retry below
    // covers runtimes where the first start already failed before the grant.
    const ret = grantVpnAuthorization(VPN_ABILITY.bundleName ?? '');
    hilog.info(0x0000, TAG, 'updateVpnAuthorizedState ret %{public}d', ret);
    try {
      await vpnExtension.startVpnExtensionAbility(VPN_ABILITY);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'vpn start rejected (%{public}s), retrying after self-grant',
        JSON.stringify(e));
      try {
        grantVpnAuthorization(VPN_ABILITY.bundleName ?? '');
        await vpnExtension.startVpnExtensionAbility(VPN_ABILITY);
      } catch (e2) {
        hilog.error(0x0000, TAG, 'vpn start failed: %{public}s', JSON.stringify(e2));
        this.phase = PHASE_FAILED;
        this.failReason = 'Could not start the VPN extension';
        this.stopHealthPolling();
        promptAction.showToast({ message: `Failed to start VPN: ${JSON.stringify(e2)}` });
        return;
      }
    }
    // Deliberately no `phase = CONNECTED` here — the health poll takes over.
  }

  /**
   * Proxy mode: the core serves SOCKS5 in this process and nothing is routed.
   * There is no consent dialog and no separate process, so this is the whole of
   * it — and the status is this page's own state rather than the extension's
   * file, since the extension is not involved.
   */
  private async connectProxy(profile: Profile): Promise<void> {
    const settings = this.settings ?? await SettingsStore.load(abilityContext());
    this.phase = PHASE_CONNECTING;
    this.failReason = '';
    this.probeSeq += 1;
    try {
      await ProxyService.start(abilityContext(), profile, settings.proxyPort, settings.shareOverLan);
      this.proxyUp = true;
      const host = settings.shareOverLan ? 'this device' : '127.0.0.1';
      this.phase = PHASE_CONNECTED;
      this.runningSince = Date.now();
      promptAction.showToast({
        message: `Proxy on ${host}:${settings.proxyPort}`,
      });
    } catch (e) {
      const err = e as BusinessError;
      this.phase = PHASE_FAILED;
      this.failReason = `Could not start the proxy: ${err.message ?? String(e)}`;
      this.proxyUp = false;
    }
  }

  private async disconnect(): Promise<void> {
    // abandon any probe still in flight so its verdict cannot land afterwards
    this.probeSeq += 1;
    if (this.proxyUp) {
      await ProxyService.stop(abilityContext());
      this.proxyUp = false;
      this.phase = PHASE_IDLE;
      this.failReason = '';
      this.runningSince = 0;
      this.stopHealthPolling();
      return;
    }
    try {
      await vpnExtension.stopVpnExtensionAbility(VPN_ABILITY);
    } catch (e) {
      // the extension may already be gone; report but still leave the UI
      // in the disconnected state rather than rejecting into the click handler
      hilog.warn(0x0000, TAG, 'vpn stop failed: %{public}s', JSON.stringify(e));
      promptAction.showToast({ message: `Failed to stop VPN: ${JSON.stringify(e)}` });
    } finally {
      this.phase = PHASE_IDLE;
      this.failReason = '';
      this.probeRttMs = 0;
      this.runningSince = 0;
      this.stopHealthPolling();
    }
  }

  private startHealthPolling(): void {
    this.stopHealthPolling();
    this.lastStats = null;
    this.runningSince = 0;
    this.txTotal = 0;
    this.rxTotal = 0;
    this.txRate = 0;
    this.rxRate = 0;
    this.healthTimer = setInterval(async () => {
      if (this.polling) {
        return;
      }
      this.polling = true;
      try {
        await this.pollTick();
      } finally {
        this.polling = false;
      }
    }, STATS_POLL_INTERVAL_MS);
  }

  private stopHealthPolling(): void {
    if (this.healthTimer >= 0) {
      clearInterval(this.healthTimer);
      this.healthTimer = -1;
    }
  }

  /** One poll: refresh the traffic rates, then advance the connection phase. */
  private async pollTick(): Promise<void> {
    const context = abilityContext();

    const stats = await TrafficStatsStore.load(context);
    if (stats !== null) {
      const last = this.lastStats;
      if (last !== null && stats.timestamp > last.timestamp) {
        const deltaSec = (stats.timestamp - last.timestamp) / 1000;
        this.txRate = Math.max(0, Math.round((stats.tx - last.tx) / deltaSec));
        this.rxRate = Math.max(0, Math.round((stats.rx - last.rx) / deltaSec));
      }
      this.lastStats = stats;
      this.txTotal = stats.tx;
      this.rxTotal = stats.rx;
    }

    const status = await VpnStatusStore.load(context);
    if (status === null) {
      // nothing written yet; only give up once the start has had its budget
      if (this.phase === PHASE_CONNECTING &&
        (Date.now() - this.connectingSince) > CONNECT_TIMEOUT_MS) {
        this.phase = PHASE_FAILED;
        this.failReason = 'Timed out starting the VPN';
        this.stopHealthPolling();
      }
      return;
    }
    this.lastStatus = status;

    if (status.state === VPN_STATE_FAILED) {
      this.phase = PHASE_FAILED;
      this.failReason = status.reason.length > 0 ? status.reason : status.detail;
      this.stopHealthPolling();
      return;
    }
    if (status.state === VPN_STATE_STOPPED) {
      // stopped from outside this page (system teardown)
      this.phase = PHASE_IDLE;
      this.failReason = '';
      this.stopHealthPolling();
      return;
    }
    if (status.state !== VPN_STATE_RUNNING) {
      return;
    }
    if (this.runningSince === 0) {
      this.runningSince = status.timestamp;
    }

    // The status file only changes on transitions, so liveness comes from the
    // traffic counters: the core reports every 500 ms while it lives. Two
    // failure shapes have to be caught — samples that stopped arriving, and
    // samples that never arrived at all (the core never got going, so there is
    // no stale timestamp to compare against and only the elapsed time tells us).
    if (stats !== null) {
      if (isStale(stats.timestamp, Date.now(), STATS_STALE_MS)) {
        this.phase = PHASE_PROBE_FAILED;
        this.failReason = 'Connection lost';
        return;
      }
    } else if (this.runningSince > 0 &&
      (Date.now() - this.runningSince) > STATS_STALE_MS) {
      this.phase = PHASE_PROBE_FAILED;
      this.failReason = 'The tunnel started, but the core is not reporting traffic';
      return;
    }
    if (this.phase === PHASE_CONNECTING || this.phase === PHASE_IDLE) {
      this.runProbe(false);
    }
  }

  /**
   * Fetches the probe URL and decides what it means.
   *
   * The fetch alone does not prove the tunnel works — under `gfwlist` and
   * `china-list` the destination is reached directly by design, and a device
   * with working internet would answer even with the tunnel dead. So the core's
   * receive counter is sampled either side of the fetch and the two are weighed
   * together (Diagnostics.interpretProbe).
   */
  private async runProbe(manual: boolean): Promise<void> {
    if (this.probeInFlight) {
      return;
    }
    const status = this.lastStatus;
    if (status === null || status.state !== VPN_STATE_RUNNING) {
      if (manual) {
        promptAction.showToast({ message: 'Not connected' });
      }
      return;
    }
    this.probeInFlight = true;
    this.probeRunning = true;
    const seq = ++this.probeSeq;
    this.phase = PHASE_VERIFYING;
    this.failReason = '';
    try {
      const settings = this.settings ?? await SettingsStore.load(abilityContext());
      const before = await TrafficStatsStore.load(abilityContext());
      const outcome = await probeThroughTunnel(settings.probeUrl, PROBE_TIMEOUT_MS);
      // let the core's 500 ms report and the extension's 1 s save land before
      // sampling the counters again
      await new Promise<void>((resolve) => setTimeout(resolve, STATS_SETTLE_MS));
      const after = await TrafficStatsStore.load(abilityContext());
      if (seq !== this.probeSeq) {
        return;
      }
      const route = this.currentProfile()?.route ?? '';
      const verdict = interpretProbe(outcome.ok, outcome.httpCode,
        before?.rx ?? 0, after?.rx ?? 0, before !== null && after !== null,
        routeProxiesByDefault(route), outcome.reason);
      if (verdict.verdict === PROBE_OK) {
        this.phase = PHASE_CONNECTED;
        this.probeRttMs = outcome.rttMs;
        this.failReason = '';
        if (manual) {
          promptAction.showToast({ message: `Connected · ${formatRtt(outcome.rttMs)}` });
        }
      } else {
        this.phase = PHASE_PROBE_FAILED;
        this.failReason = verdict.reason;
        this.probeRttMs = 0;
        if (manual) {
          promptAction.showToast({ message: `Test failed: ${verdict.reason}` });
        }
      }
    } finally {
      if (seq === this.probeSeq) {
        this.probeRunning = false;
      }
      this.probeInFlight = false;
    }
  }

  private async runSpeedTest(): Promise<void> {
    if (this.speedRunning) {
      return;
    }
    this.speedRunning = true;
    this.mbps = 0;
    try {
      const settings = this.settings ?? await SettingsStore.load(abilityContext());
      const result = await measureThroughput(settings.speedTestUrl, SPEED_TIMEOUT_MS);
      this.mbps = result.ok ? result.mbps : 0;
      promptAction.showToast({
        message: result.ok
          ? `↓ ${formatMbps(result.mbps)} (${formatBytes(result.bytes)})`
          : `Speed test failed: ${result.reason}`,
      });
    } finally {
      this.speedRunning = false;
    }
  }

  private async measureProfileLatency(profile: Profile): Promise<void> {
    if (this.measuringId.length > 0) {
      return;
    }
    this.measuringId = profile.id;
    const pending: LatencyEntry = { ok: false, ms: 0, detail: 'pending' };
    this.setLatency(profile.id, pending);
    try {
      const entry = await measureLatency(profile.host, profile.remotePort, LATENCY_TIMEOUT_MS);
      this.setLatency(profile.id, entry);
    } catch (e) {
      const failed: LatencyEntry = { ok: false, ms: 0, detail: 'failed' };
      this.setLatency(profile.id, failed);
    } finally {
      this.measuringId = '';
    }
  }

  /**
   * Replaces the whole map: ArkUI does not observe mutation of a @State
   * collection in place, so `this.latencies.set(...)` alone would not repaint.
   */
  private setLatency(id: string, entry: LatencyEntry): void {
    const next = new Map<string, LatencyEntry>(this.latencies);
    next.set(id, entry);
    this.latencies = next;
  }

  private latencyFor(id: string): LatencyEntry | null {
    const entry = this.latencies.get(id);
    return entry === undefined ? null : entry;
  }

  private latencyColor(id: string): ResourceColor {
    const entry = this.latencies.get(id);
    if (entry === undefined || entry.detail === 'pending') {
      return $r('app.color.text_secondary');
    }
    return entry.ok ? $r('app.color.success') : $r('app.color.error');
  }

  private statusText(): string {
    switch (this.phase) {
      case PHASE_CONNECTING:
        return 'Connecting…';
      case PHASE_VERIFYING:
        return 'Verifying the tunnel…';
      case PHASE_CONNECTED:
        return `Connected${this.probeRttMs > 0 ? ` · ${formatRtt(this.probeRttMs)}` : ''}`;
      case PHASE_PROBE_FAILED:
        return this.failReason.length > 0 ? this.failReason : 'Tunnel up, but no internet';
      case PHASE_FAILED:
        return this.failReason.length > 0 ? `Failed: ${this.failReason}` : 'Failed';
      default:
        return this.currentProfile() !== null ?
          `${this.currentProfile()!.name} · ${this.currentProfile()!.route}` :
          'No profile selected';
    }
  }

  private statusColor(): ResourceColor {
    switch (this.phase) {
      case PHASE_CONNECTING:
      case PHASE_VERIFYING:
        return $r('app.color.accent');
      case PHASE_CONNECTED:
        return $r('app.color.success');
      case PHASE_PROBE_FAILED:
        return $r('app.color.warning');
      case PHASE_FAILED:
        return $r('app.color.error');
      default:
        return $r('app.color.text_secondary');
    }
  }

  @Builder
  ProfileItem(profile: Profile) {
    Row() {
      Column({ space: 4 }) {
        Text(profile.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(`${profile.host}:${profile.remotePort}  ${profile.method}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.latencyFor(profile.id) !== null) {
            Text(formatLatency(this.latencyFor(profile.id)))
              .fontSize(12)
              .fontColor(this.latencyColor(profile.id))
          }
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (profile.id === this.currentId) {
        Text('✓')
          .fontSize(18)
          .fontColor($r('app.color.success'))
          .margin({ right: 8 })
      }
      Text(this.measuringId === profile.id ? '…' : 'Test')
        .fontSize(14)
        .fontColor($r('app.color.accent'))
        .margin({ right: 12 })
        .onClick(() => this.measureProfileLatency(profile))
      Text('Edit')
        .fontSize(14)
        .fontColor($r('app.color.accent'))
        .margin({ right: 12 })
        .onClick(() => {
          router.pushUrl({
            url: 'pages/ProfileEdit',
            params: { id: profile.id } as EditParams,
          });
        })
      Text('✕')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => this.removeProfile(profile))
    }
    .width('100%')
    .padding(12)
    .borderRadius(8)
    .backgroundColor(profile.id === this.currentId ? $r('app.color.surface_selected') : $r('app.color.surface'))
    .onClick(() => this.selectProfile(profile))
  }

  @Builder
  AddMenu() {
    Menu() {
      MenuItem({ content: 'Add manually' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/ProfileEdit' });
        })
      MenuItem({ content: 'Import ss:// URL' })
        .onClick(() => this.importDialog.open())
      MenuItem({ content: 'Paste from clipboard' })
        .onClick(() => this.importFromClipboard())
      MenuItem({ content: 'Import from file' })
        .onClick(() => this.importFromFile(false))
      MenuItem({ content: 'Replace from file' })
        .onClick(() => this.replaceDialog.open())
      MenuItem({ content: 'Export to file' })
        .onClick(() => this.exportToFile())
      MenuItem({ content: 'Copy to clipboard' })
        .onClick(() => this.copyToClipboard())
      MenuItem({ content: 'Subscriptions' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/Subscription' });
        })
    }
  }

  build() {
    Column() {
      // title bar
      Row() {
        Text('Shadowsocks')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Text('⚙')
          .fontSize(22)
          .fontColor($r('app.color.accent'))
          .margin({ right: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
        Text('＋')
          .fontSize(28)
          .fontColor($r('app.color.accent'))
          .bindMenu(this.AddMenu())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      // the filter, hidden while there is nothing to filter
      if (this.profiles.length > 1) {
        TextInput({ placeholder: 'Search profiles', text: this.search })
          .onChange((value) => this.search = value)
          .margin({ left: 16, right: 16, bottom: 8 })
      }

      // profile list
      List({ space: 8 }) {
        ForEach(this.shown(), (profile: Profile) => {
          ListItem() {
            this.ProfileItem(profile)
          }
        }, (profile: Profile) => profile.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })
      // long-press an entry to drag it; the order is kept in the store
      .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
        this.dragFrom = itemIndex;
      })
      .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
        if (isSuccess) {
          this.dropProfile(insertIndex);
        }
      })

      // status + stats bar
      Column({ space: 4 }) {
        Text(this.statusText())
          .fontSize(13)
          .fontColor(this.statusColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.phase === PHASE_CONNECTED || this.phase === PHASE_PROBE_FAILED) {
          Text(`↑ ${formatRate(this.txRate)} (${formatBytes(this.txTotal)})   ` +
            `↓ ${formatRate(this.rxRate)} (${formatBytes(this.rxTotal)})`)
            .fontSize(13)
            .fontColor($r('app.color.success'))
        }
        if (this.mbps > 0) {
          Text(`↓ ${formatMbps(this.mbps)}`)
            .fontSize(13)
            .fontColor($r('app.color.success'))
        }
        Button(this.isUp() ? 'Disconnect' : 'Connect')
          .width('100%')
          .height(48)
          .backgroundColor(this.isUp() ? $r('app.color.error') : $r('app.color.accent'))
          .onClick(() => {
            if (this.isUp()) {
              this.disconnect();
            } else {
              this.connect();
            }
          })
        Row({ space: 12 }) {
          Button(this.probeRunning ? 'Testing…' : 'Test connection')
            .fontSize(14)
            .height(38)
            .layoutWeight(1)
            .backgroundColor($r('app.color.accent'))
            .enabled(!this.probeRunning &&
              (this.phase === PHASE_CONNECTED || this.phase === PHASE_PROBE_FAILED))
            .onClick(() => this.runProbe(true))
          Button(this.speedRunning ? 'Testing…' : 'Speed test')
            .fontSize(14)
            .height(38)
            .layoutWeight(1)
            .backgroundColor($r('app.color.accent'))
            .enabled(!this.speedRunning &&
              (this.phase === PHASE_CONNECTED || this.phase === PHASE_PROBE_FAILED))
            .onClick(() => this.runSpeedTest())
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}

/** Confirmation for an action that cannot be undone. */
@CustomDialog
struct ConfirmDialog {
  controller: CustomDialogController;
  title: string = '';
  message: string = '';
  confirmLabel: string = 'OK';
  onConfirm: () => void = () => {
  };

  build() {
    Column({ space: 12 }) {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
      Text(this.message)
        .fontSize(14)
        .fontColor($r('app.color.text_body'))
      Row({ space: 12 }) {
        Button('Cancel')
          .backgroundColor($r('app.color.button_neutral'))
          .layoutWeight(1)
          .onClick(() => this.controller.close())
        Button(this.confirmLabel)
          .layoutWeight(1)
          .onClick(() => {
            this.onConfirm();
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(20)
  }
}

/** Router params for the profile edit page. */
export interface EditParams {
  id?: string;
}

@CustomDialog
struct ImportDialog {
  controller: CustomDialogController;
  onConfirm: (url: string) => void = () => {
  };
  @State url: string = '';

  build() {
    Column({ space: 12 }) {
      Text('Import ss:// URL')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
      TextInput({ placeholder: 'ss://…', text: this.url })
        .onChange((value) => this.url = value)
      Row({ space: 12 }) {
        Button('Cancel')
          .backgroundColor($r('app.color.button_neutral'))
          .layoutWeight(1)
          .onClick(() => this.controller.close())
        Button('Import')
          .layoutWeight(1)
          .onClick(() => {
            this.onConfirm(this.url);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(20)
  }
}
