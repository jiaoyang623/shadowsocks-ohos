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
import { promptAction, router, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyCode } from '@kit.InputKit';
import { Profile, newManualProfile } from '../model/Profile';
import { ProfileStore } from '../model/ProfileStore';
import {
  applyImport, collectProfiles, exportProfiles, exportProfileUrls, parseProfilesText,
} from '../model/ProfilesFile';
import {
  EXPORT_FILE_NAME, pickTextFiles, readClipboard, readTextFile, saveTextFile, writeClipboard,
} from '../model/Transfer';
import { abilityContext, takePendingImport } from '../model/AppContext';
import {
  activeProfileIds, AppSettings, CONNECT_TIMEOUT_MS, DEFAULT_PROXY_PORT, formatRtt,
  interpretProbe, isEnabled, isProfileEditable, isStale, MODE_PROXY,
  MODE_VPN, PHASE_CONNECTED, PHASE_CONNECTING, PHASE_FAILED, PHASE_IDLE, PHASE_PROBE_FAILED,
  PHASE_STOPPING, PHASE_VERIFYING, portNumber, PROBE_OK, routeProxiesByDefault, STATS_SETTLE_MS,
  STATS_STALE_MS, summarizeStatus, VpnStatus, VPN_STATE_FAILED, VPN_STATE_RUNNING,
  VPN_STATE_STARTING, VPN_STATE_STOPPED,
} from '../model/Diagnostics';
import {
  applyTunnelVerdict, classifyTest, DRAWER_ABOUT, DRAWER_CUSTOM_RULES,
  DRAWER_ENTRIES, DRAWER_FAQ, DRAWER_PROFILES, DRAWER_SETTINGS, DRAWER_SUBSCRIPTIONS,
  defaultDrawerSelection,
  DrawerEntry, drawerClosesAfter, drawerNavigatesAfter, drawerSelectionAfter, FAB_MARGIN_VP,
  failureText, FAQ_URL, formatStats, keyboardToggle, modeChanged, RING_DELAY_MS, RING_FILL_MS,
  SNACKBAR_DURATION_MS, serviceButtonChecked, serviceButtonEnabled, serviceButtonGlyph,
  serviceButtonLabelKey, serviceButtonTap, statsHiddenAfterScroll, statsResetRequired,
  statsStatusKind, statsTapAction, statsVisible, StatsText, TEST_ERROR, TEST_IDLE, TEST_KIND_HTTP,
  TEST_KIND_NETWORK, TEST_KIND_SUCCESS, TEST_KIND_TUNNEL, TEST_SUCCESS, TEST_TESTING,
  testStatusAfterConnection,
} from '../model/MainShell';
import { UndoBin, UNDO_TIMEOUT_MS } from '../model/UndoRemoval';
import {
  formatTraffic, liveCounters, TrafficStats, TrafficStatsStore, withLive,
} from '../model/TrafficStats';
import { VpnStatusStore } from '../model/VpnStatus';
import { PROBE_TIMEOUT_MS, probeThroughTunnel } from '../model/ConnectivityProbe';
import { SettingsStore } from '../model/Settings';
import { settleSessionTraffic } from '../model/SessionTraffic';
import { ProxyService } from '../model/ProxyService';
import { ALL_ROUTES } from '../model/Routes';
import { ensureEnabled } from '../model/ConnectionNotification';
import { profilesFromScan, profilesFromScanTexts } from '../model/QrImport';
import { decodeQrImages, pickQrImages, scanWithSystemUi } from '../model/QrScanner';
import { grantVpnAuthorization } from './VpnGrant';
import { ShareQrDialog } from './QrDialog';

const TAG = 'Index';

const VPN_ABILITY: Want = {
  deviceId: '',
  bundleName: 'com.xbt.project',
  abilityName: 'SsVpnExtensionAbility',
};

const STATS_POLL_INTERVAL_MS = 1000;

/**
 * The route names as a user reads them, in the order of ALL_ROUTES. The
 * compiler checks `$r` names, so this is a list of literals rather than a
 * loop over the route constants.
 */
export const ROUTE_LABELS: Resource[] = [
  $r('app.string.route_all'),
  $r('app.string.route_bypass_lan'),
  $r('app.string.route_bypass_china'),
  $r('app.string.route_bypass_lan_china'),
  $r('app.string.route_gfwlist'),
  $r('app.string.route_china_list'),
  $r('app.string.route_custom_rules'),
];

/** The name of a route, for a line that has only its identifier. */
export function routeLabel(route: string): Resource {
  const index = ALL_ROUTES.indexOf(route);
  return ROUTE_LABELS[index >= 0 ? index : 0];
}

/**
 * Main page: the profile list, the navigation drawer and the service controls,
 * mirroring shadowsocks-android's main screen.
 *
 * "Connected" here is not taken on faith. Starting the extension ability only
 * proves the ability was launched. Its own setup can still fail afterwards, and
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
  @State @Watch('onPhaseChanged') phase: string = PHASE_IDLE;
  @State failReason: string = '';
  @State probeRttMs: number = 0;
  @State txTotal: number = 0;
  @State rxTotal: number = 0;
  @State txRate: number = 0;
  @State rxRate: number = 0;
  @State search: string = '';
  /** True while the search field is open. Android opens it from the menu. */
  @State searchOpen: boolean = false;
  /** The profile ids whose rows are hidden and whose delete is not committed. */
  @State pendingIds: string[] = [];
  /** The URI and name the shared QR dialog shows. */
  @State shareUrl: string = '';
  @State shareName: string = '';
  /** True while one scan or image batch runs. */
  @State scanning: boolean = false;
  /**
   * Set while proxy mode is serving from this process. The VPN extension is not
   * involved in that mode, so its status file says nothing about it.
   */
  @State proxyUp: boolean = false;

  /* ---- main shell state ---- */
  @StorageLink('drawer_open') drawerOpen: boolean = false;
  @State drawerSelected: string = DRAWER_PROFILES;
  @State testStatus: string = TEST_IDLE;
  @State testMessage: string = '';
  @State testElapsedMs: number = 0;
  @State statsHiddenByScroll: boolean = false;
  @State statsBarShown: boolean = false;
  @State snackbar: string = '';
  @State bottomInsetVp: number = 0;
  @State ringMode: string = 'hidden';
  @State ringValue: number = 0;

  private healthTimer: number = -1;
  private snackbarTimer: number = -1;
  private ringTimer: number = -1;
  private undoTimer: number = -1;
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
  /** Index a drag started from, so the drop knows what to move. */
  private dragFrom: number = -1;
  /** True after the first row crossover of one drag. */
  private dragFlushed: boolean = false;
  /** The mode that is up: MODE_VPN, MODE_PROXY, or '' while stopped. */
  private runningMode: string = '';
  /** The phase before the current one, for the counter reset decision. */
  private lastPhase: string = PHASE_IDLE;
  /** The failure text the snackbar last showed. */
  private lastFailureShown: string = '';
  private pageStarted: boolean = true;
  /** False once the component is gone, so no timer or resume touches it. */
  private pageAlive: boolean = false;
  private swipeFromEdge: boolean = false;
  /** The profile proxy mode started, for the live counter. */
  private proxyProfileId: string = '';
  private undo: UndoBin = new UndoBin();
  private scroller: Scroller = new Scroller();

  private importDialog: CustomDialogController = new CustomDialogController({
    builder: ImportDialog({
      onConfirm: (text: string) => this.importTypedUrl(text),
    }),
    autoCancel: true,
  });
  // Replacing throws away every profile that is not in the file, so it asks
  // first. Importing does not, which is why only this one is confirmed.
  private replaceDialog: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: $r('app.string.index_replace_all_profiles'),
      message: $r('app.string.index_replace_all_profiles_message'),
      confirmLabel: $r('app.string.common_replace'),
      onConfirm: () => this.importFromFiles(true),
    }),
    autoCancel: true,
  });
  /**
   * The QR dialog is rebuilt for each profile. A builder captures the values it
   * reads when it is built, and the shared controller would otherwise show the
   * first profile for every later tap.
   */
  private qrDialog: CustomDialogController | null = null;

  /**
   * A profile link the app was launched with. The page is already on screen by
   * the time a link opened from elsewhere arrives, so the value is watched
   * rather than read once.
   */
  @StorageLink('pending_import_uri') @Watch('onPendingImport') pendingImport: string = '';

  aboutToAppear(): void {
    this.pageAlive = true;
    this.reloadThenScroll();
    this.resumeStatus();
    // a cold start carries the link in the want, before this page existed
    this.onPendingImport();
    this.drawerSelected = defaultDrawerSelection();
    this.readBottomInset();
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
    // the poll timer outlives the page otherwise, and keeps reading the
    // stats file (and touching @State) after the component is gone
    this.stopHealthPolling();
    this.clearSnackbar();
    this.clearRingTimer();
    this.stopUndoTimer();
    // the page is gone, so the commit must not try to reload it
    this.commitRemovals(false);
  }

  onPageShow(): void {
    // returning from the edit/subscription/settings page may have changed the
    // list and the endpoints
    this.reloadThenScroll();
    this.pageStarted = true;
    this.drawerSelected = defaultDrawerSelection();
    this.reconcileServiceMode().catch((e: Object) => {
      hilog.warn(0x0000, TAG, 'mode reconcile failed: %{public}s', JSON.stringify(e));
    });
    if (this.phase === PHASE_CONNECTING &&
      (Date.now() - this.connectingSince) >= RING_DELAY_MS) {
      this.ringMode = 'indeterminate';
    }
    // Re-check for a VPN that is already up. FAILED counts: the system consent
    // dialog can outlast this page's start timeout, and the extension comes up
    // afterwards, leaving the page showing a failure over a working tunnel
    // until something else re-syncs it.
    if (this.phase === PHASE_IDLE || this.phase === PHASE_FAILED) {
      this.resumeStatus();
    }
  }

  onPageHide(): void {
    this.pageStarted = false;
  }

  /** The drawer closes first, as Android's back press does. */
  onBackPress(): boolean {
    if (this.drawerOpen) {
      this.drawerOpen = false;
      return true;
    }
    return false;
  }

  private onPendingImport(): void {
    const uri = takePendingImport();
    if (uri.length === 0) {
      return;
    }
    // A link from a browser adds an unasked-for profile, so it is confirmed
    // first, as Android's UrlImportActivity does. On a cold start this runs
    // from aboutToAppear, before the page can raise a dialog, so the question
    // waits for the next tick.
    setTimeout(() => {
      this.confirmLinkImport(uri);
    }, 0);
  }

  /**
   * A resource as the text it stands for. Needed where a message is put
   * together in code: a component formats `$r` itself, and a template
   * literal cannot take a Resource. The parameters go with the id, so a
   * formatted resource keeps its values.
   */
  private text(value: ResourceStr): string {
    if (typeof value === 'string') {
      return value;
    }
    const params: Array<string | number> | undefined = value.params;
    if (params === undefined) {
      return abilityContext().resourceManager.getStringSync(value.id);
    }
    const args: string[] = [];
    for (const param of params) {
      args.push(`${param}`);
    }
    return abilityContext().resourceManager.getStringSync(value.id, ...args);
  }

  /**
   * A failure the user did not ask to see. `what` is the app.string of the
   * operation, so that it is named in the language the app is speaking.
   */
  private reportFailure(what: Resource, e: Object): void {
    const label = this.text(what);
    hilog.error(0x0000, TAG, '%{public}s failed: %{public}s', label, JSON.stringify(e));
    promptAction.showToast({ message: $r('app.string.index_op_failed', label) });
  }

  private showMessage(message: ResourceStr): void {
    promptAction.showToast({ message: message });
  }

  /** The message of an error, or the text of any other thrown value. */
  private readableMessage(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }

  private async reload(): Promise<void> {
    const context = abilityContext();
    // an empty list is repopulated with one blank profile, as Android does, so
    // that the list and the connect button always have something to act on
    await ProfileStore.ensureNotEmpty(context);
    // what a subscription no longer lists is kept but not shown
    this.profiles = ProfileStore.visible(await ProfileStore.getAll(context));
    this.currentId = await ProfileStore.getCurrentId(context);
    this.settings = await SettingsStore.load(context);
  }

  private reloadThenScroll(): void {
    this.reload().then(() => {
      setTimeout(() => {
        this.scrollToSelected();
      }, 0);
    }).catch((e: Object) => {
      hilog.warn(0x0000, TAG, 'reload failed: %{public}s', JSON.stringify(e));
    });
  }

  /** Brings the selected row into view after the list has rendered. */
  private scrollToSelected(): void {
    const index = ProfileStore.indexOf(this.shown(), this.currentId);
    if (index >= 0) {
      this.scroller.scrollToIndex(index, true);
    }
  }

  /** The rows to render: the stored profiles, less the filter and the pending. */
  private shown(): Profile[] {
    return ProfileStore.filter(this.profiles, this.search, this.pendingIds);
  }

  /**
   * The key of one row. The key holds every value the row shows, the edit gate,
   * and the selected flag. A ForEach reuses a cached child when its key is
   * unchanged and does not re-run the item builder, so a key of the id alone
   * would freeze the numbers, the dimmed icon and the swipe action.
   */
  private rowKey(profile: Profile): string {
    return [
      profile.id,
      profile.name,
      profile.host,
      `${profile.remotePort}`,
      profile.plugin,
      `${profile.subscriptionStatus}`,
      `${this.profileTx(profile)}`,
      `${this.profileRx(profile)}`,
      `${this.isRowEditable(profile)}`,
      `${profile.id === this.currentId}`,
    ].join('|');
  }

  /* ---- drawer ---- */

  private drawerLabel(id: string): Resource {
    switch (id) {
      case DRAWER_PROFILES:
        return $r('app.string.drawer_profiles');
      case DRAWER_SUBSCRIPTIONS:
        return $r('app.string.drawer_subscriptions');
      case DRAWER_CUSTOM_RULES:
        return $r('app.string.drawer_custom_rules');
      case DRAWER_SETTINGS:
        return $r('app.string.drawer_settings');
      case DRAWER_ABOUT:
        return $r('app.string.drawer_about');
      default:
        return $r('app.string.drawer_faq');
    }
  }

  /** The drawer icon of one entry, matching Android's navigation icons. */
  private drawerIcon(id: string): Resource {    switch (id) {
      case DRAWER_SUBSCRIPTIONS:
        return $r('sys.symbol.cloud_and_arrow_down');
      case DRAWER_CUSTOM_RULES:
        return $r('sys.symbol.checkmark_clipboard');
      case DRAWER_SETTINGS:
        return $r('sys.symbol.gearshape');
      case DRAWER_FAQ:
        return $r('sys.symbol.questionmark_circle');
      case DRAWER_ABOUT:
        return $r('sys.symbol.info_circle');
      default:
        return $r('sys.symbol.doc_text');
    }
  }

  /** The tint of one drawer entry: primary for the checked item. */
  private drawerItemColor(entry: DrawerEntry): ResourceColor {
    return entry.checkable && entry.id === this.drawerSelected
      ? $r('app.color.main_drawer_selected')
      : $r('app.color.text_body');
  }

  private onDrawerSelect(entry: DrawerEntry): void {
    if (!entry.checkable) {
      this.openFaq();
      return;
    }
    const navigates = drawerNavigatesAfter(this.drawerSelected, entry.id);
    this.drawerSelected = drawerSelectionAfter(this.drawerSelected, entry.id);
    if (drawerClosesAfter(this.drawerSelected, entry.id)) {
      this.drawerOpen = false;
    }
    if (!navigates) {
      return;
    }
    switch (entry.id) {
      case DRAWER_SUBSCRIPTIONS:
        router.pushUrl({ url: 'pages/Subscription' });
        break;
      case DRAWER_CUSTOM_RULES:
        router.pushUrl({ url: 'pages/CustomRules' });
        break;
      case DRAWER_SETTINGS:
        router.pushUrl({ url: 'pages/Settings' });
        break;
      case DRAWER_ABOUT:
        router.pushUrl({ url: 'pages/About' });
        break;
      default:
        // Profiles is the page itself
        break;
    }
  }

  /** Opens the FAQ in a browser. A failure keeps the drawer open. */
  private openFaq(): void {
    abilityContext().openLink(FAQ_URL).catch((e: Object) => {
      hilog.warn(0x0000, TAG, 'faq link failed: %{public}s', JSON.stringify(e));
      this.showSnackbar(this.text($r('app.string.drawer_faq_failed', FAQ_URL)));
    });
  }

  /* ---- profile rows ---- */

  /**
   * The profile this page has selected, or null.
   *
   * Strict: an id that names no visible row has no profile. Falling back to
   * the first row would connect a server the user did not select, which is
   * what a stale selection would otherwise do.
   */
  private currentProfile(): Profile | null {
    return this.profiles.find((p) => p.id === this.currentId) ?? null;
  }

  private isRowEditable(profile: Profile): boolean {
    return isProfileEditable(this.phase,
      activeProfileIds(this.profiles, this.currentId), profile.id);
  }

  private async selectProfile(profile: Profile): Promise<void> {
    if (!isEnabled(this.phase)) {
      return;
    }
    const wasUp = this.isUp();
    this.currentId = profile.id;
    try {
      await ProfileStore.setCurrentId(abilityContext(), profile.id);
    } catch (e) {
      this.reportFailure($r('app.string.index_op_select_profile'), e as Object);
      return;
    }
    if (wasUp) {
      await this.reloadTunnel();
    }
  }

  /**
   * Moves a dragged profile, which is the order the store keeps and the list
   * shows. Dragging is refused while a filter is on: the indices the list
   * reports are then positions in the filtered view, and moving by them would
   * put the profile somewhere the user did not point at.
   */
  private async dropProfile(insertIndex: number): Promise<void> {
    if (!isEnabled(this.phase)) {
      return;
    }
    const from = this.dragFrom;
    this.dragFrom = -1;
    if (from < 0 || this.search.trim().length > 0 || from === insertIndex) {
      return;
    }
    try {
      await ProfileStore.move(abilityContext(), from, insertIndex);
    } catch (e) {
      this.reportFailure($r('app.string.index_op_reorder'), e as Object);
    }
    await this.reload();
  }

  /**
   * Opens the editor for a stored profile. A row whose profile was removed in
   * another process reloads the list and reports that nothing opened. A failed
   * read or navigation reports itself, so the tap never does nothing.
   */
  private async openEditor(profile: Profile): Promise<void> {
    try {
      const stored = await ProfileStore.getAllOrNull(abilityContext());
      if (stored === null) {
        this.showSnackbar(this.text($r('app.string.index_edit_failed')));
        return;
      }
      if (ProfileStore.indexOf(stored, profile.id) < 0) {
        await this.reload();
        this.showSnackbar(this.text($r('app.string.index_edit_failed')));
        return;
      }
      await router.pushUrl({
        url: 'pages/ProfileEdit',
        params: { id: profile.id } as EditParams,
      });
    } catch (e) {
      hilog.error(0x0000, TAG, 'open editor failed: %{public}s', JSON.stringify(e));
      this.showSnackbar(this.text($r('app.string.index_edit_failed')));
    }
  }

  private openShareQr(profile: Profile): void {
    this.shareUrl = profile.toUri();
    this.shareName = profile.displayName();
    this.qrDialog = new CustomDialogController({
      builder: ShareQrDialog({
        url: this.shareUrl,
        name: this.shareName,
        onError: (message: ResourceStr) => {
          promptAction.showToast({ message: message });
        },
      }),
      autoCancel: true,
    });
    this.qrDialog.open();
  }

  private async copyProfileToClipboard(profile: Profile): Promise<void> {
    try {
      await writeClipboard(profile.toUri());
      await this.showResult($r('app.string.index_export_success'));
    } catch (e) {
      this.reportFailure($r('app.string.index_op_copy'), e as Object);
    }
  }

  /**
   * Seeds a profile with the manual defaults, writes the row, then opens the
   * editor. The row exists before the editor opens, so leaving the editor keeps
   * the row in the list.
   */
  private async addManualProfile(): Promise<void> {
    try {
      const context = abilityContext();
      const current = await ProfileStore.getCurrent(context);
      const profile = newManualProfile(current);
      await ProfileStore.upsert(context, profile);
      await this.reload();
      router.pushUrl({ url: 'pages/ProfileEdit', params: { id: profile.id } as EditParams });
    } catch (e) {
      this.reportFailure($r('app.string.index_op_add_profile'), e as Object);
    }
  }

  private async openManualSettings(): Promise<void> {
    await this.flushRemovals();
    await this.addManualProfile();
  }

  /* ---- pending removals ---- */

  private stageRemoval(profile: Profile): void {
    if (!this.isRowEditable(profile)) {
      return;
    }
    this.undo.add(profile.id);
    this.syncPending();
    this.startUndoTimer();
  }

  private syncPending(): void {
    this.pendingIds = this.undo.ids();
  }

  private startUndoTimer(): void {
    this.stopUndoTimer();
    this.undoTimer = setTimeout(() => {
      this.undoTimer = -1;
      this.commitRemovals();
    }, UNDO_TIMEOUT_MS);
  }

  private stopUndoTimer(): void {
    if (this.undoTimer >= 0) {
      clearTimeout(this.undoTimer);
      this.undoTimer = -1;
    }
  }

  /**
   * Writes every pending removal to the store. A failed id goes back into the
   * bin, and the bar stays up with a new timer.
   */
  private async commitRemovals(reloadList: boolean = true): Promise<void> {
    if (this.undo.size() === 0) {
      return;
    }
    this.stopUndoTimer();
    const ids = this.undo.ids();
    this.undo.clear();
    this.syncPending();
    let failed = false;
    for (const id of ids) {
      try {
        await ProfileStore.remove(abilityContext(), id);
      } catch (e) {
        failed = true;
        this.undo.add(id);
        this.reportFailure($r('app.string.index_op_delete_profile'), e as Object);
      }
    }
    if (failed) {
      this.syncPending();
      this.startUndoTimer();
    }
    if (reloadList) {
      await this.reload();
    }
  }

  /** Puts every pending row back. The store never changed, so no write runs. */
  private async undoRemovals(): Promise<void> {
    this.stopUndoTimer();
    this.undo.clear();
    this.syncPending();
  }

  private async flushRemovals(): Promise<void> {
    await this.commitRemovals();
  }

  /** Commits a pending removal, then shows the result of the action. */
  private async showResult(message: ResourceStr): Promise<void> {
    await this.flushRemovals();
    this.showMessage(message);
  }

  /* ---- link import ---- */

  private async confirmLinkImport(uri: string): Promise<void> {
    const imported = parseProfilesText(uri, this.selectedFeature());
    if (imported.length === 0) {
      this.showMessage($r('app.string.index_no_valid_profile_data'));
      return;
    }
    const lines = imported.map((p) => p.toUri()).join('\n');
    try {
      // the promise overload does not survive the ArkTS checker when the
      // module is imported through @kit.ArkUI, so the callback form is wrapped
      const answer = await new Promise<promptAction.ShowDialogSuccessResponse>((resolve, reject) => {
        promptAction.showDialog({
          title: $r('app.string.index_add_link_profile'),
          message: lines,
          buttons: [
            { text: $r('app.string.common_no'), color: $r('app.color.text_body') },
            { text: $r('app.string.common_yes'), color: $r('app.color.accent') },
          ],
        }, (err, data) => {
          if (err) {
            reject(err);
          } else {
            resolve(data);
          }
        });
      });
      if (answer.index === 1) {
        await this.importProfiles(imported, false);
      }
    } catch (e) {
      // a tap outside the dialog rejects. The link is discarded, as Android
      // discards it, and no message shows.
      hilog.info(0x0000, TAG, 'link import dialog dismissed');
    }
  }

  /* ---- import ---- */

  /**
   * The profile whose feature settings an import inherits. The selected profile
   * only: an absent selection gives null, so the defaults apply.
   */
  private selectedFeature(): Profile | null {
    for (const profile of this.profiles) {
      if (profile.id === this.currentId) {
        return profile;
      }
    }
    return null;
  }

  /**
   * Writes parsed profiles to the store and reloads the list. Returns the count
   * it added. The caller owns the message.
   */
  private async importProfiles(imported: Profile[], replace: boolean): Promise<number> {
    if (imported.length === 0) {
      return 0;
    }
    // a result that writes the list commits a pending removal first
    await this.flushRemovals();
    const context = abilityContext();
    const existing = await ProfileStore.getAll(context);
    const profiles = applyImport(existing, imported, replace);
    await ProfileStore.saveAll(context, profiles);
    await this.reload();
    return imported.length;
  }

  private async importFromClipboard(): Promise<void> {
    try {
      const text = await readClipboard();
      const imported = parseProfilesText(text, this.selectedFeature());
      if (imported.length === 0) {
        this.showMessage($r('app.string.index_import_failed'));
        return;
      }
      await this.importProfiles(imported, false);
      this.showMessage($r('app.string.index_import_success'));
    } catch (e) {
      hilog.error(0x0000, TAG, 'clipboard import failed: %{public}s', JSON.stringify(e));
      this.showMessage($r('app.string.index_import_failed'));
    }
  }

  private async importFromFiles(replace: boolean): Promise<void> {
    try {
      const uris = await pickTextFiles(abilityContext());
      if (uris.length === 0) {
        return; // the user cancelled
      }
      const texts: string[] = [];
      let readError = '';
      for (const uri of uris) {
        try {
          texts.push(readTextFile(uri));
        } catch (e) {
          readError = this.readableMessage(e as Object);
          break;
        }
      }
      const batch = collectProfiles(texts, this.selectedFeature());
      if (batch.profiles.length > 0) {
        await this.importProfiles(batch.profiles, replace);
      }
      const error = batch.error.length > 0 ? batch.error : readError;
      if (error.length > 0) {
        this.showMessage(error);
      }
    } catch (e) {
      this.showMessage(this.readableMessage(e as Object));
    }
  }

  private async importTypedUrl(text: string): Promise<void> {
    try {
      const imported = parseProfilesText(text, this.selectedFeature());
      if (imported.length === 0) {
        this.showMessage($r('app.string.index_nothing_to_import',
          this.text($r('app.string.index_import_url'))));
        return;
      }
      await this.importProfiles(imported, false);
      this.showMessage($r('app.string.index_import_success'));
    } catch (e) {
      hilog.error(0x0000, TAG, 'typed url import failed: %{public}s', JSON.stringify(e));
      this.showMessage($r('app.string.index_import_failed'));
    }
  }

  /* ---- QR scan import ---- */

  private async scanQrCode(): Promise<void> {
    if (this.scanning) {
      return;
    }
    this.scanning = true;
    try {
      let emptyResults = 0;
      while (true) {
        const result = await scanWithSystemUi(abilityContext());
        if (result.cancelled) {
          return;
        }
        const profiles = profilesFromScan(result.text, this.currentProfile());
        if (profiles.length > 0) {
          await this.importProfiles(profiles, false);
          return;
        }
        emptyResults += 1;
        if (emptyResults >= 3) {
          this.showMessage($r('app.string.qr_no_profiles'));
          return;
        }
      }
    } catch (e) {
      this.reportFailure($r('app.string.index_op_scan'), e as Object);
    } finally {
      this.scanning = false;
    }
  }

  private async importQrImages(): Promise<void> {
    if (this.scanning) {
      return;
    }
    this.scanning = true;
    try {
      const uris = await pickQrImages();
      if (uris.length === 0) {
        return; // the user cancelled
      }
      const decoded = await decodeQrImages(uris);
      const profiles = profilesFromScanTexts(decoded.texts, this.currentProfile());
      const count = await this.importProfiles(profiles, false);
      if (decoded.error.length > 0) {
        // the readable images are already imported. The first failure is shown.
        promptAction.showToast({ message: decoded.error, duration: 3000 });
        return;
      }
      if (count > 0) {
        this.showMessage($r('app.string.qr_import_success'));
      } else {
        this.showMessage($r('app.string.qr_import_failed'));
      }
    } catch (e) {
      this.reportFailure($r('app.string.index_op_import'), e as Object);
    } finally {
      this.scanning = false;
    }
  }

  /* ---- export ---- */

  /** The visible profiles, or null when the store cannot be read. */
  private async readActiveProfiles(): Promise<Profile[] | null> {
    try {
      const stored = await ProfileStore.getAllOrNull(abilityContext());
      if (stored === null) {
        hilog.error(0x0000, TAG, 'profile store is unreadable');
        return null;
      }
      return ProfileStore.visible(stored);
    } catch (e) {
      hilog.error(0x0000, TAG, 'profile read failed: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  private async copyToClipboard(): Promise<void> {
    // a result message commits a pending removal, so the copy leaves it out
    await this.flushRemovals();
    const profiles = await this.readActiveProfiles();
    if (profiles === null) {
      this.showMessage($r('app.string.index_export_failed'));
      return;
    }
    try {
      await writeClipboard(exportProfileUrls(profiles));
      this.showMessage($r('app.string.index_export_success'));
    } catch (e) {
      hilog.error(0x0000, TAG, 'clipboard export failed: %{public}s', JSON.stringify(e));
      this.showMessage($r('app.string.index_export_failed'));
    }
  }

  private async exportToFile(): Promise<void> {
    try {
      // serialize first: a failed read leaves no empty file behind
      const text = exportProfiles(await this.readActiveProfiles());
      if (text === null) {
        return;
      }
      const uri = await saveTextFile(abilityContext(), EXPORT_FILE_NAME, text);
      if (uri.length === 0) {
        return; // the user cancelled
      }
      // this action shows no message, as Android's file export shows none
    } catch (e) {
      this.showMessage(this.readableMessage(e as Object));
    }
  }

  /* ---- live counters ---- */

  private liveProfileId(): string {
    if (this.proxyUp) {
      return this.proxyProfileId;
    }
    const reported = this.lastStatus?.profileId ?? '';
    return reported.length > 0 ? reported : this.currentId;
  }

  private profileTx(profile: Profile): number {
    return withLive(profile.tx, this.txTotal, profile.id === this.liveProfileId());
  }

  private profileRx(profile: Profile): number {
    return withLive(profile.rx, this.rxTotal, profile.id === this.liveProfileId());
  }

  /* ---- stats bar text ---- */

  private resetCounters(): void {
    this.txTotal = 0;
    this.rxTotal = 0;
    this.txRate = 0;
    this.rxRate = 0;
    this.lastStats = null;
  }

  private statsStatusText(): ResourceStr {
    switch (statsStatusKind(this.phase, this.testStatus)) {
      case 'connecting':
        return $r('app.string.index_connecting');
      case 'shutting-down':
        return $r('app.string.stats_shutting_down');
      case 'connected-tap':
        return $r('app.string.stats_connected_tap');
      case 'testing':
        return $r('app.string.common_testing');
      case 'success':
        return $r('app.string.stats_success', formatRtt(this.testElapsedMs));
      case 'error':
        return $r('app.string.stats_internet_unavailable');
      case 'probe-failed':
        return this.failReason.length > 0
          ? this.failReason
          : $r('app.string.index_tunnel_up_no_internet');
      default:
        return $r('app.string.index_not_connected');
    }
  }

  private statsStatusColor(): ResourceColor {
    switch (statsStatusKind(this.phase, this.testStatus)) {
      case 'connecting':
      case 'shutting-down':
        return $r('app.color.accent');
      case 'connected-tap':
      case 'testing':
      case 'success':
        return $r('app.color.success');
      case 'probe-failed':
        return $r('app.color.warning');
      case 'error':
        return $r('app.color.error_strong');
      default:
        return $r('app.color.text_secondary');
    }
  }

  private statsText(): StatsText {
    return formatStats(this.txTotal, this.rxTotal, this.txRate, this.rxRate);
  }

  private onStatsTap(): void {
    if (statsTapAction(this.phase) === 'test') {
      this.runProbe(true);
    }
  }

  /* ---- service control ---- */

  /** True while an extension is believed to exist, so the button reads Disconnect. */
  private isUp(): boolean {
    return this.proxyUp || this.phase === PHASE_CONNECTING || this.phase === PHASE_VERIFYING ||
      this.phase === PHASE_CONNECTED || this.phase === PHASE_PROBE_FAILED ||
      this.phase === PHASE_STOPPING;
  }

  private serviceLabelResource(): Resource {
    return serviceButtonLabelKey(this.phase) === 'index_disconnect'
      ? $r('app.string.index_disconnect')
      : $r('app.string.index_connect');
  }

  private onServiceTap(): void {
    const action = serviceButtonTap(this.phase);
    if (action === 'stop') {
      this.disconnect();
    } else if (action === 'start') {
      this.connect();
    }
  }

  private async connect(): Promise<void> {
    if (this.phase === PHASE_STOPPING) {
      return;
    }
    this.clearSnackbar();
    const profile = this.currentProfile();
    if (profile === null || profile.host.length === 0 || profile.password.length === 0) {
      this.showSnackbar(this.text($r('app.string.service_no_profile')));
      return;
    }
    this.testStatus = TEST_IDLE;
    this.testMessage = '';
    this.testElapsedMs = 0;
    this.statsHiddenByScroll = false;
    this.lastFailureShown = '';
    if ((this.settings?.serviceMode ?? MODE_VPN) === MODE_PROXY) {
      this.runningMode = MODE_PROXY;
      await this.connectProxy(profile);
      return;
    }
    this.runningMode = MODE_VPN;
    // Enter the connecting phase *before* awaiting: starting the extension can
    // block on the system consent dialog for as long as the user takes to
    // answer, and the page must not look idle meanwhile. Note that this says
    // nothing about whether the tunnel will actually come up, which is decided
    // by the status file and the probe below.
    this.phase = PHASE_CONNECTING;
    this.failReason = '';
    this.probeRttMs = 0;
    this.cancelProbe();
    this.connectingSince = Date.now();
    this.startHealthPolling();
    // A session that ended without this page seeing it leaves its counters in
    // the traffic record. Add them before the new session overwrites it.
    await this.settleSession();
    await this.startVpn();
  }

  /** Starts the extension, with the emulator's self-grant and one retry. */
  private async startVpn(): Promise<void> {
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
      // asked for before the tunnel starts, so that the notification the
      // tunnel is reached through is actually published
      await ensureEnabled(abilityContext());
      await vpnExtension.startVpnExtensionAbility(VPN_ABILITY);
    } catch (e) {
      // Only a refused grant can answer to the self-grant and a second start.
      // Any other failure would fail again, or create a second instance.
      if (!this.isGrantFailure(e)) {
        this.reportVpnStartFailure(e);
        return;
      }
      hilog.warn(0x0000, TAG, 'vpn start rejected (%{public}s), retrying after self-grant',
        JSON.stringify(e));
      try {
        grantVpnAuthorization(VPN_ABILITY.bundleName ?? '');
        await vpnExtension.startVpnExtensionAbility(VPN_ABILITY);
      } catch (e2) {
        this.reportVpnStartFailure(e2);
        return;
      }
    }
    // Deliberately no `phase = CONNECTED` here. The health poll takes over.
  }

  /** True when a start error reads as a refused grant, which a retry can fix. */
  private isGrantFailure(e: Object): boolean {
    // The message and the serialized object both carry the text, and a thrown
    // Error keeps its message out of JSON.
    const error = e as BusinessError;
    const detail = `${error.message ?? ''} ${String(e)} ${JSON.stringify(e)}`.toLowerCase();
    return detail.indexOf('denied') >= 0 ||
      detail.indexOf('permission') >= 0 ||
      detail.indexOf('authoriz') >= 0;
  }

  /** Records a start failure and leaves the page in the failed phase. */
  private reportVpnStartFailure(e: Object): void {
    hilog.error(0x0000, TAG, 'vpn start failed: %{public}s', JSON.stringify(e));
    this.failReason = this.isGrantFailure(e)
      ? this.text($r('app.string.service_permission_denied'))
      : this.text($r('app.string.index_could_not_start_vpn'));
    this.stopHealthPolling();
    this.phase = PHASE_FAILED;
  }

  /**
   * Proxy mode: the core serves SOCKS5 in this process and nothing is routed.
   * There is no consent dialog and no separate process, so this is the whole of
   * it. The status is this page's own state rather than the extension's file,
   * since the extension is not involved.
   */
  private async connectProxy(profile: Profile): Promise<void> {
    const settings = this.settings ?? await SettingsStore.load(abilityContext());
    this.phase = PHASE_CONNECTING;
    this.failReason = '';
    this.cancelProbe();
    // A record left by an earlier VPN session is finished. Settle it before
    // this proxy session takes over the list. Proxy mode writes no record.
    await this.settleSession();
    try {
      await ensureEnabled(abilityContext());
      const listenPort = portNumber(settings.proxyPort, DEFAULT_PROXY_PORT);
      await ProxyService.start(abilityContext(), profile, listenPort, settings.shareOverLan);
      this.proxyUp = true;
      this.proxyProfileId = profile.id;
      // This page is the only source of a status in proxy mode. A running
      // record with the current time lets the test tap and the counters work.
      this.lastStatus = {
        state: VPN_STATE_RUNNING,
        reason: '',
        detail: '',
        profileId: profile.id,
        profileName: profile.name,
        timestamp: Date.now(),
      };
      const host = settings.shareOverLan
        ? this.text($r('app.string.source_device'))
        : '127.0.0.1';
      this.phase = PHASE_CONNECTED;
      this.runningSince = Date.now();
      promptAction.showToast({
        message: $r('app.string.index_proxy_on', host, listenPort),
      });
    } catch (e) {
      const err = e as BusinessError;
      this.proxyUp = false;
      this.proxyProfileId = '';
      this.failReason = this.text($r('app.string.index_could_not_start_proxy', err.message ?? String(e)));
      this.phase = PHASE_FAILED;
    }
  }

  /**
   * Settles a finished session. The traffic record of a live session is left
   * alone by the model, so this is safe to call on any stop path, including
   * one this page did not start. A failed write is reported and must not
   * break the transition the caller is making.
   */
  private async settleSession(): Promise<void> {
    try {
      await settleSessionTraffic(abilityContext());
    } catch (e) {
      hilog.warn(0x0000, TAG, 'session traffic settle failed: %{public}s', JSON.stringify(e));
    }
  }

  private async disconnect(): Promise<void> {
    if (this.phase === PHASE_STOPPING) {
      return;
    }
    // abandon any probe still in flight so its verdict cannot land afterwards
    this.cancelProbe();
    this.phase = PHASE_STOPPING;
    this.testStatus = TEST_IDLE;
    this.testMessage = '';
    this.stopHealthPolling();
    if (this.proxyUp) {
      await ProxyService.stop(abilityContext());
      this.proxyUp = false;
      this.proxyProfileId = '';
    } else {
      try {
        await vpnExtension.stopVpnExtensionAbility(VPN_ABILITY);
      } catch (e) {
        // the extension may already be gone. Report, then leave the UI in the
        // disconnected state rather than rejecting into the click handler.
        hilog.warn(0x0000, TAG, 'vpn stop failed: %{public}s', JSON.stringify(e));
        this.showSnackbar(this.text($r('app.string.index_vpn_stop_failed')));
      }
      const stopped = await this.waitForVpnStopped(5000);
      if (!stopped) {
        // the user asked to stop, so the page still goes to Idle
        hilog.warn(0x0000, TAG, 'the VPN did not report stopped before the deadline');
      }
    }
    // the extension's own teardown is cut off by the platform, so the session's
    // counters are written here, then the list re-read to pick them up
    await this.settleSession();
    // the session is over: its record is settled, and what the list now shows
    // includes that traffic, so adding the live total would count it twice
    this.resetCounters();
    this.probeRttMs = 0;
    this.runningSince = 0;
    this.phase = PHASE_IDLE;
    this.runningMode = '';
    this.failReason = '';
    this.lastFailureShown = '';
    await this.reload();
  }

  /**
   * Points a running tunnel at the profile that is now selected. The core reads
   * the profile once, when it starts, so leaving it running keeps the old
   * server. Android reloads its service on the same gesture for the same
   * reason.
   */
  private async reloadTunnel(): Promise<void> {
    const profile = this.currentProfile();
    if (profile === null) {
      // the selected row is gone, so there is no server to move the tunnel to;
      // the old tunnel stays up and keeps its own profile
      hilog.warn(0x0000, TAG, 'the selected profile is not in the list, tunnel unchanged');
      this.showSnackbar(this.text($r('app.string.service_no_profile')));
      return;
    }
    if (this.proxyUp) {
      // the core owns the profile for this process; stop it and start again
      await ProxyService.stop(abilityContext());
      this.proxyUp = false;
      this.proxyProfileId = '';
      await this.connectProxy(profile);
      return;
    }
    this.cancelProbe();
    this.phase = PHASE_STOPPING;
    // The wait below reads the status itself; a health tick that applied the
    // old status after CONNECTING is set would stop the new session's polling.
    this.stopHealthPolling();
    try {
      await vpnExtension.stopVpnExtensionAbility(VPN_ABILITY);
    } catch (e) {
      // an extension that is already gone is no obstacle to starting it again
      hilog.info(0x0000, TAG, 'vpn stop before reload: %{public}s', JSON.stringify(e));
    }
    // The core is single-instance. The extension stops it before it records
    // `stopped` (see SsVpnExtensionAbility.onDestroy), and a start in a reused
    // process stops a leftover core first, so waiting until the old extension
    // is gone is enough to keep the new start out of ALREADY_RUNNING.
    const stopped = await this.waitForVpnStopped(5000);
    if (!stopped) {
      // The old core may still run, so a new start is unsafe. Report and stop.
      this.failReason = this.text($r('app.string.index_vpn_stop_timeout'));
      this.phase = PHASE_FAILED;
      this.stopHealthPolling();
      return;
    }
    // before the next session overwrites the record. The counters belong to
    // the profile the user has just left.
    await this.settleSession();
    this.phase = PHASE_CONNECTING;
    this.failReason = '';
    this.probeRttMs = 0;
    this.cancelProbe();
    this.connectingSince = Date.now();
    this.startHealthPolling();
    await this.startVpn();
  }

  /**
   * Waits until the extension no longer reports starting or running.
   * Returns false when the deadline passes first.
   *
   * The status file only changes on transitions, so a `running` record from a
   * long-lived tunnel is old and perfectly normal. The traffic record is the
   * liveness signal: the extension refreshes it every second while it lives,
   * including the heartbeat a session without a stat endpoint writes. A stale
   * record with a stale status means the extension is gone, and there is
   * nothing left to wait for.
   */
  private async waitForVpnStopped(timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const context = abilityContext();
      const status = await VpnStatusStore.load(context);
      if (status === null ||
        (status.state !== VPN_STATE_STARTING && status.state !== VPN_STATE_RUNNING)) {
        return true;
      }
      const record = await TrafficStatsStore.load(context);
      const live = record !== null && !record.settled &&
        !isStale(record.timestamp, Date.now(), STATS_STALE_MS);
      const statusRecent = !isStale(status.timestamp, Date.now(),
        CONNECT_TIMEOUT_MS + STATS_STALE_MS);
      if (!live && !statusRecent) {
        return true;
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 100));
    }
    hilog.warn(0x0000, TAG, 'the old tunnel did not report stopped in %{public}d ms', timeoutMs);
    return false;
  }

  private startHealthPolling(): void {
    this.stopHealthPolling();
    this.lastStats = null;
    // A stale record must not name the live profile for the new session.
    this.lastStatus = null;
    this.runningSince = 0;
    this.txTotal = 0;
    this.rxTotal = 0;
    this.txRate = 0;
    this.rxRate = 0;
    this.healthTimer = setInterval(async () => {
      if (!this.pageAlive || this.polling) {
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

    // The raw record also carries the session's liveness. Its counters are
    // usable only while they belong to the live session (TrafficStats).
    const record = await TrafficStatsStore.load(context);
    const stats = liveCounters(record);
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
    // A settled record belongs to a session that is already counted. An
    // unsettled record proves its writer lives, even when it has no counters.
    const heartbeat = record !== null && !record.settled ? record.timestamp : 0;

    const status = await VpnStatusStore.load(context);
    // A record written before this connect belongs to the previous session.
    // Ignore it, or an old failure or stop would move the page at once.
    if (this.phase === PHASE_CONNECTING && status !== null &&
      status.timestamp < this.connectingSince) {
      return;
    }
    // During the teardown window only a clean stop moves the page. A failure
    // that the dying extension reports is not a new failure.
    if (this.phase === PHASE_STOPPING) {
      if (status !== null && status.state === VPN_STATE_STOPPED) {
        this.phase = PHASE_IDLE;
        this.resetCounters();
        this.runningMode = '';
        this.stopHealthPolling();
      }
      return;
    }
    if (status === null) {
      // nothing written yet; only give up once the start has had its budget
      if (this.phase === PHASE_CONNECTING &&
        (Date.now() - this.connectingSince) > CONNECT_TIMEOUT_MS) {
        this.failReason = this.text($r('app.string.index_vpn_start_timeout'));
        this.phase = PHASE_FAILED;
        this.stopHealthPolling();
      }
      return;
    }
    this.lastStatus = status;

    // A start that stays `starting` past the budget is stuck. The record
    // exists, so the missing-file timeout above would never fire.
    if (this.phase === PHASE_CONNECTING && status.state === VPN_STATE_STARTING &&
      (Date.now() - this.connectingSince) > CONNECT_TIMEOUT_MS) {
      this.failReason = this.text($r('app.string.index_vpn_start_timeout'));
      this.phase = PHASE_FAILED;
      this.stopHealthPolling();
      return;
    }

    if (status.state === VPN_STATE_FAILED) {
      this.failReason = failureText(status.reason, status.detail);
      this.phase = PHASE_FAILED;
      this.stopHealthPolling();
      // the extension reported a failure, so the session is over. This is the
      // stop path this page did not start.
      await this.settleSession();
      return;
    }
    if (status.state === VPN_STATE_STOPPED) {
      // stopped from outside this page (system teardown)
      this.resetCounters();
      this.runningMode = '';
      this.testStatus = TEST_IDLE;
      this.phase = PHASE_IDLE;
      this.failReason = '';
      this.stopHealthPolling();
      await this.settleSession();
      return;
    }
    if (status.state !== VPN_STATE_RUNNING) {
      return;
    }
    if (this.runningSince === 0) {
      this.runningSince = status.timestamp;
    }

    // The status file only changes on transitions, so liveness comes from the
    // traffic record: the extension refreshes it every second while it lives.
    // Two failure shapes have to be caught. A record that stops being
    // refreshed, and no record at all, because the core never got going. Only
    // the elapsed time tells us the second case.
    const now = Date.now();
    const firstLoss = this.phase !== PHASE_PROBE_FAILED;
    if (heartbeat > 0) {
      if (isStale(heartbeat, now, STATS_STALE_MS)) {
        this.failReason = this.text($r('app.string.index_connection_lost'));
        this.phase = PHASE_PROBE_FAILED;
        if (firstLoss) {
          await this.settleSession();
        }
        return;
      }
    } else if (this.runningSince > 0 &&
      (now - this.runningSince) > STATS_STALE_MS) {
      this.failReason = this.text($r('app.string.index_no_traffic'));
      this.phase = PHASE_PROBE_FAILED;
      if (firstLoss) {
        await this.settleSession();
      }
      return;
    }
    if (this.phase === PHASE_CONNECTING || this.phase === PHASE_IDLE) {
      this.runProbe(false);
    }
  }

  /**
   * Abandons a probe in flight. The sequence number moves, so the abandoned
   * probe cannot land its verdict. The flag clears at once, so the next
   * session is not held back by the abandoned probe.
   */
  private cancelProbe(): void {
    this.probeSeq += 1;
    this.probeInFlight = false;
  }

  /**
   * Fetches the probe URL and decides what it means.
   *
   * The fetch alone does not prove the tunnel works. Under `gfwlist` and
   * `china-list` the destination is reached directly by design, and a device
   * with working internet would answer even with the tunnel dead. So the core's
   * receive counter is sampled either side of the fetch and the two are weighed
   * together (Diagnostics.interpretProbe).
   */
  private async runProbe(manual: boolean): Promise<void> {
    if (!manual && this.probeInFlight) {
      return;
    }
    const status = this.lastStatus;
    if (status === null || status.state !== VPN_STATE_RUNNING) {
      if (manual) {
        promptAction.showToast({ message: $r('app.string.index_not_connected') });
      }
      return;
    }
    // A manual test abandons an automatic probe that is still in flight.
    const seq = ++this.probeSeq;
    this.probeInFlight = true;
    const visible = statsVisible(this.phase);
    if (manual && visible) {
      this.testStatus = TEST_TESTING;
      this.testMessage = '';
      this.testElapsedMs = 0;
    }
    if (!manual) {
      this.phase = PHASE_VERIFYING;
      this.failReason = '';
    }
    try {
      const settings = this.settings ?? await SettingsStore.load(abilityContext());
      // Only live counters can show that the fetch moved bytes. A settled
      // record belongs to an earlier session.
      const beforeRecord = await TrafficStatsStore.load(abilityContext());
      const before = liveCounters(beforeRecord);
      const outcome = await probeThroughTunnel(settings.probeUrl, PROBE_TIMEOUT_MS);
      // let the core's 500 ms report and the extension's 1 s save land before
      // sampling the counters again
      await new Promise<void>((resolve) => setTimeout(resolve, STATS_SETTLE_MS));
      const afterRecord = await TrafficStatsStore.load(abilityContext());
      const after = liveCounters(afterRecord);
      if (seq !== this.probeSeq) {
        return;
      }
      const route = this.currentProfile()?.route ?? '';
      const verdict = interpretProbe(outcome.ok, outcome.httpCode,
        before?.rx ?? 0, after?.rx ?? 0, before !== null && after !== null,
        routeProxiesByDefault(route), outcome.reason);
      if (manual) {
        if (visible) {
          this.applyManualResult(outcome.ok, outcome.httpCode, outcome.bodyLength,
            outcome.reason, outcome.rttMs, verdict.verdict === PROBE_OK, verdict.reason);
        }
        return;
      }
      if (verdict.verdict === PROBE_OK) {
        this.probeRttMs = outcome.rttMs;
        this.failReason = '';
        this.phase = PHASE_CONNECTED;
      } else {
        this.failReason = verdict.reason;
        this.probeRttMs = 0;
        this.phase = PHASE_PROBE_FAILED;
      }
    } finally {
      if (seq === this.probeSeq) {
        this.probeInFlight = false;
      }
    }
  }

  /**
   * The manual test result. A success turns the phase connected and shows the
   * handshake time. An HTTP, network or tunnel error shows the reason once.
   */
  private applyManualResult(ok: boolean, httpCode: number, bodyLength: number,
    reason: string, rttMs: number, tunnelOk: boolean, tunnelReason: string): void {
    const result = applyTunnelVerdict(classifyTest(ok, httpCode, bodyLength, reason),
      tunnelOk, tunnelReason);
    if (result.kind === TEST_KIND_SUCCESS) {
      this.probeRttMs = rttMs;
      this.failReason = '';
      this.testStatus = TEST_SUCCESS;
      this.testElapsedMs = rttMs;
      this.phase = PHASE_CONNECTED;
      return;
    }
    this.failReason = result.reason;
    this.probeRttMs = 0;
    this.testStatus = TEST_ERROR;
    let message = '';
    if (result.kind === TEST_KIND_HTTP) {
      message = this.text($r('app.string.stats_error_code', String(result.code)));
    } else if (result.kind === TEST_KIND_NETWORK) {
      message = this.text($r('app.string.stats_network_error', result.reason));
    } else if (result.kind === TEST_KIND_TUNNEL) {
      message = result.reason;
    }
    this.testMessage = message;
    this.phase = PHASE_PROBE_FAILED;
    this.showSnackbar(message);
  }

  /**
   * Stops a service whose mode no longer matches the settings. The old tunnel
   * would otherwise keep carrying traffic in the old mode.
   */
  private async reconcileServiceMode(): Promise<void> {
    this.settings = await SettingsStore.load(abilityContext());
    if (!this.isUp() || this.runningMode.length === 0) {
      return;
    }
    if (!modeChanged(this.runningMode, this.settings.serviceMode)) {
      return;
    }
    await this.disconnect();
    this.showSnackbar(this.text($r('app.string.index_mode_changed')));
  }

  /**
   * Reconciles the page with a VPN that may already be running. The extension
   * outlives the UI, so after an app restart the file is the only record that
   * the tunnel is up.
   */
  private async resumeStatus(): Promise<void> {
    if (this.phase === PHASE_STOPPING) {
      return;
    }
    const context = abilityContext();
    const settings = this.settings ?? await SettingsStore.load(context);
    this.settings = settings;
    if (settings.serviceMode === MODE_PROXY && ProxyService.isRunning()) {
      if (!this.pageAlive) {
        return;
      }
      this.proxyUp = true;
      this.runningMode = MODE_PROXY;
      this.phase = PHASE_CONNECTED;
      this.startHealthPolling();
      return;
    }
    const status = await VpnStatusStore.load(context);
    const summary = summarizeStatus(status);
    if (status === null || summary === PHASE_IDLE || summary === PHASE_FAILED) {
      // no session of this page runs, so a traffic record left behind belongs
      // to a finished session and its counters go to the profile now
      await this.settleSession();
      return;
    }
    // A `running` record only means the extension started once. The process may
    // have died since without writing anything, and this file is never cleared
    // on teardown. Trust it only when it is recent, or when the traffic record
    // is still being refreshed, which is the real liveness signal. A settled
    // record belongs to a session that is already counted.
    const record = await TrafficStatsStore.load(context);
    const recent = !isStale(status.timestamp, Date.now(),
      CONNECT_TIMEOUT_MS + STATS_STALE_MS);
    const countersLive = record !== null && !record.settled &&
      !isStale(record.timestamp, Date.now(), STATS_STALE_MS);
    if (!recent && !countersLive) {
      await this.settleSession();
      return;
    }
    if (!this.pageAlive) {
      return;
    }
    this.startHealthPolling();
    // after the poll reset above, so the record still names the live profile
    this.lastStatus = status;
    if (summary === PHASE_CONNECTED) {
      // the extension is up, but this page has not verified anything yet
      this.runProbe(false);
    }
  }

  /* ---- snackbar and ring ---- */

  private showSnackbar(message: string): void {
    this.clearSnackbar();
    this.snackbar = message;
    this.snackbarTimer = setTimeout(() => {
      this.snackbarTimer = -1;
      this.snackbar = '';
    }, SNACKBAR_DURATION_MS);
  }

  private clearSnackbar(): void {
    if (this.snackbarTimer >= 0) {
      clearTimeout(this.snackbarTimer);
      this.snackbarTimer = -1;
    }
    this.snackbar = '';
  }

  private startRingDelay(): void {
    this.clearRingTimer();
    this.ringTimer = setTimeout(() => {
      this.ringTimer = -1;
      if (this.phase === PHASE_CONNECTING && this.pageStarted) {
        this.ringMode = 'indeterminate';
      }
    }, RING_DELAY_MS);
  }

  private startRingFill(): void {
    this.clearRingTimer();
    this.ringMode = 'determinate';
    this.ringValue = 0;
    animateTo({ duration: RING_FILL_MS, curve: Curve.EaseOut }, () => {
      this.ringValue = 1;
    });
    this.ringTimer = setTimeout(() => {
      this.ringTimer = -1;
      this.ringMode = 'hidden';
      this.ringValue = 0;
    }, RING_FILL_MS + 100);
  }

  private hideRing(): void {
    this.clearRingTimer();
    this.ringMode = 'hidden';
    this.ringValue = 0;
  }

  private clearRingTimer(): void {
    if (this.ringTimer >= 0) {
      clearTimeout(this.ringTimer);
      this.ringTimer = -1;
    }
  }

  /**
   * Runs on every phase change. It keeps the test status, the counters, the
   * stats bar, the failure snackbar and the ring in step with the phase.
   */
  private onPhaseChanged(): void {
    this.testStatus = testStatusAfterConnection(this.testStatus, this.phase);
    if (!statsVisible(this.phase)) {
      this.testMessage = '';
      this.testElapsedMs = 0;
    }
    if (statsResetRequired(this.lastPhase, this.phase)) {
      this.resetCounters();
    }
    const visible = statsVisible(this.phase);
    if (visible) {
      this.statsBarShown = true;
      if (!statsVisible(this.lastPhase)) {
        this.statsHiddenByScroll = false;
      }
    } else {
      this.statsBarShown = false;
    }
    if (this.phase === PHASE_FAILED && this.failReason.length > 0 &&
      this.failReason !== this.lastFailureShown) {
      this.lastFailureShown = this.failReason;
      this.showSnackbar(this.failReason);
    }
    if (this.phase === PHASE_CONNECTING) {
      this.startRingDelay();
    } else if (this.phase === PHASE_CONNECTED) {
      this.startRingFill();
    } else {
      this.hideRing();
    }
    this.lastPhase = this.phase;
  }

  /* ---- bottom inset ---- */

  private readBottomInset(): void {
    window.getLastWindow(abilityContext()).then((win: window.Window) => {
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomInsetVp = px2vp(area.bottomRect.height);
    }).catch((e: Object) => {
      hilog.warn(0x0000, TAG, 'bottom inset unavailable: %{public}s', JSON.stringify(e));
    });
  }

  /* ---- builders ---- */

  @Builder
  DrawerPanel() {
    Column() {
      Column() {
        Text($r('app.string.app_name'))
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.main_toolbar_text'))
      }
      .width('100%')
      .height(120)
      .padding({ left: 20, right: 20 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.main_toolbar'))

      ForEach(DRAWER_ENTRIES, (entry: DrawerEntry) => {
        Row() {
          // Android tints the checked item, icon and text alike, with its
          // primary colour, and marks it with no other sign.
          SymbolGlyph(this.drawerIcon(entry.id))
            .fontSize(20)
            .fontColor([this.drawerItemColor(entry)])
            .margin({ right: 16 })
          Text(this.drawerLabel(entry.id))
            .fontSize(16)
            .fontColor(this.drawerItemColor(entry))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 20, right: 20 })
        .backgroundColor(entry.checkable && entry.id === this.drawerSelected
          ? $r('app.color.surface_selected')
          : $r('app.color.surface'))
        .accessibilityText(this.text(this.drawerLabel(entry.id)))
        .onClick(() => this.onDrawerSelect(entry))
      // The key carries the checked state. ForEach reuses a cached child when
      // the key is unchanged, so the tint would freeze without it.
      }, (entry: DrawerEntry) =>
      `${entry.id}:${entry.checkable && entry.id === this.drawerSelected}`)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  AddMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.index_scan_qr_code') })
        .onClick(() => this.scanQrCode())
      MenuItem({ content: $r('app.string.index_import_qr_image') })
        .onClick(() => this.importQrImages())
      MenuItem({ content: $r('app.string.index_manual_settings') })
        .onClick(() => this.openManualSettings())
      MenuItem({ content: $r('app.string.index_import_url') })
        .onClick(() => this.importDialog.open())
      MenuItem({ content: $r('app.string.index_import_from_clipboard') })
        .onClick(() => this.importFromClipboard())
      MenuItem({ content: $r('app.string.index_import_from_file') })
        .onClick(() => this.importFromFiles(false))
      MenuItem({ content: $r('app.string.index_replace_from_file') })
        .onClick(() => this.replaceDialog.open())
      MenuItem({ content: $r('app.string.index_subscriptions') })
        .onClick(() => {
          router.pushUrl({ url: 'pages/Subscription' });
        })
    }
  }

  @Builder
  ExportMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.index_export_to_clipboard') })
        .onClick(() => this.copyToClipboard())
      MenuItem({ content: $r('app.string.index_export_to_file') })
        .onClick(() => this.exportToFile())
    }
  }

  @Builder
  SwipeDelete(profile: Profile) {
    Row() {
      Text($r('app.string.common_delete'))
        .fontSize(14)
        .fontColor($r('app.color.on_container'))
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.error_container'))
    .onClick(() => this.stageRemoval(profile))
  }

  build() {
    SideBarContainer(SideBarContainerType.Overlay) {
      this.DrawerPanel()
      Stack() {
        Column() {
          // toolbar, on Android's blue-grey app bar
          Row() {
            Text('☰')
              .fontSize(22)
              .fontColor($r('app.color.main_toolbar_text'))
              .margin({ right: 16 })
              .accessibilityText($r('app.string.drawer_open'))
              .onClick(() => {
                this.drawerOpen = true;
              })
            Text($r('app.string.index_title_profiles'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.main_toolbar_text'))
              .layoutWeight(1)
            // The three actions follow Android's toolbar order: add, export,
            // search. Android has no permanent search field; the magnifier
            // opens one, as its search action opens a SearchView.
            SymbolGlyph($r('sys.symbol.notepad_badge_plus'))
              .fontSize(24)
              .fontColor([$r('app.color.main_toolbar_text')])
              .margin({ right: 16 })
              .accessibilityText($r('app.string.index_add_profile'))
              .bindMenu(this.AddMenu())
            SymbolGlyph($r('sys.symbol.arrow_up_to_line'))
              .fontSize(22)
              .fontColor([$r('app.color.main_toolbar_text')])
              .margin({ right: 16 })
              .accessibilityText($r('app.string.index_export'))
              .bindMenu(this.ExportMenu())
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(22)
              .fontColor([$r('app.color.main_toolbar_text')])
              .accessibilityText($r('app.string.index_search_profiles'))
              .onClick(() => {
                this.searchOpen = !this.searchOpen;
                if (!this.searchOpen) {
                  this.search = '';
                }
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor($r('app.color.main_toolbar'))
          // Android's app bar is raised: a thin shadow falls on the list.
          .shadow({
            radius: 6,
            color: $r('app.color.main_toolbar_shadow'),
            offsetY: 2,
          })
          .zIndex(1)

          // Shown by the search action, as Android opens its SearchView.
          if (this.searchOpen) {
            TextInput({ placeholder: $r('app.string.index_search_profiles'), text: this.search })
              .onChange((value) => this.search = value)
              .margin({ left: 16, right: 16, bottom: 8 })
          }

          // profile list. Android's rows run edge to edge: the left band is the
          // row's marker and starts at the screen edge.
          List({ space: 0, scroller: this.scroller }) {
            ForEach(this.shown(), (profile: Profile) => {
              ListItem() {
                ProfileRow({
                  profile: profile,
                  selected: profile.id === this.currentId,
                  subscriptionActive: profile.isSubscriptionLocked(),
                  editable: this.isRowEditable(profile),
                  tx: this.profileTx(profile),
                  rx: this.profileRx(profile),
                  onSelect: () => this.selectProfile(profile),
                  onEdit: () => this.openEditor(profile),
                  onSubscription: () => this.openEditor(profile),
                  onBlocked: () => {
                    this.showSnackbar(this.text($r('app.string.index_edit_running')));
                  },
                  onShareQr: () => this.openShareQr(profile),
                  onShareCopy: () => this.copyProfileToClipboard(profile),
                })
              }
              .swipeAction(this.swipeOptions(profile))
            }, (profile: Profile) => this.rowKey(profile))
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 0, right: 0 })
          .onDidScroll((delta: number) => {
            const next = statsHiddenAfterScroll(this.statsHiddenByScroll, delta);
            if (next !== this.statsHiddenByScroll) {
              animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
                this.statsHiddenByScroll = next;
              });
            }
          })
          // long-press an entry to drag it; the order is kept in the store
          .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
            // A pending removal stays in the stored list, so the visible index
            // does not name the same row there. Refuse the drag.
            if (!isEnabled(this.phase) || this.pendingIds.length > 0) {
              this.dragFrom = -1;
              return;
            }
            this.dragFrom = itemIndex;
            this.dragFlushed = false;
          })
          .onItemDragMove((event: ItemDragInfo, itemIndex: number, insertIndex: number) => {
            // the first crossover of one drag commits a pending removal
            if (!this.dragFlushed) {
              this.dragFlushed = true;
              this.commitRemovals();
            }
          })
          .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number,
            isSuccess: boolean) => {
            if (!isEnabled(this.phase)) {
              return;
            }
            if (isSuccess) {
              this.dropProfile(insertIndex);
            }
          })

          // the undo bar sits after the list and before the status bar
          if (this.pendingIds.length > 0) {
            Row({ space: 12 }) {
              Text(this.pendingIds.length === 1
                ? $r('app.string.index_removed')
                : $r('app.string.index_removed_n', this.pendingIds.length))
                .fontSize(14)
                .fontColor($r('app.color.text_body'))
                .layoutWeight(1)
              Button($r('app.string.common_undo'))
                .backgroundColor($r('app.color.accent_container'))
                .fontColor($r('app.color.on_container'))
                .onClick(() => this.undoRemovals())
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.surface'))
          }

          // snackbar, test row, service button and stats bar
          Column({ space: 4 }) {
            if (this.snackbar.length > 0) {
              Row() {
                Text(this.snackbar)
                  .fontSize(13)
                  .fontColor($r('app.color.text_body'))
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor($r('app.color.surface'))
              .margin({ left: 16, right: 16, bottom: 8 })
            }
            Row() {
              ServiceButtonView({
                phase: this.phase,
                buttonEnabled: serviceButtonEnabled(this.phase),
                checked: serviceButtonChecked(this.phase),
                glyphToken: serviceButtonGlyph(this.phase),
                label: this.text(this.serviceLabelResource()),
                ringMode: this.ringMode,
                ringValue: this.ringValue,
                onToggle: () => this.onServiceTap(),
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            // Android anchors the FAB to the stats bar: the lower half of the
            // button sits in the bar. The offset moves the button down without
            // moving the list, and zIndex keeps it above the bar.
            .offset({ y: this.statsBarShown ? 32 : 0 })
            .zIndex(1)
            StatsBarView({
              shown: this.statsBarShown,
              hiddenByScroll: this.statsHiddenByScroll,
              statusText: this.statsStatusText(),
              statusColor: this.statsStatusColor(),
              txTotal: this.statsText().txTotal,
              txRate: this.statsText().txRate,
              rxTotal: this.statsText().rxTotal,
              rxRate: this.statsText().rxRate,
              onTap: () => this.onStatsTap(),
            })
          }
          .width('100%')
          .padding({
            left: 0,
            right: 0,
            top: 8,
            bottom: this.bottomInsetVp + FAB_MARGIN_VP,
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.main_page'))
        .focusable(true)
        .defaultFocus(true)
        .onKeyEvent((event: KeyEvent) => {
          let ctrl = false;
          if (event.getModifierKeyState !== undefined) {
            try {
              ctrl = event.getModifierKeyState(['Ctrl']);
            } catch (e) {
              ctrl = false;
            }
          }
          if (event.type === KeyType.Down && ctrl && event.keyCode === KeyCode.KEYCODE_G) {
            const action = keyboardToggle(this.phase);
            if (action === 'stop') {
              this.disconnect();
            } else {
              this.connect();
            }
            return true;
          }
          if (event.type === KeyType.Down && ctrl && event.keyCode === KeyCode.KEYCODE_T) {
            this.runProbe(true);
            return true;
          }
          return false;
        })
        // An edge swipe opens the drawer. The drawer does not follow the
        // finger: SideBarContainer.showSideBarWithGesture needs API 26.
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionStart((event: GestureEvent) => {
              this.swipeFromEdge = event.fingerList.length > 0 &&
                event.fingerList[0].localX <= 24;
            })
            .onActionEnd((event: GestureEvent) => {
              if (this.swipeFromEdge && event.offsetX >= 48) {
                this.drawerOpen = true;
              }
              this.swipeFromEdge = false;
            })
        )

        if (this.drawerOpen) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor($r('app.color.scrim'))
            .onClick(() => {
              this.drawerOpen = false;
            })
        }
      }
      .width('100%')
      .height('100%')
    }
    .showSideBar(this.drawerOpen)
    .onChange((open: boolean) => {
      this.drawerOpen = open;
    })
    .sideBarPosition(SideBarPosition.Start)
    .showControlButton(false)
    .autoHide(false)
    .sideBarWidth(280)
    .minSideBarWidth(240)
    .maxSideBarWidth(320)
  }

  /**
   * The swipe action of one row. A locked row has no action area, so the swipe
   * cannot reveal a delete it would refuse.
   */
  private swipeOptions(profile: Profile): SwipeActionOptions {
    if (!this.isRowEditable(profile)) {
      return {};
    }
    const options: SwipeActionOptions = {
      end: {
        builder: () => {
          this.SwipeDelete(profile);
        },
        onAction: () => this.stageRemoval(profile),
        actionAreaDistance: 64,
      },
    };
    return options;
  }
}

/** The floating service button: a glyph, a checked fill and a progress ring. */
@Component
struct ServiceButtonView {
  @Prop phase: string = PHASE_IDLE;
  @Prop buttonEnabled: boolean = true;
  @Prop checked: boolean = false;
  @Prop glyphToken: string = 'connect';
  @Prop label: string = '';
  @Prop ringMode: string = 'hidden';
  @Prop ringValue: number = 0;
  onToggle: () => void = () => {
  };

  /** Android's service button is a paper plane: outline when idle, filled when busy. */
  private glyphSymbol(): Resource {
    return this.glyphToken === 'connect'
      ? $r('sys.symbol.paperplane')
      : $r('sys.symbol.paperplane_fill');
  }

  build() {
    Stack() {
      if (this.ringMode === 'indeterminate') {
        LoadingProgress()
          .width(64)
          .height(64)
          .color($r('app.color.accent'))
      }
      if (this.ringMode === 'determinate') {
        Progress({ value: this.ringValue, total: 1, type: ProgressType.Ring })
          .width(64)
          .height(64)
          .color($r('app.color.success'))
      }
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.glyphSymbol())
          .fontSize(28)
          .fontColor([$r('app.color.main_fab_text')])
      }
      .width(56)
      .height(56)
      .backgroundColor(this.checked
        ? $r('app.color.main_fab_connected')
        : $r('app.color.main_fab'))
      .fontColor($r('app.color.main_fab_text'))
      .enabled(this.buttonEnabled)
      .accessibilityText(this.label)
      .onClick(() => this.onToggle())
    }
    .width(64)
    .height(64)
  }
}

/** The live traffic bar and its status line. It hides by phase and by scroll. */
@Component
struct StatsBarView {
  @Prop shown: boolean = false;
  @Prop hiddenByScroll: boolean = false;
  @Prop statusText: ResourceStr = '';
  @Prop statusColor: ResourceColor = $r('app.color.text_secondary');
  @Prop txTotal: string = '';
  @Prop txRate: string = '';
  @Prop rxTotal: string = '';
  @Prop rxRate: string = '';
  onTap: () => void = () => {
  };

  build() {
    // Android's stats bar: the send and receive lines with their rates, then
    // the status line, on the blue-grey primary-300 fill.
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(this.txTotal)
          .fontSize(14)
          .fontColor($r('app.color.main_stats_text'))
        Blank()
        Text(this.txRate)
          .fontSize(14)
          .fontColor($r('app.color.main_stats_text'))
      }
      .width('100%')
      Row({ space: 8 }) {
        Text(this.rxTotal)
          .fontSize(14)
          .fontColor($r('app.color.main_stats_text'))
        Blank()
        Text(this.rxRate)
          .fontSize(14)
          .fontColor($r('app.color.main_stats_text'))
      }
      .width('100%')
      Text(this.statusText)
        .fontSize(16)
        .fontColor(this.statusColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.main_stats'))
    .visibility(this.shown ? Visibility.Visible : Visibility.None)
    .translate({ y: this.shown && !this.hiddenByScroll ? 0 : 72 })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onClick(() => this.onTap())
  }
}

/**
 * One row of the profile list.
 *
 * The layout follows Android's profile row: the name, the address and plugin
 * lines with the traffic at the lower right, and the edit (or subscription)
 * and share icons at the upper right. A component rather than an inline
 * builder so that the traffic values refresh while the page is live: ForEach
 * caches an item by its key and does not re-run the item builder for it, so
 * only an explicit @Prop input makes the framework redraw the numbers.
 */
@Component
struct ProfileRow {
  @Prop profile: Profile = new Profile();
  @Prop selected: boolean = false;
  @Prop subscriptionActive: boolean = false;
  @Prop editable: boolean = true;
  @Prop tx: number = 0;
  @Prop rx: number = 0;
  onSelect: () => void = () => {
  };
  onEdit: () => void = () => {
  };
  onSubscription: () => void = () => {
  };
  onBlocked: () => void = () => {
  };
  onShareQr: () => void = () => {
  };
  onShareCopy: () => void = () => {
  };

  /** The title: the name, or host:port when the name is empty. */
  private titleText(): string {
    return this.profile.displayName();
  }

  /**
   * The address line, shown only when the title is a name.
   *
   * The model's displaySecondary also joins the plugin. The row shows the
   * plugin on its own line through a resource, so it renders the address part
   * here and takes the plugin from displaySecondary's rule.
   */
  private addressText(): string {
    return this.profile.name.length > 0
      ? `${this.profile.host}:${this.profile.remotePort}`
      : '';
  }

  /** The action icon colour: the text colour, dimmed while editing is blocked. */
  private actionColor(): ResourceColor {
    return this.editable ? $r('app.color.text_body') : $r('app.color.text_secondary');
  }

  @Builder
  ShareMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.index_qr_code') })
        .onClick(() => this.onShareQr())
      MenuItem({ content: $r('app.string.index_share_copy') })
        .onClick(() => this.onShareCopy())
    }
  }

  build() {
    Row() {
      Column({ space: 4 }) {
        Text(this.titleText())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_neutral'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Column({ space: 2 }) {
            if (this.addressText().length > 0) {
              Text(this.addressText())
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.profile.hasPlugin()) {
              Text($r('app.string.index_profile_plugin', this.profile.plugin))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (formatTraffic(this.tx, this.rx).length > 0) {
            Text(formatTraffic(this.tx, this.rx))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 12 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row() {
        if (this.subscriptionActive) {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(20)
            .fontColor([this.actionColor()])
            .opacity(this.editable ? 1 : 0.5)
            .margin({ left: 8 })
            .accessibilityText($r('app.string.index_row_subscription'))
            .onClick(() => {
              if (this.editable) {
                this.onSubscription();
              } else {
                this.onBlocked();
              }
            })
        } else {
          SymbolGlyph($r('sys.symbol.pencil_line'))
            .fontSize(20)
            .fontColor([this.actionColor()])
            .opacity(this.editable ? 1 : 0.5)
            .margin({ left: 8 })
            .accessibilityText($r('app.string.common_edit'))
            .onClick(() => {
              if (this.editable) {
                this.onEdit();
              } else {
                this.onBlocked();
              }
            })
        }
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(20)
          .fontColor([$r('app.color.text_body')])
          .margin({ left: 12 })
          .accessibilityText($r('app.string.index_share'))
          .onClick(() => {
            // an empty handler keeps the tap from selecting the row
          })
          .bindMenu(this.ShareMenu())
      }
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding({ left: 16, right: 8, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.main_page'))
    // Android marks every row with an 8dp band on its left edge: green for the
    // selected row, blue-grey for the others. The band, not a card, is the
    // marker, and it runs the full height of the row.
    .border({
      width: { left: 8, bottom: 1 },
      color: {
        left: this.selected
          ? $r('app.color.main_row_band_selected')
          : $r('app.color.main_row_band'),
        bottom: $r('app.color.divider'),
      },
    })
    .onClick(() => this.onSelect())
  }
}

/** Confirmation for an action that cannot be undone. */
@CustomDialog
struct ConfirmDialog {
  controller: CustomDialogController;
  title: ResourceStr = '';
  message: ResourceStr = '';
  confirmLabel: ResourceStr = $r('app.string.common_ok');
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
        Button($r('app.string.common_cancel'))
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .layoutWeight(1)
          .onClick(() => this.controller.close())
        Button(this.confirmLabel)
          .layoutWeight(1)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.on_container'))
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
      Text($r('app.string.index_import_url'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
      TextInput({ placeholder: 'ss://…', text: this.url })
        .onChange((value) => this.url = value)
      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .backgroundColor($r('app.color.button_neutral'))
          .fontColor($r('app.color.on_neutral'))
          .layoutWeight(1)
          .onClick(() => this.controller.close())
        Button($r('app.string.common_import'))
          .layoutWeight(1)
          .backgroundColor($r('app.color.accent_container'))
          .fontColor($r('app.color.on_container'))
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
