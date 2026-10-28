# LLD — HarmonyOS 5.4.0 Android parity

Fields: 实现盘点、数据结构、算法、测试计划、责任映射.

This document is the merged low-level design for the parity batch.
Each unit plan lists the files, the code changes, the state, the validation rules and the planned tests.

## Units

| Unit | Area | Plan |
| --- | --- | --- |
| U01 | Main shell | [U01](#u01) |
| U02 | Profile list | [U02](#u02) |
| U03 | Profile editor | [U03](#u03) |
| U04 | Import and export | [U04](#u04) |
| U05 | Subscriptions | [U05](#u05) |
| U06 | Custom rules | [U06](#u06) |
| U07 | Per-app proxy | [U07](#u07) |
| U08 | Plugins | [U08](#u08) |
| U09 | Settings | [U09](#u09) |
| U10 | QR and About | [U10](#u10) |
| U11 | System surfaces | [U11](#u11) |


<a id="u01"></a>
## U01 Main shell

### Scope

U01 covers the main shell of the HarmonyOS client. The unit adds the Android main screen surfaces to the existing `Index` page.

In scope:

- Toolbar with a navigation icon and a title.
- Navigation drawer with six destinations.
- Service button with state icon, enabled rule, checked color and progress ring.
- Stats bar with status text, four traffic values and a tap-to-test action.
- Snackbar for service messages, above the service button.
- Start, stop, stop-while-connecting and mode-change flow.
- Drawer open state after a page return.
- Back press that closes the drawer first.
- Keyboard shortcuts for toggle and test.

Out of scope:

- Profile row, search, reorder and delete (U02).
- Subscription pages (U05).
- Custom rules editor (U06).
- Settings fields (U09).
- About page (U10).
- Notification actions and system surfaces (U11).
- Per-app proxy (U07).
- Proxy-mode traffic counters. The inventory records them as partial.

The Android source is `MainActivity.kt`, `ToolbarFragment.kt`, `ServiceButton.kt`, `StatsBar.kt`, `FabProgressBehavior.kt`, `WindowInsetsListeners.kt`, `layout_main.xml`, `navigation_header.xml`, `navigation_main.xml`, and the start and stop subset of `Core.kt` and `BaseService.kt`.

### Android to HarmonyOS mapping

| Android surface | HarmonyOS implementation | Reason |
| --- | --- | --- |
| `MainActivity` plus one fragment holder | One `Index` page plus router pages | The app already uses the Stage model and `router` |
| `DrawerLayout` and `NavigationView` | `SideBarContainer` in `Overlay` mode | Built-in ArkUI drawer container |
| `ServiceButton` floating action button | `ServiceButtonView` component in `Index.ets` | Same handler, no fragment |
| `StatsBar` bottom app bar | `StatsBarView` component in `Index.ets` | Same data, no bottom app bar |
| Material snackbar | In-page banner above the service button | `promptAction` cannot anchor a message |
| AIDL service state | `VpnStatusStore` file plus `Diagnostics` phases | No bound service on HarmonyOS |
| `HttpsTest` | `ConnectivityProbe` plus the test status | The probe already exists |

### Files to change

| Path | State | Change |
| --- | --- | --- |
| `entry/src/main/ets/model/MainShell.ets` | new | Pure U01 rules: drawer, service button, ring, test status, stats, failure text |
| `entry/src/main/ets/pages/Index.ets` | change | Toolbar, drawer, service button, stats bar, snackbar, start and stop flow |
| `entry/src/main/ets/model/Diagnostics.ets` | change | Add the `PHASE_STOPPING` phase |
| `entry/src/main/ets/model/ConnectivityProbe.ets` | change | Add `bodyLength` to `ProbeOutcome` |
| `entry/src/main/ets/vpnability/SsVpnExtensionAbility.ets` | change | Name the start failure with the parity message |
| `entry/src/main/resources/base/element/string.json` | change | Add 19 English strings |
| `entry/src/main/resources/zh_CN/element/string.json` | change | Add the same 19 strings in Chinese |
| `entry/src/main/resources/base/element/color.json` | change | Add `success_container` and `scrim` |
| `entry/src/main/resources/dark/element/color.json` | change | Add the same two colors for the dark theme |
| `entry/src/test/List.test.ets` | change | Register `parityU01Test` |
| `entry/src/test/ParityU01.test.ets` | new | 27 host unit tests |
| `entry/src/ohosTest/ets/test/MainShellE2e.test.ets` | new | 5 on-device UI cases |
| `entry/src/ohosTest/ets/test/VpnE2e.test.ets` | change | Add 3 U01 device cases: disconnect, scroll hide, ring |
| `entry/src/ohosTest/ets/test/List.test.ets` | change | Register `mainShellE2eTest` |

The plan does not change `ProfileStore.ets`, `TrafficStats.ets`, `SessionTraffic.ets`, `ConnectionNotification.ets` or `ProxyService.ets`. U01 reads them as they are. The session-ownership fix after the review does change `TrafficStats.ets` and `SessionTraffic.ets`; the Stores and Traffic flow sections below describe the delivered shape.

### Implementation plan

### 1. New pure module `model/MainShell.ets`

The module holds the U01 decisions. It imports only `Diagnostics` and `TrafficStats`. It calls no kit API. The host runner can load it.

#### Drawer rules

```ts
export const DRAWER_PROFILES: string = 'profiles';
export const DRAWER_SUBSCRIPTIONS: string = 'subscriptions';
export const DRAWER_CUSTOM_RULES: string = 'customRules';
export const DRAWER_SETTINGS: string = 'globalSettings';
export const DRAWER_FAQ: string = 'faq';
export const DRAWER_ABOUT: string = 'about';

export interface DrawerEntry {
  id: string;
  checkable: boolean;
}

export const DRAWER_ENTRIES: DrawerEntry[] = [
  { id: DRAWER_PROFILES, checkable: true },
  { id: DRAWER_SUBSCRIPTIONS, checkable: true },
  { id: DRAWER_CUSTOM_RULES, checkable: true },
  { id: DRAWER_SETTINGS, checkable: true },
  { id: DRAWER_FAQ, checkable: false },
  { id: DRAWER_ABOUT, checkable: true },
];

export function isCheckableDrawerItem(id: string): boolean;
export function defaultDrawerSelection(): string;
export function drawerSelectionAfter(current: string, selected: string): string;
export function drawerClosesAfter(current: string, selected: string): boolean;
export function drawerNavigatesAfter(current: string, selected: string): boolean;
```

Rules:

- `defaultDrawerSelection` returns `DRAWER_PROFILES`.
- `drawerSelectionAfter` returns `selected` when the item is checkable. It returns `current` for FAQ and for an unknown id.
- `drawerClosesAfter` returns `false` for FAQ. It returns `true` for every checkable item, including the checked item.
- `drawerNavigatesAfter` returns `false` for FAQ. It returns `false` when `selected` equals `current`. It returns `true` for another checkable item.

The six ids match the Android menu ids in `navigation_main.xml`.

#### Service button rules

```ts
export const RING_DELAY_MS: number = 1200;
export const RING_FILL_MS: number = 400;
export const SNACKBAR_DURATION_MS: number = 4000;
export const FAB_MARGIN_VP: number = 16;

export function canStop(phase: string): boolean;
export function canStart(phase: string): boolean;
export function serviceButtonEnabled(phase: string): boolean;
export function serviceButtonChecked(phase: string): boolean;
export function serviceButtonLabelKey(phase: string): string;
export function serviceButtonGlyph(phase: string): string;
export function serviceButtonTap(phase: string): string;
export function keyboardToggle(phase: string): string;
export function ringState(phase: string, connectingForMs: number): string;
```

Rules:

- `canStop` returns `true` for `PHASE_CONNECTING`, `PHASE_VERIFYING`, `PHASE_CONNECTED` and `PHASE_PROBE_FAILED`. It returns `false` for `PHASE_IDLE`, `PHASE_FAILED` and `PHASE_STOPPING`.
- `canStart` returns `true` for `PHASE_IDLE` and `PHASE_FAILED`.
- `serviceButtonEnabled` returns `canStop(phase) || canStart(phase)`. The button is disabled in `PHASE_STOPPING`.
- `serviceButtonChecked` returns `true` for `PHASE_CONNECTED` and `PHASE_PROBE_FAILED`. Both phases mean the tunnel is up.
- `serviceButtonLabelKey` returns `'index_disconnect'` when `canStop` is true. It returns `'index_connect'` otherwise. The Android rule gives Stop only when the state can stop.
- `serviceButtonGlyph` returns these tokens:
  - `'connect'` for `PHASE_IDLE` and `PHASE_FAILED`.
  - `'stop'` for `PHASE_CONNECTING` and `PHASE_VERIFYING`.
  - `'check'` for `PHASE_CONNECTED` and `PHASE_PROBE_FAILED`.
  - `'wait'` for `PHASE_STOPPING`.
- `serviceButtonTap` returns `'none'` for `PHASE_STOPPING`. It returns `'stop'` when `canStop` is true. It returns `'start'` when `canStart` is true. It returns `'none'` otherwise.
- `keyboardToggle` returns `'stop'` when `canStop` is true. It returns `'start'` otherwise. This mirrors Ctrl+G, which launches the start contract during `Stopping`. The page rejects that start with a phase guard.
- `ringState` returns `'indeterminate'` when the phase is `PHASE_CONNECTING` and `connectingForMs >= RING_DELAY_MS`. It returns `'hidden'` otherwise. The page handles the fill on `Connected`.

#### Test status and stats bar

```ts
export const TEST_IDLE: string = 'idle';
export const TEST_TESTING: string = 'testing';
export const TEST_SUCCESS: string = 'success';
export const TEST_ERROR: string = 'error';

export const TEST_KIND_SUCCESS: string = 'success';
export const TEST_KIND_HTTP: string = 'http';
export const TEST_KIND_NETWORK: string = 'network';
export const TEST_KIND_TUNNEL: string = 'tunnel';

export interface TestResult {
  kind: string;
  code: number;
  reason: string;
}

export function classifyTest(ok: boolean, httpCode: number, bodyLength: number,
  reason: string): TestResult;
export function applyTunnelVerdict(result: TestResult, tunnelOk: boolean,
  tunnelReason: string): TestResult;
export function testStatusAfterConnection(current: string, phase: string): string;
export function statsVisible(phase: string): boolean;
export function statsStatusKind(phase: string, test: string): string;
export function statsHiddenAfterScroll(hidden: boolean, delta: number): boolean;
export function statsResetRequired(previous: string, next: string): boolean;
export function statsTapAction(phase: string): string;

export interface StatsText {
  txTotal: string;
  txRate: string;
  rxTotal: string;
  rxRate: string;
}

export function formatStats(tx: number, rx: number, txRate: number,
  rxRate: number): StatsText;
```

Rules:

- `classifyTest` returns `TEST_KIND_SUCCESS` for code 204, and for code 200 with `bodyLength === 0`.
- `classifyTest` returns `TEST_KIND_HTTP` with the code for another 2xx code. It also returns this kind when `httpCode > 0`.
- `classifyTest` returns `TEST_KIND_NETWORK` with the reason when `httpCode === 0`. The case covers a transport failure.
- `applyTunnelVerdict` replaces a success result with `TEST_KIND_TUNNEL` when `tunnelOk` is false. It keeps an HTTP or network result unchanged.
- `testStatusAfterConnection` returns `current` while `statsVisible` is true. It returns `TEST_IDLE` otherwise.
- `statsVisible` returns `true` for `PHASE_CONNECTED` and `PHASE_PROBE_FAILED`.
- `statsStatusKind` returns these tokens:
  - `'connecting'` for `PHASE_CONNECTING`.
  - `'shutting-down'` for `PHASE_STOPPING`.
  - `'connected-tap'`, `'testing'`, `'success'` or `'error'` for `PHASE_CONNECTED`, chosen by the test status.
  - `'testing'`, `'success'` or `'error'` for `PHASE_PROBE_FAILED` when the manual test sets one of them.
  - `'probe-failed'` for `PHASE_PROBE_FAILED` with `TEST_IDLE`. The page shows `failReason` for this token.
  - `'not-connected'` for every other phase.
- `statsHiddenAfterScroll` returns `true` for a positive delta, `false` for a negative delta, and `hidden` for a zero delta. A positive delta means the content moved up.
- `formatStats` returns four strings: `▲ ` plus `formatBytes(tx)`, `formatRate(txRate)`, `▼ ` plus `formatBytes(rx)`, and `formatRate(rxRate)`.
- `statsResetRequired` returns `true` when the previous phase is visible and the next phase is not.
- `statsTapAction` returns `'test'` when the stats bar is visible. It returns `'none'` otherwise.

#### Failure and mode rules

```ts
export function failureText(reason: string, detail: string): string;
export function modeChanged(runningMode: string, settingsMode: string): boolean;

export const FAQ_URL: string =
  'https://github.com/shadowsocks/shadowsocks-android/blob/master/.github/faq.md';
```

Rules:

- `failureText` trims both inputs. With two values it returns `reason + ': ' + detail`. With one value it returns that value. With no value it returns an empty string.
- `modeChanged` returns `true` when `runningMode` is not empty and differs from `settingsMode`.

### 2. `model/Diagnostics.ets`

Add one constant after `PHASE_LOST`:

```ts
export const PHASE_STOPPING: string = 'stopping';
```

The page uses this phase for the teardown window. `summarizeStatus` does not return it, because the status file has no stopping state. The page sets it before it calls `stopVpnExtensionAbility`.

### 3. `model/ConnectivityProbe.ets`

Add a field to `ProbeOutcome`:

```ts
export interface ProbeOutcome {
  ok: boolean;
  httpCode: number;
  bodyLength: number;
  rttMs: number;
  reason: string;
}
```

Set the field in all three constructors:

- The success constructor reads `response.result`. When it is a string, `bodyLength` is its length. Otherwise `bodyLength` is 0.
- The non-2xx constructor uses the same length.
- The exception constructor uses 0.

`classifyTest` uses `bodyLength` to reject a 200 response that carries a body. Android does the same.

### 4. `pages/Index.ets`

The page keeps its current structure. The profile list, search, row component, dialogs and import flow stay.

#### 4.1 New state and fields

| Member | Type | Initial | Purpose |
| --- | --- | --- | --- |
| `@State @Watch('onPhaseChanged') phase` | `string` | `PHASE_IDLE` | Existing phase, now watched |
| `@StorageLink('drawer_open') drawerOpen` | `boolean` | `false` | Drawer visibility, survives a page return |
| `@State drawerSelected` | `string` | `DRAWER_PROFILES` | Checked drawer item |
| `@State testStatus` | `string` | `TEST_IDLE` | Connection test state |
| `@State testMessage` | `string` | `''` | Error text for the snackbar |
| `@State testElapsedMs` | `number` | `0` | Handshake time for the success text |
| `@State statsHiddenByScroll` | `boolean` | `false` | Scroll hide |
| `@State statsBarShown` | `boolean` | `false` | Phase-driven visibility |
| `@State snackbar` | `string` | `''` | Banner text |
| `@State bottomInsetVp` | `number` | `0` | Navigation bar inset |
| `@State ringMode` | `string` | `'hidden'` | Hidden, indeterminate or determinate |
| `@State ringValue` | `number` | `0` | Ring value |
| `private snackbarTimer` | `number` | `-1` | Banner timer |
| `private ringTimer` | `number` | `-1` | Ring delay and fill timer |
| `private pageStarted` | `boolean` | `true` | Ring delay condition |
| `private runningMode` | `string` | `''` | `MODE_VPN` or `MODE_PROXY` while up |
| `private lastPhase` | `string` | `PHASE_IDLE` | Previous phase for reset decisions |
| `private lastFailureShown` | `string` | `''` | Snackbar de-duplication |
| `private swipeFromEdge` | `boolean` | `false` | Drawer gesture start |

Change the `phase` declaration from `@State phase` to `@State @Watch('onPhaseChanged') phase`.

#### 4.2 Lifecycle

- `aboutToAppear`: keep `reload`, `resumeStatus` and `onPendingImport`. Add `this.drawerSelected = defaultDrawerSelection()` and `this.readBottomInset()`.
- `onPageShow`: keep `reload`. Add `this.pageStarted = true` and `this.drawerSelected = defaultDrawerSelection()`. Call `this.reconcileServiceMode()` and catch its rejection. If the phase is `PHASE_CONNECTING` and the ring delay has passed, set `ringMode = 'indeterminate'`.
- Add `onPageHide`: set `this.pageStarted = false`.
- `aboutToDisappear`: keep `stopHealthPolling`. Clear `snackbarTimer` and `ringTimer`.
- Add `onBackPress(): boolean`: if `drawerOpen` is true, set it to false and return true. Otherwise return false.
- Add `onPhaseChanged()`:
  - Call `testStatusAfterConnection(this.testStatus, this.phase)`.
  - Clear `testMessage` and `testElapsedMs` when the phase is not visible.
  - Call `statsResetRequired(this.lastPhase, this.phase)`. When it is true, reset the four counters and set `lastStats = null`.
  - Drive `statsBarShown` with `statsVisible(this.phase)` and the show or hide animation.
  - Show the state snackbar once when the phase is `PHASE_FAILED` and `failReason` differs from `lastFailureShown`.
  - Drive the ring: start the delay on `PHASE_CONNECTING`, start the fill on `PHASE_CONNECTED`, hide the ring on every other phase.
  - Set `this.lastPhase = this.phase`.

#### 4.3 Toolbar and drawer

Replace the title row with a toolbar row:

- A text glyph `☰` on the start edge. It calls `this.drawerOpen = true`. Its accessibility text is `$r('app.string.drawer_open')`.
- The title `$r('app.string.drawer_profiles')` with `layoutWeight(1)`.
- The existing `＋` menu on the end edge. `AddMenu` stays unchanged.

Remove the `⚙` gear from the toolbar. The drawer has Settings.

Wrap the page content in a `SideBarContainer`:

```ts
SideBarContainer(SideBarContainerType.Overlay) {
  this.DrawerPanel()
} {
  Stack() {
    Column() { ...existing content... }
    if (this.drawerOpen) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.drawerOpen = false)
    }
  }
}
.showSideBar(this.drawerOpen)
.onChange((open: boolean) => { this.drawerOpen = open; })
.sideBarPosition(SideBarPosition.Start)
.showControlButton(false)
.autoHide(false)
.sideBarWidth(280)
.minSideBarWidth(240)
.maxSideBarWidth(320)
```

`@StorageLink('drawer_open')` keeps the open state across a page return. The `onChange` callback writes the state.

Add `@Builder DrawerPanel()`:

- A header with a height of 120 vp. The background is `$r('app.color.accent_container')`. The title is `$r('app.string.app_name')` in `$r('app.color.on_container')`, 28 fp, bold. The Android header image has no asset in this app, so the header is a color block. The image is decorative.
- A `ForEach(DRAWER_ENTRIES, ...)` with one row for each entry. The row is 48 vp high. It has the label from `drawerLabel(entry.id)`. It shows `✓` when `entry.id === drawerSelected` and the item is checkable. The row sets `.accessibilityText` to the same label.
- The `ForEach` key contains `entry.id` and the checked state. The framework reuses a cached item when the key is unchanged, so the check mark needs both values in the key.
- The selected row uses `$r('app.color.surface_selected')` as its fill.
- The panel uses `$r('app.color.surface')` as its fill.

Add `drawerLabel(id: string): Resource` with a `switch` over the six ids. The `$r` names are compile-time literals, so a switch is necessary.

Add `onDrawerSelect(entry: DrawerEntry): void`:

1. If `entry.checkable` is false, call `openFaq()` and return. The drawer stays open.
2. Record `const navigates = drawerNavigatesAfter(this.drawerSelected, entry.id)` before the update.
3. Set `drawerSelected = drawerSelectionAfter(drawerSelected, entry.id)`.
4. If `drawerClosesAfter(this.drawerSelected, entry.id)` is true, set `drawerOpen = false`.
5. If `navigates` is false, return. This is the already checked item.
6. Route by id:
   - `DRAWER_SUBSCRIPTIONS` opens `pages/Subscription`.
   - `DRAWER_CUSTOM_RULES` opens `pages/CustomRules`.
   - `DRAWER_SETTINGS` opens `pages/Settings`.
   - `DRAWER_ABOUT` opens `pages/About`.
   - `DRAWER_PROFILES` does nothing. The page is already the profile screen.

Add `openFaq(): void`:

- Call `abilityContext().openLink(FAQ_URL)` and catch the rejection.
- On failure, call `showSnackbar(this.text($r('app.string.drawer_faq_failed', FAQ_URL)))`.
- Do not close the drawer.

Add the edge swipe:

- Attach a `PanGesture` with `PanDirection.Horizontal` to the content `Column`.
- On the start event, set `swipeFromEdge` when `fingerList[0].localX <= 24`.
- On the end event, set `drawerOpen = true` when `swipeFromEdge` is true and `offsetX >= 48`.
- Reset `swipeFromEdge` on every end event.

The scrim closes the drawer on a tap. The swipe does not follow the finger. `SideBarContainer.showSideBarWithGesture` needs API 26, so the app cannot use it on API 12.

#### 4.4 Service button

Add `@Component struct ServiceButtonView` in `Index.ets`. Props:

| Prop | Type | Meaning |
| --- | --- | --- |
| `phase` | `string` | Current phase |
| `enabled` | `boolean` | From `serviceButtonEnabled` |
| `checked` | `boolean` | From `serviceButtonChecked` |
| `glyphToken` | `string` | From `serviceButtonGlyph` |
| `label` | `string` | Accessibility text |
| `ringMode` | `string` | Hidden, indeterminate or determinate |
| `ringValue` | `number` | Ring value |
| `onToggle` | `() => void` | Tap handler |

Build:

- A `Stack` with a width and height of 64 vp.
- When `ringMode === 'indeterminate'`, a `LoadingProgress` of 64 vp with `$r('app.color.accent')`.
- When `ringMode === 'determinate'`, a `Progress({ value: ringValue, total: 1, type: ProgressType.Ring })` of 64 vp with `$r('app.color.success')`.
- A circular `Button({ type: ButtonType.Circle })` of 56 vp.
- The background is `$r('app.color.success_container')` when `checked` is true. Otherwise it is `$r('app.color.accent_container')`. The Button also sets `.fontColor($r('app.color.on_container'))`.
- The glyph map is `connect` to `▶`, `stop` to `■`, `check` to `✓`, and `wait` to `…`. The `Text` uses `$r('app.color.on_container')`.
- Set `.enabled(enabled)` and `.accessibilityText(label)`.
- `onClick` calls `onToggle`.

The page places the component in a `Row` with a `Blank()` before it, so the button sits at the end edge. The row sits above the stats bar.

Ring timers in the page:

- Add `startRingDelay()`: cancel the old timer, then set `ringTimer` for `RING_DELAY_MS`. On expiry, when the phase is `PHASE_CONNECTING` and `pageStarted` is true, set `ringMode = 'indeterminate'`. When the page is stopped, leave the ring hidden. `onPageShow` shows it if the delay has passed.
- Add `startRingFill()`: cancel the delay, set `ringMode = 'determinate'` and `ringValue = 0`. Call `animateTo({ duration: RING_FILL_MS, curve: Curve.EaseOut }, () => { this.ringValue = 1 })`. Set `ringTimer` for `RING_FILL_MS + 100` to set `ringMode = 'hidden'`.
- Add `hideRing()`: cancel the timer, set `ringMode = 'hidden'` and `ringValue = 0`.

#### 4.5 Stats bar

Add `@Component struct StatsBarView` in `Index.ets`. Props:

| Prop | Type | Meaning |
| --- | --- | --- |
| `shown` | `boolean` | Phase-driven visibility |
| `hiddenByScroll` | `boolean` | Scroll hide |
| `statusText` | `string` | Status line |
| `statusColor` | `ResourceColor` | Status color |
| `txTotal` | `string` | Upload total with `▲` |
| `txRate` | `string` | Upload rate |
| `rxTotal` | `string` | Download total with `▼` |
| `rxRate` | `string` | Download rate |
| `onTap` | `() => void` | Tap handler |

Build:

- A `Column` with the status `Text` (13 fp, two lines maximum).
- A `Row` with `txTotal` and `txRate`.
- A `Row` with `rxTotal` and `rxRate`.
- A fill of `$r('app.color.surface')`, padding 12 and a radius of 8.
- `.visibility(shown ? Visibility.Visible : Visibility.None)`.
- `.translate({ y: shown && !hiddenByScroll ? 0 : 72 })`.
- `.onClick(() => onTap())`.

Page methods:

- `statsStatusText()`: use `statsStatusKind(this.phase, this.testStatus)` and map the token:
  - `connecting` to `$r('app.string.index_connecting')`.
  - `shutting-down` to `$r('app.string.stats_shutting_down')`.
  - `connected-tap` to `$r('app.string.stats_connected_tap')`.
  - `testing` to `$r('app.string.common_testing')`.
  - `success` to `$r('app.string.stats_success', formatRtt(this.testElapsedMs))`.
  - `error` to `$r('app.string.stats_internet_unavailable')`.
  - `probe-failed` to `this.failReason` when it is not empty. Otherwise it uses `$r('app.string.index_tunnel_up_no_internet')`.
  - `not-connected` to `$r('app.string.index_not_connected')`.
- `statsStatusColor()`: return `accent` for connecting and shutting-down. Return `success` for connected-tap, testing and success. Return `warning` for probe-failed. Return `error_strong` for error. Return `text_secondary` for not-connected.
- `statsText()`: call `formatStats(this.txTotal, this.rxTotal, this.txRate, this.rxRate)`.
- `onStatsTap()`: when `statsTapAction(this.phase) === 'test'`, call `runProbe(true)`.

The list scroll handler:

```ts
.onDidScroll((delta: number) => {
  const next = statsHiddenAfterScroll(this.statsHiddenByScroll, delta);
  if (next !== this.statsHiddenByScroll) {
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.statsHiddenByScroll = next;
    });
  }
})
```

`onPhaseChanged` drives `statsBarShown`:

- On entering a visible phase, set `statsBarShown = true` and `statsHiddenByScroll = false`.
- On leaving, set `statsBarShown = false`.

The bar uses `.animation({ duration: 180, curve: Curve.EaseOut })` for the translate value. The scroll hide animates. The phase hide uses `Visibility.None` and is immediate. This is a small difference from the Android show and hide animation.

#### 4.6 Start, stop, mode and probe

`connect()`:

- Return when the phase is `PHASE_STOPPING`.
- Call `clearSnackbar()`.
- Keep the profile check. Replace the toast with `showSnackbar(this.text($r('app.string.service_no_profile')))`. The check covers a null profile, an empty host and an empty password.
- Set `testStatus = TEST_IDLE`, `testMessage = ''`, `testElapsedMs = 0`, `statsHiddenByScroll = false` and `lastFailureShown = ''`.
- Set `runningMode = MODE_PROXY` and call `connectProxy(profile)` in proxy mode.
- Set `runningMode = MODE_VPN` in VPN mode. Keep the current connecting setup and call `startVpn()`.

`startVpn()`:

- Keep `grantVpnAuthorization`, `ensureEnabled` and the retry.
- On the second failure, set `phase = PHASE_FAILED`. Set `failReason` to `this.text($r('app.string.service_permission_denied'))` when the error text contains `denied`, `permission` or `authoriz` (lowercase compare). Otherwise set it to `this.text($r('app.string.index_could_not_start_vpn'))`.
- Stop health polling. Remove the direct toast. `onPhaseChanged` shows the snackbar.
- Keep the comment that Connected is left to the health poll.

`connectProxy()`:

- Keep the current flow. `runningMode` is already set by `connect`.
- On success, set `phase = PHASE_CONNECTED` and keep the toast.
- On failure, set `phase = PHASE_FAILED`, `failReason` and `proxyUp = false`.

`disconnect()`:

- Return when the phase is `PHASE_STOPPING`.
- Increment `probeSeq`.
- Set `phase = PHASE_STOPPING`, `testStatus = TEST_IDLE`, `testMessage = ''`.
- Call `stopHealthPolling()`.
- In proxy mode, call `ProxyService.stop`, set `proxyUp = false`.
- In VPN mode, call `vpnExtension.stopVpnExtensionAbility` in a `try` block. On failure, call `showSnackbar(this.text($r('app.string.index_vpn_stop_failed')))`. Then call `await this.waitForVpnStopped(5000)`.
- Call `await settleSessionTraffic(abilityContext())`.
- Reset the four counters and `lastStats`.
- Set `phase = PHASE_IDLE`, `runningMode = ''`, `failReason = ''`, `lastFailureShown = ''`.
- Call `await this.reload()`.

`resumeStatus()`:

- Load the settings before the status file.
- If the mode is `MODE_PROXY` and `ProxyService.isRunning()` is true, set `proxyUp = true`, `runningMode = MODE_PROXY`, `phase = PHASE_CONNECTED` and `startHealthPolling()`. Return.
- Keep the current VPN status logic.

`pollTick()`:

- Keep the traffic rate calculation, using only a live record (`liveCounters`). A settled record belongs to a finished session.
- When the phase is `PHASE_STOPPING`, react only to `VPN_STATE_STOPPED`. Set `phase = PHASE_IDLE`, reset the counters, clear `runningMode`, stop polling and return. Ignore `VPN_STATE_FAILED` during the stop window.
- Keep the connect timeout branch. On timeout, set `phase = PHASE_FAILED` and `failReason = this.text($r('app.string.index_vpn_start_timeout'))`.
- On `VPN_STATE_FAILED`, set `failReason = failureText(status.reason, status.detail)`. Set `phase = PHASE_FAILED`, stop polling and settle the session.
- On `VPN_STATE_STOPPED`, set `phase = PHASE_IDLE`, reset the counters, clear `runningMode`, clear `testStatus`, stop polling and settle the session. This is the stop the page did not start.
- Keep the liveness checks, using the traffic record's timestamp (counters or heartbeat). Set `phase = PHASE_PROBE_FAILED` with the existing reason strings, and settle the session on the first failure.
- Keep the automatic probe call for `PHASE_CONNECTING` and `PHASE_IDLE`.

`runProbe(manual: boolean)`:

- When `manual` is false and `probeInFlight` is true, return.
- Increment `probeSeq` and use the new value as `seq`. This abandons an older probe.
- Set `probeInFlight = true` and `probeRunning = true`.
- When `manual` is true and `statsVisible(this.phase)` is true, set `testStatus = TEST_TESTING`, `testMessage = ''` and `testElapsedMs = 0`.
- When `manual` is false, set `phase = PHASE_VERIFYING`.
- Keep the probe call, the settle wait and the two traffic samples.
- Return when `seq !== this.probeSeq`.
- Keep `interpretProbe`.
- For an automatic probe, keep the current phase update. Do not change `testStatus`.
- For a manual probe with a visible stats bar:
  - Build `classifyTest(outcome.ok, outcome.httpCode, outcome.bodyLength, outcome.reason)`.
  - Apply `applyTunnelVerdict(result, verdict.verdict === PROBE_OK, verdict.reason)`.
  - On `TEST_KIND_SUCCESS`, set `phase = PHASE_CONNECTED`, `probeRttMs = outcome.rttMs`, `testStatus = TEST_SUCCESS` and `testElapsedMs = outcome.rttMs`. Show no snackbar.
  - On an error kind, set `phase = PHASE_PROBE_FAILED`, `testStatus = TEST_ERROR` and `failReason = result.reason`. Set `testMessage` from the kind:
    - `TEST_KIND_HTTP` to `this.text($r('app.string.stats_error_code', String(result.code)))`.
    - `TEST_KIND_NETWORK` to `this.text($r('app.string.stats_network_error', result.reason))`.
    - `TEST_KIND_TUNNEL` to `result.reason`.
  - Call `showSnackbar(this.testMessage)` once.
- For a manual probe without a visible stats bar, keep the phase and test status unchanged. Ctrl+T can then run a test that no observer shows.
- In `finally`, clear `probeInFlight` and `probeRunning` only when `seq === this.probeSeq`.

`reconcileServiceMode()`:

- Load the settings and set `this.settings`.
- Return when `isUp()` is false or `runningMode` is empty.
- Return when `modeChanged(runningMode, settings.serviceMode)` is false.
- Call `await this.disconnect()`.
- Call `showSnackbar(this.text($r('app.string.index_mode_changed')))`.

`isUp()` must include `PHASE_STOPPING`. The profile switch and the mode change both need to know that an old tunnel still exists.

#### 4.7 Snackbar and bottom inset

Add `showSnackbar(message: string): void`:

- Clear `snackbarTimer`.
- Set `this.snackbar = message`.
- Set `snackbarTimer` for `SNACKBAR_DURATION_MS`. Clear the message on expiry.

Add `clearSnackbar(): void` for teardown.

Render the snackbar as the first child of the bottom `Column`. It is a `Text` in a rounded `Row` with `$r('app.color.surface')` fill and `$r('app.color.text_body')` text. It is visible only when `snackbar.length > 0`. It sits above the service button.

Add `readBottomInset()`:

- Call `window.getLastWindow(abilityContext())`.
- Call `getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)`.
- Set `bottomInsetVp = px2vp(area.bottomRect.height)`.
- Catch the rejection and log a warning.

The bottom `Column` uses `.padding({ bottom: this.bottomInsetVp + FAB_MARGIN_VP })`.

Bottom order from top to bottom:

1. Snackbar.
2. Test and speed test row.
3. Service button row.
4. Stats bar.

#### 4.8 Keyboard shortcuts

Set `.focusable(true).defaultFocus(true)` on the root content `Column`.

Add `.onKeyEvent((event: KeyEvent) => { ... })`:

- Read `event.getModifierKeyState` when it exists. Check `['Ctrl']`.
- On `KeyType.Down` with Ctrl and `KeyCode.KEYCODE_G`:
  - Call `keyboardToggle(this.phase)`.
  - Call `this.disconnect()` for `'stop'`. Call `this.connect()` for `'start'`.
  - Return true.
- On `KeyType.Down` with Ctrl and `KeyCode.KEYCODE_T`:
  - Call `this.runProbe(true)`.
  - Return true.
- Return false for every other key.

Import `KeyCode` from `@kit.InputKit`. `KeyType` is a global ArkUI type.

#### 4.9 Existing test and speed buttons

Keep both buttons. The test button keeps `runProbe(true)`. The speed test is unchanged.

The stats bar tap is the new parity path. The button stays as an explicit affordance.

### 5. `vpnability/SsVpnExtensionAbility.ets`

Change the `markFailed` reason in the `startTunFd` failure branch:

```ts
await VpnStatusStore.markFailed(this.context, profile.id, profile.name,
  'Failed to connect the remote server', detail);
```

The page composes the final text with `failureText`. The result reads `Failed to connect the remote server: <native detail>`.

Keep the other reasons:

- `'No profile configured'` for the empty profile.
- `'Could not establish the VPN interface'` for a failed tun creation.
- `'The core stopped right after starting'` for the liveness check.

The last case is the HarmonyOS equivalent of the Android guarded process. It is not the same mechanism.

### 6. Resources

#### Strings

Add these entries to `resources/base/element/string.json` and `resources/zh_CN/element/string.json`. The resource name has three dot-separated parts.

| Name | English | Chinese |
| --- | --- | --- |
| `drawer_navigation` | Navigation | 导航 |
| `drawer_open` | Open navigation drawer | 打开导航抽屉 |
| `drawer_profiles` | Profiles | 配置 |
| `drawer_subscriptions` | Subscriptions | 订阅 |
| `drawer_custom_rules` | Custom rules | 自定义规则 |
| `drawer_settings` | Settings | 设置 |
| `drawer_faq` | FAQ | 常见问题 |
| `drawer_about` | About | 关于 |
| `drawer_faq_failed` | Could not open %s | 无法打开 %s |
| `service_stop` | Stop | 停止 |
| `service_permission_denied` | Permission denied to create a VPN service | 创建 VPN 服务的权限被拒绝 |
| `service_no_profile` | Please select a profile | 请选择一个配置 |
| `stats_connected_tap` | Connected, tap to check connection | 已连接，点击测试连接 |
| `stats_success` | Success: HTTPS handshake took %s | 成功：HTTPS 握手耗时 %s |
| `stats_internet_unavailable` | Internet Unavailable | 网络不可用 |
| `stats_error_code` | Error code: #%s | 错误码：#%s |
| `stats_network_error` | Fail to detect internet connection: %s | 无法检测网络连接：%s |
| `stats_shutting_down` | Shutting down… | 正在关闭… |
| `index_mode_changed` | Service mode changed, connect again | 服务模式已更改，请重新连接 |

The existing strings `index_connect`, `index_disconnect`, `index_connecting`, `index_not_connected`, `common_testing` and `index_vpn_stop_failed` stay.

#### Colors

Add these entries to `resources/base/element/color.json` and `resources/dark/element/color.json`.

| Name | Light | Dark | Use |
| --- | --- | --- | --- |
| `success_container` | `#388E3C` | `#2E7D32` | Background of the checked service button, with `on_container` text |
| `scrim` | `#66000000` | `#99000000` | Drawer scrim over the content |

`success_container` is a fill token. `success` stays the text and icon token. This follows the existing `_container` and `on_container` convention.

### 7. Test registration

In `entry/src/test/List.test.ets`:

```ts
import parityU01Test from './ParityU01.test';
...
parityU01Test();
```

In `entry/src/ohosTest/ets/test/List.test.ets`:

```ts
import mainShellE2eTest from './MainShellE2e.test';
...
mainShellE2eTest();
```

### State and data

### Phase table

| Phase | Source | Service button | Stats bar | Test status |
| --- | --- | --- | --- | --- |
| `PHASE_IDLE` | No status file, clean stop, outside stop | Connect, enabled, accent fill | Hidden | Idle |
| `PHASE_CONNECTING` | Start requested, status `starting`, or no file | Stop, enabled, accent fill, ring after 1200 ms | Hidden | Idle |
| `PHASE_VERIFYING` | Automatic probe in flight | Stop, enabled, accent fill | Hidden | Idle |
| `PHASE_CONNECTED` | Status `running`, probe OK | Stop, enabled, `success_container` fill | Shown | Idle, testing, success or error |
| `PHASE_PROBE_FAILED` | Status `running`, probe failed, or stale counters | Stop, enabled, `success_container` fill | Shown | Idle, testing or error |
| `PHASE_STOPPING` | Disconnect requested | Disabled, wait glyph | Hidden | Idle |
| `PHASE_FAILED` | Status `failed`, start rejected, or connect timeout | Connect, enabled, accent fill | Hidden | Idle |

The phase comes from the status file, the traffic file and the page's own probe. The page does not trust `startVpnExtensionAbility` alone.

### Test status table

| Test status | Set by | Stats status text | Snackbar |
| --- | --- | --- | --- |
| `TEST_IDLE` | Connect, leaving a visible phase, stop | Connected, tap to check connection | None |
| `TEST_TESTING` | Manual probe start with a visible stats bar | Testing… | None |
| `TEST_SUCCESS` | Manual probe, code 204 or empty 200, tunnel verdict OK | Success: HTTPS handshake took `<ms>`ms | None |
| `TEST_ERROR` | Manual probe with an HTTP, network or tunnel error | Internet Unavailable | The error text, once |

A test result from a probe that started before a stop or a new probe is discarded through `probeSeq`.

### Drawer state table

| State | Type | Default | Writer | Reader |
| --- | --- | --- | --- | --- |
| `drawer_open` | AppStorage boolean | `false` | Toolbar icon, scrim, swipe, `onChange` | `SideBarContainer.showSideBar` |
| `drawerSelected` | `@State string` | `profiles` | `onDrawerSelect` | Check mark in the drawer |

The page resets `drawerSelected` to `profiles` on `onPageShow`. The main page always shows the profile list, so Profiles is the correct checked item after a return. The other destinations are separate pages.

### Stores

| Store | Owner | U01 use |
| --- | --- | --- |
| `store/profiles.json` | `ProfileStore` | Read the list. Add settled session counters |
| `store/current_profile_id.json` | `ProfileStore` | Read the selected profile id |
| `store/settings.json` | `SettingsStore` | Read the service mode and the probe URL |
| `store/vpn_status.json` | VPN extension | Read the phase and the failure reason |
| `store/traffic_stats.json` | VPN extension and traffic model | Read the record; mark it settled after the counters are added |
| `store/traffic_settled.json` | Traffic model | The settlement receipt: the token of the last session added |
| `store/traffic_pending.json` | VPN extension and traffic model | An unsettled record a later start moved aside; settled first, then removed |

U01 adds no new store file.

### Traffic flow

1. The core reports a 16-byte sample every 500 ms.
2. The extension saves at most one sample per second to `store/traffic_stats.json`. The record names the profile, a per-start session token, a closed flag and a settled flag. A start that finds another session's unsettled record moves it to `store/traffic_pending.json` instead of overwriting it.
3. The page polls the record every 1000 ms. A record that is settled belongs to a finished session and is not used for rates or liveness.
4. The page computes the rates from two consecutive samples.
5. The page shows `▲` and `▼` totals and the two rates.
6. On leaving a visible phase, the page sets the four values to zero and clears `lastStats`.
7. Only the UI process marks the record settled, and only after it added the counters. The claim is written first, so a second settle adds nothing.

The 1000 ms poll is deliberate. The extension saves once per second, so a faster poll would read the same sample again. The HLD contract C-04 states this rule.

### Validation and errors

| Condition | Detection | Result | Message |
| --- | --- | --- | --- |
| No profile, empty host, or empty password | `connect()` check | No start. Phase does not change | `service_no_profile` |
| Start request rejected after the retry | `startVpn` catch | Phase `FAILED` | `service_permission_denied` for a denial-like error, else `index_vpn_start_failed` |
| Extension reports `failed` | `pollTick` reads the status file | Phase `FAILED` | `failureText(reason, detail)`, once per reason |
| Extension reports `stopped` from outside | `pollTick` | Phase `IDLE`, counters reset | None |
| Stop requested twice | Phase `STOPPING` guard and disabled button | The second request does nothing | None |
| Stop does not finish in 5 s | `waitForVpnStopped` timeout | Log a warning, settle, phase `IDLE` | None |
| Connect timeout with no status file | `CONNECT_TIMEOUT_MS` in `pollTick` | Phase `FAILED` | `index_vpn_start_timeout` |
| Probe returns a non-204 code | `classifyTest` | Test status `ERROR` | `stats_error_code` with the code |
| Probe throws or returns no response | `classifyTest` | Test status `ERROR` | `stats_network_error` with the reason |
| Probe succeeds but the counters do not move | `applyTunnelVerdict` | Test status `ERROR` | The verdict reason |
| Probe result arrives after a stop or a new probe | `probeSeq` mismatch | The result is discarded | None |
| FAQ link fails to open | `openLink` rejection | The drawer stays open | `drawer_faq_failed` with the URL |
| Service mode changes while up | `reconcileServiceMode` | The old mode stops, counters settle, phase `IDLE` | `index_mode_changed` |
| Snackbar replaced by a new message | `showSnackbar` | The old timer is cleared | The new message |
| Page disappears with a pending timer | `aboutToDisappear` | All three timers are cleared | None |

Failure reasons from the extension stay in English. The existing model layer uses English failure reasons. The page shows the composed text unchanged.

### Test plan

The unit tests run on the host with `./test-arkts-host.sh`. The device cases run with `ci/hos-emulator-e2e.sh`. The VPN cases need a real device.

Unit anchors use the prescribed form `entry/src/test/ParityU01.test.ets::U01#<name>`. Device anchors use `entry/src/ohosTest/ets/test/<file>::U01#<name>`.

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| TC-U01-12 | `entry/src/test/ParityU01.test.ets` | `U01#drawer-has-six-entries` | unit |
| TC-U01-31 | `entry/src/test/ParityU01.test.ets` | `U01#drawer-keeps-one-checked-item` | unit |
| TC-U01-13 | `entry/src/test/ParityU01.test.ets` | `U01#drawer-same-item-only-closes` | unit |
| TC-U01-15 | `entry/src/test/ParityU01.test.ets` | `U01#drawer-faq-keeps-open-and-checks-nothing` | unit |
| TC-U01-38 | `entry/src/test/ParityU01.test.ets` | `U01#drawer-defaults-to-profiles` | unit |
| TC-U01-24 | `entry/src/test/ParityU01.test.ets` | `U01#can-stop-covers-every-up-phase` | unit |
| TC-U01-05 | `entry/src/test/ParityU01.test.ets` | `U01#button-disabled-while-stopping` | unit |
| TC-U01-01 | `entry/src/test/ParityU01.test.ets` | `U01#button-checked-only-when-connected` | unit |
| TC-U01-04 | `entry/src/test/ParityU01.test.ets` | `U01#button-label-and-glyph-follow-the-phase` | unit |
| TC-U01-02 | `entry/src/test/ParityU01.test.ets` | `U01#button-tap-stops-or-starts` | unit |
| TC-U01-06 | `entry/src/test/ParityU01.test.ets` | `U01#ring-waits-then-shows-indeterminate` | unit |
| TC-U01-18 | `entry/src/test/ParityU01.test.ets` | `U01#keyboard-toggle-maps-to-stop-or-start` | unit |
| TC-U01-08 | `entry/src/test/ParityU01.test.ets` | `U01#stats-bar-visible-only-when-connected` | unit |
| TC-U01-20 | `entry/src/test/ParityU01.test.ets` | `U01#stats-bar-hides-and-returns-on-scroll` | unit |
| TC-U01-08 | `entry/src/test/ParityU01.test.ets` | `U01#stats-status-while-not-connected` | unit |
| TC-U01-09 | `entry/src/test/ParityU01.test.ets` | `U01#stats-status-follows-the-test` | unit |
| TC-U01-28 | `entry/src/test/ParityU01.test.ets` | `U01#test-status-resets-when-leaving-connected` | unit |
| TC-U01-09 | `entry/src/test/ParityU01.test.ets` | `U01#test-classifies-204-and-empty-200` | unit |
| TC-U01-10 | `entry/src/test/ParityU01.test.ets` | `U01#test-reports-an-http-error-code` | unit |
| TC-U01-23 | `entry/src/test/ParityU01.test.ets` | `U01#test-reports-a-network-error` | unit |
| TC-U01-11 | `entry/src/test/ParityU01.test.ets` | `U01#stats-format-totals-and-rates` | unit |
| TC-U01-05 | `entry/src/test/ParityU01.test.ets` | `U01#stats-reset-when-leaving-connected` | unit |
| TC-U01-09 | `entry/src/test/ParityU01.test.ets` | `U01#stats-tap-starts-a-test-only-when-connected` | unit |
| TC-U01-07 | `entry/src/test/ParityU01.test.ets` | `U01#failure-text-appends-the-detail` | unit |
| TC-U01-32 | `entry/src/test/ParityU01.test.ets` | `U01#failure-text-keeps-a-profile-error-unprefixed` | unit |
| TC-U01-16 | `entry/src/test/ParityU01.test.ets` | `U01#mode-change-stops-the-old-service` | unit |
| TC-U01-19 | `entry/src/test/ParityU01.test.ets` | `U01#snackbar-duration-and-fab-margin-are-set` | unit |
| TC-U01-12 | `entry/src/ohosTest/ets/test/MainShellE2e.test.ets` | `U01#drawer-opens-and-lists-six-entries` | e2e |
| TC-U01-14 | `entry/src/ohosTest/ets/test/MainShellE2e.test.ets` | `U01#back-closes-the-drawer` | e2e |
| TC-U01-25 | `entry/src/ohosTest/ets/test/MainShellE2e.test.ets` | `U01#edge-swipe-opens-and-scrim-closes` | e2e |
| TC-U01-08 | `entry/src/ohosTest/ets/test/MainShellE2e.test.ets` | `U01#stats-bar-is-hidden-while-stopped` | e2e |
| TC-U01-38 | `entry/src/ohosTest/ets/test/MainShellE2e.test.ets` | `U01#drawer-open-state-survives-a-return` | e2e |
| TC-U01-05 | `entry/src/ohosTest/ets/test/VpnE2e.test.ets` | `U01#disconnect-from-connected-resets-the-bar` | e2e |
| TC-U01-20 | `entry/src/ohosTest/ets/test/VpnE2e.test.ets` | `U01#stats-bar-hides-on-list-scroll` | e2e |
| TC-U01-06 | `entry/src/ohosTest/ets/test/VpnE2e.test.ets` | `U01#ring-waits-then-fills` | e2e |

The 27 unit tests cover the pure rules. The 8 device cases cover the parts that need ArkUI or a real tunnel.

### Platform notes

- The app uses pages, not fragments. The drawer is on `Index.ets`. Settings, Subscriptions, Custom rules and About are router pages with their own back action.
- The app has no bound service. The phase comes from `store/vpn_status.json`, the traffic sample and the page's probe. There is no `onServiceDisconnected` callback.
- The page starts in `PHASE_IDLE` and the service button is enabled. On HarmonyOS the page owns the core, so `Idle` means the core is known stopped. Android disables the button until a binder reports Stopped. The observable result differs for a moment at launch.
- `promptAction.showToast` cannot anchor a message. The app uses an in-page banner above the service button.
- The app has no Android vector icons. The service button uses the text glyphs `▶`, `■`, `✓` and `…`.
- The drawer header uses the existing `app_name` string. It has no Iceland font and no decorative image. The Android header has both.
- `config_mediumAnimTime` does not exist on HarmonyOS. `RING_DELAY_MS` is 1200 ms. The Android value is about 220 plus 1000 ms.
- The core reports every 500 ms. The extension saves once per second. The page polls once per second, as HLD contract C-04 states.
- The Android aggregate sample with profile id 0 has no HarmonyOS equivalent. The core runs one instance, so every sample is aggregate.
- The pointer icon rule for API 24 and later does not apply. The app sets the enabled state and the accessibility text.
- `SideBarContainer.showSideBarWithGesture` needs API 26. The app uses a `PanGesture` for the edge swipe and a scrim tap for the close action. Close by a drag does not follow the finger.
- The back press uses the `onBackPress` lifecycle callback of the `@Entry` page.
- Keyboard shortcuts need page focus and a hardware keyboard. The phone build may not reach them.
- The bottom inset comes from `window.getWindowAvoidArea(TYPE_NAVIGATION_INDICATOR)`. The `FAB_MARGIN_VP` value is 16. The service button sits above the stats bar, as the Android floating action button sits above the bottom app bar.
- The checked service button uses the new `success_container` fill token. The `success` token stays for text and icons.
- The FAQ link uses `UIAbilityContext.openLink`. A browser must handle the URL.
- The notification permission flow does not change. `startVpn` and `connectProxy` still call `ensureEnabled` first.
- The minimum API is 12. All planned APIs are present in the API 12 declarations, except the drawer gesture API noted above.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| U01-Q1 | Does `SideBarContainer` in `Overlay` mode draw its own scrim on API 12? If it does, the custom scrim duplicates it | ArkUI owner |
| U01-Q2 | Which error does `startVpnExtensionAbility` return when the user denies the VPN consent? The dedicated message needs a reliable test | Platform owner |
| U01-Q3 | Does `onDidScroll` report a positive delta when the user swipes up on the target device? The unit test fixes the convention and the device test confirms the sign | ArkUI owner |
| U01-Q4 | Must the stats bar hide in `PHASE_PROBE_FAILED`? The plan keeps it visible because the tunnel is up and the traffic values are useful | Product owner |
| U01-Q5 | Should the drawer move to the Settings, Subscription, CustomRules and About pages? U01 adds it to `Index` only, so the checked item cannot follow those pages | Product owner |
| U01-Q6 | Does the page root receive key events on a phone with no focused text field? Ctrl+G and Ctrl+T may need a hardware keyboard test | Platform owner |
| U01-Q7 | Can the emulator browser open the GitHub FAQ URL? If it cannot, the failure snackbar is the only emulator evidence | Platform owner |

<a id="u02"></a>
## U02 Profile list

### Scope

This LLD covers unit U02 of the HarmonyOS 5.4.0 parity batch. The unit supplies the profile list, the row layout, search, reorder, delete, and the share popup. The existing page and model structure stays.

### In scope

| Area | Result |
| --- | --- |
| Toolbar | The title reads Profiles. The add and settings actions stay. |
| Search | A search field filters the list by profile name and host. The field is always available. |
| List | Active profiles show in ascending user order. Obsolete profiles have no row. |
| Row | Title, secondary line, traffic line, selection mark, and the edit, subscription, and share actions. |
| Row input | The service phase gates the row tap, the drag, the edit icon, and the swipe. |
| Reorder | A long-press drag rewrites the stored order. |
| Delete | A swipe toward the start edge hides the row and shows an undo bar. |
| Undo | Undo restores the row. The timeout or a flush commits the delete. |
| Share popup | QR code and Export to Clipboard. |
| QR dialog | A 264 vp code of the profile `ss://` URI. |
| Scroll | The list scrolls to the selected row when the page opens. |

### Out of scope

- The connect control and the service state machine. U01 owns them. U02 reads the phase.
- The profile editor fields. U03 owns them.
- The Add and Export menu flows, the file picker, and the clipboard import. U04 owns them.
- Subscription refresh and merge. U05 owns them.
- QR scanning. U10 owns it.

### Deliberate deviations from Android

| Rule | Android behavior | HarmonyOS behavior | Reason |
| --- | --- | --- | --- |
| R-UB-17 | The edit icon throws on a profile deleted in another process. | The page reloads and opens no editor. | A crash is not a parity target. |
| R-UB-33 | A committed delete leaves the selected id stale. | `ProfileStore.remove` selects the first remaining profile. | Connect must not point at a deleted profile. |
| R-UB-51 | A search during a pending removal can show a duplicate row on Undo. | The pending profile stays hidden under every query. | A duplicate row is a defect. |
| R-UB-03, R-UB-04 | The service state Idle refuses a row tap and a drag. | HarmonyOS has no Idle state. `PHASE_IDLE` is the stopped state and accepts input. | No bound service exists before Connect. |

### Files to change

| File | Kind | Change |
| --- | --- | --- |
| `entry/src/main/ets/pages/Index.ets` | Change | Toolbar title, search, list, row wiring, swipe delete, undo bar, share popup, phase gates, scroll. |
| `entry/src/main/ets/pages/QrDialog.ets` | New | `ShareQrDialog` custom dialog with a 264 vp QR canvas. |
| `entry/src/main/ets/model/Profile.ets` | Change | `displayName()` and `displaySecondary()`. |
| `entry/src/main/ets/model/ProfileStore.ets` | Change | `sorted()`, `filter()`, and `indexOf()`. |
| `entry/src/main/ets/model/Diagnostics.ets` | Change | `PHASE_STOPPING`, `isEnabled()`, `activeProfileIds()`, and `isProfileEditable()`. |
| `entry/src/main/ets/model/UndoRemoval.ets` | New | `UndoBin` and `UNDO_TIMEOUT_MS`. |
| `entry/src/main/ets/model/TrafficStats.ets` | Change | `formatTraffic()` and `withLive()`. |
| `entry/src/main/ets/model/Transfer.ets` | Change | Mark the clipboard data as local only. |
| `entry/src/main/resources/base/element/string.json` | Change | Eight new English strings. |
| `entry/src/main/resources/zh_CN/element/string.json` | Change | The same eight strings in Chinese. |
| `entry/src/test/ParityU02.test.ets` | New | The U02 host specs. |
| `entry/src/test/List.test.ets` | Change | Register the U02 suite. |

The three new files carry the GPL-3.0 header block.

### Implementation plan

The existing classes keep their names and their responsibilities. The plan adds methods and properties. It moves the row display rules and the gate rules into the model, where the host runner can test them.

### 1. `model/Profile.ets`

Add two instance methods to `class Profile`.

```ts
/** The row title: the name, or host:port when the name is empty. */
displayName(): string

/**
 * The row's second line: the address when a name exists, then the plugin.
 * An empty string means the line is hidden.
 */
displaySecondary(): string
```

Rules:

- `displayName()` returns `name` when it is not empty. Otherwise it returns `` `${host}:${remotePort}` ``.
- `displaySecondary()` adds `` `${host}:${remotePort}` `` only when the name is not empty.
- `displaySecondary()` adds `Plugin: ${plugin}` when the plugin is not empty.
- `displaySecondary()` joins the two parts with `\n`. It returns `''` when both parts are absent.

### 2. `model/ProfileStore.ets`

Add three static methods. Change `getAll()` to use the first one.

```ts
/** A copy of the list in ascending userOrder. The stored order stays unchanged. */
static sorted(profiles: Profile[]): Profile[]

/**
 * The rows to show: the search filter and the pending removals.
 * An empty query keeps every profile. The filter reads name and host only.
 */
static filter(profiles: Profile[], query: string, hiddenIds: string[] = []): Profile[]

/** The row index of a profile id, or -1 when the id has no row. */
static indexOf(profiles: Profile[], id: string): number
```

Rules:

- `sorted()` copies the array before it sorts. It never writes.
- `filter()` trims the query and lowercases it. It lowercases `name` and `host` for the compare.
- `filter()` drops every id in `hiddenIds`.
- `filter()` does not match `remotePort`, `method`, or `plugin`.
- `getAll()` returns `ProfileStore.sorted(profiles)` in place of the inline sort.
- `visible()` stays unchanged.

### 3. `model/Diagnostics.ets`

Add one phase constant and three pure functions. Import `Profile` from `./Profile`.

```ts
/** The tunnel is tearing down. No row accepts input. */
export const PHASE_STOPPING: string = 'stopping';

/** True when a row accepts a tap or a drag. */
export function isEnabled(phase: string): boolean

/** The selected id and its UDP fallback id, when both exist in the list. */
export function activeProfileIds(profiles: Profile[], currentId: string): string[]

/** True when the edit icon and the swipe are available for this profile. */
export function isProfileEditable(phase: string, activeIds: string[], profileId: string): boolean
```

Rules:

- `isEnabled(phase)` returns `false` for `PHASE_STOPPING`. It returns `true` for every other value.
- `activeProfileIds()` resolves the selected profile as `currentProfile()` does. An absent id falls back to the first profile.
- `activeProfileIds()` returns an empty array for an empty list.
- `activeProfileIds()` adds `udpFallbackId` when the field is not empty, the id differs from the selected id, and the id exists in the list.
- `isProfileEditable()` returns `true` for `PHASE_IDLE` and `PHASE_FAILED`.
- `isProfileEditable()` returns `phase !== PHASE_STOPPING && activeIds.indexOf(profileId) < 0` for every other phase.
- An unknown phase locks an active profile. An unknown phase keeps a non-active profile editable.

Phase mapping:

| HarmonyOS phase | Android service state | Row tap and drag | Edit, subscription, and swipe |
| --- | --- | --- | --- |
| `PHASE_IDLE` | Stopped | Enabled | Enabled |
| `PHASE_CONNECTING` | Connecting | Enabled | Active profile locked |
| `PHASE_VERIFYING` | Connecting | Enabled | Active profile locked |
| `PHASE_CONNECTED` | Connected | Enabled | Active profile locked |
| `PHASE_PROBE_FAILED` | Connected | Enabled | Active profile locked |
| `PHASE_LOST` | Connected | Enabled | Active profile locked |
| `PHASE_STOPPING` | Stopping | Disabled | Active profile locked |
| `PHASE_FAILED` | Stopped | Enabled | Enabled |

### 4. `model/UndoRemoval.ets` (new)

Add the pending-removal model. It is pure. It imports nothing.

```ts
/** How long the undo bar waits before the delete commits. */
export const UNDO_TIMEOUT_MS: number = 4000;

/** The profile ids whose rows are hidden and whose delete is not committed. */
export class UndoBin {
  add(id: string): void
  ids(): string[]
  size(): number
  has(id: string): boolean
  clear(): void
}
```

Rules:

- `add()` ignores an empty id and an id already in the bin.
- `ids()` returns a copy in removal order.
- `clear()` empties the bin.
- The bin keeps ids only. The store is the source of the row and the order. A pending removal does not write the store.

### 5. `model/TrafficStats.ets`

Add two pure functions.

```ts
/** The traffic line, or '' when both counters are zero. */
export function formatTraffic(tx: number, rx: number): string

/** The stored counter plus the live counter for the running profile only. */
export function withLive(stored: number, live: number, isLive: boolean): number
```

Rules:

- `formatTraffic()` returns `''` when `tx <= 0` and `rx <= 0`.
- `formatTraffic()` returns `` `↑ ${formatBytes(tx)}  ↓ ${formatBytes(rx)}` `` otherwise.
- `withLive()` returns `stored + live` when `isLive` is true. It returns `stored` otherwise.

### 6. `model/Transfer.ets`

Change `writeClipboard()`.

- Create the `PasteData` in a local variable.
- Set `data.shareOption = pasteboard.ShareOption.LOCALDEVICE`.
- Pass the variable to `board.setData()`.

This keeps every copied profile password on the device. HarmonyOS has no equivalent of Android's sensitive flag.

### 7. `pages/QrDialog.ets` (new)

Add an exported custom dialog. It mirrors `ProfileQr.ets` for the drawing.

```ts
@CustomDialog
export struct ShareQrDialog {
  controller: CustomDialogController;
  url: string = '';
  name: string = '';
  onError: (message: ResourceStr) => void = () => {
  };
  @State hasError: boolean = false;
  private code: QrCode | null = null;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private painter: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  aboutToAppear(): void
  private draw(): void
  build(): void
}
```

Rules:

- Keep the local constants `CODE_SIZE = 264`, `QUIET_ZONE = 4`, and the draw loop from `ProfileQr.ets`.
- `aboutToAppear()` calls `encodeQr(url, QR_EC_L)`.
- An empty `url` is an error.
- On an encode error, set `hasError`, call `onError($r('app.string.qr_too_long'))`, and close the dialog in a zero-delay timer.
- The build shows the `qr_title` heading, the canvas or the error text, the profile name, and an OK button.
- The OK button carries `accent_container` and `on_container`.
- The canvas keeps the two literal colors. A QR code stays dark on light in every theme.

### 8. `pages/Index.ets`

#### 8.1 Imports and state

Add imports:

```ts
import { ShareQrDialog } from './QrDialog';
import { UndoBin, UNDO_TIMEOUT_MS } from '../model/UndoRemoval';
import {
  PHASE_STOPPING, activeProfileIds, isEnabled, isProfileEditable,
} from '../model/Diagnostics';
import { formatTraffic, withLive } from '../model/TrafficStats';
```

`Diagnostics` already exports the other phase constants. Keep the existing import list and extend it.

Add state and fields to `struct Index`:

```ts
@State pendingIds: string[] = [];       // the ids under the undo bar
@State shareUrl: string = '';           // the URI for the QR dialog
@State shareName: string = '';          // the name for the QR dialog
private undo: UndoBin = new UndoBin();
private undoTimer: number = -1;
private scroller: Scroller = new Scroller();
private dragFlushed: boolean = false;
private proxyProfileId: string = '';
private qrDialog: CustomDialogController = new CustomDialogController({
  builder: ShareQrDialog({
    url: this.shareUrl,
    name: this.shareName,
    onError: (message: ResourceStr) => {
      promptAction.showToast({ message: message });
    },
  }),
  autoCancel: true,
});
```

Remove the fields `lastDeleted` and `lastDeletedIndex`.

#### 8.2 List and search

- Set the toolbar title to `$r('app.string.index_title_profiles')`.
- Render the `TextInput` for `search` for every list size. Remove the `if (this.profiles.length > 1)` condition.
- Change `shown()` to `return ProfileStore.filter(this.profiles, this.search, this.pendingIds);`.
- Keep `ProfileStore.ensureNotEmpty()` in `reload()`. An empty store still gets one default profile.
- Add `rowKey(profile: Profile): string`. Use it as the `ForEach` key. The key holds every value the row shows, the edit gate, and the selected flag.
- Add `scroller: this.scroller` to `List({ space: 8, scroller: this.scroller })`.
- Add `scrollToSelected()`. It reads `ProfileStore.indexOf(this.shown(), this.currentId)` and calls `this.scroller.scrollToIndex(index, true)` when the index is at least zero.
- Add `reloadThenScroll()`. It awaits `reload()`, then calls `scrollToSelected()` in a zero-delay timer.
- Call `reloadThenScroll()` from `aboutToAppear()` and `onPageShow()` in place of `reload()`.

#### 8.3 Row input gates

Add:

```ts
private isRowEditable(profile: Profile): boolean {
  return isProfileEditable(this.phase,
    activeProfileIds(this.profiles, this.currentId), profile.id);
}
```

Change these methods:

- `selectProfile(profile)` returns at once when `!isEnabled(this.phase)`.
- `dropProfile(insertIndex)` returns at once when `!isEnabled(this.phase)`. Keep the existing refusal while a search query is active.
- `disconnect()` returns at once when `this.phase === PHASE_STOPPING`.
- `connect()` returns at once when `this.phase === PHASE_STOPPING`.

#### 8.4 `PHASE_STOPPING` transitions

- `disconnect()` sets `this.phase = PHASE_STOPPING` before it stops the proxy or the extension. It sets `PHASE_IDLE` in the existing `finally` block or after the proxy stop.
- `reloadTunnel()` sets `this.phase = PHASE_STOPPING` before `stopVpnExtensionAbility`. It keeps the value through `waitForVpnStopped` and `settleSessionTraffic`. It sets `PHASE_CONNECTING` at the existing place before `startVpn()`.
- `pollTick()` returns after the stats update when `this.phase === PHASE_STOPPING`.
- `resumeStatus()` returns at once when `this.phase === PHASE_STOPPING`.
- `isUp()` includes `PHASE_STOPPING`.
- `statusText()` returns `$r('app.string.index_stopping')` for `PHASE_STOPPING`.
- `statusColor()` returns `$r('app.color.text_secondary')` for `PHASE_STOPPING`.

#### 8.5 Drag

- `onItemDragStart` returns at once and sets `dragFrom = -1` when `!isEnabled(this.phase)`.
- `onItemDragStart` sets `dragFrom = itemIndex` and `dragFlushed = false` when input is enabled.
- Add `onItemDragMove`. On the first call of one drag, set `dragFlushed = true` and call `commitRemovals()` without await. This flush is the first row crossover.
- `onItemDrop` returns when `!isEnabled(this.phase)`. Otherwise it keeps the existing `isSuccess` check and calls `dropProfile(insertIndex)`.

#### 8.6 Swipe delete and the undo bar

Replace `removeProfile(profile)` and `undoDelete()` with these methods:

```ts
private stageRemoval(profile: Profile): void
private syncPending(): void
private startUndoTimer(): void
private stopUndoTimer(): void
private async commitRemovals(reloadList: boolean = true): Promise<void>
private async undoRemovals(): Promise<void>
private async flushRemovals(): Promise<void>
private async showResult(message: ResourceStr): Promise<void>
```

Rules:

- `stageRemoval()` returns when `!this.isRowEditable(profile)`. Otherwise it calls `this.undo.add(profile.id)`, `syncPending()`, and `startUndoTimer()`.
- `syncPending()` sets `this.pendingIds = this.undo.ids()`.
- `startUndoTimer()` stops the old timer and sets one `setTimeout` of `UNDO_TIMEOUT_MS` that calls `commitRemovals()`.
- `commitRemovals()` returns at once when the bin is empty.
- `commitRemovals()` stops the timer, takes `this.undo.ids()`, clears the bin, and syncs. It calls `ProfileStore.remove(abilityContext(), id)` for each id. It collects a failed id and puts it back in the bin. It reports a failure and restarts the timer when any id fails. It calls `reload()` when `reloadList` is true.
- `undoRemovals()` stops the timer, clears the bin, and syncs. It does not write the store.
- `flushRemovals()` awaits `commitRemovals()`.
- `showResult()` awaits `flushRemovals()` and calls `promptAction.showToast({ message })`.
- `aboutToDisappear()` stops the undo timer and calls `commitRemovals(false)` without await. The page is gone, so the commit must not reload it.

Replace the delete confirmation dialog and its strings. The undo bar replaces the modal `promptAction.showDialog`.

Place the undo bar after the `List` and before the status bar:

```ts
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
```

#### 8.7 Swipe action on the row

Attach `swipeAction` to each `ListItem`:

```ts
.swipeAction(this.isRowEditable(profile)
  ? {
    end: {
      builder: () => {
        this.SwipeDelete(profile);
      },
      onAction: () => this.stageRemoval(profile),
      actionAreaDistance: 64,
    },
  }
  : {})
```

Add `@Builder SwipeDelete(profile: Profile)`. It renders one `Row` with `common_delete`. The text uses `$r('app.color.on_container')`. The fill uses `$r('app.color.error_container')`.

The `end` action area is the right side in a left-to-right layout. A swipe to the left reveals it. That is the swipe toward the start edge. Verify the right-to-left case on a device.

#### 8.8 Share popup and QR dialog

Add:

```ts
private async openEditor(profile: Profile): Promise<void>
private openShareQr(profile: Profile): void
private async shareCopy(profile: Profile): Promise<void>
private async openManualSettings(): Promise<void>
```

Rules:

- `openEditor()` reads `ProfileStore.getAll(abilityContext())`. It returns silently after `reload()` when the id is gone. Otherwise it pushes `pages/ProfileEdit` with `{ id: profile.id }`.
- `openShareQr()` sets `shareUrl = profile.toUri()` and `shareName = profile.displayName()`, then calls `this.qrDialog.open()`.
- `shareCopy()` calls `writeClipboard(profile.toUri())` and then `showResult($r('app.string.index_share_copied'))`. On an error it calls `reportFailure($r('app.string.index_op_copy'), e)`.
- `openManualSettings()` awaits `flushRemovals()` and then pushes `pages/ProfileEdit`.
- Change the `AddMenu()` Manual Settings item to call `openManualSettings()`.
- Call `await this.flushRemovals()` at the start of `importText()`. This hook covers every import path.
- Replace the success toasts in `importText()`, `exportToFile()`, and `copyToClipboard()` with `await this.showResult(...)`.

#### 8.9 Live counters

Add:

```ts
private liveProfileId(): string {
  if (this.proxyUp) {
    return this.proxyProfileId;
  }
  const reported = this.lastStatus?.profileId ?? '';
  return reported.length > 0 ? reported : this.currentId;
}
```

- Set `this.proxyProfileId = profile.id` in `connectProxy()`.
- Clear `this.proxyProfileId = ''` in the proxy branch of `disconnect()`.
- Set `this.lastStatus = null` in `startHealthPolling()`.
- Change `profileTx()` to `return withLive(profile.tx, this.txTotal, profile.id === this.liveProfileId());`.
- Change `profileRx()` the same way.

The live counters belong to the running profile. They do not belong to the selected profile. The two ids differ during a profile switch.

#### 8.10 `struct ProfileRow`

Change the props and callbacks.

Remove:

- `onDelete: () => void`.

Add:

```ts
@Prop subscriptionActive: boolean = false;
@Prop editable: boolean = true;
onEdit: () => void = () => {
};
onSubscription: () => void = () => {
};
onShareQr: () => void = () => {
};
onShareCopy: () => void = () => {
};
```

Change the build:

- Title: `Text(this.profile.displayName())`.
- Secondary line: render only when `this.profile.displaySecondary().length > 0`. Use two `maxLines`. Remove the method from this line.
- Keep the latency text in the same row as the secondary line.
- Traffic: render only when the text is not empty. Use `formatTraffic(this.tx, this.rx)`.
- Test action: keep `$r('app.string.common_test')` and the existing latency test callback.
- Edit or subscription action:
  - Show `$r('app.string.common_edit')` when `!this.subscriptionActive`.
  - Show `$r('app.string.index_row_subscription')` when `this.subscriptionActive`.
  - Both call `onEdit` or `onSubscription`.
  - Both use `$r('app.color.text_secondary')` and `.enabled(false)` when `!this.editable`.
  - Both use `$r('app.color.accent')` when `this.editable`.
- Share action: `Text($r('app.string.index_row_share'))` with `.bindMenu(this.ShareMenu())`. It is never disabled.
- Add `@Builder ShareMenu()`. It renders one `Menu` with two items:
  - `$r('app.string.qr_title')` calls `onShareQr`.
  - `$r('app.string.index_share_copy')` calls `onShareCopy`.
- Remove the `✕` delete text.

Add `rowKey(profile: Profile)` to `Index` and use it as the `ForEach` key:

```ts
private rowKey(profile: Profile): string {
  return [
    profile.id, profile.name, profile.host, profile.remotePort, profile.plugin,
    profile.subscriptionStatus,
    this.profileTx(profile), this.profileRx(profile),
    formatLatency(this.latencyFor(profile.id)), this.measuringId === profile.id,
    this.isRowEditable(profile), profile.id === this.currentId,
  ].join('|');
}
```

The key must change when the phase changes, when a profile field changes, and when the selection changes. Otherwise `ForEach` reuses a row with the old values, the old swipe action, the old dimmed icon, or the old selected mark.

### 9. Resources

Add these entries to `resources/base/element/string.json`:

| Name | English |
| --- | --- |
| `index_title_profiles` | Profiles |
| `index_row_share` | Share |
| `index_row_subscription` | Subscription |
| `index_share_copy` | Export to Clipboard |
| `index_share_copied` | Copied the profile link |
| `index_removed` | Removed |
| `index_removed_n` | %d items removed |
| `index_stopping` | Disconnecting… |

Add the same names to `resources/zh_CN/element/string.json`:

| Name | Chinese |
| --- | --- |
| `index_title_profiles` | 配置 |
| `index_row_share` | 分享 |
| `index_row_subscription` | 订阅 |
| `index_share_copy` | 导出到剪贴板 |
| `index_share_copied` | 已复制配置链接 |
| `index_removed` | 已删除 |
| `index_removed_n` | 已删除 %d 项 |
| `index_stopping` | 正在断开… |

The QR menu item and the QR dialog reuse the existing `qr_title`. The delete area reuses the existing `common_delete`. The edit and test actions reuse `common_edit` and `common_test`.

### 10. Tests

- Add `entry/src/test/ParityU02.test.ets` with the suite name `U02`.
- Import the suite in `entry/src/test/List.test.ets` and call it from `testsuite()`.
- The spec imports only model files. It does not import a page.

### State and data

### Page state

| Name | Type | Initial | Use |
| --- | --- | --- | --- |
| `profiles` | `Profile[]` | `[]` | The visible stored profiles, in user order. |
| `currentId` | `string` | `''` | The selected profile id. |
| `phase` | `string` | `PHASE_IDLE` | The service phase. It gates row input. |
| `search` | `string` | `''` | The filter text. |
| `pendingIds` | `string[]` | `[]` | The ids under the undo bar. A mirror of the bin. |
| `shareUrl` | `string` | `''` | The URI for the QR dialog. |
| `shareName` | `string` | `''` | The name for the QR dialog. |
| `proxyUp` | `boolean` | `false` | True while proxy mode serves from this process. |
| `lastStatus` | `VpnStatus \| null` | `null` | The last status-file record. It names the live profile. |

### Private fields

| Name | Type | Use |
| --- | --- | --- |
| `undo` | `UndoBin` | The pending removals. |
| `undoTimer` | `number` | The one timeout for the bar. |
| `scroller` | `Scroller` | The list scroll position. |
| `dragFlushed` | `boolean` | True after the first crossover of one drag. |
| `proxyProfileId` | `string` | The profile proxy mode started. |
| `qrDialog` | `CustomDialogController` | The shared QR dialog. |

### Pending-removal state machine

| From | Event | To | Effect |
| --- | --- | --- | --- |
| Clean | Swipe an editable row | Pending | Add the id. Hide the row. Start the timer. Show the bar. |
| Pending | Swipe another row | Pending | Add the id. Restart the timer. The count grows. |
| Pending | Tap Undo | Clean | Clear the bin. Show the rows again. No store write. |
| Pending | Timer ends | Clean | Delete each id from the store. Reload. |
| Pending | Drag crossover, add, page exit, or a result message | Clean | Delete each id from the store. Reload. |
| Pending | Store delete fails | Pending | Put the failed id back. Show the failure. Restart the timer. |

### Data rules

- The store keeps every swiped profile until the delete commits. The row hides through `pendingIds`.
- The store order never changes during a pending removal. Undo therefore restores the original index by construction.
- The bin is memory only. A process death leaves every profile in the store. This is safe.
- `pendingIds` is a subset of the stored ids.
- `store/profiles.json`, `store/current_profile_id`, and their formats do not change.
- No new store file exists. No migration exists.
- The live traffic counters belong to `liveProfileId()`. The stored counters stay unchanged until a session settlement.

### Row content

| Element | Source | Hidden when |
| --- | --- | --- |
| Title | `profile.displayName()` | Never |
| Secondary line | `profile.displaySecondary()` | The text is `''` |
| Traffic line | `formatTraffic(tx, rx)` | The text is `''` |
| Selected mark | `profile.id === currentId` | The ids differ |
| Edit or subscription icon | `subscriptionStatus === STATUS_ACTIVE` selects the subscription icon | Never. The icon is dimmed when locked. |
| Share icon | Always present | Never |

### Validation and errors

| Case | Check | Result |
| --- | --- | --- |
| Swipe on a locked row | `isProfileEditable()` is false | No action area exists and no removal starts. |
| Swipe again while pending | The id is already in the bin | The bin ignores the duplicate. |
| Drag while `PHASE_STOPPING` | `isEnabled()` is false | `onItemDrop` returns and the store does not change. |
| Move write failure | `ProfileStore.move()` rejects | Report `index_op_reorder`. Reload the stored order. |
| Commit delete failure | `ProfileStore.remove()` rejects | Keep the id pending. Report `index_op_delete_profile`. Restart the timer. |
| Undo | The store never changed | No error is possible. The rows return. |
| Share copy failure | `writeClipboard()` rejects | Report `index_op_copy`. Do not log the URI. |
| Clipboard write | Always | The data uses `ShareOption.LOCALDEVICE`. |
| QR encode failure | `encodeQr()` throws | Close the dialog and show `qr_too_long`. |
| Empty QR URL | `url.length === 0` | Treat the input as an encode failure. |
| Edit a missing profile | `ProfileStore.getAll(abilityContext())` holds no such id | Reload and open no editor. |
| Search with no match | `ProfileStore.filter()` returns `[]` | Show an empty list. The selected id stays. |
| Unknown phase | `isEnabled()` is true, `isProfileEditable()` locks an active id | Input stays usable. The active profile stays locked. |
| Empty query | `search.trim()` is `''` | Show every non-pending profile in user order. |
| Empty undo bin | `commitRemovals()` reads no ids | Return without a store write, a reload, or a message. |

The failure log never includes a password. Log the error object only. Never log the `ss://` URI.

### Test plan

All rows run on the host with `./test-arkts-host.sh`. The runner compiles `entry/src/main/ets/model/` and the specs. A page is not in the compile set, so every planned test targets a model function.

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| TC-U02-38 | `entry/src/test/ParityU02.test.ets` | `U02#list-orders-by-user-order` | unit |
| TC-U02-38 | `entry/src/test/ParityU02.test.ets` | `U02#list-hides-obsolete-profiles` | unit |
| TC-U02-37 | `entry/src/test/ParityU02.test.ets` | `U02#title-uses-name-or-host-port` | unit |
| R-UB-08 | `entry/src/test/ParityU02.test.ets` | `U02#secondary-line-uses-address-when-named` | unit |
| R-UB-09 | `entry/src/test/ParityU02.test.ets` | `U02#secondary-line-adds-plugin` | unit |
| TC-U02-40 | `entry/src/test/ParityU02.test.ets` | `U02#secondary-line-empty-when-nothing-to-show` | unit |
| R-UB-11 | `entry/src/test/ParityU02.test.ets` | `U02#traffic-line-empty-at-zero` | unit |
| R-UB-12 | `entry/src/test/ParityU02.test.ets` | `U02#live-counters-only-for-running-profile` | unit |
| TC-U02-04 | `entry/src/test/ParityU02.test.ets` | `U02#search-ignores-case` | unit |
| TC-U02-04 | `entry/src/test/ParityU02.test.ets` | `U02#search-matches-host` | unit |
| TC-U02-04 | `entry/src/test/ParityU02.test.ets` | `U02#search-ignores-port` | unit |
| TC-U02-06 | `entry/src/test/ParityU02.test.ets` | `U02#empty-search-restores-all` | unit |
| TC-U02-03 | `entry/src/test/ParityU02.test.ets` | `U02#row-input-refused-while-stopping` | unit |
| TC-U02-34 | `entry/src/test/ParityU02.test.ets` | `U02#idle-phase-accepts-row-input` | unit |
| TC-U02-35 | `entry/src/test/ParityU02.test.ets` | `U02#edit-enabled-when-profile-not-active` | unit |
| TC-U02-42 | `entry/src/test/ParityU02.test.ets` | `U02#active-ids-cover-udp-fallback` | unit |
| TC-U02-13 | `entry/src/test/ParityU02.test.ets` | `U02#undo-bin-counts-removals` | unit |
| TC-U02-11 | `entry/src/test/ParityU02.test.ets` | `U02#undo-restores-store-order` | unit |
| TC-U02-12 | `entry/src/test/ParityU02.test.ets` | `U02#commit-clears-the-bin` | unit |
| TC-U02-43 | `entry/src/test/ParityU02.test.ets` | `U02#pending-removal-stays-hidden-under-search` | unit |
| R-UB-50 | `entry/src/test/ParityU02.test.ets` | `U02#selected-index-found-for-scroll` | unit |

The anchors are `entry/src/test/ParityU02.test.ets::U02#<name>`.

Test detail:

| Test name | Input | Expected |
| --- | --- | --- |
| `U02#list-orders-by-user-order` | Orders 2, 1, 3 | Ids appear as 1, 2, 3. The input array keeps its order. |
| `U02#list-hides-obsolete-profiles` | One user profile and one obsolete profile | `visible()` returns the user profile only. |
| `U02#title-uses-name-or-host-port` | `Home` at `1.2.3.4:8388`. Then an empty name. | `Home`. Then `1.2.3.4:8388`. |
| `U02#secondary-line-uses-address-when-named` | Name `Home`, no plugin | The line is `1.2.3.4:8388`. |
| `U02#secondary-line-adds-plugin` | Name `Home`, plugin `obfs-local`. Then an empty name with the same plugin. | `1.2.3.4:8388\nPlugin: obfs-local`. Then `Plugin: obfs-local`. |
| `U02#secondary-line-empty-when-nothing-to-show` | Empty name, no plugin | The line is `''`. |
| `U02#traffic-line-empty-at-zero` | `tx = 0`, `rx = 0` | The line is `''`. |
| `U02#live-counters-only-for-running-profile` | Stored 100, live 10, running true and false | 110 and 100. |
| `U02#search-ignores-case` | Query `ALP`, name `Alpha` | The profile stays. |
| `U02#search-matches-host` | Query `example`, host `a.example` | The profile stays. |
| `U02#search-ignores-port` | Query `8388`, port 8388 | The list is empty. |
| `U02#empty-search-restores-all` | Query `''`, three profiles | All three appear in order. |
| `U02#row-input-refused-while-stopping` | `PHASE_STOPPING` and every other phase | False for stopping. True for the others. |
| `U02#idle-phase-accepts-row-input` | `PHASE_IDLE` | True. This records the Stopped mapping. |
| `U02#edit-enabled-when-profile-not-active` | Connected with active `a`, ids `[a, b]` | `a` is locked. `b` is editable. Idle unlocks both. |
| `U02#active-ids-cover-udp-fallback` | Profile `a` names `b` as its fallback | The ids are `[a, b]`. A missing fallback is dropped. |
| `U02#undo-bin-counts-removals` | Add `a`, `b`, `a` | Size 2. Ids are `[a, b]`. |
| `U02#undo-restores-store-order` | Hide `a` and `b`, then clear the bin | The filter returns the original order. |
| `U02#commit-clears-the-bin` | Add `a`, read `ids()`, call `clear()` | The copy is `[a]`. The bin is empty. |
| `U02#pending-removal-stays-hidden-under-search` | Hidden `a`, query `alp` | The list is empty. |
| `U02#selected-index-found-for-scroll` | Selected id at index 1, then a missing id | 1, then -1. |

The device cases in `docs/versions/5.4.0/e2e/U02.md` stay the acceptance for the gestures and the dialogs. The host specs cover the decisions behind them.

### Platform notes

- `SwipeActionItem` has `builder`, `onAction`, and `actionAreaDistance`. The SDK declares them in `list_item.d.ts`. Use `end` for a swipe toward the start edge in a left-to-right layout.
- ArkUI has no snackbar API. The undo bar is an in-page row. It does not float over other content.
- `promptAction.showToast()` has no action button. It cannot carry Undo.
- `ForEach` caches a row by key. The key must include `isRowEditable(profile)`. Otherwise a phase change leaves a stale swipe action or a stale dimmed icon.
- ArkUI may still show a drag preview when `onItemDragStart` returns no builder. The drop handler refuses the move. A device check confirms the row stays.
- The host runner compiles `model/` only. A rule that needs a test must live in a model function. Do not test a page method.
- The QR dialog draws at 264 vp, the Android size. Its canvas keeps the two literal black and white colors. The page uses no theme token there for a reason.
- The QR encoder already implements R-UB-22. `encodeQr()` sets the UTF-8 ECI hint only when the text is not ISO-8859-1 and the mode is byte. The dialog needs no charset code.
- `pasteboard.PasteData.shareOption` takes `ShareOption.LOCALDEVICE`. The `localOnly` field exists and is deprecated in favor of `shareOption`. HarmonyOS has no sensitive flag. The profile password can still appear in the system clipboard preview.
- `PHASE_IDLE` is the HarmonyOS stopped state. HarmonyOS has no bound-but-idle service. The Android Idle refusal in TC-U02-34 has no direct equivalent, and this LLD treats the idle page as Stopped.
- R-UB-34: Android saves each changed profile. `ProfileStore.move()` renumbers every key and saves the list once through `JsonStore`. The resulting order is the same. The single write is atomic.
- `PHASE_STOPPING` may also be defined by U01. Keep one definition in `Diagnostics.ets` and let both units read it.
- The row Test button is a HarmonyOS addition. It stays. It is not part of the Android row.
- The search field stays visible. Android expands a SearchView from the toolbar. The filter behavior is the same.
- The toolbar Export menu copies the profile JSON array. The row popup copies one `ss://` URI. The two actions differ by design.
- The list scroll uses `Scroller.scrollToIndex(index, true)`. Call it after the list has rendered. A zero-delay timer is enough.
- Confirm the shared `qrDialog` controller reads the current `shareUrl` and `shareName` on each open. If the builder captures the first values, rebuild the controller in `openShareQr()`.
- A profile switch settles the old session before the new start. The live counters are keyed by the status-file profile id, not by the selected id. This prevents a counter from moving to the new row during the switch.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| Q-1 | Does U01 define `PHASE_STOPPING` and its transitions, or does U02 own them? This LLD assumes one definition in `Diagnostics.ets`. | U01 owner |
| Q-2 | Must HarmonyOS reproduce the stale selected id after a committed delete (R-UB-33)? This LLD keeps the selection valid. | Product owner |
| Q-3 | `architecture.md` lists multiselect actions for U02. The U02 machine spec has no multiselect control or rule. Is multiselect in this batch? | Product owner |
| Q-4 | Does the right-to-left layout map the ArkUI `end` action area to the start edge on a device? A device check is needed. | HarmonyOS platform owner |
| Q-5 | Is the Chinese text for the removed count correct with `%d`? HarmonyOS has no plural resource form. | Product owner |
| Q-6 | The QR failure shows `qr_too_long`, not the raw exception text. Confirm this localized message is acceptable for TC-U02-28. | Product owner |
| Q-7 | May the row keep the Test action? It is not in the Android row layout but it exists in 5.3.5. | Product owner |

<a id="u03"></a>
## U03 Profile editor

### Scope

This unit covers the profile editor and the UDP fallback chooser.

In scope:

- The editor header: the title `Profile config`, a close control that discards the draft, and a Remove action with confirmation.
- The editor fields: the IPv6 switch, the UDP fallback row, the five-digit port field, and the port normalization on Save.
- The editor load: close at once when the profile id does not resolve to a stored profile.
- The manual profile: create the row with the code defaults and copy the current profile's feature fields.
- The UDP fallback chooser: the Disabled row and the eligible profile rows.
- The draft rule: a fallback choice stays in the editor draft until Save.

Out of scope:

- Apps VPN mode and the app picker. Owner unit: U07.
- The plugin chooser, Configure..., the plugin help, the untrusted warning, and the options validation. Owner unit: U08.
- Import and export of `udp_fallback`. Owner unit: U04.
- UDP fallback behavior in the tunnel. The core has no fallback config key. See Open questions.
- IPv6 routing in the tunnel. The tun stays IPv4 only.
- Metered Hint, Direct Boot storage, and plugin signature checks. These need Android platform surfaces.

Parity result after this unit:

| Result | E2E cases |
| --- | --- |
| implemented | TC-U03-01, TC-U03-03, TC-U03-04, TC-U03-05, TC-U03-06, TC-U03-07, TC-U03-08, TC-U03-09, TC-U03-10, TC-U03-12, TC-U03-14, TC-U03-18, TC-U03-19, TC-U03-20, TC-U03-21, TC-U03-22, TC-U03-23, TC-U03-24, TC-U03-27, TC-U03-28, TC-U03-31 |
| partial | TC-U03-02 (method default), TC-U03-13 (method list), TC-U03-15 (U08), TC-U03-25 (plugin label), TC-U03-29 (password row) |
| missing | TC-U03-11 (U07), TC-U03-16 (U08), TC-U03-26 (U08) |
| android-only | TC-U03-17, TC-U03-30 |

TC-U03-02 stays partial on the Encrypt Method field. The core cannot run the Android default `aes-256-cfb`, so the form shows `AES-256-GCM`. See Platform notes.

### Files to change

| # | File | Change |
| --- | --- | --- |
| 1 | `entry/src/main/ets/model/Profile.ets` | Add `normalizeRemotePort`, `copyFeatureSettings`, `newManualProfile`, and `isSubscriptionLocked`. |
| 2 | `entry/src/main/ets/model/UdpFallback.ets` | New. Add the fallback eligibility, display, row index, and handoff codec functions. |
| 3 | `entry/src/main/ets/model/AppContext.ets` | Add `setPendingFallback` and `takePendingFallback`. |
| 4 | `entry/src/main/ets/model/Diagnostics.ets` | Add `ipv6SwitchEnabled`. |
| 5 | `entry/src/main/ets/pages/ProfileEdit.ets` | Add the IPv6 switch, the fallback row, the Remove action, the title, the close control, the port cap, the load gate, and the save changes. |
| 6 | `entry/src/main/ets/pages/UdpFallback.ets` | New chooser page. |
| 7 | `entry/src/main/ets/pages/Index.ets` | The Manual Settings item creates the profile row, then opens the editor. |
| 8 | `entry/src/main/resources/base/element/string.json` | Add 9 English strings. |
| 9 | `entry/src/main/resources/zh_CN/element/string.json` | Add the same 9 strings in Chinese. |
| 10 | `entry/src/main/resources/base/profile/main_pages.json` | Register `pages/UdpFallback`. |
| 11 | `entry/src/test/ParityU03.test.ets` | New host spec suite. |
| 12 | `entry/src/test/List.test.ets` | Import and run the new suite. |

### Implementation plan

### model/Profile.ets

Add three module constants. Keep them private.

```ts
const MANUAL_HOST = 'example.shadowsocks.org';
const MANUAL_PASSWORD = 'u1rRWTssNv0p';
const MANUAL_METHOD = 'aes-256-gcm';
```

Add `normalizeRemotePort(text: string): number`.

- Read the text with `Number.parseInt(text, 10)`.
- Return 8388 when the value is `NaN`, less than 1, or greater than 65535.
- Return the value in every other case.
- This function is the only port rule. The dialog and the save path use it.

Add `copyFeatureSettings(from: Profile, to: Profile): void`.

- Copy `route`, `ipv6`, and `udpdns` from `from` to `to`.
- Do not copy `host`, `remotePort`, `password`, `method`, `name`, `remoteDns`, or `udpFallbackId`. Android copies none of those.
- The app has no metered, per-app, bypass, or individual fields. The copy covers the fields that exist.

Add `newManualProfile(current: Profile | null): Profile`.

- Create `new Profile()`.
- Set `host = MANUAL_HOST`, `name = MANUAL_HOST`, `remotePort = 8388`, `password = MANUAL_PASSWORD`, and `method = MANUAL_METHOD`.
- The name takes the host because the profile row renders `name` without a fallback. An empty name draws a blank row.
- Call `copyFeatureSettings(current, profile)` when `current` is not null.
- Call `profile.ensureId()`.
- Return the profile.
- Do not change the constructor defaults. Imports and `ProfileStore.ensureNotEmpty` keep the current defaults.

Add `isSubscriptionLocked(profile: Profile): boolean`.

- Return `profile.subscriptionStatus === STATUS_ACTIVE`.
- Do not test `subscriptionId`. The rule uses the status alone, as Android does.

### model/UdpFallback.ets (new)

Import `Profile` and `STATUS_OBSOLETE` from `./Profile`. Keep this module free of kit imports, so the host spec can load it.

Add an internal interface for the handoff value.

```ts
interface FallbackChoiceJson {
  profileId?: string;
  fallbackId?: string;
}
```

Add `eligibleFallbacks(profiles: Profile[], editedId: string): Profile[]`.

- Keep a profile when all three conditions hold:
  - `subscriptionStatus !== STATUS_OBSOLETE`.
  - `id !== editedId`.
  - `plugin.length === 0`.
- Preserve the input order. `ProfileStore.getAll` already sorts by `userOrder`.

Add `fallbackDisplayName(profile: Profile): string`.

- Return `profile.name` when it is not empty.
- Return `[host]:port` when the host contains `:`.
- Return `host:port` in every other case.
- The two address forms match Android's `formattedAddress`.

Add `fallbackSummary(profiles: Profile[], fallbackId: string): string`.

- Return `''` when `fallbackId` is empty.
- Find the profile with that id.
- Return `''` when no profile has the id. A dangling id shows as Disabled and stays in the draft, as Android does.
- Return `fallbackDisplayName(profile)` in every other case.

Add `fallbackRowIndex(profiles: Profile[], fallbackId: string): number`.

- Return `0` when no profile has the id.
- Return `index + 1` in every other case.
- Row 0 is the Disabled row. The chooser uses the result for `Scroller.scrollToIndex`.

Add `encodeFallbackChoice(profileId: string, fallbackId: string): string`.

- Return `JSON.stringify({ profileId, fallbackId })`.
- The empty `fallbackId` means Disabled.

Add `decodeFallbackChoice(profileId: string, raw: string): string | null`.

- Return `null` when `raw` is empty.
- Parse the JSON in a `try` block.
- Return `null` when the parse throws.
- Return `null` when `parsed.profileId !== profileId`.
- Return `null` when `typeof parsed.fallbackId !== 'string'`.
- Return `parsed.fallbackId` in every other case. The value can be `''` for Disabled.
- The caller must test against `null`, not against a falsy value.

### model/AppContext.ets

Import `decodeFallbackChoice` and `encodeFallbackChoice` from `./UdpFallback`.

Add a private key constant.

```ts
const FALLBACK_KEY = 'pending_udp_fallback';
```

Add `setPendingFallback(profileId: string, fallbackId: string): void`.

- Call `AppStorage.setOrCreate(FALLBACK_KEY, encodeFallbackChoice(profileId, fallbackId))`.
- A new choice replaces an older one.

Add `takePendingFallback(profileId: string): string | null`.

- Read the key with `AppStorage.get`.
- Return `null` when the value is absent or empty.
- Call `decodeFallbackChoice(profileId, raw)`.
- Return `null` when the decode returns `null`. Leave the stored value in place.
- Clear the key with `AppStorage.setOrCreate(FALLBACK_KEY, '')`.
- Return the decoded value.
- The `''` result means Disabled. The `null` result means no choice.

### model/Diagnostics.ets

Add `ipv6SwitchEnabled(serviceMode: string): boolean`.

- Return `serviceMode === MODE_VPN`.
- Place it after the `MODE_*` constants.
- The function is pure. The editor and the host spec use it.

### pages/ProfileEdit.ets

Add these imports:

- `MODE_VPN` and `ipv6SwitchEnabled` from `../model/Diagnostics`.
- `SettingsStore` from `../model/Settings`.
- `isSubscriptionLocked`, `newManualProfile`, and `normalizeRemotePort` from `../model/Profile`.
- `fallbackSummary` from `../model/UdpFallback`.
- `takePendingFallback` from `../model/AppContext`. The editor does not write the pending key.
- `UdpFallbackParams` from `./UdpFallback`.

Change the state and private properties.

- Add `@State ipv6: boolean = false`.
- Add `@State udpFallbackId: string = ''`.
- Add `@State fallbackName: string = ''`.
- Add `@State serviceMode: string = MODE_VPN`.
- Add `@State ready: boolean = false`.
- Add `@State fallbackTouched: boolean = false`.
- Add `private allProfiles: Profile[] = []`.

Change `aboutToAppear`.

1. Load the service mode with `SettingsStore.load(abilityContext())`. Set `this.serviceMode` in the success branch. Keep `MODE_VPN` in the failure branch.
2. Read `EditParams` as today.
3. When `id` is empty, initialize the form from `newManualProfile(null)`. Set `ready = true`. Set `initialForm = formSnapshot()`. Return.
4. Set `profileId = id`.
5. Call `ProfileStore.getAll(abilityContext())`.
6. On success, store the list in `allProfiles`.
7. Find the profile with the id. Call `router.back()` and return when no profile has the id. This closes a stale launch before the form draws.
8. Initialize `editedProfile`, `name`, `host`, `remotePort`, `password`, `methodIndex`, `methodCustom`, `routeIndex`, `pluginOptions`, `pluginIndex`, `pluginOpts`, `remoteDns`, `ipv6`, and `udpFallbackId`.
9. Set `readOnly = isSubscriptionLocked(profile)`.
10. Set `fallbackName = fallbackSummary(allProfiles, udpFallbackId)`.
11. Set `ready = true`. Set `initialForm = formSnapshot()`.
12. On failure, show `app.string.profile_edit_load_failed` and call `router.back()`.

Add `onPageShow(): void`.

- Return when `profileId` is empty.
- Call `takePendingFallback(this.profileId)`.
- Return when the result is `null`.
- Set `udpFallbackId` to the result. The value `''` means Disabled.
- Set `fallbackTouched = true`. A tap on the checked row still makes the draft dirty, as R-UC-28 requires.
- Set `fallbackName = fallbackSummary(this.allProfiles, this.udpFallbackId)`.

Change `formSnapshot()`.

- Append `this.ipv6 ? '1' : '0'` and `this.udpFallbackId` to the joined values.
- Keep the existing separator.

Change `isDirty()`.

- Return `this.fallbackTouched || this.formSnapshot() !== this.initialForm`.

Change `buildProfile()`.

- Replace the port line with `profile.remotePort = normalizeRemotePort(this.remotePort)`.
- Add `profile.ipv6 = this.ipv6`.
- Add `profile.udpFallbackId = this.udpFallbackId`.
- Keep every existing field.

Change `save()`.

- Remove the `ProfileStore.setCurrentId` call. Android's Apply writes the row and does not select it.
- Keep the required-field guard, the upsert, the failure toast, and `router.back()`.

Add `private async confirmRemove(): Promise<void>`.

- Return when `profileId` is empty.
- Show `promptAction.showDialog` with one title and two buttons:
  - Title: `app.string.profile_edit_remove_confirm`.
  - Button 0: `app.string.common_cancel`, color `app.color.text_body`.
  - Button 1: `app.string.profile_edit_remove`, color `app.color.error`.
- Wrap the call in `try`. Return on a rejection. A tap outside the dialog rejects the promise.
- Return when `answer.index !== 1`.
- Call `ProfileStore.remove(abilityContext(), this.profileId)` in a `try`.
- On failure, show `app.string.profile_edit_remove_failed` with the error message and return.
- Call `router.back()` on success.

Add `private openUdpFallback(): void`.

- Return when `profileId` is empty or `readOnly` is true.
- Build `UdpFallbackParams = { profileId: this.profileId, currentId: this.udpFallbackId }`.
- Call `router.pushUrl({ url: 'pages/UdpFallback', params })`.

Change `build()`.

- Keep the top row. Replace the right spacer with `Text('✕')`. The glyph calls `router.back()` directly. This control discards a dirty draft, as R-UC-35 requires.
- Keep the left `common_back` label. It calls `confirmLeave()`.
- Replace the centered title with `app.string.profile_edit_title`. Use it for both the add and the edit path.
- Wrap the form fields in `if (this.ready)`. Draw the header always.
- Keep the existing field order. Set `.maxLength(5)` on the port `TextInput`. Keep `InputType.Number`. Insert the IPv6 row after the Route select:
  - A `Row` with the label `app.string.profile_edit_ipv6` and a `Toggle({ type: ToggleType.Switch, isOn: this.ipv6 })`.
  - Set `.enabled(ipv6SwitchEnabled(this.serviceMode))` on the `Toggle`.
  - Set `this.ipv6` in `onChange`.
  - Add a hint line with `app.string.profile_edit_ipv6_hint` under the row.
- Insert the UDP fallback row after the plugin options field:
  - A `Row` with two lines. The first line is `app.string.profile_edit_udp_fallback`. The second line is `fallbackName` when it is not empty, else `app.string.profile_edit_disabled`.
  - Add a chevron glyph on the right.
  - Set `.enabled(!this.readOnly && this.profileId.length > 0)`.
  - Set `.onClick(() => this.openUdpFallback())`.
- Add a Remove button above the QR button and above the Save button:
  - Show it when `profileId.length > 0`.
  - Use `app.string.profile_edit_remove`, `app.color.error_container`, and `app.color.on_container`.
  - Call `confirmRemove()`.
- Keep the QR button and the Save button.

### pages/UdpFallback.ets (new)

Import `router` from `@kit.ArkUI`, `Profile` from `../model/Profile`, `ProfileStore` from `../model/ProfileStore`, `abilityContext` and `setPendingFallback` from `../model/AppContext`, and `eligibleFallbacks`, `fallbackDisplayName`, and `fallbackRowIndex` from `../model/UdpFallback`.

Declare the page and its params.

```ts
export interface UdpFallbackParams {
  profileId: string;
  currentId: string;
}
```

Declare `@Entry @Component struct UdpFallback` with these state and private properties:

- `@State rows: Profile[] = []`.
- `@State currentId: string = ''`.
- `@State ready: boolean = false`.
- `private editedId: string = ''`.
- `private allProfiles: Profile[] = []`.
- `private scroller: Scroller = new Scroller()`.

Add `aboutToAppear(): void`.

1. Read `router.getParams()` as `UdpFallbackParams | null`.
2. Read `profileId`. Call `router.back()` and return when it is empty. This is R-UC-31.
3. Set `editedId = profileId`. Set `currentId` from `params.currentId`, and use `''` when the parameter is absent.
4. Call `ProfileStore.getAll(abilityContext())`.
5. On success, find the edited profile. Call `router.back()` and return when it is absent.
6. Store the list in `allProfiles`.
7. Set `rows = eligibleFallbacks(allProfiles, editedId)`.
8. When `currentId` is empty, set it from the stored profile's `udpFallbackId`.
9. Set `ready = true`.
10. On failure, call `router.back()`.

Add `private choose(fallbackId: string): void`.

- Call `setPendingFallback(this.editedId, fallbackId)`.
- Call `router.back()`.
- The value `''` is the Disabled row.

Add `@Builder ChoiceRow(label: ResourceStr, id: string, checked: boolean)`.

- Draw a `Row` with the label, a `Blank()`, and a check glyph when `checked` is true.
- Use `app.color.text_body` for the label and `app.color.accent` for the check glyph.
- Set `.onClick(() => this.choose(id))` on the row.

Change `build()`.

- Draw a header row with the title `app.string.profile_edit_udp_fallback` and a close `Text('✕')`. The close calls `router.back()` and stores nothing.
- Draw `List({ scroller: this.scroller })` when `ready` is true.
- Add the Disabled row first: `ChoiceRow($r('app.string.profile_edit_disabled'), '', currentId.length === 0)`.
- Add the profile rows with `ForEach(this.rows, ...)`. Use `fallbackDisplayName(profile)` as the label. Use `currentId === profile.id` for the check. Use `profile.id` as the key.
- Add `.onAppear` to the `List`. When `currentId` is not empty, call `this.scroller.scrollToIndex(fallbackRowIndex(this.rows, this.currentId))`. This is R-UC-30.
- Keep the default system back behavior. It calls `router.back()` and stores nothing.

### pages/Index.ets

Change the `index_add_manually` menu item.

- Replace the direct `router.pushUrl` call with `this.addManualProfile()`.

Add `private async addManualProfile(): Promise<void>`.

- Call `ProfileStore.getCurrent(abilityContext())`.
- Call `newManualProfile(current)`.
- Call `ProfileStore.upsert(abilityContext(), profile)`.
- Call `router.pushUrl({ url: 'pages/ProfileEdit', params: { id: profile.id } as EditParams })`.
- On failure, call `this.reportFailure($r('app.string.profile_edit_add_profile'), e as Object)`.
- The row exists before the editor opens. This is R-UC-36.
- Do not call `ProfileStore.setCurrentId`. Android does not select the new profile.

### Resources

Add these strings to `resources/base/element/string.json`:

| Name | Value |
| --- | --- |
| `profile_edit_title` | Profile config |
| `profile_edit_ipv6` | IPv6 route |
| `profile_edit_ipv6_hint` | Redirect IPv6 traffic to the remote server |
| `profile_edit_udp_fallback` | UDP fallback |
| `profile_edit_disabled` | Disabled |
| `profile_edit_remove` | Remove |
| `profile_edit_remove_confirm` | Are you sure you want to remove this profile? |
| `profile_edit_remove_failed` | Could not remove the profile: %s |
| `profile_edit_load_failed` | Could not load the profile |

Add the same names to `resources/zh_CN/element/string.json`:

| Name | Value |
| --- | --- |
| `profile_edit_title` | 服务器配置 |
| `profile_edit_ipv6` | IPv6 路由 |
| `profile_edit_ipv6_hint` | 将 IPv6 流量转发到远程服务器 |
| `profile_edit_udp_fallback` | UDP 备用服务器 |
| `profile_edit_disabled` | 已禁用 |
| `profile_edit_remove` | 移除 |
| `profile_edit_remove_confirm` | 确定要移除这个服务器吗？ |
| `profile_edit_remove_failed` | 无法移除服务器：%s |
| `profile_edit_load_failed` | 无法读取服务器配置 |

`profile_edit_remove_failed` takes one `%s`. Count it by hand at the call site.

Add `"pages/UdpFallback"` to `resources/base/profile/main_pages.json`.

### State and data

### States

| Object | States | Transitions |
| --- | --- | --- |
| Editor draft | clean, dirty | A field change makes it dirty. A fallback choice makes it dirty even when the value does not change. A save or a discard closes the editor. |
| Fallback handoff | none, waiting, taken | The chooser writes `waiting`. The editor for the same profile takes it and clears the key. A choice for another profile stays waiting. |
| Profile lock | editable, locked | A profile with `subscriptionStatus === STATUS_ACTIVE` opens locked. Every other profile opens editable. |
| IPv6 switch | enabled, disabled | The switch is enabled when `serviceMode === MODE_VPN`. The switch is disabled in proxy mode. |
| Fallback selection | disabled, profile | The Disabled row stores `''`. A profile row stores its id. Both close the chooser and mark the draft dirty. |

### Data

| Store | Key | Shape | Writer | Reader |
| --- | --- | --- | --- | --- |
| `filesDir/store/profiles.json` | profile record | `Profile.udpFallbackId` is a string. `''` means Disabled. | Editor Save through `ProfileStore.upsert` | Editor, chooser, list |
| AppStorage | `pending_udp_fallback` | JSON text `{ "profileId": string, "fallbackId": string }` | Chooser | Editor |
| Editor state | `initialForm`, `fallbackTouched` | Strings and a boolean | Editor | Editor |

- `udpFallbackId` already exists in `Profile` and in `ProfileStore.fromJson`. The store schema does not change.
- The pending key lives in the UI process memory. It does not survive an app restart. A lost key only loses an unsaved choice.
- The editor clears the key when it takes the choice. A second `onPageShow` without a new choice returns `null`.
- The chooser always writes a choice for the edited profile id. The editor ignores a choice for another id.
- `ProfileJson` does not carry `udp_fallback`. Import and export leave it out. U04 owns that field.

### Validation and errors

| Condition | Behavior | Text or token |
| --- | --- | --- |
| Host, password, or method is empty on Save | Keep the editor open. Show a toast. | `profile_edit_required_fields` |
| Port text is outside 1 through 65535 | Store 8388. | none |
| Port field holds five characters | Refuse the sixth character. | none |
| Port field receives a letter | The numeric input refuses it. | none |
| Profile id does not resolve on load | Close the editor before the form draws. Show no message. | none |
| Profile read fails on load | Show a toast. Close the editor. | `profile_edit_load_failed` |
| Save write fails | Show a toast. Keep the editor open. | `common_save_failed` |
| Remove is confirmed | Remove the row. Close the editor. | none |
| Remove is cancelled or dismissed | Change nothing. Keep the editor open. | none |
| Remove write fails | Show a toast. Keep the editor open. | `profile_edit_remove_failed` |
| Read-only profile | Disable name, host, port, password, method, plugin, plugin options, and fallback. Keep route, remote DNS, and IPv6 enabled. | `profile_edit_subscription_readonly` |
| Service mode is proxy | Disable the IPv6 switch. A tap does nothing. | none |
| Fallback id is empty | Show Disabled. Store `''` on Save. | `profile_edit_disabled` |
| Fallback id names no stored profile | Show Disabled. Keep the id in the draft, as Android does. | `profile_edit_disabled` |
| Chooser opens with no profile id | Close the chooser before the list draws. | none |
| Chooser is closed with the close control or system back | Store nothing. Keep the draft clean. | none |
| Pending choice is malformed | Ignore it. Keep the draft clean. | none |
| Pending choice names another profile | Ignore it. Leave the key in place. | none |
| Save on a new manual profile | The row exists already. Write the form values into it. | none |

### Test plan

Run the suite with `./test-arkts-host.sh`. An anchor is `<test file>::<test name>`. The describe block is `U03`.

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| TU03-01 | `entry/src/test/ParityU03.test.ets` | `U03#portOutsideRangeFallsBack` | unit |
| TU03-02 | `entry/src/test/ParityU03.test.ets` | `U03#portInsideRangeIsKept` | unit |
| TU03-03 | `entry/src/test/ParityU03.test.ets` | `U03#manualProfileUsesDefaults` | model |
| TU03-04 | `entry/src/test/ParityU03.test.ets` | `U03#manualProfileCopiesFeatures` | model |
| TU03-05 | `entry/src/test/ParityU03.test.ets` | `U03#activeSubscriptionLocksEdits` | unit |
| TU03-06 | `entry/src/test/ParityU03.test.ets` | `U03#ipv6SwitchNeedsVpnMode` | unit |
| TU03-07 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackKeepsOtherProfiles` | unit |
| TU03-08 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackOmitsEditedProfile` | unit |
| TU03-09 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackOmitsPluginProfiles` | unit |
| TU03-10 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackOmitsObsoleteProfiles` | unit |
| TU03-11 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackNameUsesName` | unit |
| TU03-12 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackNameUsesAddress` | unit |
| TU03-13 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackSummaryHidesMissingProfile` | unit |
| TU03-14 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackRowIndexSkipsDisabledRow` | unit |
| TU03-15 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackChoiceReachesItsEditor` | unit |
| TU03-16 | `entry/src/test/ParityU03.test.ets` | `U03#fallbackChoiceIgnoresOtherProfiles` | unit |

### Test detail

- TU03-01: `'0'`, `'65536'`, `'70000'`, `'-1'`, `'abc'`, and `''` all return 8388.
- TU03-02: `'1'`, `'65535'`, `'8388'`, and `'12345'` return their own value.
- TU03-03: a profile from `newManualProfile(null)` has host and name `example.shadowsocks.org`, port 8388, password `u1rRWTssNv0p`, method `aes-256-gcm`, route `all`, and no IPv6. It has an id.
- TU03-04: a current profile with route `gfwlist`, `ipv6 = true`, and `udpdns = true` passes those three fields to the new profile. The new profile keeps the manual host, password, and method.
- TU03-05: `STATUS_ACTIVE` returns true. `STATUS_USER_CONFIGURED` and `STATUS_OBSOLETE` return false.
- TU03-06: `MODE_VPN` returns true. `MODE_PROXY` returns false.
- TU03-07: a plain active profile stays in the list.
- TU03-08: the edited profile is not in the list.
- TU03-09: a profile with a plugin is not in the list.
- TU03-10: an obsolete profile is not in the list.
- TU03-11: a profile named `Backup` displays `Backup`.
- TU03-12: a profile with no name displays `backup.example:8388`. An IPv6 host displays `[2001:db8::1]:8388`.
- TU03-13: an empty id and an unknown id both return `''`.
- TU03-14: the first eligible profile returns 1. An unknown id returns 0.
- TU03-15: a choice for profile A with id 7 decodes to `7`. A Disabled choice decodes to `''`.
- TU03-16: a choice for profile A read for profile B returns `null`. A malformed value returns `null`. An empty value returns `null`.

### Coverage

| Rules | Cases |
| --- | --- |
| R-UC-07, R-UC-09 | TU03-01, TU03-02 |
| R-UC-12 | TU03-06 |
| R-UC-16 | TU03-05 |
| R-UC-26 | TU03-11, TU03-12, TU03-13 |
| R-UC-27 | TU03-07, TU03-08, TU03-09, TU03-10 |
| R-UC-28, R-UC-29, R-UC-40 | TU03-15, TU03-16 |
| R-UC-30 | TU03-14 |
| R-UC-36, R-UC-37, R-UC-41 | TU03-03, TU03-04 |

The other rules in U03 are UI behavior. The 31 cases in `docs/versions/5.4.0/e2e/U03.md` verify them on a device. The load gate, the close control, the Remove dialog, the dirty flag, and the chooser navigation have no host anchor.

### Platform notes

- The Remove action is a button at the bottom of the form. Android puts it in the toolbar menu. The action, the confirmation, and the result are the same.
- The editor has two exit controls. The `✕` discards a dirty draft. The `Back` label and the system back gesture ask first. This matches Android's toolbar up icon and system back.
- The editor's action button reads Save. Android reads Apply. The behavior is the same. The unsaved-changes dialog uses the same word, so the page stays consistent.
- The password field masks the value and offers the platform reveal control. The Android row summary of one bullet per character has no equivalent in an inline form. TC-U03-29 stays partial.
- The Encrypt Method list holds the six AEAD presets and the custom field. Android lists 22 entries, including stream ciphers. The core is built with `aead-cipher` and `aead-cipher-2022` only, so it cannot run an entry such as `aes-256-cfb`. A manual profile therefore starts with `aes-256-gcm`, not Android's `aes-256-cfb`.
- Metered Hint needs a VPN metered flag. `vpnExtension.VpnConfig` has no such field on API 12.
- Direct Boot storage has no HarmonyOS equivalent. R-UC-38 does not apply.
- The app picker and the plugin UI belong to U07 and U08. Plugin signing keys are an Android concept.
- The IPv6 switch stores the profile flag. The tun stays IPv4 only, so the flag does not change routing yet.
- The UDP fallback choice is stored and shown. The core config has no `udp_fallback` key in this checkout, and only one core instance can run. The choice does not change the tunnel yet.
- The chooser is a page. It returns its choice through AppStorage, not through an activity result.
- Profile ids are strings. Eligibility compares strings, not long values.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| OQ-U03-1 | Must the core apply the UDP fallback? This needs a second server entry in the config and a UDP path that can switch servers. | Native bridge owner |
| OQ-U03-2 | Must a new manual profile use Android's `aes-256-cfb` default even though the core rejects it? The plan uses `aes-256-gcm`. | Product owner |
| OQ-U03-3 | Must the Encrypt Method menu list all 22 Android entries, including ciphers the core cannot run? | Product owner |
| OQ-U03-4 | Must the tun get an IPv6 address and route so the IPv6 flag takes effect? | VPN extension owner |
| OQ-U03-5 | Must import and export carry `udp_fallback`? The field is an Android nested profile object. | U04 owner |

<a id="u04"></a>
## U04 Import and export

### Scope

This unit covers the import and export flows of the Profiles screen.

In scope:

- Clipboard import, file import and replace from file.
- Manual Settings, which seeds a profile before it opens the editor.
- Link import from an `ss://` VIEW intent.
- Clipboard export, file export and the row share menu.
- The feedback message for each result.
- The model functions that parse, merge and write profile data.

Out of scope:

- The QR scanner and the About page. U10 owns them.
- The UDP fallback chooser and the editor field. U03 owns them. This unit stores and links the fallback.
- The app picker and the VPN application lists. U07 owns them. This unit stores the per-app settings.
- Subscriptions. U05 owns them.
- Search, row tap, edit, delete and reorder. U02 owns them. The row share menu belongs here.

Target state:

- The unit closes the model part of the 6 missing cases: TC-U04-09, TC-U04-10, TC-U04-11, TC-U04-24, TC-U04-31 and TC-U04-35. The editor display for TC-U04-09, TC-U04-10, TC-U04-11 and TC-U04-35 arrives with U03 and U07.
- 9 partial cases become implemented: TC-U04-03, TC-U04-13, TC-U04-19, TC-U04-23, TC-U04-25, TC-U04-27, TC-U04-28, TC-U04-29 and TC-U04-32.
- TC-U04-12, TC-U04-17, TC-U04-18 and TC-U04-34 keep a platform deviation.
- TC-U04-14 keeps a U03 dependency for the IPv6 field.
- The 14 implemented cases stay green.
- TC-U04-20 has no HarmonyOS equivalent. The unit records it as not portable.

The app reports a result as a toast. A toast is the platform equivalent of the Android snackbar. This document uses the word toast.

### Files to change

| File | Change |
| --- | --- |
| `entry/src/main/ets/model/Profile.ets` | Add `metered`, `proxyApps`, `bypass` and `individual`. Add `copyFeatureSettings`. Add the feature parameter to `parseUrl`. |
| `entry/src/main/ets/model/ProfilesFile.ets` | Parse the feature settings, `proxy_apps` and `udp_fallback`. Add the strict document parser and the batch collector. Rework the import merge and the export. |
| `entry/src/main/ets/model/ProfileStore.ets` | Add defaults for the four new fields in `fromJson`. |
| `entry/src/main/ets/model/Transfer.ets` | Read every chosen document. Split the picker from the file read. Set the `.json` suffix on the save picker. |
| `entry/src/main/ets/pages/Index.ets` | Rework the import and export actions, the menus, the link dialog and the row share menu. |
| `entry/src/main/ets/pages/ProfileQr.ets` | Show the encoder message and close the page when encoding fails. |
| `entry/src/main/resources/base/element/string.json` | Add the new messages. |
| `entry/src/main/resources/zh_CN/element/string.json` | Add the new messages in Chinese. |
| `entry/src/test/ProfilesFile.test.ets` | Update the calls for the new `exportProfiles` result type. |
| `entry/src/test/List.test.ets` | Register `parityU04Test`. |
| `entry/src/test/ParityU04.test.ets` | New spec file. |

### Implementation plan

Write `entry/src/test/ParityU04.test.ets` first. Run `./test-arkts-host.sh` and see the new specs fail. Then implement the model, the page and the strings. Run the host specs again. Verify the UI cases with the E2E suite.

### 1. `model/Profile.ets`

Add four fields to `Profile`, after `udpdns`:

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `metered` | `boolean` | `false` | Android metered-network hint. Stored and exported. |
| `proxyApps` | `boolean` | `false` | Android Apps VPN mode. U07 consumes it. |
| `bypass` | `boolean` | `false` | Android per-app bypass flag. U07 consumes it. |
| `individual` | `string` | `''` | Bundle names, one per line. U07 consumes it. |

Add this module function next to `nextUserOrder`:

```ts
export function copyFeatureSettings(feature: Profile | null, target: Profile): void
```

The function returns when `feature` is `null`. It copies these seven fields, the same set as Android's `copyFeatureSettingsTo`:

- `route`
- `ipv6`
- `metered`
- `proxyApps`
- `bypass`
- `individual`
- `udpdns`

Change `Profile.parseUrl`:

```ts
static parseUrl(url: string, feature: Profile | null = null): Profile | null
```

After the URL fields are set, call `copyFeatureSettings(feature, profile)`. The URL owns `host`, `remotePort`, `method`, `password`, `plugin`, `pluginOpts` and `name`. The feature source provides no plugin and no name.

### 2. `model/ProfilesFile.ets`

#### 2.1 JSON interfaces

Extend the interfaces:

```ts
export interface ProxyAppsJson {
  enabled: boolean;
  bypass?: boolean;
  android_list?: string[];
}

export interface UdpFallbackJson {
  server: string;
  server_port: number;
  password: string;
  method: string;
}

export interface ProfileJson {
  // existing fields stay
  udp_fallback?: UdpFallbackJson;
}
```

Add the parse result types:

```ts
interface ParsedEntry {
  profile: Profile;
  fallback: Profile | null;
}

export interface ImportBatch {
  profiles: Profile[];
  error: string;
}
```

#### 2.2 `profileFromJson`

Change the signature:

```ts
export function profileFromJson(
  record: Record<string, Object>,
  feature: Profile | null,
  fallback: boolean = false
): Profile | null
```

Keep the four required fields and the port range check:

- `server` is a non-empty string.
- `server_port` is a number or a numeric string. The value is an integer in 1..65535.
- `password` is a non-empty string.
- `method` is a non-empty string.

Then apply these rules:

1. Create the profile and call `copyFeatureSettings(feature, profile)`.
2. Set `host`, `remotePort`, `password` and `method`.
3. Set `name` from `remarks`. Use `server` when `remarks` is absent or empty.
4. Read `plugin`. Set `pluginOpts` when the plugin is not empty. Never inherit the plugin.
5. Read `route` when it is a non-empty string. Otherwise keep the inherited value.
6. Return now when `fallback` is true. A fallback reads only the plugin, the remarks and the route.
7. Set `remoteDns` from `remote_dns` when it is a non-empty string. Otherwise use `DEFAULT_REMOTE_DNS`. Do not inherit `remote_dns`.
8. Set `ipv6`, `metered` and `udpdns` from the JSON only when the field is a boolean. Otherwise keep the inherited value.
9. Read `proxy_apps` when it is an object:
   - `enabled` and `bypass` replace the inherited values only when they are booleans.
   - `android_list` replaces `individual` only when it is an array. Join the items with `\n`.
10. Do not read `udp_fallback` here. The entry parser reads it.

Add a helper for the boolean rule:

```ts
function booleanField(record: Record<string, Object>, key: string): boolean | null
```

The helper returns the value when it is a boolean. It returns `null` for every other value.

#### 2.3 Entry parsing and recursion

Add:

```ts
function entryFromJson(record: Record<string, Object>, feature: Profile | null): ParsedEntry | null
```

Behavior:

- Call `profileFromJson(record, feature, false)`. Return `null` when the call returns `null`.
- Read `udp_fallback` when it is an object.
- Call `profileFromJson(fallbackRecord, feature, true)`. Set the fallback to `null` when the call returns `null`.
- Return the profile and its fallback.

Replace `profilesInValue` with:

```ts
function entriesInValue(
  value: Object | null | undefined,
  depth: number,
  feature: Profile | null
): ParsedEntry[]
```

Keep the current rules:

- Stop at `MAX_DEPTH`.
- Recurse into every array element.
- Try `entryFromJson` on every object.
- Stop the search inside a recognized profile object.
- Recurse into every field of an unrecognized object.

Replace `profilesFromUrls` with:

```ts
function entriesFromUrls(text: string, feature: Profile | null): ParsedEntry[]
```

The function calls `Profile.parseUrl(token, feature)`.

#### 2.4 Document parsing

Add the strict parser:

```ts
export function parseProfileDocument(text: string, feature: Profile | null): Profile[]
```

Behavior:

1. Return `[]` for empty text.
2. When the first character is `{` or `[`, call `JSON.parse`. Let the error escape.
3. Call `entriesInValue`. Return `flattenEntries(entries)`.
4. Otherwise parse `ss://` URLs. When the text holds no URL, try `Profile.decodeBase64` and parse URLs again.
5. Return `[]` when no profile is found.

Keep `parseProfilesText` as the lenient parser:

```ts
export function parseProfilesText(text: string, feature: Profile | null = null): Profile[]
```

Change it to:

1. Try the strict path for text that starts with `{` or `[`. Return the profiles when the result is not empty.
2. Ignore a parse error and scan for `ss://` URLs.
3. Try the base64 decode path.
4. Return `[]` when nothing parses.

The lenient parser keeps the current subscription behavior. A malformed JSON body does not throw from this function.

Add:

```ts
function flattenEntries(entries: ParsedEntry[]): Profile[]
```

The function assigns an id to every profile and to every fallback. It sets `profile.udpFallbackId = fallback.id` for each pair. It returns the main profile followed by its fallback.

#### 2.5 Batch collection

Add:

```ts
export function collectProfiles(texts: string[], feature: Profile | null): ImportBatch
```

Behavior:

- For each text, call `parseProfileDocument` and append the profiles.
- Catch an error, keep the first message, and continue with the next text.
- Return the collected profiles and the first message. The message is `''` when no error occurs.

Use this helper for the message:

```ts
function errorText(e: Object): string
```

It returns `e.message` for an `Error`. It returns `String(e)` for other values.

#### 2.6 Import merge

Change `applyImport`:

```ts
export function applyImport(existing: Profile[], imported: Profile[], replace: boolean): Profile[]
```

Add this guard first:

```ts
if (replace && imported.length === 0) {
  return existing.slice();
}
```

The replacement clears the list only when it creates a profile. This matches R-UD-07.

Then:

1. Build the set of fallback ids. A fallback id is the value of an imported profile's `udpFallbackId`.
2. Build the kept list. For import mode, drop a fallback that matches a stored profile and record the stored id. A match has the same host, `remotePort`, password and method, and an empty plugin. For replace mode, keep every fallback.
3. Build the result. Append in import mode. Start from an empty list in replace mode.
4. For each kept profile, record its parsed id. In replace mode, copy `id`, `tx`, `rx` and the name from the stored profile with the same address. Call `ensureId` and assign the user order.
5. Rewrite every `udpFallbackId` through the parsed-id map and the reused-id map.

The merged list keeps the main profile and its fallback as two rows. The main points at the fallback with `udpFallbackId`.

Add:

```ts
function findFallbackMatch(profiles: Profile[], fallback: Profile): Profile | null
```

#### 2.7 Export

Change the signature:

```ts
export function exportProfiles(profiles: Profile[] | null, sip008: boolean = false): string | null
```

Behavior:

1. Return `null` when `profiles` is `null`.
2. Drop every profile with `subscriptionStatus === STATUS_OBSOLETE`.
3. Write `server`, `server_port`, `password` and `method` for every profile.
4. Return at this point when `sip008` is true.
5. Write `plugin` and `plugin_opts` only when the plugin is not empty.
6. Write `remarks`, `route`, `remote_dns`, `ipv6`, `metered`, `proxy_apps` and `udpdns`.
7. Write `proxy_apps` as `{ enabled }`. When `enabled` is true, add `bypass` and `android_list`. The list is `individual.split('\n')`.
8. Look up `udp_fallback` in the active list by `udpFallbackId`. Write the nested object only when the fallback exists and its plugin is empty.
9. Return `JSON.stringify(entries, null, 2)`.

Add:

```ts
export function exportProfileUrls(profiles: Profile[]): string
```

The function drops obsolete profiles, maps each profile through `toUri` and joins the results with `\n`. A single profile returns one URL and no newline.

### 3. `model/ProfileStore.ets`

Add four defaults in `fromJson`:

```ts
profile.metered = parsed.metered ?? false;
profile.proxyApps = parsed.proxyApps ?? false;
profile.bypass = parsed.bypass ?? false;
profile.individual = parsed.individual ?? '';
```

### 4. `model/Transfer.ets`

Replace `pickTextFile` with:

```ts
export async function pickTextFiles(context: common.Context): Promise<string[]>
```

The function creates a `DocumentViewPicker`. It creates a `DocumentSelectOptions`, sets `maxSelectNumber = 20` and returns `view.select(options)`. The platform default is 500 files on API 20 and earlier. The limit bounds one import batch.

Add:

```ts
export function readTextFile(uri: string): string
```

The function returns `fs.readTextSync(uri)`. A read error escapes to the caller.

Change `saveTextFile`:

- Set `options.fileSuffixChoices = ['.json']`.
- Keep `options.newFileNames = [name]`.
- Keep the current open and write steps.

### 5. `pages/Index.ets`

#### 5.1 Imports

Add:

- `copyFeatureSettings` from `../model/Profile`.
- `collectProfiles`, `exportProfiles` and `exportProfileUrls` from `../model/ProfilesFile`.
- `pickTextFiles`, `readTextFile` from `../model/Transfer`. Remove the `pickTextFile` import.
- `QrParams` from `./ProfileQr`.

#### 5.2 Menus

Add a builder:

```ts
@Builder ExportMenu()
```

The menu holds two items:

- `$r('app.string.index_export_to_clipboard')` calls `this.copyToClipboard()`.
- `$r('app.string.index_export_to_file')` calls `this.exportToFile()`.

Change `AddMenu`:

- Remove the two export items.
- Keep Add manually, Import ss:// URL, Import from Clipboard, Import from file, Replace from file and Subscriptions.
- Use the new string keys.
- Point Add manually at `this.addManualProfile()`.
- Point the ImportDialog `onConfirm` at `this.importTypedUrl(text)`.
- Point the two file items at `importFromFiles(false)` and `this.replaceDialog.open()`.
- Point the replace dialog `onConfirm` at `importFromFiles(true)`.

Add the export entry to the title bar. Place it before the add entry:

```ts
Text($r('app.string.index_export'))
  .fontSize(14)
  .fontColor($r('app.color.accent'))
  .margin({ right: 12 })
  .bindMenu(this.ExportMenu())
```

#### 5.3 Messages

Add:

```ts
private readableMessage(e: Object): string
```

It returns `e.message` for an `Error` and `String(e)` for other values.

Add:

```ts
private showMessage(message: ResourceStr): void
```

It calls `promptAction.showToast`.

#### 5.4 Import

Add:

```ts
private selectedFeature(): Profile | null
```

The function returns the profile whose id equals `currentId`. It returns `null` when no profile matches. It does not fall back to the first profile. This matches R-UD-09.

Add:

```ts
private async importProfiles(imported: Profile[], replace: boolean): Promise<void>
```

Behavior:

1. Read the stored list with `ProfileStore.getAll`.
2. Merge with `applyImport`.
3. Save with `ProfileStore.saveAll`.
4. Call `this.reload()`.

Do not change the selected profile. Remove the current block that selects `profiles[0]` when `currentId` is empty. This matches R-UD-04.

Replace `importText` and `importFromText` with these methods:

```ts
private async importFromClipboard(): Promise<void>
private async importFromFiles(replace: boolean): Promise<void>
private async importTypedUrl(text: string): Promise<void>
```

`importFromClipboard`:

1. Read the clipboard.
2. Parse with `parseProfilesText(text, this.selectedFeature())`.
3. Show `index_import_failed` when the result is empty. Do not change the list.
4. Call `importProfiles(imported, false)` and show `index_import_success`.
5. Show `index_import_failed` for a thrown error.

`importFromFiles`:

1. Call `pickTextFiles`. Return when the result is empty.
2. Read the files in order. Stop at the first read error and keep its message.
3. Call `collectProfiles(texts, this.selectedFeature())`.
4. Call `importProfiles(result.profiles, replace)` when the profile list is not empty.
5. Choose the first error. Use the parse error when it is not empty. Otherwise use the read error.
6. Show the error message when it is not empty. Show no message for a clean import.
7. Show `readableMessage(e)` for a thrown picker error or a thrown save error.

`importTypedUrl` serves the extra Import ss:// URL dialog. Parse with `parseProfilesText`, show `index_nothing_to_import` for an empty result, show `index_import_success` after a successful import and show `index_import_failed` for a thrown error.

#### 5.5 Link import

Change `confirmLinkImport`:

1. Parse with `parseProfilesText(uri, this.selectedFeature())`.
2. Show `index_no_valid_profile_data` and return when the result is empty.
3. Build the dialog message from `imported.map((p) => p.toUri()).join('\n')`. This matches R-UD-42.
4. Use the title `index_add_link_profile` with the value "Add this Shadowsocks Profile?".
5. Use the buttons `common_no` and `common_yes`. Button index 1 is Yes.
6. Call `importProfiles(imported, false)` for Yes. Show no success message.
7. Return without a message for a dismissed dialog. A dismissal discards the import, as R-UD-43 requires.

#### 5.6 Export

Add:

```ts
private async readActiveProfiles(): Promise<Profile[] | null>
```

The function returns `ProfileStore.visible(await ProfileStore.getAll(context))`. It returns `null` on a thrown read. This is the HarmonyOS form of a null `serializeToJson` result.

Change `copyToClipboard`:

1. Read the active list. Show `index_export_failed` when the result is `null`.
2. Write `exportProfileUrls(profiles)` with `writeClipboard`.
3. Show `index_export_success` on success.
4. Show `index_export_failed` for a thrown write.

Change `exportToFile`:

1. Call `exportProfiles(await this.readActiveProfiles())`.
2. Return when the result is `null`. Write nothing. Show no message.
3. Call `saveTextFile(abilityContext(), EXPORT_FILE_NAME, text)`. Return when the user cancels.
4. Show no success message.
5. Show `readableMessage(e)` for a thrown read or write.

Add:

```ts
private async copyProfileToClipboard(profile: Profile): Promise<void>
```

The function writes `profile.toUri()`. It shows `index_export_success` or `index_export_failed`.

Add:

```ts
private showProfileQr(profile: Profile): void
```

The function pushes `pages/ProfileQr` with `{ url: profile.toUri(), name: profile.name }` as `QrParams`.

#### 5.7 Manual Settings

Add:

```ts
private async addManualProfile(): Promise<void>
```

Behavior:

1. Create a `Profile`.
2. Call `copyFeatureSettings(this.selectedFeature(), profile)`.
3. Call `ProfileStore.upsert`. The store assigns the last user order.
4. Push `pages/ProfileEdit` with `{ id: profile.id }`.
5. Show `index_op_add_profile` through `reportFailure` for a thrown error.

The editor loads the stored profile. The back arrow leaves the row in the list. This matches R-UD-30.

#### 5.8 Row share menu

Add two callbacks to `ProfileRow`:

```ts
onQr: () => void
onExport: () => void
```

Add a builder to `ProfileRow`:

```ts
@Builder shareMenu()
```

The menu holds:

- `$r('app.string.index_qr_code')` calls `this.onQr()`.
- `$r('app.string.index_export_to_clipboard')` calls `this.onExport()`.

Add a share entry to the row before the test entry:

```ts
Text('↗')
  .fontSize(16)
  .fontColor($r('app.color.accent'))
  .margin({ right: 12 })
  .accessibilityText($r('app.string.index_share'))
  .onClick(() => {
  })
  .bindMenu(this.shareMenu())
```

The empty click handler stops the tap from selecting the row. The entry is enabled in every service state, as R-UD-50 requires.

In `Index`, pass:

```ts
onQr: () => this.showProfileQr(profile),
onExport: () => this.copyProfileToClipboard(profile),
```

### 6. `pages/ProfileQr.ets`

In the `aboutToAppear` catch block:

1. Keep the inline error state.
2. Show a toast with the thrown message. Use `e.message` for an `Error`.
3. Call `router.back()` with `setTimeout(..., 0)`.

The QR code opens as a page. Android opens a dialog. Closing the page is the HarmonyOS form of dismissing the Android dialog.

### 7. Strings

Add these names to both string files:

| Name | English | Chinese |
| --- | --- | --- |
| `common_yes` | Yes | 是 |
| `common_no` | No | 否 |
| `index_export` | Export… | 导出… |
| `index_export_to_clipboard` | Export to Clipboard | 导出到剪贴板 |
| `index_import_from_clipboard` | Import from Clipboard | 从剪贴板导入 |
| `index_manual_settings` | Manual Settings | 手动设置 |
| `index_share` | Share | 分享 |
| `index_qr_code` | QR code | 二维码 |
| `index_import_success` | Successfully import! | 导入成功！ |
| `index_import_failed` | Failed to import. | 导入失败。 |
| `index_export_success` | Successfully export! | 导出成功！ |
| `index_export_failed` | Failed to export. | 导出失败。 |
| `index_no_valid_profile_data` | No valid profile data found. | 未找到有效的档案数据。 |
| `index_op_add_profile` | Add profile | 添加档案 |

Change these values:

| Name | New English value | New Chinese value |
| --- | --- | --- |
| `index_add_link_profile` | Add this Shadowsocks Profile? | 添加此 Shadowsocks 档案？ |
| `index_import_from_file` | Import from file… | 从文件导入… |
| `index_replace_from_file` | Replace from file… | 用文件替换… |
| `index_export_to_file` | Export to file… | 导出到文件… |

Remove these keys when no code uses them:

- `index_paste_from_clipboard`
- `index_add_manually`
- `index_copy_to_clipboard`
- `index_clipboard_empty`
- `index_imported_n`
- `index_replaced_n`
- `index_exported_n`
- `index_copied_n`

Keep `index_nothing_to_import` and the `index_source_*` keys for the extra Import ss:// URL dialog.

### State and data

### Profile record

The record lives in `store/profiles.json`. The four new fields are persisted with the rest of the profile:

```json
{
  "id": "...",
  "name": "Work",
  "host": "198.51.100.7",
  "remotePort": 8388,
  "password": "...",
  "method": "aes-256-gcm",
  "route": "all",
  "plugin": "",
  "pluginOpts": "",
  "remoteDns": "dns.google",
  "udpdns": false,
  "ipv6": false,
  "metered": false,
  "proxyApps": false,
  "bypass": false,
  "individual": "",
  "udpFallbackId": "",
  "subscriptionStatus": 0,
  "tx": 0,
  "rx": 0,
  "userOrder": 1
}
```

`udpFallbackId` links a main profile to its fallback profile. Both profiles are rows in the same list.

### Import batch state

| From | To | Event | Producer |
| --- | --- | --- | --- |
| idle | picking | The user chooses Import from file or Replace from file | `Index.importFromFiles` |
| picking | idle | The picker returns no URI | `Index.importFromFiles` |
| picking | parsing | The picker returns one or more URIs | `Index.importFromFiles` |
| parsing | applied | At least one profile parses | `ProfilesFile.collectProfiles`, `Index.importProfiles` |
| parsing | rejected | No profile parses and no error occurs | `ProfilesFile.collectProfiles` |
| parsing | failed | A document read or parse throws | `ProfilesFile.collectProfiles`, `Index.importFromFiles` |
| applied | idle | The page reloads the list | `Index.reload` |
| failed | idle | The page shows the first error and keeps the applied profiles | `Index.importFromFiles` |

A batch can be applied and failed at the same time. The page applies the valid profiles first. It shows the first error after that.

### Link import state

| From | To | Event | Producer |
| --- | --- | --- | --- |
| launched | parsing | `EntryAbility` stores the pending link and the page takes it | `EntryAbility.takeImportUri`, `Index.onPendingImport` |
| parsing | confirming | At least one profile parses | `Index.confirmLinkImport` |
| parsing | invalid | No profile parses | `Index.confirmLinkImport` |
| confirming | imported | The user taps Yes | `Index.confirmLinkImport` |
| confirming | discarded | The user taps No or dismisses the dialog | `Index.confirmLinkImport` |
| imported | finished | The dialog closes | `Index.confirmLinkImport` |
| discarded | finished | The dialog closes | `Index.confirmLinkImport` |
| invalid | finished | The toast shows and the dialog does not open | `Index.confirmLinkImport` |

There is no separate import activity. The page stays open.

### Import merge

- An import appends the new profiles after the highest `userOrder`.
- An import does not change the selected profile.
- A replace drops the stored profiles and keeps the id and the counters of a profile with the same `host:remotePort`.
- A replace with no parsed profile changes nothing.
- A parsed fallback reuses a stored profile with the same host, port, password, method and an empty plugin. Otherwise the fallback becomes a second profile.
- An imported profile leaves its subscription. `subscriptionId` becomes `''`.

### Export data

- Clipboard export writes newline-joined `ss://` URLs. It writes no JSON.
- File export writes a two-space-indented JSON array of active profiles.
- Active means `subscriptionStatus !== STATUS_OBSOLETE`.
- The file entry carries the four base fields, the nine Android feature fields and the nested `udp_fallback`.
- The `plugin` and `plugin_opts` fields appear only with a plugin.
- The `udp_fallback` object appears only when the fallback is active and has no plugin.

### Validation and errors

### JSON profile validation

A JSON object is a profile only when all four fields pass:

- `server` is a non-empty string.
- `server_port` is an integer in 1..65535. A numeric string is accepted.
- `password` is a non-empty string.
- `method` is a non-empty string.

A recognized profile stops the recursive search. An unrecognized object is a container. The parser searches every field and every array element to depth 8.

### Feature inheritance

An imported profile inherits these fields from the selected profile:

- `route`
- `ipv6`
- `metered`
- `proxyApps`
- `bypass`
- `individual`
- `udpdns`

A JSON boolean overrides an inherited boolean. A non-boolean value keeps the inherited value. A missing selected profile gives the field defaults: route `all`, the booleans `false`, and `individual` `''`.

`remote_dns`, the plugin and the name are never inherited.

### Fallback validation

- A fallback object needs the same four fields.
- A fallback reads the plugin, the remarks and the route only.
- The parse returns before `remote_dns`, `ipv6`, `metered`, `proxy_apps` and `udpdns`.
- An invalid fallback object is ignored. The main profile imports alone.
- A fallback with a plugin does not export as `udp_fallback`.

### Result table

| Condition | Behavior | Toast | Case |
| --- | --- | --- | --- |
| The clipboard is empty or unreadable | No change | Failed to import. | TC-U04-02, TC-U04-25 |
| The clipboard holds no `ss://` URL | No change | Failed to import. | TC-U04-02 |
| The clipboard holds valid URLs | Append | Successfully import! | TC-U04-01, TC-U04-26 |
| The file import parses at least one profile | Append, no message | None | TC-U04-03, TC-U04-24 |
| The file import parses no profile and no error occurs | No change | None | TC-U04-27 |
| A document holds malformed JSON | Apply the profiles parsed before it, continue with later documents | The exception message | TC-U04-23, TC-U04-24 |
| A file read throws | Apply the profiles parsed before it, stop later documents | The exception message | R-UD-54 |
| The picker is cancelled | No change | None | TC-U04-04, TC-U04-30 |
| The replace parses at least one profile | Replace the list, keep the counters for the same address | None | TC-U04-05 |
| The replace parses no profile | No change | None | TC-U04-06 |
| The clipboard list read fails or the write throws | No change | Failed to export. | TC-U04-28, TC-U04-29 |
| The clipboard export succeeds | Write the URL lines | Successfully export! | TC-U04-12, TC-U04-18 |
| The export list read fails | No file | None | TC-U04-31 |
| The file write throws | No file | The exception message | TC-U04-32 |
| The file export succeeds | Write the JSON array | None | TC-U04-13 |
| The link holds no profile | No dialog | No valid profile data found. | TC-U04-16 |
| The user taps Yes | Append, no message | None | TC-U04-15 |
| The user taps No or dismisses | No change | None | TC-U04-22, TC-U04-33 |

The exception messages come from the platform or from `JSON.parse`. They are English. AGENTS.md records this known gap.

### Test plan

The planned specs live in `entry/src/test/ParityU04.test.ets`. Register the suite in `entry/src/test/List.test.ets`:

```ts
import parityU04Test from './ParityU04.test';
// inside testsuite()
parityU04Test();
```

The suite uses `describe('U04', ...)`. Each spec uses `it('<name>', 0, ...)`. The anchor format is `entry/src/test/ParityU04.test.ets::U04#<name>`.

Run the specs with `./test-arkts-host.sh`.

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| TC-U04-09, TC-U04-35 | `entry/src/test/ParityU04.test.ets` | `U04#jsonImportInheritsFeatureSettings` | unit |
| TC-U04-09 | `entry/src/test/ParityU04.test.ets` | `U04#jsonImportOverridesInheritedSettings` | unit |
| TC-U04-09 | `entry/src/test/ParityU04.test.ets` | `U04#jsonImportUsesDefaultsWithoutSelectedProfile` | unit |
| TC-U04-11 | `entry/src/test/ParityU04.test.ets` | `U04#jsonImportReadsProxyApps` | unit |
| TC-U04-10 | `entry/src/test/ParityU04.test.ets` | `U04#importsFallbackAsSecondProfile` | unit |
| TC-U04-10 | `entry/src/test/ParityU04.test.ets` | `U04#fallbackReadsOnlyPluginRemarksAndRoute` | unit |
| TC-U04-10 | `entry/src/test/ParityU04.test.ets` | `U04#fallbackReusesStoredProfile` | unit |
| TC-U04-10 | `entry/src/test/ParityU04.test.ets` | `U04#fallbackIsCreatedWhenNoStoredMatch` | unit |
| TC-U04-13 | `entry/src/test/ParityU04.test.ets` | `U04#exportWritesAndroidJsonShape` | unit |
| TC-U04-13 | `entry/src/test/ParityU04.test.ets` | `U04#exportOmitsPluginFieldsWithoutPlugin` | unit |
| TC-U04-13 | `entry/src/test/ParityU04.test.ets` | `U04#exportOmitsFallbackWithPlugin` | unit |
| TC-U04-13 | `entry/src/test/ParityU04.test.ets` | `U04#exportSkipsObsoleteProfiles` | unit |
| TC-U04-31 | `entry/src/test/ParityU04.test.ets` | `U04#exportReturnsNullForNullList` | unit |
| TC-U04-12, TC-U04-18 | `entry/src/test/ParityU04.test.ets` | `U04#clipboardTextJoinsUrlsWithNewlines` | unit |
| TC-U04-12 | `entry/src/test/ParityU04.test.ets` | `U04#clipboardTextOfOneProfileHasNoNewline` | unit |
| TC-U04-23 | `entry/src/test/ParityU04.test.ets` | `U04#malformedJsonDocumentThrows` | unit |
| TC-U04-24 | `entry/src/test/ParityU04.test.ets` | `U04#collectKeepsProfilesBeforeBadDocument` | unit |
| TC-U04-24 | `entry/src/test/ParityU04.test.ets` | `U04#collectKeepsFirstError` | unit |
| TC-U04-06 | `entry/src/test/ParityU04.test.ets` | `U04#replaceWithNoProfilesKeepsList` | unit |
| TC-U04-05 | `entry/src/test/ParityU04.test.ets` | `U04#replaceKeepsCountersForSameAddress` | unit |
| TC-U04-02, TC-U04-25 | `entry/src/test/ParityU04.test.ets` | `U04#clipboardTextWithoutUrlsYieldsNoProfiles` | unit |
| TC-U04-26 | `entry/src/test/ParityU04.test.ets` | `U04#clipboardTextKeepsValidUrlBesideBadOne` | unit |
| TC-U04-27 | `entry/src/test/ParityU04.test.ets` | `U04#jsonArrayOfNumbersYieldsNoProfiles` | unit |
| TC-U04-14 | `entry/src/test/ParityU04.test.ets` | `U04#manualSeedCopiesFeatureSettings` | unit |
| TC-U04-35 | `entry/src/test/ParityU04.test.ets` | `U04#urlImportCopiesFeatureSettings` | unit |
| regression | `entry/src/test/ParityU04.test.ets` | `U04#lenientParseKeepsSubscriptionBehavior` | unit |
| TC-U04-08 | `entry/src/test/ParityU04.test.ets` | `U04#jsonImportSkipsBadPort` | unit |
| R-UD-14 | `entry/src/test/ParityU04.test.ets` | `U04#storeReadsNewFieldsWithDefaults` | unit |

The UI steps stay with the E2E suite. These cases need a device: TC-U04-01, TC-U04-03, TC-U04-04, TC-U04-12, TC-U04-14, TC-U04-15, TC-U04-16, TC-U04-17, TC-U04-18, TC-U04-19, TC-U04-22, TC-U04-28, TC-U04-29, TC-U04-30, TC-U04-32, TC-U04-33 and TC-U04-34.

### Platform notes

- The HarmonyOS pasteboard has no sensitive flag. R-UD-19 stays partial. The app cannot mark a copied profile URL as sensitive.
- The document picker filters by file suffix. It has no `application/*` and `text/*` MIME filter. The app opens the picker with no suffix filter, so every document type is selectable. This covers the Android filter.
- The document picker returns several URIs by default. The plan sets `maxSelectNumber = 20` to bound one batch.
- The save picker offers the name `profiles.json` and the `.json` suffix. It has no MIME type setting.
- The save picker can pre-create the destination file. The page serializes the list before it opens the picker. A null serialization therefore leaves no file. This is a deliberate difference from the Android order.
- The platform has no intent handler lookup. The app cannot report that no file manager is installed. TC-U04-20 is not portable.
- The app has one ability. A link becomes a dialog on the profile list. There is no separate import screen in the recent task list. TC-U04-34 stays partial.
- The QR code is a page. The Android QR code is a dialog. The content and the size are equal. The unit treats the page as the dialog equivalent.
- A parse error carries the JSON engine message. A read or write error carries the platform message. Both can appear in English in the Chinese UI. This is the known model-layer gap in AGENTS.md.
- `android_list` holds Android package names. HarmonyOS bundles have different names. The app preserves the names and leaves the mapping to U07.
- `metered` has no platform behavior. The app stores and exports it.
- `proxy_apps` and `udp_fallback` are storage until U07 and U03 consume them. The import and export are complete in this unit.
- The ArkUI menu has no hardware keyboard accelerators. R-UD-48 and R-UD-49 are not portable.

### Open questions

1. The E2E suite expects no toast after a file import or a file export. The current app shows a count. Does the product accept the loss of this feedback?
2. A replace keeps the id of a profile with the same address, so the row stays selected. Android gives the row a new id, so no row is selected. TC-U04-05 expects the Android behavior. Which behavior is the parity target?
3. TC-U04-09, TC-U04-10, TC-U04-11, TC-U04-14 and TC-U04-35 show values in the editor. The IPv6, DNS over UDP and UDP fallback fields belong to U03. Apps VPN mode belongs to U07. Do these cases count as implemented for U04 before those units land?
4. The clipboard parser accepts JSON and base64 bodies as an extension. R-UD-01 names `ss://` URLs only. Should the app restrict the clipboard path to URLs?
5. A JSON entry without `remarks` gets the server address as its name. Android keeps the name empty. The current behavior keeps the rows readable. Should the app match Android?
6. Should the app keep the extra Import ss:// URL dialog? Android has no such dialog. It is outside the Android specification.
7. Does R-UD-19 have a HarmonyOS equivalent at any API level? The pasteboard API in the installed SDK has no sensitivity field.
8. Should `exportProfiles` own the active-only filter, or should the page pass a filtered list? The plan puts the filter inside the function, so every caller is safe.

<a id="u05"></a>
## U05 Subscriptions

### Scope

This document is the detailed design for unit U05, subscriptions.
It covers the controls C-U05-001 to C-U05-020 and the rules R-UE-01 to R-UE-29.
It covers the flows F-U05-01 to F-U05-06.
It does not change code.

The design keeps the existing module split:

- `model/Subscription.ets` owns parsing, URL rules and the merge.
- `model/ProfileStore.ets` owns profile persistence.
- `pages/Subscription.ets` owns the screen and the dialog.
- A new `model/SubscriptionRefresh.ets` owns one refresh run.

The design adds four behaviors:

1. One edit dialog for add and edit.
2. A sorted URL list with duplicated URL suppression.
3. Removal with an undo window. The profiles stay.
4. One batch refresh of all subscription URLs. The refresh merges all bodies in one run.

Out of scope:

- The drawer entry and the navigation belong to U01.
- Import and export belong to U04.
- UDP fallback body parsing belongs to U03. U05 keeps the stored field.
- Per-app fields belong to U07. U05 copies the fields that exist.
- Automatic refresh and grouping have no U05 criterion. See the open questions.

Platform decisions:

- HarmonyOS has no Android `Service`, `startService` or `BroadcastReceiver`. The refresh run lives in the UI process.
- HarmonyOS does not let a third-party app create a system live view notification. The notification shows the count as text. It has no progress bar.
- HarmonyOS has no snackbar. The page shows an undo bar for 5 s.
- HarmonyOS has no Android URL handler registry. The validator uses a built-in scheme set and `bundleManager.canOpenLink`.

### Files to change

| # | File | Kind | Purpose |
| --- | --- | --- | --- |
| 1 | `entry/src/main/ets/model/Subscription.ets` | Modify | Add URL rules, list transforms, a body parser with feature settings, a batch merge and a body fetch. |
| 2 | `entry/src/main/ets/model/Profile.ets` | Modify | Add `copyFeatureSettingsFrom` and `copyTransportFrom`. |
| 3 | `entry/src/main/ets/model/SubscriptionRefresh.ets` | Add | Hold one refresh run, the notification and the abort event. |
| 4 | `entry/src/main/ets/model/ProfileStore.ets` | Modify | Remove `removeSubscriptionProfiles`. A URL removal must keep its profiles. |
| 5 | `entry/src/main/ets/pages/Subscription.ets` | Modify | Add the edit dialog, the sorted list, the swipe removal, the undo bar and the batch refresh control. |
| 6 | `entry/src/main/resources/base/element/string.json` | Modify | Add the English strings. Remove the unused strings. |
| 7 | `entry/src/main/resources/zh_CN/element/string.json` | Modify | Add the Chinese strings. Remove the unused strings. |
| 8 | `entry/src/main/module.json5` | Modify | Add `querySchemes` for the non-web schemes. |
| 9 | `entry/src/test/ParityU05.test.ets` | Add | Hold the planned host tests. |
| 10 | `entry/src/test/List.test.ets` | Modify | Register `parityU05Test`. |
| 11 | `entry/src/test/Subscription.test.ets` | Modify | Expect a parse error for malformed JSON. |
| 12 | `entry/src/test/SubscriptionMerge.test.ets` | Modify | Use `mergeSubscriptionRun`. |

### Implementation plan

### 1. `model/Subscription.ets`

Keep the classes `Subscription` and `SubscriptionStore`.
Keep the fields `id`, `url` and `updatedAt`.
Keep `fromJson`, `upsert` and `remove`.

#### 1.1 Add URL types and functions

```ts
export interface ParsedSubscriptionUrl {
  protocol: string;   // lower-case, as java.net.URL.getProtocol
  host: string;       // as written, '' when absent
  port: number;       // -1 when absent
  file: string;       // path plus query, '' when absent
}

export type SubscriptionUrlError = '' | 'no_protocol' | 'unknown_protocol';

export interface SubscriptionUrlCheck {
  valid: boolean;
  cleartext: boolean; // true when the scheme is http
  scheme: string;     // lower-case, '' when the text has no scheme
  error: SubscriptionUrlError;
}

export function parseSubscriptionUrl(text: string): ParsedSubscriptionUrl | null;

export function validateSubscriptionUrl(
  text: string, canOpen: (link: string) => boolean): SubscriptionUrlCheck;

export function compareSubscriptionUrls(a: string, b: string): number;

export function sortSubscriptions(list: Subscription[]): Subscription[];

export function findSubscriptionByUrl(list: Subscription[], url: string): Subscription | null;
```

Rules for `parseSubscriptionUrl`:

1. Trim the text.
2. Read the scheme with `^([A-Za-z][A-Za-z0-9+.-]*):`. Return null when the text has no scheme.
3. Lower-case the scheme.
4. Read the part after `//` as the authority. Read the authority up to `/`, `?` or `#`.
5. Take the host after the last `@`. Remove the brackets of an IPv6 literal.
6. Read the port after the last `:` when the text is numeric. Use -1 when the port is absent.
7. Set `file` to the path plus `?query`. Leave out the fragment.
8. When the text has no `//`, set the host to `''` and the file to the rest without the fragment.
9. Keep the host case. `java.net.URL.getHost` keeps the case.

Rules for `validateSubscriptionUrl`:

1. Trim the text.
2. Set `scheme` to the lower-case scheme. Set it to `''` when the text has no scheme.
3. Return `no_protocol` when `parseSubscriptionUrl` returns null.
4. Return `valid` with `cleartext = true` for the `http` scheme.
5. Return `valid` with `cleartext = false` for the `https`, `ftp` and `file` schemes.
6. For any other scheme, call `canOpen(text)`. Return `unknown_protocol` when the call returns false or throws.
7. Return `valid` when the call returns true.

The built-in set mirrors the Java URL handlers that shadowsocks-android depends on. The set makes `ftp` and `file` pass on HarmonyOS, as R-UE-04 requires.

Rules for `compareSubscriptionUrls`:

1. Compare `host` as a string.
2. Compare `port` as a number.
3. Compare `file` as a string.
4. Compare `protocol` as a string.

This order is `URLSorter` in `core/src/main/java/com/github/shadowsocks/utils/Sorters.kt`.
`file` includes the query. Two URLs with equal paths and different queries therefore compare by the query.

`sortSubscriptions` uses a stable sort. Two equal URLs keep their input order.
`SubscriptionStore.normalize` removes an unparseable URL before the sort.
`compareSubscriptionUrls` compares an unparseable URL by its raw text when a caller does not filter first.

#### 1.2 Add dialog result and list transforms

```ts
export type SubscriptionDialogButton = 'ok' | 'cancel' | 'remove';

export interface SubscriptionEditResult {
  edited: string | null;    // the text of OK
  replacing: string | null; // the stored URL under edit
}

export function editResult(button: SubscriptionDialogButton, text: string,
  original: string): SubscriptionEditResult | null;

export interface SubscriptionListChange {
  list: Subscription[];
  changed: boolean;
}

export function addSubscriptionUrl(list: Subscription[],
  subscription: Subscription): SubscriptionListChange;

export function replaceSubscriptionUrl(list: Subscription[], oldUrl: string,
  subscription: Subscription): Subscription[];

export function restoreSubscriptions(list: Subscription[],
  removed: Subscription[]): Subscription[];
```

Rules for `editResult`:

1. Return null for `cancel`.
2. Return null for `remove` when `original` is empty.
3. Return `{ edited: null, replacing: original }` for `remove`.
4. Return `{ edited: text, replacing: original or null }` for `ok`.

Rules for `addSubscriptionUrl`:

1. Return `{ list, changed: false }` when `findSubscriptionByUrl` finds an equal URL.
2. Append the subscription and sort the list.
3. Return `{ list, changed: true }`.

Rules for `replaceSubscriptionUrl`:

1. Drop the record that equals `oldUrl`.
2. Keep an existing record that equals the new URL. Do not add a second record.
3. Append the new record when no equal record exists.
4. Sort the list.

Rules for `restoreSubscriptions`:

1. Append every removed record.
2. Drop comparator-equal duplicates. The restored record wins.
3. Sort the list.

#### 1.3 Change `SubscriptionStore`

`SubscriptionStore.getAll` keeps the JSON read. Add four steps after the parse:

1. Revive every record with `fromJson`.
2. Drop every record whose `url` does not parse.
3. Drop comparator-equal duplicates. The last record wins, as `SortedList.add` replaces an equal item.
4. Sort by URL.

Add this static helper. The host tests call it.

```ts
static normalize(records: Subscription[]): Subscription[];
```

`SubscriptionStore.saveAll` sorts a copy before `JSON.stringify`.
The file stays `store/subscriptions.json`.
The HLD data design owns the file. The Android newline format is not copied. See Platform notes.

#### 1.4 Change the body parser

```ts
export class SubscriptionParseError extends Error {
  constructor(message: string);
}

export function parseSubscriptionBody(body: string, subscriptionId: string,
  feature: Profile | null = null): Profile[];
```

Keep the two body forms:

- A base64 blob of `ss://` lines.
- A JSON document.

Change the JSON branch:

1. Call `JSON.parse`. Throw `SubscriptionParseError` when the call fails.
2. Walk the parsed value with a depth limit of 8.
3. Treat an object with `server`, `server_port`, `password` and `method` as a server entry.
4. Walk the values of any other object or array. This finds `servers`, `configs` and unnamed arrays.
5. Skip an object that lacks one of the four fields.

Change the profile build for a JSON server entry:

1. Set `host`, `remotePort`, `password` and `method`. Accept a numeric or numeric-string port.
2. Copy the feature settings with `profile.copyFeatureSettingsFrom(feature)` when `feature` is not null.
3. Set `name` to `remarks` when it is a non-empty string. Else set `name` to the host.
4. Set `plugin` and `pluginOpts` from the body.
5. Set `route` from the body when `isValidRoute` accepts it. Else keep the copied route.
6. Set `remoteDns` from the body when it is a non-empty string. Else set `DEFAULT_REMOTE_DNS`.
7. Set `ipv6` and `udpdns` from the body when the value is a boolean. Else keep the copied value.
8. Set `subscriptionId`. Call `ensureId`.

Change the `ss://` branch:

1. Parse the line with `Profile.parseUrl`.
2. Copy the feature settings when `feature` is not null.
3. Set `subscriptionId`. Call `ensureId`.

Do not copy `plugin`, `remoteDns` or the transport fields from the feature profile.
R-UE-23 says the body or the default supplies `remote_dns`.
R-UE-22 says the body supplies the transport fields.

Bare literals such as `Not Found` must not throw. The text is not JSON and it contains no `ss://` line. A base64 decode can succeed and still yields no `ss://` line. The function returns an empty list.
A body that starts with `{` or `[` is JSON. A JSON syntax error throws.
Keep the empty-body case. It returns an empty list.

#### 1.5 Replace the single merge with a batch merge

Remove `mergeSubscription`.
Add this function:

```ts
export interface SubscriptionMergeResult {
  profiles: Profile[];
  currentId: string;
  deleted: number;
}

export function mergeSubscriptionRun(existing: Profile[], fresh: Profile[],
  currentId: string): SubscriptionMergeResult;
```

Algorithm:

1. Make an empty result list and an empty key map. The key is `name + "\n" + addressKey(profile)`.
2. For each stored profile in list order:
   1. Skip a user-configured profile. Append it untouched.
   2. Compute the key.
   3. When the map holds the key, delete this profile. When its id is `currentId`, set `currentId` to `''`. Count the deletion.
   4. When the status is Active, set it to Obsolete.
   5. Append the profile and put it in the map.
3. For each incoming profile in body order:
   1. Compute the key.
   2. When the map holds an Active profile, ignore the incoming profile.
   3. When the map holds an Obsolete profile, call `matched.copyTransportFrom(incoming)`. Set the status to Active and the subscription id to the incoming id. Keep the stored id, route, resolver, counters and order.
   4. Otherwise, create the profile Active. Call `ensureId`. Set the subscription id and `userOrder = nextUserOrder(result)`.
   5. Put the profile in the map.
4. Return the result, the current id and the deletion count.

This function implements R-UE-21, R-UE-22, R-UE-24, R-UE-25 and R-UE-28.
It runs with an empty `fresh` list. Every Active non-user profile then becomes Obsolete.

#### 1.6 Split the fetch from the parse

Remove `fetchSubscription`.
Add this function:

```ts
export interface SubscriptionFetchControl {
  register(request: http.HttpRequest): void;
  unregister(request: http.HttpRequest): void;
  isCancelled(): boolean;
}

export async function fetchSubscriptionBody(url: string,
  control?: SubscriptionFetchControl): Promise<string>;
```

Rules:

1. Create one `http.createHttp()` request.
2. Register the request with the control object.
3. Send a GET request with a 15 s connect timeout and a 15 s read timeout.
4. Throw on a status code outside 200 to 299.
5. Return `response.result as string`.
6. Call `unregister` and `destroy` in `finally`.
7. Throw when `control.isCancelled()` is true after the response.

### 2. `model/Profile.ets`

Add two methods to `Profile`.

```ts
/** Copy the feature settings that a new subscription profile inherits. */
copyFeatureSettingsFrom(feature: Profile): void {
  this.route = feature.route;
  this.ipv6 = feature.ipv6;
  this.udpdns = feature.udpdns;
}

/** Copy the transport fields that a re-listed profile takes. */
copyTransportFrom(incoming: Profile): void {
  this.password = incoming.password;
  this.method = incoming.method;
  this.plugin = incoming.plugin;
  this.pluginOpts = incoming.pluginOpts;
  this.udpFallbackId = incoming.udpFallbackId;
}
```

Do not copy `remoteDns`, `route`, `localAddress`, `localPort`, `name`, `host`, `remotePort`, `id`, `tx`, `rx`, `userOrder` or `subscriptionStatus`.
Add the per-app fields to `copyFeatureSettingsFrom` when U07 adds them.

### 3. `model/SubscriptionRefresh.ets` (new)

#### 3.1 Constants and types

```ts
export const SUBSCRIPTION_ABORT_EVENT = 'com.xbt.project.subscription.abort';
export const SUBSCRIPTION_NOTIFICATION_ID = 2;

export interface SubscriptionUrlRef { id: string; url: string; }

export interface SubscriptionFetchOutcome {
  id: string;
  body: string;  // '' when the download failed
  error: string; // '' when the download succeeded
}

export interface SubscriptionRefreshProgress {
  done: number;
  total: number;
  finishing: boolean;
}

export type SubscriptionRefreshErrorKind = 'fetch' | 'parse' | 'store';

export interface SubscriptionRefreshError {
  kind: SubscriptionRefreshErrorKind;
  message: string;
}

export interface SubscriptionRefreshCallbacks {
  onProgress: (progress: SubscriptionRefreshProgress) => void;
  onError: (error: SubscriptionRefreshError) => void;
}
```

#### 3.2 `SubscriptionRefreshRun`

```ts
export class SubscriptionRefreshRun {
  readonly urls: SubscriptionUrlRef[];
  readonly outcomes: SubscriptionFetchOutcome[];
  done: number = 0;
  finishing: boolean = false;
  cancelled: boolean = false;
  merging: boolean = false;

  constructor(subscriptions: Subscription[]);

  recordFetch(outcome: SubscriptionFetchOutcome): void;
  markFinishing(): void;
  requestCancel(): void;
  beginMerge(): boolean;
  shouldCommit(): boolean;
  succeededIds(): string[];
  failureCount(): number;
}
```

Behavior:

- The constructor copies `id` and `url` from every subscription. This is the one read of the URL list. R-UE-29.
- `recordFetch` appends one outcome and increments `done`. It ignores a call after `done === urls.length`.
- `markFinishing` sets `finishing` to true.
- `requestCancel` sets `cancelled` to true.
- `beginMerge` sets `merging` to `!cancelled` and returns `merging`.
- `shouldCommit` returns `merging`. A cancel after the merge start does not stop the write. R-UE-18 boundary.
- `succeededIds` returns the ids whose outcome has an empty `error`.
- `failureCount` returns the number of outcomes with a non-empty `error`.

Keep every native API call inside methods. Do not call a native API at module load. The host runner imports this file for `SubscriptionRefreshRun`.

#### 3.3 `SubscriptionRefresh`

```ts
export class SubscriptionRefresh {
  static isRunning(): boolean;

  static async start(context: common.UIAbilityContext,
    subscriptions: Subscription[],
    callbacks: SubscriptionRefreshCallbacks): Promise<void>;

  static cancel(): void;

  private static async publishProgress(context: common.UIAbilityContext,
    run: SubscriptionRefreshRun): Promise<void>;
  private static async subscribeAbort(): Promise<void>;
  private static async unsubscribeAbort(): Promise<void>;
  private static async stopAgent(): Promise<WantAgent>;
}
```

Private static fields:

- `run: SubscriptionRefreshRun | undefined`
- `requests: http.HttpRequest[]`
- `subscriber: commonEventManager.CommonEventSubscriber | undefined`

`start` steps:

1. Return when `run` is defined. A second start is ignored.
2. Set `run` from a copy of `subscriptions`. Set the run before the first `await`.
3. Subscribe to `SUBSCRIPTION_ABORT_EVENT`.
4. Call `ensureEnabled(context)` from `ConnectionNotification.ets`.
5. Publish the syncing notification with `0 of N`.
6. Fetch every URL in parallel. For each URL:
   1. Call `fetchSubscriptionBody` with a control object. The control registers and unregisters the request in `requests`. `isCancelled` reads the run.
   2. On success, record `{ id, body, error: '' }`.
   3. On error, record `{ id, body: '', error: message }`. Skip the `onError` call when the run is cancelled.
   4. In `finally`, publish the new count and call `onProgress`.
7. Call `markFinishing`. Publish the finishing notification.
8. Call `beginMerge` when the run is not cancelled. Return to the cleanup step when the call returns false.
9. Read the current profile with `ProfileStore.getCurrent`, the stored profiles with `ProfileStore.getAll` and the current id with `ProfileStore.getCurrentId`.
10. Parse every successful body with `parseSubscriptionBody(body, id, feature)`. A parse error calls `onError({ kind: 'parse' })` and skips that body.
11. Call `mergeSubscriptionRun`.
12. Call `ProfileStore.saveAll`. Call `ProfileStore.setCurrentId` when the id changed.
13. Read `SubscriptionStore.getAll`. Set `updatedAt` to `Date.now()` for every subscription with a successful body that parsed to at least one profile. Call `SubscriptionStore.saveAll`.
14. Catch a store error and call `onError({ kind: 'store' })`. The atomic `JsonStore` write keeps the old file.
15. In `finally`: cancel the notification, unsubscribe from the abort event, clear `requests` and clear `run`.

`cancel` steps:

1. Return when `run` is undefined.
2. Call `run.requestCancel`.
3. Call `destroy` on every request in `requests`. Catch and log each error.
4. Do not stop a profile write that already started. `shouldCommit` reports that state.

Notification steps:

1. Build a `notificationManager.NotificationRequest` with `id = SUBSCRIPTION_NOTIFICATION_ID`.
2. Use `notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT`.
3. Set `normal.title` to `subscription_syncing_n` with `done` and `total`. Set `normal.title` to `subscription_finishing` in the finishing phase.
4. Set `normal.text` to `subscription_service`.
5. Set `isOngoing: true`.
6. Add one action button with `subscription_stop`.
7. Build the button want agent with `wantAgent.getWantAgent` and `actionType: wantAgent.OperationType.SEND_COMMON_EVENT`. Use `wants: [{ action: SUBSCRIPTION_ABORT_EVENT }]`.
8. Catch a publish error and log it. A refused notification permission does not stop the run.

Abort subscription steps:

1. Create a subscriber with `commonEventManager.createSubscriber({ events: [SUBSCRIPTION_ABORT_EVENT] })`.
2. Call `commonEventManager.subscribe` with a callback that calls `SubscriptionRefresh.cancel`.
3. Call `commonEventManager.unsubscribe` in the cleanup step.
4. Put the subscription before the first publish. A Stop tap during a fetch must find the subscriber.

### 4. `model/ProfileStore.ets`

Remove `removeSubscriptionProfiles`.
No other change.
A URL removal no longer touches `store/profiles.json`.
The next refresh marks the orphan profiles Obsolete through `mergeSubscriptionRun`.

### 5. `pages/Subscription.ets`

#### 5.1 State and fields

```ts
@State subscriptions: Subscription[] = [];
@State profileCounts: Map<string, number> = new Map();
@State refreshRunning: boolean = false;
@State removed: Subscription[] = [];
@State undoVisible: boolean = false;

private undoTimer: number = -1;
private listScroller: Scroller = new Scroller();
private dialog: CustomDialogController | null = null;
```

Remove `updatingId` and the `addDialog` field.

Add these imports:

- `bundleManager` from `@kit.AbilityKit`.
- `SubscriptionRefresh` from `../model/SubscriptionRefresh`.
- `addSubscriptionUrl`, `editResult`, `findSubscriptionByUrl`, `replaceSubscriptionUrl`, `restoreSubscriptions` and `validateSubscriptionUrl` from `../model/Subscription`.
- `SubscriptionDialogButton` as a type from `../model/Subscription`.

#### 5.2 Methods

`aboutToAppear`:

1. Call `reload`.
2. Set `refreshRunning` to `SubscriptionRefresh.isRunning()`.

`aboutToDisappear`:

1. Call `hideUndo`.
2. Do not cancel a refresh run. The run ends in its own `finally`.

`reload`:

1. Read `SubscriptionStore.getAll(abilityContext())`.
2. Read `ProfileStore.getAll(abilityContext())`.
3. Count the profiles by `subscriptionId`.
4. Set `subscriptions` and `profileCounts`.

`openAdd`:

1. Call `openDialog('', false)`.

`openEdit`:

1. Call `openDialog(subscription.url, true)`.

`openDialog(initialUrl, editing)`:

1. Create a `CustomDialogController` with `EditSubscriptionDialog`.
2. Pass `initialUrl` and `editing`.
3. Pass `onResult` as `(button, text) => this.applyResult(button, text, initialUrl)`.
4. Set `autoCancel: true`.
5. Call `open`.

`applyResult(button, text, original)`:

1. Call `editResult(button, text, original)`. Return when the result is null.
2. Read the current list.
3. When `result.replacing` is not null, find the record and drop it from the list. When `result.edited` is null, push the record to `removed` and call `showUndo`.
4. When `result.edited` is not null, do these steps:
   1. Trim the text.
   2. When an equal URL exists, keep the existing record.
   3. Else create a `Subscription` with the old id, the old `updatedAt` and the new URL. Call `ensureId`.
   4. Append the record.
5. Call `SubscriptionStore.saveAll`.
6. Call `reload`.
7. Call `scrollToUrl` with the edited URL or the replacing URL.

`remove(subscription)`:

1. Read the current list.
2. Drop the record with the same id.
3. Call `SubscriptionStore.saveAll`.
4. Push the record to `removed`.
5. Call `showUndo`.
6. Call `reload`.

`showUndo`:

1. Set `undoVisible` to true.
2. Clear the old timer.
3. Start a 5000 ms timer. The timer calls `hideUndo`.

`hideUndo`:

1. Clear the timer.
2. Set `undoVisible` to false.
3. Clear `removed`.

`undo`:

1. Read the current list.
2. Call `restoreSubscriptions(list, this.removed)`.
3. Call `SubscriptionStore.saveAll`.
4. Call `hideUndo`.
5. Call `reload`.

`refreshAll`:

1. Return when `refreshRunning` is true.
2. Set `refreshRunning` to true.
3. Call `SubscriptionRefresh.start` with `abilityContext()`, `this.subscriptions` and two callbacks.
4. The `onProgress` callback updates no state. The notification shows the count.
5. The `onError` callback shows a long toast. Use `subscription_update_failed` for a fetch error, `subscription_parse_failed` for a parse error and `common_save_failed` for a store error. Set `duration: 10000`.
6. In `finally`, set `refreshRunning` to false and call `reload`.

`scrollToUrl(url)`:

1. Find the index of the record with `findSubscriptionByUrl`.
2. Call `this.listScroller.scrollToIndex(index)` when the index is not negative.

#### 5.3 Build

Header:

1. Keep the Back text and the `index_subscriptions` title.
2. Add one row with two buttons.
3. The first button uses `subscription_add_subscription`. It calls `openAdd`.
4. The second button uses `subscription_refresh`. It calls `refreshAll` and is disabled while `refreshRunning` is true.
5. Give both buttons `backgroundColor($r('app.color.accent_container'))` and `fontColor($r('app.color.on_container'))`.

List:

1. Use `List({ space: 8, scroller: this.listScroller })`.
2. Set `scrollBar(BarState.Auto)`.
3. Keep the empty-state text.
4. Each `ListItem` does these steps:
   1. Call `swipeAction({ start: { builder: () => { this.DeleteAction() }, onAction: () => this.remove(subscription) } })`.
   2. Call `onClick(() => this.openEdit(subscription))`.
   3. Keep the URL text and the metadata line.
   4. Remove the per-row Update and Delete texts.
5. The `DeleteAction` builder has one root `Row` with one red `Text` that uses `subscription_remove`.

Undo bar:

1. Show the bar when `undoVisible` is true.
2. Use `subscription_removed` when `removed.length` is 1. Use `subscription_removed_n` with the count otherwise.
3. Add one `Button` with `subscription_undo`. Use `accent_container` and `on_container`.
4. The button calls `undo`.

#### 5.4 `EditSubscriptionDialog`

```ts
@CustomDialog
struct EditSubscriptionDialog {
  controller: CustomDialogController;
  initialUrl: string = '';
  editing: boolean = false;
  onResult: (button: SubscriptionDialogButton, text: string) => void = () => {};

  @State url: string = '';
  @State valid: boolean = false;
  @State error: ResourceStr = '';
  @State warning: ResourceStr = '';
}
```

`aboutToAppear`:

1. Set `url` to `initialUrl`.
2. Call `validate(url)`.

`validate(text)`:

1. Call `validateSubscriptionUrl(text, (link) => this.canOpen(link))`.
2. Set `valid` to `check.valid`.
3. Set `warning` to `subscription_cleartext_warning` when `check.cleartext` is true. Else set it to `''`.
4. Set `error` from `check.error`. Use `subscription_url_no_protocol` with the text for `no_protocol`. Use `subscription_url_unknown_protocol` with `check.scheme` for `unknown_protocol`. Set `''` for a valid text.

`canOpen(link)`:

1. Call `bundleManager.canOpenLink(link)`.
2. Return false when the call throws.

Build:

1. Show the title `subscription_edit_title` for add and edit. R-UE-05.
2. Use `TextArea({ placeholder: 'https://…', text: this.url })` with a fixed height. Call `validate` in `onChange`.
3. Show `error` below the field when it is not empty.
4. Show `warning` below the field when it is not empty.
5. Add one button row:
   1. `Remove` only when `editing` is true. Use `error_container` and `on_container`. It calls `onResult('remove', this.url)` and closes.
   2. `Cancel` with `button_neutral` and `on_neutral`. It calls `onResult('cancel', this.url)` and closes.
   3. `OK` with `accent_container` and `on_container`. It is disabled while `valid` is false. It calls `onResult('ok', this.url)` and closes.

The `Remove` button is absent for an add. R-UE-06.
`Cancel` produces no list change and no store write. R-UE-27.

### 6. `module.json5`

Add this module field:

```json5
"querySchemes": ["ftp", "file", "mailto"]
```

The schemes let `canOpenLink` check a non-built-in scheme.
The built-in set covers `ftp` and `file` without this call. The list is a safety net for the general rule.

### 7. Strings

Add these strings to both resource files.

| Name | English | Chinese |
| --- | --- | --- |
| `subscription_edit_title` | Edit subscription | 编辑订阅 |
| `subscription_remove` | Remove | 删除 |
| `subscription_undo` | Undo | 撤销 |
| `subscription_removed` | Removed | 已删除 |
| `subscription_removed_n` | %d items removed | 已删除 %d 项 |
| `subscription_refresh` | Refresh servers from subscription | 从订阅刷新服务器 |
| `subscription_syncing_n` | Syncing subscriptions… (%d of %d) | 正在同步订阅…（%d/%d） |
| `subscription_finishing` | Finishing up… | 正在收尾… |
| `subscription_stop` | Stop | 停止 |
| `subscription_service` | Subscription Service | 订阅服务 |
| `subscription_cleartext_warning` | Cleartext HTTP traffic is insecure | 明文 HTTP 流量不安全 |
| `subscription_url_no_protocol` | No protocol: %s | 缺少协议：%s |
| `subscription_url_unknown_protocol` | Unknown protocol: %s | 未知协议：%s |
| `subscription_parse_failed` | Subscription parse failed: %s | 订阅解析失败：%s |

Change this value:

| Name | Old English | New English |
| --- | --- | --- |
| `subscription_add_subscription` | Add subscription | Add a subscription |

Remove these unused strings:

- `subscription_url_required`
- `subscription_no_profiles`
- `subscription_updated_n`

Keep `subscription_no_subscriptions`, `subscription_never_updated`, `subscription_profiles_updated` and `subscription_update_failed`.

### State and data

### Stores

| Store | Contents | Read rule | Write rule |
| --- | --- | --- | --- |
| `store/subscriptions.json` | JSON array of `{ id, url, updatedAt }` | Drop an unparseable URL. Drop a comparator-equal duplicate. Sort by URL. | Sort by URL. Write with `JsonStore`, which uses a temporary file and a rename. |
| `store/profiles.json` | Profile list with `subscriptionId`, `subscriptionStatus`, `userOrder`, `tx` and `rx` | Sort by `userOrder`. | Write the merge result. Keep the atomic `JsonStore` write. |
| `store/current_profile_id` | Selected profile id | Empty means no selection. | Set to `''` when the merge deletes the current duplicate. |
| Notification id 2 | Refresh notification | One request per run. | Publish again to update. Cancel in the run cleanup. |

The refresh run state is in memory. It is not stored. A process death ends the run.

### Dialog validation state

| State | Entry | OK | Field message |
| --- | --- | --- | --- |
| `unvalidated` | The dialog opens before the first check. | Disabled | None |
| `invalid` | The text is empty, has no scheme, or has an unknown scheme. | Disabled | Parse error |
| `valid` | The text has a built-in or handled scheme, and the scheme is not `http`. | Enabled | None |
| `valid_cleartext_http` | The text has the `http` scheme. | Enabled | Cleartext warning |

Transitions:

| From | Event | To |
| --- | --- | --- |
| `unvalidated` | `aboutToAppear` calls `validate` | `invalid`, `valid` or `valid_cleartext_http` |
| `invalid` | The text changes | `invalid`, `valid` or `valid_cleartext_http` |
| `valid` | The text changes | `invalid`, `valid` or `valid_cleartext_http` |
| `valid_cleartext_http` | The text changes | `invalid`, `valid` or `valid_cleartext_http` |

### Refresh run state

| State | Condition | Screen | Notification |
| --- | --- | --- | --- |
| `idle` | `SubscriptionRefresh.run` is undefined | Refresh button enabled | None |
| `fetching` | The run exists, `finishing` is false and the run is not cancelled | Refresh button disabled | `Syncing subscriptions… (k of N)` |
| `finishing` | `finishing` is true and the run is not cancelled | Refresh button disabled | `Finishing up…` |
| `cancelled before merge` | `cancelled` is true and `merging` is false | Refresh button disabled until cleanup | Removed in cleanup |
| `cancelled after merge start` | `merging` is true | Refresh button disabled until cleanup | Removed in cleanup |

Transitions:

| From | Event | To |
| --- | --- | --- |
| `idle` | `start` with any URL count | `fetching` |
| `fetching` | Every fetch settles | `finishing` |
| `fetching` | `cancel` | `cancelled before merge`, then `idle` |
| `finishing` | The merge and the write end | `idle` |
| `fetching` or `finishing` | A second `start` | No change. The second start is ignored. |
| `finishing` | `cancel` after `beginMerge` returns true | `finishing`. The write continues. |

### Undo window state

| State | Condition | Screen |
| --- | --- | --- |
| `none` | `removed` is empty | The bar is hidden |
| `pendingUndo` | `removed` is not empty | The bar shows the count and Undo |

Transitions:

| From | Event | To |
| --- | --- | --- |
| `none` | A swipe or `Remove` | `pendingUndo` |
| `pendingUndo` | Another removal | `pendingUndo`. The count includes the whole window. The timer restarts. |
| `pendingUndo` | `Undo` | `none`. The URLs return sorted and the store is written. |
| `pendingUndo` | The timer ends, the bar is dismissed, or the page is left | `none`. The removal stands. |

### Data records

`Subscription` keeps `id`, `url` and `updatedAt`.
`SubscriptionMergeResult` carries `profiles`, `currentId` and `deleted`.
`SubscriptionFetchOutcome` carries `id`, `body` and `error`.
`SubscriptionRefreshRun` carries `urls`, `outcomes`, `done`, `finishing`, `cancelled` and `merging`.

### Call chains

Add:

1. Toolbar Add, then the dialog, then OK.
2. `editResult('ok')`, then `addSubscriptionUrl`, then `SubscriptionStore.saveAll`.
3. `reload`, then `scrollToUrl`.

Edit:

1. Row tap, then the dialog with the stored URL.
2. `editResult('ok', newText, oldUrl)`, then `replaceSubscriptionUrl`, then `SubscriptionStore.saveAll`.
3. `reload`, then `scrollToUrl`.

Remove:

1. Swipe or the dialog Remove button.
2. `editResult`, then `SubscriptionStore.saveAll`, then `showUndo`.
3. The profiles file does not change.

Undo:

1. Undo, then `restoreSubscriptions`, then `SubscriptionStore.saveAll`.
2. `hideUndo`, then `reload`.

Refresh:

1. The refresh button, then `SubscriptionRefresh.start`.
2. `SubscriptionRefreshRun` snapshot, then the abort subscription, then the notification.
3. `fetchSubscriptionBody` for every URL, then `recordFetch`, then the notification count.
4. `markFinishing`, then the current profile and the stored profiles.
5. `parseSubscriptionBody`, then `mergeSubscriptionRun`.
6. `ProfileStore.saveAll`, then `setCurrentId` when needed.
7. `SubscriptionStore.saveAll` with the new `updatedAt` values.
8. Notification cancel, abort unsubscribe, run clear.

### Validation and errors

### URL validation

| Input | Handler check | Result | OK | Message |
| --- | --- | --- | --- | --- |
| Empty text | None | `no_protocol` | Disabled | `subscription_url_no_protocol` |
| `example.com` | None | `no_protocol` | Disabled | `subscription_url_no_protocol` |
| `https://example.com/sub` | Built-in | Valid | Enabled | None |
| `http://example.com/sub` | Built-in | Valid, cleartext | Enabled | `subscription_cleartext_warning` |
| `ftp://example.com/list` | Built-in | Valid | Enabled | None |
| `file:///sdcard/subscription.json` | Built-in | Valid | Enabled | None |
| `foo://example.com` | `canOpen` returns false | `unknown_protocol` | Disabled | `subscription_url_unknown_protocol` |
| `custom://host/path` | `canOpen` returns true | Valid | Enabled | None |
| `http://` | Built-in | Valid | Enabled | None. The refresh later shows a fetch error. |

`java.net.URL` accepts `http://` with an empty host. The validator copies that behavior.
A leading or trailing space is trimmed before the check. `java.net.URL` trims it too.

### List and dialog errors

| Event | Result |
| --- | --- |
| Add an equal URL | No new row, no store write, no message |
| Edit to an equal stored URL | The old row is removed, one equal row remains, the store has one line |
| Remove the last URL | The list is empty, the undo bar still shows Undo |
| Undo after a later removal | Every URL in the window returns sorted |
| Undo window ends | The deletion stands and the store keeps it |
| Cancel in the dialog | No list change and no store write |

### Refresh errors

| Event | Result |
| --- | --- |
| A status code outside 200 to 299 | `onError({ kind: 'fetch' })`. A long toast shows `subscription_update_failed` with the status. The body is skipped. |
| A network exception | Same as an HTTP error. |
| A malformed JSON body | `onError({ kind: 'parse' })`. A long toast shows `subscription_parse_failed`. The body adds no profile. |
| A JSON body with no server entry | No profile and no toast. The URL's profiles become Obsolete. |
| A body of bare literals | No profile and no toast. The body has no `ss://` line. The URL's profiles become Obsolete. |
| A failed body | The other bodies still merge. The failing URL's profiles become Obsolete. |
| A body of `[]` or `{}` | No profile and no toast. The URL's profiles become Obsolete. |
| No stored URL | The run goes from `fetching` to `finishing`. The merge with an empty list obsoletes every Active non-user profile. |
| Every download fails | Same as no stored URL. Every Active non-user profile becomes Obsolete. |
| A store write error | `onError({ kind: 'store' })`. A long toast shows `common_save_failed`. The old file stays. |
| A refused notification permission | A log line. The run continues. |
| Cancel during a fetch | No toast for the fetch. No profile write. The notification is removed. |
| Cancel after `beginMerge` | The merge and the profile write complete. |
| The current duplicate is deleted | `currentId` becomes `''`. `ProfileStore.getCurrent` then falls back to the first profile. |

A long toast uses `promptAction.showToast` with `duration: 10000`.

### Test plan

Levels:

- `unit`: one pure function or one state object. Runs in `./test-arkts-host.sh`.
- `integration`: two or more model units composed with fakes. No native API. Runs in `./test-arkts-host.sh`.
- `e2e`: one journey case. The case stays in the U05 E2E document.

Planned host anchors use `entry/src/test/ParityU05.test.ets::U05#<name>`.

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| R-UE-01, R-UE-03 | `entry/src/test/ParityU05.test.ets` | `U05#url-validation-states` | unit |
| R-UE-02 | `entry/src/test/ParityU05.test.ets` | `U05#cleartext-http-warns-and-passes` | unit |
| R-UE-04 | `entry/src/test/ParityU05.test.ets` | `U05#url-scheme-rules` | unit |
| R-UE-06 | `entry/src/test/ParityU05.test.ets` | `U05#remove-appears-only-for-a-stored-url` | unit |
| R-UE-07 | `entry/src/test/ParityU05.test.ets` | `U05#edit-replaces-the-old-url` | unit |
| R-UE-07 | `entry/src/test/ParityU05.test.ets` | `U05#edit-to-an-existing-url-leaves-one-row` | unit |
| R-UE-08 | `entry/src/test/ParityU05.test.ets` | `U05#remove-result-carries-the-removed-url` | unit |
| R-UE-10 | `entry/src/test/ParityU05.test.ets` | `U05#undo-restores-every-removed-url` | unit |
| R-UE-11 | `entry/src/test/ParityU05.test.ets` | `U05#stored-list-round-trips-in-url-order` | unit |
| R-UE-12 | `entry/src/test/ParityU05.test.ets` | `U05#stored-unparseable-urls-are-dropped` | unit |
| R-UE-13 | `entry/src/test/ParityU05.test.ets` | `U05#rows-sort-by-host-port-file-protocol` | unit |
| R-UE-14 | `entry/src/test/ParityU05.test.ets` | `U05#adding-an-equal-url-changes-nothing` | unit |
| R-UE-17 | `entry/src/test/ParityU05.test.ets` | `U05#progress-counts-finished-downloads` | unit |
| R-UE-18 | `entry/src/test/ParityU05.test.ets` | `U05#cancel-before-merge-writes-nothing` | unit |
| R-UE-18 | `entry/src/test/ParityU05.test.ets` | `U05#cancel-after-merge-start-does-not-stop-the-write` | unit |
| R-UE-19 | `entry/src/test/ParityU05.test.ets` | `U05#failed-download-is-skipped-and-reported` | unit |
| R-UE-20 | `entry/src/test/ParityU05.test.ets` | `U05#json-parse-error-is-reported-and-skipped` | unit |
| R-UE-20 | `entry/src/test/ParityU05.test.ets` | `U05#bare-literals-add-nothing-and-do-not-raise` | unit |
| R-UE-20 | `entry/src/test/ParityU05.test.ets` | `U05#single-json-object-parses` | unit |
| R-UE-21 | `entry/src/test/ParityU05.test.ets` | `U05#surviving-active-profiles-become-obsolete` | unit |
| R-UE-22 | `entry/src/test/ParityU05.test.ets` | `U05#relisted-obsolete-keeps-id-and-takes-transport` | unit |
| R-UE-23 | `entry/src/test/ParityU05.test.ets` | `U05#new-profile-copies-feature-settings` | unit |
| R-UE-23 | `entry/src/test/ParityU05.test.ets` | `U05#body-keys-override-feature-settings` | unit |
| R-UE-23 | `entry/src/test/ParityU05.test.ets` | `U05#remote-dns-is-body-or-default` | unit |
| R-UE-24 | `entry/src/test/ParityU05.test.ets` | `U05#stored-duplicate-is-deleted` | unit |
| R-UE-24 | `entry/src/test/ParityU05.test.ets` | `U05#deleting-the-current-duplicate-resets-the-selection` | unit |
| R-UE-24 | `entry/src/test/ParityU05.test.ets` | `U05#user-configured-profile-is-never-deleted` | unit |
| R-UE-25 | `entry/src/test/ParityU05.test.ets` | `U05#active-incoming-duplicate-is-ignored` | unit |
| R-UE-27 | `entry/src/test/ParityU05.test.ets` | `U05#cancel-result-changes-nothing` | unit |
| R-UE-28 | `entry/src/test/ParityU05.test.ets` | `U05#empty-run-still-obsoletes-profiles` | integration |
| R-UE-29 | `entry/src/test/ParityU05.test.ets` | `U05#run-snapshots-the-url-list-once` | unit |
| R-UE-01, R-UE-05 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-01` | e2e |
| R-UE-05, R-UE-06 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-05` | e2e |
| R-UE-08, R-UE-10 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-06` | e2e |
| R-UE-09 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-07` | e2e |
| R-UE-17 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-08` | e2e |
| R-UE-15 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-09` | e2e |
| R-UE-16 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-10` | e2e |
| R-UE-19 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-12` | e2e |
| R-UE-26 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-19` | e2e |
| R-UE-28 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-22` | e2e |
| R-UE-19, R-UE-28 | `docs/versions/5.4.0/e2e/U05.md` | `TC-U05-24` | e2e |

Test notes:

1. `U05#url-scheme-rules` passes a fake `canOpen` that returns false. The test asserts that `ftp` and `file` still pass and that `foo` fails.
2. The host hypium shim has no `assertThrow`. `U05#json-parse-error-is-reported-and-skipped` uses a `try` block and asserts a boolean.
3. `U05#run-snapshots-the-url-list-once` changes the source list after the run construction. The run must keep the old URLs.
4. `U05#empty-run-still-obsoletes-profiles` composes `SubscriptionRefreshRun` with `mergeSubscriptionRun`.
5. `Subscription.test.ets` keeps the base64, SIP008 and malformed-entry tests. Change the `{invalid json` expectation from an empty list to a thrown `SubscriptionParseError`.
6. `SubscriptionMerge.test.ets` keeps every case. Replace `mergeSubscription` with `mergeSubscriptionRun(...).profiles`. The "another subscription" case now expects that other Active profiles become Obsolete in the run. The fresh `A` profile revives the stored `mine` profile.
7. The remaining E2E cases in the U05 document need no new anchor. The unit and integration rows cover their model part.

### Platform notes

1. There is no Android `Service`. `SubscriptionRefresh` is a static controller in the UI process. A process death ends the run. A second start is ignored. Android stops the service on a second start. HarmonyOS has no service intent, so the UI cannot send one.
2. `NotificationProgress` exists only in `NotificationSystemLiveViewContent`. The SDK says a third-party app cannot create a system live view notification. The refresh notification is basic text. The count in the title is the portable part of R-UE-17. C-U05-016's determinate and indeterminate bars are not portable.
3. The Stop action uses `wantAgent.OperationType.SEND_COMMON_EVENT`. The run subscribes to the event with `commonEventManager` only while it is active. This mirrors the Android receiver that exists only during a run. Verify the delivery on a device. The fallback is `START_ABILITY` and a new `handleAction` branch in `EntryAbility.ets`.
4. There is no snackbar. The page shows an undo bar. The bar uses a 5 s timer. Android uses the snackbar default duration. The criteria do not set the duration.
5. `bundleManager.canOpenLink` needs the scheme in `querySchemes`. Add the list in `module.json5`. The built-in set `http`, `https`, `ftp` and `file` does not need the call. `java.net.URL` has handlers for these schemes, and R-UE-04 names `ftp` and `file`.
6. `@kit.NetworkKit` `http` fetches only HTTP and HTTPS. A stored `ftp` or `file` URL passes the dialog and fails the refresh with a long toast. Android has the same result. It casts the connection to `HttpURLConnection`.
7. `promptAction.showToast` takes a duration from 1500 ms to 10000 ms. Use 10000 ms for the long toast.
8. The URL field uses `TextArea`. C-U05-009 requires a multi-line field. `TextInput` is single-line.
9. The row swipe uses `ListItem.swipeAction({ start: ... })` and `onAction`. Only the start edge is enabled. This matches `ItemTouchHelper.START`.
10. The list uses `scrollBar(BarState.Auto)`. There is no letter popup. C-U05-018 is the fast-scroll handle. The standard scroll bar is the closest platform surface.
11. The row keeps the HarmonyOS metadata line with the profile count and the last update. Android shows only the URL. This is an existing HarmonyOS extension and does not block parity.
12. The host test runner compiles `model/` and the specs with the `@kit` stubs. Keep every native call inside a method. `validateSubscriptionUrl` takes the handler check as an argument. `SubscriptionRefreshRun` makes no native call. The host spec imports `SubscriptionRefresh.ets` only for the run class.
13. `Index.ets` reloads on `onPageShow`. A refresh needs no cross-page listener. Android calls `ProfileManager.listener?.reloadProfiles()`, which is a no-op while the Subscriptions screen is open.
14. `ProfileStore.removeSubscriptionProfiles` has no caller after this change. Remove it. An orphan profile stays in `store/profiles.json` and becomes Obsolete at the next refresh.
15. The per-app fields `metered`, `proxyApps`, `bypass` and `individual` do not exist in the HarmonyOS `Profile` yet. U07 adds them. Extend `copyFeatureSettingsFrom` then.
16. The UDP fallback field exists. U05 copies it on a revive. Body parsing for `udp_fallback` belongs to U03.
17. The notification uses the app default slot. Android uses the channel `service-subscription`. HarmonyOS has no named channel in this API surface. The notification id 2 does not collide with the tunnel notification id 1.
18. The refresh runs while the UI process lives. The app has no background grant for this run. The platform can freeze the process when the app leaves the foreground. See U05-Q7.
19. R-UE-11 names the Android public store format. The HLD data design stores the subscription list as `store/subscriptions.json` with `{ id, url, updatedAt }`. The list behavior is the same. Every stored URL survives a restart. The file format differs, because the HarmonyOS store holds the subscription id and the update date.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| U05-Q1 | Does `canOpenLink` resolve `file`, `ftp` and `mailto` on the target devices? The built-in set covers `ftp` and `file`. The list covers other schemes. | Platform owner |
| U05-Q2 | Does a notification action with `SEND_COMMON_EVENT` reach a dynamic subscriber in a third-party app? If not, use the `START_ABILITY` fallback and handle the action in `EntryAbility`. | Platform owner |
| U05-Q3 | Is a text count acceptable in place of the Android progress bar? The public SDK does not let a third-party app create a system live view. | Product owner |
| U05-Q4 | The architecture lists auto-refresh under U05. The U05 criteria have no auto-refresh control. Does automatic refresh belong to this unit or to a later unit? | Product owner |
| U05-Q5 | The architecture lists grouping under U05. The U05 criteria have no grouping control. Does profile grouping belong to this unit? | Product owner |
| U05-Q6 | Which JSON keys must the subscription parser accept beyond the SIP008 keys in this LLD? `udp_fallback` needs U03. | Product owner |
| U05-Q7 | Must a refresh continue when the user leaves the page or the app enters the background? The UI process has no grant for this run. | Platform owner |
| U05-Q8 | Is 5 s the correct undo window? The criteria do not set a duration. Android uses the snackbar default. | Product owner |
| U05-Q9 | Android shows `MalformedURLException` text for a bad URL. HarmonyOS shows localized messages. Is the wording difference acceptable? | Product owner |
| U05-Q10 | Should the row keep the HarmonyOS profile-count and last-update line? Android shows only the URL. | Product owner |

<a id="u06"></a>
## U06 Custom rules

### Scope

U06 aligns the HarmonyOS Custom rules screen with the Android 5.3.5 behavior.
The unit changes the page and the ACL model.

In scope:

- The Edit rule editor with the Generic, Domain, and URL templates.
- Validation for each template.
- Rule storage in the user file.
- Add, edit, remove, copy, cut, and undo.
- The Add rule(s) menu with three entries.
- Clipboard import with the subnet filter.
- One-tap GFW List import.
- The swipe gate on the custom-rules route.
- The forced-bypass composition.
- An import depth of ten.

Out of scope:

- Drawer navigation and the screen entry. U01 owns them.
- Background work scheduling and retry. HarmonyOS has no WorkManager.
- Fail-fast import at connect time. HLD C-06 keeps the cached file.
- The fast-scroll letter popup.
- Within-group sorting of the rule list.

The existing page structure, `Acl` parser, `AclSync` refresh-on-start, `Transfer` clipboard adapter, `ProfileStore`, and `VpnStatusStore` stay.

### Files to change

| File | Change |
| --- | --- |
| `entry/src/main/ets/model/CustomRules.ets` | Add the rule templates, validation, row building, edit helpers, undo helpers, copy text, import filter, swipe gate, and the forced-bypass subnet drop. |
| `entry/src/main/ets/model/Acl.ets` | Add the `defaultBypass` parameter to `parseAcl`. Pass the parent default to an imported child in `flattenAcl`. |
| `entry/src/main/ets/model/AclSync.ets` | Set the import depth to ten. Add the cached-or-bundled ACL reader for the GFW List action. |
| `entry/src/main/ets/pages/CustomRules.ets` | Replace the draft row with the Add rule(s) menu and the editor overlay. Add tap-to-toggle, Back handling, the undo bar, the swipe gate, and the ACL copy text. |
| `entry/src/main/resources/base/element/string.json` | Add the English strings in this document. |
| `entry/src/main/resources/zh_CN/element/string.json` | Add the Chinese strings with the same names. |
| `entry/src/test/List.test.ets` | Register the new parity spec. |
| `entry/src/test/CustomRules.test.ets` | Update the tests that depend on the old `addRule` storage form and the old import filter. |
| `entry/src/test/ParityU06.test.ets` | New host spec for the planned tests. |

### Implementation plan

### Model: `model/CustomRules.ets`

Keep the existing exports.
Add the symbols in this table.

| Symbol | Kind | Signature | Responsibility |
| --- | --- | --- | --- |
| `RULE_KIND_GENERIC` | constant | `string = 'generic'` | The Generic template identifier. |
| `TEMPLATE_ORDER` | constant | `string[]` | The template selector order: Generic, Domain, URL. |
| `RULE_ERROR_PATTERN` | constant | `string = 'pattern'` | A regular-expression syntax error. |
| `RULE_ERROR_DOMAIN` | constant | `string = 'domain'` | A domain form error. |
| `RULE_ERROR_URL` | constant | `string = 'url'` | A URL form error. |
| `RULE_WARNING_CLEARTEXT` | constant | `string = 'cleartext'` | A cleartext HTTP warning. |
| `RuleRow` | interface | `{ value: string; kind: string }` | One rule row. Move it here from the page. |
| `RuleCheck` | interface | `{ valid: boolean; error: string; warning: string; detail: string }` | One validation result. |
| `isSubnet` | function | `(value: string): boolean` | True for an IPv4 or IPv6 address or subnet. |
| `isUrlRule` | function | `(value: string): boolean` | True for an `http` or `https` URL with a host. |
| `ruleRows` | function | `(text: string): RuleRow[]` | Build the list rows from the composed text. |
| `checkRule` | function | `(template: string, text: string): RuleCheck` | Validate one rule for one template. |
| `storedRule` | function | `(template: string, text: string): string` | Return the storage form for one rule. |
| `ruleTemplateFor` | function | `(value: string): string` | Pick the template that matches a stored rule. |
| `ruleEditorText` | function | `(value: string): string` | Return the text the editor shows for a stored rule. |
| `showRemove` | function | `(value: string): boolean` | True when the editor must show the Remove button. |
| `setRule` | function | `(userText: string, oldValue: string, template: string, text: string): string` | Remove the old rule and add the new one. |
| `joinRemovals` | function | `(existing: string[], added: string[]): string[]` | Put the newest removal batch first. |
| `restoreRules` | function | `(userText: string, removed: string[]): string` | Add removed rules back in list order. |
| `aclTextForRules` | function | `(values: string[]): string` | Build the clipboard ACL text for a selection. |
| `toggleSelected` | function | `(selected: string[], value: string): string[]` | Add or remove one value from the selection. |
| `swipeBlocked` | function | `(route: string, state: string): boolean` | True when the swipe gate is closed. |
| `canSwipe` | function | `(selectedCount: number, blocked: boolean): boolean` | True when a swipe may remove a row. |
| `domainRule` | function | `(text: string): string` | Build the anchored domain pattern. |
| `domainFromRule` | function | `(value: string): string \| null` | Read the domain name from an anchored pattern. |
| `toAsciiDomain` | function | `(text: string): string \| null` | Convert a domain to its ASCII form. |
| `toUnicodeDomain` | function | `(text: string): string` | Convert an ASCII domain to its Unicode form. |

Change these existing functions.

- `composeCustomRules(userText)`:
  - Parse the text with `parseAcl(userText, true)`, or start from `emptyAcl()`.
  - When `doc.bypass` is false, set it to true.
  - When the original default was proxy, drop the subnet entries from `doc.bypassEntries`.
  - Keep the bypass hostnames.
  - Return the serialized document.
- `addRule(userText, kind, value)`:
  - Return `userText` unchanged when `checkRule(kind, value).valid` is false.
  - Add a URL to `doc.urls`.
  - Add a Domain rule as `domainRule(value)` to `doc.proxyEntries`.
  - Add a Generic or Subnet rule as `value` to `doc.proxyEntries`.
  - Add an empty Generic rule as `''` to `doc.proxyEntries`.
  - Check for duplicates only in the target list.
  - Return the serialized document.
- `addRulesFromText(userText, aclText)`:
  - Parse the incoming text with `parseAcl(aclText, true)`.
  - Use only the incoming proxy entries. A bypass entry describes the route the list came from.
  - When `incoming.bypass` is false, drop subnet entries.
  - Skip empty entries.
  - Check for duplicates only in `doc.proxyEntries` and `doc.urls`.
  - Return the serialized document.
- `removeRules(userText, values)` stays. It removes from both entry lists and the URL list.

`ruleRows(text)` has these rules:

1. Parse the text with `parseAcl`.
2. Read only `doc.proxyEntries` and `doc.urls`. Bypass entries stay in the file but are not rows, as on Android.
3. Put subnet entries first, then hostname entries, then URLs.
4. Keep the file order inside each group.
5. Drop a duplicate value before it becomes a row.

`checkRule(template, text)` has these rules:

| Template | Valid input | Error code | Detail |
| --- | --- | --- | --- |
| Generic | A subnet, or any text that `new RegExp(text)` accepts | `RULE_ERROR_PATTERN` | The `RegExp` exception message |
| Domain | An empty text, or a domain that `toAsciiDomain` accepts | `RULE_ERROR_DOMAIN` | Empty |
| URL | An `http` or `https` URL with a host | `RULE_ERROR_URL` | Empty |

`checkRule` sets `RULE_WARNING_CLEARTEXT` for an `http` URL.
It sets no warning for `https`.

`storedRule(template, text)` has these rules:

- Generic returns `text`.
- Subnet returns `text`.
- Domain returns `domainRule(text)`.
- URL returns `text`.

`domainRule(text)`:

1. Convert the text with `toAsciiDomain`. Use the raw text when the conversion fails.
2. Escape every regular-expression metacharacter in each label.
3. Join the labels with `\\.`.
4. Return `(?:^|\\.)<name>$`.

The trailing `$` is required.
Without it, the rule also matches `example.com.evil.com` and `example.com.cn`.

`domainFromRule(value)`:

1. Accept these prefixes: `(?:^|\\.)`, `(^|\\.)`, `^(.*\\.)?`.
2. Require a trailing `$`.
3. Replace each `\\.` in the inner text with `.`.
4. Convert the result with `toUnicodeDomain`.
5. Return `null` when no prefix matches.

`toAsciiDomain(text)`:

1. Return `''` for an empty text.
2. Split the text on `.`.
3. Reject an empty label.
4. For an ASCII label, accept only letters, digits, and inner hyphens. Reject a leading or trailing hyphen, an underscore, and a space.
5. For a Unicode label, encode it with Punycode (RFC 3492), prefix `xn--`, and check the label length.
6. Reject a label longer than 63 characters and a name longer than 253 characters.
7. Join the labels with `.`.
8. Return `null` on a rejection.

`toUnicodeDomain(text)` decodes each `xn--` label with Punycode and keeps the other labels.

`ruleTemplateFor(value)`:

1. Return `RULE_KIND_URL` when `isUrlRule(value)` is true.
2. Return `RULE_KIND_DOMAIN` when `domainFromRule(value)` is not null.
3. Return `RULE_KIND_GENERIC` in all other cases.

`ruleEditorText(value)`:

- Return `value` for a URL and a Generic rule.
- Return `domainFromRule(value)` for a Domain rule.

`showRemove(value)` returns true when `value.length > 0`.
The editor uses it for an edit of an existing rule.
A new rule and an empty rule hide the Remove button.

`setRule(userText, oldValue, template, text)`:

1. Remove `oldValue` with `removeRule` when it is not empty.
2. Add the new rule with `addRule`.
3. Return the new text.

`joinRemovals(existing, added)` returns `added.concat(existing)`.

`restoreRules(userText, removed)`:

- Walk `removed` from the first element to the last.
- Add a URL with `RULE_KIND_URL`.
- Add every other value with `RULE_KIND_GENERIC`.
- Return the new text.

`aclTextForRules(values)`:

1. Start from `emptyAcl()`.
2. Set `bypass = true`.
3. Add a URL value to `urls`.
4. Add every other value to `proxyEntries`.
5. Return `serializeAcl(doc)`.

`swipeBlocked(route, state)` returns true when `route === ROUTE_CUSTOM_RULES` and `state` is `VPN_STATE_STARTING` or `VPN_STATE_RUNNING`.
The caller passes `VPN_STATE_STOPPED` when the status file is absent.
A `failed` state leaves the gate open because no tunnel runs.

`canSwipe(selectedCount, blocked)` returns `selectedCount === 0 && !blocked`.

`toggleSelected(selected, value)` removes the value when it is present.
It appends the value when it is absent.
It returns a new array in both cases.

`isSubnet(value)`:

1. Split on `/` into one or two parts.
2. Parse the address as IPv4 when it has no colon.
3. Parse the address as IPv6 when it has a colon.
4. Reject a prefix that is not a decimal number in `0..32` for IPv4 and `0..128` for IPv6.
5. Return true for a valid address with no prefix.
6. Reject `999.1.1.1`, `10.0.0.0/33`, `a.test`, and an empty text.
7. Accept `14.102.250.18`, `10.0.0.0/8`, `::1`, and `::1/128`.

`isUrlRule(value)` accepts `^https?://` followed by a host.
It rejects a missing scheme, a missing host, whitespace, and any non-`http` scheme.

### Model: `model/Acl.ets`

- Add the optional parameter `defaultBypass: boolean = false` to `parseAcl`.
  - Set `doc.bypass` to `defaultBypass` at the start.
  - Set the current section to `proxy` when `defaultBypass` is true.
  - Set the current section to `bypass` when `defaultBypass` is false.
  - A default line still changes `doc.bypass` and leaves the current section alone.
  - Keep every other rule of the parser.
  - The one-argument form keeps the current behavior for every existing caller.
- Change `flattenAcl`:
  - Parse each imported child with `parseAcl(childText, doc.bypass)`.
  - This matches Android's `Acl.flatten`, which parses a child with the parent default.
- The `parseAcl` comment records the reason: entries before a list section belong to the proxy list when the caller asks for a bypass default.
  - The import path uses this form.
  - The GFW List file uses this form.

### Model: `model/AclSync.ets`

- Replace `const MAX_DEPTH = 2` with `export const MAX_ACL_DEPTH: number = 10`.
- `refreshAcl` passes `MAX_ACL_DEPTH` to `flattenAcl`.
- Add `export async function readAclText(context: common.Context, name: string): Promise<string>`.
  - Return the cached copy from `cachedAcl(context, name)` when it is not empty.
  - Read `acl/<name>` from `context.resourceManager.getRawFileContent`.
  - Decode the bytes with a local `bytesToText`.
  - Return `''` when the read fails.
- Add `function bytesToText(bytes: Uint8Array): string`.
  - Copy the byte-to-character loop used by `SsVpnExtensionAbility`.
  - The ACL files are ASCII, so the loop is sufficient.

### Page: `pages/CustomRules.ets`

Remove the local `interface RuleRow`.
Import it from `model/CustomRules`.

Replace these state properties.

| Property | Type | Initial value | Use |
| --- | --- | --- | --- |
| `rows` | `RuleRow[]` | `[]` | The visible rules. |
| `selected` | `string[]` | `[]` | The selected rule values. |
| `swipeBlocked` | `boolean` | `false` | The swipe gate state. |
| `editorOpen` | `boolean` | `false` | The editor overlay is visible. |
| `editorTemplate` | `string` | `RULE_KIND_GENERIC` | The selected template. |
| `editorText` | `string` | `''` | The editor input. |
| `editorValid` | `boolean` | `true` | The OK button state. |
| `editorError` | `string` | `''` | The error code. |
| `editorWarning` | `string` | `''` | The warning code. |
| `editorDetail` | `string` | `''` | The platform error text. |
| `editorRemoveVisible` | `boolean` | `false` | The Remove button state. |
| `removed` | `string[]` | `[]` | The undo bin. |
| `undoVisible` | `boolean` | `false` | The undo bar is visible. |

Add these private properties.

| Property | Type | Use |
| --- | --- | --- |
| `editorOriginal` | `string` | The stored value the editor opened for. |
| `editorEditing` | `boolean` | The editor opened for an existing rule. |
| `undoTimer` | `number` | The undo bar timer handle. |
| `listScroller` | `Scroller` | The rule list scroller. |

Add these methods.

| Method | Signature | Responsibility |
| --- | --- | --- |
| `currentText` | `(): string` | `composeCustomRules(readUserRules(abilityContext()))`. |
| `reload` | `(): void` | Set `rows` from `ruleRows(this.currentText())`. |
| `change` | `(next: string): Promise<void>` | Write the user file, then reload. Show `common_save_failed` on a write error. |
| `refreshGate` | `(): Promise<void>` | Read the current profile and the VPN status. Set `swipeBlocked`. |
| `openAdd` | `(): void` | Open the editor with the Generic template, empty text, and no Remove button. |
| `openEdit` | `(row: RuleRow): void` | Open the editor with the matching template and the stored text. Set Remove from `showRemove(row.value)`. |
| `closeEditor` | `(): void` | Hide the overlay and clear the editor fields. |
| `setEditorTemplate` | `(template: string): void` | Set the template and re-run validation. |
| `recheckEditor` | `(): void` | Set `editorValid`, `editorError`, `editorWarning`, and `editorDetail` from `checkRule`. |
| `editorMessage` | `(): ResourceStr` | Map the error or warning code to the display text. |
| `editorMessageColor` | `(): Resource` | Return `error_strong` for an error and `warning` for a warning. |
| `saveEditor` | `(): Promise<void>` | Ignore an invalid input. Call `setRule` or `addRule`. Write, close, append an empty row when the stored value is empty, and scroll to the saved value. |
| `removeEditor` | `(): Promise<void>` | Close the editor and remove `editorOriginal`. |
| `importFromClipboard` | `(): Promise<void>` | Read the clipboard. Add its rules. Show `custom_rules_import_failed` when nothing is added. |
| `importGfwList` | `(): Promise<void>` | Read the cached or bundled `gfwlist.acl`. Add its rules. Report nothing when the file is missing or empty. |
| `remove` | `(values: string[]): Promise<void>` | Remove the values, clear the selection, add the values to the undo bin, and show the undo bar. |
| `showUndo` | `(): void` | Show the undo bar and restart the four-second timer. |
| `commitRemovals` | `(): void` | Clear the undo bin and hide the bar. |
| `undoRemovals` | `(): Promise<void>` | Restore the undo bin, clear it, and append an empty row when a restored value is empty. |
| `toggle` | `(value: string): void` | Replace `selected` with `toggleSelected`. |
| `copySelected` | `(): Promise<boolean>` | Write `aclTextForRules(this.selected)`. Show the export toast. Return the result. |
| `cutSelected` | `(): Promise<void>` | Copy the selection, then remove it whatever the copy result. |
| `scrollTo` | `(value: string): void` | Find the row and call `listScroller.scrollToIndex` after a zero-delay timer. |

Lifecycle:

- `aboutToAppear` calls `reload` and `refreshGate`.
- `onPageShow` calls `reload` and `refreshGate`.
- `aboutToDisappear` calls `commitRemovals` and clears `selected`.
- `onBackPress` closes the editor first.
- `onBackPress` clears a non-empty selection second.
- `onBackPress` returns false when the editor is closed and the selection is empty.

UI changes:

- Put the Add rule(s) button in the header row, in place of the trailing space.
- Show the Add rule(s) button only when `selected.length === 0`. The selection bar takes over the actions.
- Bind a menu with exactly three entries: Manual Settings, Import from Clipboard, GFW List.
  - Manual Settings calls `openAdd`.
  - Import from Clipboard calls `importFromClipboard`.
  - GFW List calls `importGfwList`.
- Remove the draft `TextInput`, the three kind buttons, and the standalone import button.
- Keep the explainer, the empty-state text, the selection bar, and the list.
- Wrap the page in a `Stack` with the editor overlay.
  - The overlay shows a scrim with the `background` token.
  - The card shows the title, the template `Select`, the `TextInput`, the message line, and the button row.
  - The button row holds Cancel, Remove, and OK.
  - OK uses `.enabled(this.editorValid)`.
  - Remove is present only when `editorRemoveVisible` is true.
  - A tap on the scrim calls `closeEditor`.
- Add the undo bar above the list.
  - The bar shows `custom_rules_removed_n` with `removed.length`.
  - The bar holds an Undo button.
- The rule row:
  - A tap calls `openEdit` when the selection is empty.
  - A tap calls `toggle` when the selection is not empty.
  - A long press calls `toggle`.
  - A check mark shows when the row is selected.
  - Remove the per-row cross icon.
- The swipe action:
  - Use `canSwipe(this.selected.length, this.swipeBlocked)`.
  - Pass an `end` object with a `builder` and an `onAction`.
  - `onAction` calls `remove([row.value])`.
  - Pass an empty object when `canSwipe` is false.
- The list uses `List({ space: 6, scroller: this.listScroller })`.

Colour rules:

- The overlay scrim uses the `background` token with an opacity below 1.
- The editor card uses the `surface` token.
- The title uses the `text_body` token.
- The message line uses `error_strong` for an error and `warning` for a warning.
- The OK button uses `accent_container` and `on_container`.
- The Cancel button uses `button_neutral` and `on_neutral`.
- The Remove button uses `error_container` and `on_container`.
- The Add rule(s) button uses `button_neutral` and `on_neutral`.
- The undo bar uses the `surface` token.
- The undo text uses the `text_body` token.
- The Undo button uses `button_neutral` and `on_neutral`.
- The template `Select` uses the theme default text colour on the card.

### Resources

Add these names to both string files.

| Name | English value |
| --- | --- |
| `custom_rules_add_rules` | Add rule(s)… |
| `custom_rules_manual_settings` | Manual Settings |
| `custom_rules_gfw_list` | GFW List |
| `custom_rules_edit_rule` | Edit rule |
| `custom_rules_template_generic` | Subnet or Hostname PCRE pattern |
| `custom_rules_template_domain` | Domain name and all its subdomain names |
| `custom_rules_template_url` | URL to online config |
| `custom_rules_domain_invalid` | Enter a valid domain name |
| `custom_rules_url_invalid` | Enter a valid URL with a scheme |
| `custom_rules_cleartext_warning` | Cleartext HTTP traffic is insecure |
| `custom_rules_exported` | Successfully export! |
| `custom_rules_export_failed` | Failed to export. |
| `custom_rules_import_failed` | Failed to import. |

Keep the existing `custom_rules_imported_n`, `custom_rules_removed_n`, `custom_rules_selected_n`, `custom_rules_select_all`, `custom_rules_cut`, `custom_rules_draft_hint`, and the common strings.

### Tests

- Add `import parityU06Test from './ParityU06.test';` to `entry/src/test/List.test.ets`.
- Call `parityU06Test()` in the suite.
- Update `entry/src/test/CustomRules.test.ets`:
  - A Domain add now stores the anchored pattern.
  - A Domain add with an invalid text returns the input unchanged.
  - A duplicate check uses the target list only.
  - A plain list with a subnet keeps the subnet.
  - A `[proxy_all]` list with a subnet drops the subnet.
- Add `entry/src/test/ParityU06.test.ets` with the tests in the test plan.

### State and data

| State | Owner | Storage | Transitions |
| --- | --- | --- | --- |
| Editor | Page | Page memory | Closed → open for add, open for edit → closed by OK, Cancel, Remove, scrim, or Back. |
| Selection | Page | Page memory | Empty → one value → several values → empty by toggle, Back, Remove, Cut, or page leave. |
| Undo bin | Page | Page memory and timer | Empty → one removal → more removals → empty by Undo, timer expiry, or page leave. |
| Swipe gate | Page | Sampled from the profile store and the status file | Open → closed when the route is custom-rules and the service is starting or running. |
| User rules | Model | `filesDir/custom-rules-user.acl` | Absent → written on the first add, edit, import, remove, or undo. |
| Served rules | VPN extension | `filesDir/acl/custom-rules.acl` | Written at each custom-rules start. The page never writes it. |
| GFW cache | Model | `filesDir/acl-cache/gfwlist.acl` | Written by `AclSync.refreshAcl` after a gfwlist start with import URLs. |
| GFW bundled | Resources | `rawfile/acl/gfwlist.acl` | Read-only. |

Data flow:

1. The page reads the user file.
2. The page composes the forced-bypass document.
3. The page builds the rows from the proxy entries and the URLs.
4. The page writes the composed document after each change.
5. The extension reads the user file at start and composes the served copy.

Invariants:

- The composed document always starts with `[bypass_all]`.
- A proxy-default user file loses its subnet entries on the first read.
- A bypass hostname stays in the file and does not become a row.
- The page writes only the user file.
- The undo bin holds rule values, not row indexes.
- The status file and the profile store are read-only for this page.

### Validation and errors

| Condition | Detection | Result |
| --- | --- | --- |
| Generic text does not compile | `new RegExp(text)` throws | OK is disabled. The error line shows the exception message. |
| Generic text is empty | `checkRule` returns valid | OK is enabled. The rule is stored as an empty line. |
| Domain text has an empty label | `toAsciiDomain` returns null | OK is disabled. The error line shows `custom_rules_domain_invalid`. |
| Domain text is empty | `toAsciiDomain('')` returns `''` | OK is enabled. The stored rule is `(?:^|\\.)$`. |
| URL text has no scheme or host | `isUrlRule` returns false | OK is disabled. The error line shows `custom_rules_url_invalid`. |
| URL text is `http` | `isUrlRule` returns true and the scheme is `http` | OK is enabled. The error line shows `custom_rules_cleartext_warning`. |
| URL text is `https` | `isUrlRule` returns true and the scheme is `https` | OK is enabled. The error line is empty. |
| Clipboard read fails | `readClipboard` rejects | The list is unchanged. Show `custom_rules_import_failed`. |
| Clipboard adds no rule | The row count does not change | The list is unchanged. Show `custom_rules_import_failed`. |
| Clipboard write fails | `writeClipboard` rejects | Show `custom_rules_export_failed`. Cut still removes the selection. |
| GFW file is absent or empty | `readAclText` returns `''` | The list is unchanged. Show no message. |
| User file write fails | `writeUserRules` throws | Keep the old rows. Show `common_save_failed` with the message. |
| Swipe gate is closed | `canSwipe` returns false | The row does not move. Tap, OK, Remove, Cut, and Copy still work. |
| Undo timer expires | The four-second timer fires | Clear the undo bin. The removal stays. |
| Page leaves with an undo bar | `aboutToDisappear` | Clear the undo bin. The removal stays. |
| OK with an invalid input | `editorValid` is false | The button is disabled. No write occurs. |
| Remove on an empty rule | `editorRemoveVisible` is false | The button is absent. |

The editor keeps the old file until a valid OK.
Cancel, a scrim tap, and Back make no write.

### Test plan

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| TC-U06-02 | `entry/src/test/ParityU06.test.ets` | `U06#add-rule-and-row-order` | unit |
| TC-U06-03 | `entry/src/test/ParityU06.test.ets` | `U06#generic-pattern-validation` | unit |
| TC-U06-04 | `entry/src/test/ParityU06.test.ets` | `U06#domain-rule-anchor` | unit |
| R-UF-07, R-UF-08 | `entry/src/test/ParityU06.test.ets` | `U06#domain-idn-punycode` | unit |
| R-UF-07 | `entry/src/test/ParityU06.test.ets` | `U06#domain-rejects-empty-label` | unit |
| TC-U06-05 | `entry/src/test/ParityU06.test.ets` | `U06#url-rule-cleartext-warning` | unit |
| R-UF-10 | `entry/src/test/ParityU06.test.ets` | `U06#template-read-back` | unit |
| TC-U06-25 | `entry/src/test/ParityU06.test.ets` | `U06#empty-generic-rule` | unit |
| TC-U06-06 | `entry/src/test/ParityU06.test.ets` | `U06#edit-replaces-rule` | unit |
| TC-U06-07, TC-U06-11 | `entry/src/test/ParityU06.test.ets` | `U06#remove-and-undo` | unit |
| TC-U06-18, TC-U06-30 | `entry/src/test/ParityU06.test.ets` | `U06#undo-count-accumulates` | unit |
| TC-U06-28 | `entry/src/test/ParityU06.test.ets` | `U06#undo-dismissal-keeps-removal` | unit |
| TC-U06-15, TC-U06-16 | `entry/src/test/ParityU06.test.ets` | `U06#copy-selection-as-acl` | unit |
| TC-U06-08, TC-U06-09, TC-U06-32 | `entry/src/test/ParityU06.test.ets` | `U06#import-clipboard-and-subnet-filter` | unit |
| TC-U06-10 | `entry/src/test/ParityU06.test.ets` | `U06#gfwlist-import` | unit |
| TC-U06-12, TC-U06-13, TC-U06-33 | `entry/src/test/ParityU06.test.ets` | `U06#swipe-gate` | unit |
| TC-U06-14 | `entry/src/test/ParityU06.test.ets` | `U06#selection-toggle` | unit |
| TC-U06-20, TC-U06-34 | `entry/src/test/ParityU06.test.ets` | `U06#compose-forced-bypass` | unit |
| TC-U06-19 | `entry/src/test/ParityU06.test.ets` | `U06#flatten-depth-ten` | unit |
| TC-U06-27 | `entry/src/test/ParityU06.test.ets` | `U06#remove-button-visibility` | unit |
| TC-U06-24 | `entry/src/test/ParityU06.test.ets` | `U06#route-acl-file-map` | unit |

Each planned anchor is `entry/src/test/ParityU06.test.ets::U06#<name>`.

Device checks stay outside this table:

- TC-U06-01 checks the drawer entry. U01 owns the drawer.
- TC-U06-12, TC-U06-13, and TC-U06-33 include the real swipe gesture.
- TC-U06-17 checks the system Back key.
- TC-U06-26 checks Cancel and a dialog dismissal.
- TC-U06-29 checks the page-leave lifecycle.
- TC-U06-31 checks a failed clipboard write.
- TC-U06-19, TC-U06-24, and TC-U06-35 check the connect, deploy, and stale-file paths on a device.
- TC-U06-21, TC-U06-22, and TC-U06-23 stay as platform divergences.

Test data for the host spec:

- A user text with a proxy list, a bypass hostname, a subnet, and an import URL.
- A clipboard text with `[proxy_all]`, `[proxy_list]`, and one subnet.
- A gfwlist text with `[bypass_all]`, `[proxy_list]`, one bare IP, one hostname, and one import URL.
- A ten-level import chain.
- The VPN states `starting`, `running`, `failed`, and `stopped`.
- The domain examples `example.com`, `münchen.example`, `例子.测试`, and `a..b`.
- The URL examples `http://a.example/list`, `https://a.example/list`, and `a.example`.

### Platform notes

| Android surface | HarmonyOS equivalent | Difference |
| --- | --- | --- |
| `java.util.regex.Pattern` | ECMAScript `RegExp` | A few Java escapes and possessive quantifiers are absent. |
| `java.net.IDN` | Pure Punycode in `model/CustomRules.ets` | Names are converted without a platform IDN library. |
| `java.net.URL` | A form check for `http` and `https` | Other schemes are rejected. |
| `SortedList` | Array in file order | The rows are grouped as subnets, hostnames, and URLs. The order inside a group follows the file. |
| `Snackbar` | In-page undo bar with a four-second timer | A second removal joins the bar and updates the count. |
| `ItemTouchHelper` | `swipeAction` with `onAction` | A full swipe removes the row on release. |
| `ActionMode` | In-page selection bar and `onBackPress` | Back clears the selection before it leaves the page. |
| `WorkManager` | `AclSync.refreshAcl` at start | No retry, no charging constraint, no ten-second delay. |
| `noBackupFilesDir` asset copy | Rawfile read and `filesDir/acl-cache` | The GFW List action prefers the cached copy, then the rawfile. |
| Clipboard | `pasteboard` through `model/Transfer.ets` | The same text formats. |

Recorded divergences:

- A failed import URL does not stop the connect. The start uses the cached copy. HLD C-06 requires this.
- The flattened copy keeps the `#IMPORT_URL` lines. The core treats them as comments.
- An empty Generic rule is a row for the current session. A reload drops it because `parseAcl` skips empty lines. Android has the same limit after a process restart.
- The swipe gate is sampled at `aboutToAppear` and `onPageShow`. A state change while the page is open does not update the gate until the next page show.
- A persisted `failed` state leaves the swipe gate open. Android returns to `Stopped` after a failed start.
- The URL template accepts `http` and `https` only. The app fetches imported lists over HTTP in `AclSync`.
- The page shows only proxy entries and URLs. Bypass hostnames stay in the file and stay hidden.
- The user file is rewritten in the composed form on the first change after a proxy-default file is read.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| U06-Q1 | Does the rule list need sorting inside each group, as Android's `SortedList` does? | Product owner |
| U06-Q2 | Is full RFC 3492 Punycode required for the first release, or are ASCII domains sufficient? | Product owner |
| U06-Q3 | Must the editor show bypass hostnames that Android keeps hidden? | Product owner |
| U06-Q4 | Must the URL template accept non-HTTP schemes, as `java.net.URL` does? | Product owner |
| U06-Q5 | Must the custom-rules entry move to a navigation drawer? | U01 owner |
| U06-Q6 | Must the connect fail on an unreachable import URL, as Android does? | Architecture owner |
| U06-Q7 | Must the swipe gate poll the status file while the page is open? | Product owner |
| U06-Q8 | Is the fast-scroll letter popup required? | Product owner |
| U06-Q9 | Must an empty Generic rule survive a page reload? | Product owner |
| U06-Q10 | Must the page rewrite a proxy-default user file on first view? | Product owner |

<a id="u07"></a>
## U07 Per-app proxy

### Scope

This document plans the HarmonyOS implementation of unit U07, per-app proxy with Apps VPN mode.
The unit adds the mode and the list to a profile, the app picker page, and the application lists for the VPN extension.
The existing page and model structure stays.

### In scope

| Area | Result |
| --- | --- |
| Profile record | The mode, the bypass flag, and the list live on the profile. |
| Editor entry | The profile editor opens the app picker. The entry works in VPN service mode only. |
| App picker page | The Mode group, search, rows, manual add, and a loading state. |
| Mode group | Off, On, and Bypass. The choices are exclusive. |
| Selection | A row tap toggles one bundle name. The visible row order does not change. |
| Draft | The page edits an in-memory draft. The editor writes the profile. |
| Import and export | The clipboard text holds the bypass flag on the first line and one bundle name per later line. |
| Apply to all | The action copies the bypass flag and the list to every profile. |
| Profile JSON | The export writes `proxy_apps`. The import reads it. |
| VPN config | `trustedApplications` in On mode. `blockedApplications` in Bypass mode. |
| Client bundle | The client always stays outside the tunnel. |

### Out of scope

- A public list of installed bundles. The public SDK needs a system permission for it.
- Android UIDs, retained packages, the `android` package, and the INTERNET permission filter.
- App icons and localized labels of other bundles.
- Package-change broadcasts. The public listener needs a system permission.
- Fast scroll, the keyboard search action, and hardware menu shortcuts.

### Deliberate deviations from Android

| Rule | Android behavior | HarmonyOS behavior | Reason |
| --- | --- | --- | --- |
| R-UG-03 | The UID is the selection key | The bundle name is the selection key | HarmonyOS has no public UID for another app |
| R-UG-10 | The package manager lists every INTERNET app | The page lists stored names and accepts a manual name | Enumeration needs a system permission |
| R-UG-12 | The row shows the icon, the label, and the package with UID | The row shows the bundle name | The public query returns no cross-bundle icon or resolved label |
| R-UG-16 | The search matches UID digits | The search matches the bundle name | No UID |
| R-UG-18 | A receiver reloads the list after an install | The page reloads on show and after an edit | No public listener with a normal permission |
| R-UG-24 | A failed row update throws after earlier writes | One atomic `saveAll` | A partial write is a defect |

### Target parity

Target parity after this unit: 21 cases implemented, 2 cases partial, 5 cases android-only.

- Partial: TC-U07-04 and TC-U07-07. The icon, the label, and the UID parts stay absent.
- Android-only: TC-U07-08, TC-U07-09, TC-U07-24, TC-U07-26, and TC-U07-27.

The Test plan and the case disposition table below list every case.

### Files to change

| File | Kind | Change |
| --- | --- | --- |
| `entry/src/main/ets/model/Profile.ets` | Change | Add `proxyAppsEnabled`, `proxyAppsBypass`, and `proxyAppsList`. |
| `entry/src/main/ets/model/ProfileStore.ets` | Change | Read the three fields. Add `getAllOrNull` and one parse helper. |
| `entry/src/main/ets/model/ProfilesFile.ets` | Change | Read and write `proxy_apps`. |
| `entry/src/main/ets/model/PerApp.ets` | New | The mode, list, search, import, export, draft, and VPN list rules. |
| `entry/src/main/ets/model/AppCatalog.ets` | New | The bundle query adapter and the query permission behavior. |
| `entry/src/main/ets/pages/AppPicker.ets` | New | The Apps VPN mode page. |
| `entry/src/main/ets/pages/ProfileEdit.ets` | Change | The editor row, the draft handoff, and the dirty check. |
| `entry/src/main/ets/vpnability/SsVpnExtensionAbility.ets` | Change | Build and pass the two VPN application lists. |
| `entry/src/main/module.json5` | Change | Declare `ohos.permission.GET_BUNDLE_INFO`. |
| `entry/src/main/resources/base/profile/main_pages.json` | Change | Add `pages/AppPicker`. |
| `entry/src/main/resources/base/element/string.json` | Change | Add 32 English strings. |
| `entry/src/main/resources/zh_CN/element/string.json` | Change | Add the same 32 strings in Chinese. |
| `entry/src/test/ParityU07.test.ets` | New | The U07 host specs. |
| `entry/src/test/List.test.ets` | Change | Register the U07 suite. |
| `AGENTS.md` | Change | Add the new page and model files to the layout. Add the query permission. |

The three new code files carry the GPL-3.0 header block.
The E2E journey spec lives in the shared `entry/src/ohosTest/ets/test/ParityE2e.test.ets` file. The batch owns that file. The Test plan records the anchor.

### Implementation plan

The plan keeps the existing classes and their owners.
It moves every decision that a host spec can check into `model/PerApp.ets`.
The page renders state and collects input.

### 1. `model/Profile.ets`

Add three fields after `ipv6`:

```ts
/** Apps VPN mode: the profile proxies selected bundle names, or all but them. */
proxyAppsEnabled: boolean = false;
/** True means Bypass: the selected apps skip the tunnel. False means On: only they use it. */
proxyAppsBypass: boolean = false;
/** Newline-joined bundle names. shadowsocks-android stores package names here. */
proxyAppsList: string = '';
```

No method reads the fields in this class.
`toTunConfig` does not change.
The core config carries no per-app field. The VPN extension applies the lists.

### 2. `model/ProfileStore.ets`

In `fromJson`, after `profile.route`, copy the three fields:

```ts
profile.proxyAppsEnabled = parsed.proxyAppsEnabled ?? false;
profile.proxyAppsBypass = parsed.proxyAppsBypass ?? false;
profile.proxyAppsList = parsed.proxyAppsList ?? '';
```

Add one private parse helper and one public read method.

```ts
/** The stored list, or null when the file is present and cannot be parsed. */
private static parse(raw: string): Profile[] | null

/**
 * The stored list, or null when the file is present and cannot be read.
 * `getAll` returns [] for an absent file and for a corrupt file alike.
 * A caller that writes back what it read must tell the two apart.
 */
static async getAllOrNull(context: common.Context): Promise<Profile[] | null>
```

Rules:

- `parse('')` returns `[]`.
- `parse` parses the JSON array, maps each record through `fromJson`, and sorts by `userOrder`.
- `parse` returns `null` on a JSON error.
- `getAll` returns `ProfileStore.parse(await JsonStore.read(...)) ?? []`. The behavior does not change.
- `getAllOrNull` reads the file. An empty read with no file returns `[]`. An empty read with a present file returns `null`. Otherwise it returns `parse(raw)`.

`getAllOrNull` is the read path for Apply Settings to All Profiles.
A null result stops the action before any write.

### 3. `model/PerApp.ets` (new)

The file has no kit import. It imports `Profile` from `./Profile` for `applyToAll`.
The host runner can compile and run it.

Constants and types:

```ts
export const APP_MODE_OFF: string = 'off';
export const APP_MODE_ON: string = 'on';
export const APP_MODE_BYPASS: string = 'bypass';

/** The platform accepts at most 64 bundle names per list before API 23. */
export const MAX_APP_LIST: number = 64;

/** One app row. HarmonyOS has no UID, so the label is the bundle name. */
export interface AppEntry {
  bundleName: string;
  label: string;
}

/** The mode and the list, as the draft and the profile hold them. */
export interface PerAppState {
  enabled: boolean;
  bypass: boolean;
  list: string;
}

/** The two application lists a VpnConfig takes. Only one is non-empty. */
export interface VpnAppLists {
  trusted: string[];
  blocked: string[];
}
```

Functions:

```ts
export function appMode(enabled: boolean, bypass: boolean): string
export function namesOf(list: string): string[]
export function joinNames(names: string[]): string
export function toggleName(list: string, bundleName: string): string
export function isValidBundleName(name: string): boolean
export function matchesQuery(entry: AppEntry, query: string): boolean
export function visibleEntries(entries: AppEntry[], query: string): AppEntry[]
export function sortEntries(entries: AppEntry[], selected: string): AppEntry[]
export function exportText(bypass: boolean, list: string): string
export function parseImportText(text: string): PerAppState | null
export function applyToAll(profiles: Profile[], bypass: boolean, list: string): Profile[]
export function selectionCap(bypass: boolean): number
export function vpnApplicationLists(enabled: boolean, bypass: boolean, list: string,
  clientBundle: string, cap: number = MAX_APP_LIST): VpnAppLists
```

Rules:

- `appMode` returns Off for `enabled = false`. It returns Bypass for `enabled = true` and `bypass = true`. It returns On for every other pair.
- `namesOf` splits on `\n`. It trims each line. It drops empty lines. It drops duplicates. It keeps the input order.
- `joinNames` applies the `namesOf` rule and joins with `\n`.
- `toggleName` removes the name when it exists. It appends the name when it does not. It keeps the order of the other names.
- `isValidBundleName` accepts two or more dot-separated segments. Each segment starts with an ASCII letter. The later characters are letters, digits, or `_`. The total length is at most 128. The expression is `/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/`.
- `matchesQuery` trims and lowercases the query. An empty query matches. It matches a case-insensitive substring of `label` or `bundleName`.
- `visibleEntries` filters with `matchesQuery`. It keeps the input order.
- `sortEntries` copies the array. Selected names come first. Within one group the label sorts ascending. The function does not write the stored list.
- `exportText` returns `` `${bypass}\n${joinNames(namesOf(list))}` ``.
- `parseImportText` returns `null` for an empty text.
- `parseImportText` reads the first line as the flag. The value `true` in any letter case sets bypass. Every other first line clears bypass.
- `parseImportText` with no newline returns an empty list.
- `parseImportText` with a newline normalizes the remaining lines with `namesOf`.
- `applyToAll` sets `proxyAppsBypass` and `proxyAppsList` on every profile. It does not change `proxyAppsEnabled`. It returns the same array. The caller saves the array.
- `selectionCap` returns `MAX_APP_LIST - 1` in Bypass mode. It returns `MAX_APP_LIST` in On mode. The client bundle consumes one slot in the blocked list.
- `vpnApplicationLists` returns two empty lists when `enabled` is false.
- `vpnApplicationLists` in On mode returns the selected names without the client bundle as `trusted`. It returns `blocked = []`.
- `vpnApplicationLists` in Bypass mode returns `trusted = []`. It returns `blocked` with the client bundle first, then the selected names without the client bundle.
- `vpnApplicationLists` cuts each list to `cap`.
- `vpnApplicationLists` never returns both lists non-empty.

Draft:

```ts
/**
 * The per-app values of the profile the editor has open.
 * One draft exists per UI process. The VPN extension never reads it.
 */
export class PerAppDraft {
  static profileId: string = '';
  static enabled: boolean = false;
  static bypass: boolean = false;
  static list: string = '';
  static dirty: boolean = false;

  static open(profile: Profile): void
  static ensureEnabled(): void
  static setMode(mode: string): void
  static setList(list: string): void
  static state(): PerAppState
  static snapshot(): string
  static clear(): void
}
```

Rules:

- `open` copies the three profile values. It normalizes the list with `joinNames(namesOf(...))`. It sets `dirty = false`.
- `ensureEnabled` sets `enabled = true` and `dirty = true` when the draft was disabled. It does nothing otherwise.
- `setMode` applies Off, On, or Bypass. It keeps the list. It sets `dirty = true`.
- `setList` normalizes the list. It sets `dirty = true`.
- `state` returns a copy of the three values.
- `snapshot` returns `"<0|1>|<0|1>|<list>"`. The editor compares snapshots.
- `clear` resets every field.

### 4. `model/AppCatalog.ets` (new)

The adapter owns every `bundleManager` call.

```ts
import { bundleManager, common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { AppEntry } from './PerApp';

/** `bundleManager.getBundleInfo` is public since API 14. */
export const QUERY_MIN_API: number = 14;

export const REASON_UNAVAILABLE: string = 'query-unavailable';
export const REASON_PERMISSION: string = 'permission-denied';
export const REASON_NOT_FOUND: string = 'not-found';
export const REASON_FAILED: string = 'query-failed';

export interface ResolvedApp {
  entry: AppEntry;
  found: boolean;
  reason: string;
}

export function queryAvailable(): boolean
export function selfBundleName(context: common.Context): string
export async function resolveName(bundleName: string): Promise<ResolvedApp>
export async function resolveNames(bundleNames: string[]): Promise<ResolvedApp[]>
export async function installedNames(bundleNames: string[]): Promise<InstalledNames>
```

`InstalledNames` is `{ names: string[], reason: string }`.

Rules:

- `queryAvailable` returns `deviceInfo.sdkApiVersion >= QUERY_MIN_API`.
- `selfBundleName` returns `context.applicationInfo.name`.
- On an error, `selfBundleName` returns `bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).name`. This API is public since API 10 and needs no permission.
- On a second error, `selfBundleName` returns `''`.
- `resolveName` returns `REASON_UNAVAILABLE` when the API is absent or the function is absent.
- `resolveName` calls `bundleManager.getBundleInfo(bundleName, bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)`.
- `resolveName` returns `found = true` on success. The row label is the bundle name.
- `resolveName` maps error `17700001` to `REASON_NOT_FOUND`.
- `resolveName` maps error `201` to `REASON_PERMISSION`.
- `resolveName` maps every other error to `REASON_FAILED`.
- `resolveNames` calls `resolveName` for each name in order. It never throws.
- `installedNames` returns `InstalledNames`: the names plus the reason the query could not verify them.
- When the query is unavailable, `installedNames` keeps a copy of the input and returns `REASON_UNAVAILABLE`. An empty list would change which apps use the tunnel, and the names are exact bundle names the user selected.
- `installedNames` drops a name only for `REASON_NOT_FOUND`. It keeps a name for every other reason, because the app cannot tell a transient failure from an absent app. It reports the first reason that is not `REASON_NOT_FOUND`.
- The extension calls `installedNames` and logs its reason. The page calls `resolveNames`.

Permission:

- `module.json5` declares `ohos.permission.GET_BUNDLE_INFO`.
- The permission is normal and system-granted. The app holds it at install. No runtime prompt appears.
- The app does not declare `GET_BUNDLE_INFO_PRIVILEGED`, `GET_INSTALLED_BUNDLE_LIST`, `LISTEN_BUNDLE_CHANGE`, or `ENTERPRISE_GET_INSTALLED_BUNDLE_LIST`. Those are system-basic permissions. A third-party HAP cannot hold them.

### 5. `pages/AppPicker.ets` (new)

Export the route parameters. The profile editor imports them.

```ts
export interface AppPickerParams {
  profileId?: string;
}
```

Component:

```ts
@Entry
@Component
struct AppPicker {
  @State mode: string = APP_MODE_ON;
  @State entries: AppEntry[] = [];
  @State selectedNames: string[] = [];
  @State missing: string[] = [];
  @State query: string = '';
  @State loading: boolean = true;
  @State reason: string = '';
  @State newBundle: string = '';
  private profileId: string = '';
  private clientBundle: string = '';
  private generation: number = 0;
}
```

Methods:

```ts
aboutToAppear(): void
onPageShow(): void
private async load(): Promise<void>
private syncFromDraft(): void
private chooseMode(mode: string): void
private toggle(entry: AppEntry): void
private isSelected(name: string): boolean
private visible(): AppEntry[]
private async addBundle(): Promise<void>
private async applyToAllProfiles(): Promise<void>
private async exportClipboard(): Promise<void>
private async importClipboard(): Promise<void>
private summaryReason(): ResourceStr
@Builder ModeRow(mode: string, label: ResourceStr)
@Builder AppRow(entry: AppEntry)
build()
```

`aboutToAppear` does this:

1. Read `router.getParams()` as `AppPickerParams`.
2. Set `profileId`.
3. Load `clientBundle` with `AppCatalog.selfBundleName(abilityContext())`.
4. When `PerAppDraft.profileId` differs from `profileId`, load the profile with `ProfileStore.getAll`. Open the draft with the profile, or with a new `Profile` when the id is absent or unknown.
5. Call `PerAppDraft.ensureEnabled()`. This forces the mode on when the stored flag was off.
6. Call `syncFromDraft()`.
7. Call `load()`.

`onPageShow` calls `syncFromDraft()`.

`load` does this:

1. Set `loading = true`.
2. Increment `generation`. Keep the value in a local variable.
3. Resolve `namesOf(PerAppDraft.list)` with `AppCatalog.resolveNames`.
4. Return without a state change when `generation` changed. The newer load owns the state.
5. Set `reason` from the resolved results. Use `''` for an empty list. Otherwise use `REASON_UNAVAILABLE`, `REASON_PERMISSION`, or `REASON_FAILED` when every result has that reason. Use `''` otherwise.
6. Set `entries` to `sortEntries(resolved.map((item) => item.entry), PerAppDraft.list)`.
7. Set `missing` to the names with `REASON_NOT_FOUND`.
8. Set `loading = false`.
9. Catch an error and set `reason = REASON_FAILED` and `loading = false`.

`syncFromDraft` copies the draft into the page state:

```ts
this.mode = appMode(PerAppDraft.enabled, PerAppDraft.bypass);
this.selectedNames = namesOf(PerAppDraft.list);
```

`chooseMode` calls `PerAppDraft.setMode(mode)`, calls `syncFromDraft()`, and calls `router.back()` for Off.

`toggle` calls `PerAppDraft.setList(toggleName(PerAppDraft.list, entry.bundleName))` and updates `selectedNames`. It does not call `load()` and does not re-sort.

`visible` returns `visibleEntries(this.entries, this.query)`.

`addBundle` does this:

1. Trim `newBundle`.
2. Reject an invalid name with `app_picker_invalid_name`.
3. Reject the client bundle with `app_picker_client_app`.
4. Return for a selected name.
5. Reject a list at `selectionCap(PerAppDraft.bypass)` with `app_picker_limit`.
6. When the query is available, resolve the name. Reject only `REASON_NOT_FOUND` with `app_picker_not_found`. Add the name for every other reason.
7. Call `PerAppDraft.setList(toggleName(PerAppDraft.list, name))`.
8. Clear `newBundle`.
9. Call `syncFromDraft()` and `load()`.

`applyToAllProfiles` does this:

1. Read `ProfileStore.getAllOrNull(abilityContext())`.
2. Stop with `app_picker_export_fail` when the result is null.
3. Call `applyToAll(profiles, PerAppDraft.bypass, PerAppDraft.list)`.
4. Save with `ProfileStore.saveAll`.
5. Show `app_picker_apply_done`.
6. Show `app_picker_export_fail` on an error.

`exportClipboard` calls `writeClipboard(exportText(PerAppDraft.bypass, PerAppDraft.list))`.
It shows `app_picker_export_ok` or `app_picker_export_fail`.

`importClipboard` does this:

1. Read the clipboard with `readClipboard()`. Treat an error as an empty text.
2. Call `parseImportText`.
3. Show `app_picker_import_fail` and stop when the result is null.
4. Call `PerAppDraft.setMode(parsed.bypass ? APP_MODE_BYPASS : APP_MODE_ON)`.
5. Call `PerAppDraft.setList(parsed.list)`.
6. Call `syncFromDraft()` and `load()`.
7. Show `app_picker_import_ok`.

`summaryReason` maps `REASON_UNAVAILABLE`, `REASON_PERMISSION`, and `REASON_FAILED` to the three string resources. It returns an empty string for `''`.

The `build()` layout keeps the editor page style:

1. A header row with Back, the title `app_picker_title`, and the overflow button.
2. A search row with a `TextInput` and a Clear button. The Clear button shows only when the query is not empty.
3. The Mode label and three `ModeRow` rows.
4. The reason text when `reason` is not empty.
5. A `LoadingProgress` while `loading` is true. The list stays hidden.
6. A `List` with one `ListItem` per visible entry. The list fills the remaining height and uses the system scroll bar.
7. An add row with a `TextInput` and an Add button.

The overflow button uses `bindMenu` with three entries in this order:

```ts
{ value: $r('app.string.app_picker_apply_all'), action: () => { this.applyToAllProfiles(); } }
{ value: $r('app.string.app_picker_export'), action: () => { this.exportClipboard(); } }
{ value: $r('app.string.app_picker_import'), action: () => { this.importClipboard(); } }
```

`ModeRow` uses `Radio({ value: mode, group: 'appMode' })` with `.checked(this.mode === mode)` and `.onChange`. The change handler calls `chooseMode` only for a checked value.

`AppRow` uses this shape:

```ts
Row() {
  Text(entry.label).layoutWeight(1)
  if (this.missing.indexOf(entry.bundleName) >= 0) {
    Text($r('app.string.app_picker_not_installed'))
  }
  Toggle({ type: ToggleType.Switch, isOn: this.isSelected(entry.bundleName) })
    .hitTestBehavior(HitTestMode.None)
}
.onClick(() => this.toggle(entry))
```

The `Toggle` rejects taps. The row owns the tap, as the Android row does.

The `ForEach` key must include the selected state:

```ts
(entry: AppEntry) => `${entry.bundleName}#${this.isSelected(entry.bundleName) ? 1 : 0}`
```

Without the selected state in the key, ArkUI reuses the cached row and the switch stays at its first value.
This is the same trap as the profile rows in `Index.ets`.

Every `Button` sets `backgroundColor` and `fontColor`.
The page uses these tokens: `accent_container`, `on_container`, `button_neutral`, `on_neutral`, `text_body`, `text_secondary`, `accent`, and `surface`.
The page calls `abilityContext()`. It does not declare a `context` property.

### 6. `pages/ProfileEdit.ets`

Add these imports:

```ts
import { MODE_VPN } from '../model/Diagnostics';
import { SettingsStore } from '../model/Settings';
import { PerAppDraft, namesOf } from '../model/PerApp';
import { AppPickerParams } from './AppPicker';
```

Add these page state properties:

| Property | Type | Initial | Purpose |
| --- | --- | --- | --- |
| `serviceMode` | `string` | `MODE_VPN` | The stored service mode |
| `proxyAppsEnabled` | `boolean` | `false` | The draft mode flag |
| `proxyAppsBypass` | `boolean` | `false` | The draft bypass flag |
| `proxyAppsList` | `string` | `''` | The draft list |

Change the lifecycle methods:

- `aboutToAppear` calls `PerAppDraft.clear()` first.
- `aboutToAppear` loads the settings with `SettingsStore.load(abilityContext())` and copies `serviceMode`.
- The new-profile branch calls `PerAppDraft.open(new Profile())`, `syncPerApp()`, and then `formSnapshot()`.
- The existing-profile branch calls `PerAppDraft.open(profile)` and `syncPerApp()` before `initialForm = formSnapshot()`.
- Add `onPageShow(): void { this.syncPerApp(); }`.
- Add `aboutToDisappear(): void { PerAppDraft.clear(); }`.

Change `formSnapshot` to append `PerAppDraft.snapshot()` to the joined values.
The unsaved-changes dialog then covers a per-app edit.

Change `buildProfile` to copy the draft:

```ts
profile.proxyAppsEnabled = PerAppDraft.enabled;
profile.proxyAppsBypass = PerAppDraft.bypass;
profile.proxyAppsList = PerAppDraft.list;
```

Change `save` to call `PerAppDraft.clear()` after `ProfileStore.upsert` and `ProfileStore.setCurrentId`.
Change `confirmLeave` to call `PerAppDraft.clear()` on the no-change path and on the discard path.
The Save path clears the draft inside `save`.

Add these methods:

```ts
private syncPerApp(): void
private openAppPicker(): void
private proxyAppsSummary(): ResourceStr
```

`syncPerApp` copies the draft into the three state properties.

`openAppPicker` runs only in `MODE_VPN`. It calls `PerAppDraft.ensureEnabled()`, calls `syncPerApp()`, and pushes the page:

```ts
const params: AppPickerParams = { profileId: this.profileId };
router.pushUrl({ url: 'pages/AppPicker', params: params });
```

`proxyAppsSummary` returns `profile_edit_proxy_apps_vpn_only` outside VPN mode.
It returns `profile_edit_proxy_apps_off` when the draft is disabled.
It returns `profile_edit_proxy_apps_on` or `profile_edit_proxy_apps_bypass` with the count `namesOf(this.proxyAppsList).length`.

Add the row after the route selector and before the plugin selector:

```ts
Row() {
  Column({ space: 2 }) {
    Text($r('app.string.profile_edit_proxy_apps'))
    Text(this.proxyAppsSummary())
  }.layoutWeight(1)
  Toggle({ type: ToggleType.Switch, isOn: this.proxyAppsEnabled })
    .selectedColor($r('app.color.accent_container'))
    .hitTestBehavior(HitTestMode.None)
}
.enabled(this.serviceMode === MODE_VPN)
.onClick(() => this.openAppPicker())
```

The row stays enabled for an active subscription profile.
The per-app fields are local. `mergeSubscription` copies only the transport fields, so a subscription refresh keeps them.

### 7. `vpnability/SsVpnExtensionAbility.ets`

Add these imports:

```ts
import { appMode, joinNames, namesOf, vpnApplicationLists, MAX_APP_LIST } from '../model/PerApp';
import { installedNames, selfBundleName } from '../model/AppCatalog';
```

In `onCreate`, after the profile check and before `this.connection = vpnExtension.createVpnConnection(...)`, add:

```ts
const clientBundle = selfBundleName(this.context);
const wanted = namesOf(profile.proxyAppsList);
const installed = profile.proxyAppsEnabled ? await installedNames(wanted) : [];
if (profile.proxyAppsEnabled) {
  for (const name of wanted) {
    if (installed.indexOf(name) < 0) {
      hilog.warn(0x0000, TAG, 'skipped bundle %{public}s', name);
    }
  }
}
const appLists = vpnApplicationLists(profile.proxyAppsEnabled, profile.proxyAppsBypass,
  joinNames(installed), clientBundle, MAX_APP_LIST);
hilog.info(0x0000, TAG, 'per-app mode %{public}s: trusted %{public}d, blocked %{public}d',
  appMode(profile.proxyAppsEnabled, profile.proxyAppsBypass),
  appLists.trusted.length, appLists.blocked.length);
```

Remove `trustedApplications: []` and `blockedApplications: []` from the `VpnConfig` literal.
After the literal, add the one list that is not empty:

```ts
if (appLists.trusted.length > 0) {
  config.trustedApplications = appLists.trusted;
}
if (appLists.blocked.length > 0) {
  config.blockedApplications = appLists.blocked;
}
```

Rules:

- The two fields are mutually exclusive. The code sets at most one.
- An empty list means no application list. The platform then applies the VPN to every app.
- The client bundle is never in the trusted list. The helper removes it.
- The client bundle is always in the blocked list in Bypass mode. The helper adds it first.
- A list over 64 names is cut. The page also prevents the overrun.
- The query runs before the VPN interface is created. It adds no permission prompt.
- The query failure does not fail the start. The names pass through on an unavailable or denied query.
- The core config does not change. The per-app lists are platform VPN fields only.

### 8. `model/ProfilesFile.ets`

Change `ProxyAppsJson`:

```ts
export interface ProxyAppsJson {
  enabled: boolean;
  bypass?: boolean;
  /** Newline-joined bundle names. The name is Android's for export parity. */
  android_list?: string;
}
```

In `profileFromJson`, after the `udpdns` line, read the block:

```ts
const proxyApps = record['proxy_apps'];
if (proxyApps !== null && typeof proxyApps === 'object') {
  const block = proxyApps as Record<string, Object>;
  profile.proxyAppsEnabled = block['enabled'] === true;
  if (profile.proxyAppsEnabled) {
    profile.proxyAppsBypass = block['bypass'] === true;
    const list = block['android_list'];
    profile.proxyAppsList = typeof list === 'string' ? joinNames(namesOf(list)) : '';
  }
}
```

Rules:

- An absent `proxy_apps` block leaves the default values.
- `enabled: false` ignores `bypass` and `android_list`.
- An unknown name stays in the list. It may refer to an app that is not installed.
- Blank lines and duplicates are removed.

In `exportProfiles`, replace the fixed block with:

```ts
const proxyApps: ProxyAppsJson = { enabled: profile.proxyAppsEnabled };
if (profile.proxyAppsEnabled) {
  proxyApps.bypass = profile.proxyAppsBypass;
  proxyApps.android_list = joinNames(namesOf(profile.proxyAppsList));
}
entry.proxy_apps = proxyApps;
```

Rules:

- Every non-SIP008 entry carries `proxy_apps`.
- The SIP008 branch returns before this code. It carries no `proxy_apps`.
- `bypass` and `android_list` appear only when enabled is true.
- Remove the comment that says the settings are dropped.

Add this import:

```ts
import { joinNames, namesOf } from './PerApp';
```

### 9. `module.json5`

Add this entry to `requestPermissions`:

```json5
{
  // resolves a bundle name the app picker stores into a bundle record;
  // normal grant, no runtime prompt
  "name": "ohos.permission.GET_BUNDLE_INFO"
}
```

Do not add a system-basic permission.

### 10. `resources/base/profile/main_pages.json`

Add the page:

```json
"pages/AppPicker"
```

### 11. Strings

Add these keys to `resources/base/element/string.json` and the same keys to `resources/zh_CN/element/string.json`:

| Name | English | Chinese |
| --- | --- | --- |
| `app_picker_title` | `Apps VPN mode` | `应用 VPN 模式` |
| `app_picker_mode` | `Mode` | `模式` |
| `app_picker_mode_off` | `Off` | `关闭` |
| `app_picker_mode_on` | `On` | `开启` |
| `app_picker_mode_bypass` | `Bypass` | `绕过` |
| `app_picker_search` | `Search apps` | `搜索应用` |
| `app_picker_clear` | `Clear` | `清除` |
| `app_picker_add_hint` | `Bundle name, for example com.example.app` | `包名，例如 com.example.app` |
| `app_picker_add` | `Add` | `添加` |
| `app_picker_menu` | `More options` | `更多选项` |
| `app_picker_apply_all` | `Apply Settings to All Profiles` | `应用到所有配置` |
| `app_picker_export` | `Export to Clipboard` | `导出到剪贴板` |
| `app_picker_import` | `Import from Clipboard` | `从剪贴板导入` |
| `app_picker_apply_done` | `Applied to all profiles` | `已应用到所有配置` |
| `app_picker_export_ok` | `Successfully export!` | `导出成功！` |
| `app_picker_export_fail` | `Failed to export.` | `导出失败。` |
| `app_picker_import_ok` | `Successfully import!` | `导入成功！` |
| `app_picker_import_fail` | `Failed to import.` | `导入失败。` |
| `app_picker_empty` | `No apps selected` | `未选择应用` |
| `app_picker_query_unavailable` | `The app list is unavailable on this device. Add bundle names manually.` | `此设备无法列出应用。请手动添加包名。` |
| `app_picker_query_denied` | `The app query permission is missing. Add bundle names manually.` | `缺少应用查询权限。请手动添加包名。` |
| `app_picker_query_failed` | `The app query failed. Add bundle names manually.` | `应用查询失败。请手动添加包名。` |
| `app_picker_not_installed` | `Not installed` | `未安装` |
| `app_picker_client_app` | `The Shadowsocks app always stays outside the tunnel.` | `Shadowsocks 应用始终不经过隧道。` |
| `app_picker_invalid_name` | `Enter a valid bundle name.` | `请输入有效的包名。` |
| `app_picker_not_found` | `No installed app has this bundle name.` | `没有已安装的应用使用此包名。` |
| `app_picker_limit` | `Up to %d apps can be selected.` | `最多可选择 %d 个应用。` |
| `profile_edit_proxy_apps` | `Apps VPN mode` | `应用 VPN 模式` |
| `profile_edit_proxy_apps_off` | `Off` | `关闭` |
| `profile_edit_proxy_apps_on` | `On, %d apps` | `开启，%d 个应用` |
| `profile_edit_proxy_apps_bypass` | `Bypass, %d apps` | `绕过，%d 个应用` |
| `profile_edit_proxy_apps_vpn_only` | `VPN service mode only` | `仅限 VPN 服务模式` |

Count the `%d` arguments by hand. `app_picker_limit` takes one. Each `profile_edit_proxy_apps_on` and `profile_edit_proxy_apps_bypass` takes one.

### 12. `AGENTS.md`

Add these files to the repository layout:

- `entry/src/main/ets/model/PerApp.ets`
- `entry/src/main/ets/model/AppCatalog.ets`
- `entry/src/main/ets/pages/AppPicker.ets`

Add `ohos.permission.GET_BUNDLE_INFO` to the permission note.
Add one line to the runtime flow: the VPN extension passes the per-app lists to `VpnConfig`.

### State and data

### Stored profile shape

`store/profiles.json` gains three keys on each profile:

```json
{
  "proxyAppsEnabled": true,
  "proxyAppsBypass": false,
  "proxyAppsList": "com.example.a\ncom.example.b"
}
```

| Key | Type | Default | Writer | Reader |
| --- | --- | --- | --- | --- |
| `proxyAppsEnabled` | boolean | `false` | Profile editor save, app picker Off | VPN extension, app picker, export |
| `proxyAppsBypass` | boolean | `false` | Profile editor save, Apply Settings | VPN extension, app picker, export |
| `proxyAppsList` | string | `''` | Profile editor save, Apply Settings | VPN extension, app picker, export |

The mode derives from the two flags:

| `proxyAppsEnabled` | `proxyAppsBypass` | Mode |
| --- | --- | --- |
| `false` | any | Off |
| `true` | `false` | On |
| `true` | `true` | Bypass |

### Export shape

Every non-SIP008 export entry carries `proxy_apps`:

```json
{
  "proxy_apps": {
    "enabled": true,
    "bypass": false,
    "android_list": "com.example.a\ncom.example.b"
  }
}
```

A disabled profile writes `{ "enabled": false }` only.

### Draft

| State | Type | Source | Lifetime |
| --- | --- | --- | --- |
| `profileId` | string | Editor open | Until save, discard, or process death |
| `enabled` | boolean | Stored profile, Mode group | Until save, discard, or process death |
| `bypass` | boolean | Stored profile, Mode group, import | Until save, discard, or process death |
| `list` | string | Stored profile, row taps, import | Until save, discard, or process death |
| `dirty` | boolean | Every draft change | Until save, discard, or process death |

The draft is in the UI process memory. It has no file. A process death discards unsaved edits.

### VPN config

| Field | Type | Mode | Cap | Client bundle |
| --- | --- | --- | --- | --- |
| `trustedApplications` | `string[]` | On | 64 | Absent |
| `blockedApplications` | `string[]` | Bypass | 64 | First |

The extension sets one field. It sets neither when the list is empty.
The platform reads the field at `create()`. A per-app edit applies on the next connect.

### Consistency

- The UI process is the only writer of `store/profiles.json`.
- The VPN extension reads the profile at start. It never writes the profile.
- Apply Settings reads, changes, and writes the whole list in one `saveAll`.
- `saveAll` writes a temporary file and renames it. A failure leaves the old file.
- The per-app list keeps names of uninstalled apps. The extension skips them when the query works.
- A subscription refresh keeps the per-app fields. `mergeSubscription` copies only the transport fields.

### Validation and errors

| Condition | Behavior | Message | Owner |
| --- | --- | --- | --- |
| The bundle name is empty or malformed | The page adds no name | `app_picker_invalid_name` | `isValidBundleName` |
| The bundle name is the client bundle | The page adds no name | `app_picker_client_app` | `addBundle` |
| The bundle name is already selected | The page adds no name | None | `addBundle` |
| The list is at the cap | The page adds no name | `app_picker_limit` | `selectionCap` |
| The query is unavailable | The page shows the reason and still accepts a manual name | `app_picker_query_unavailable` | `AppCatalog` |
| The query permission is denied | The page shows the reason and keeps the stored names | `app_picker_query_denied` | `AppCatalog` |
| The query works and the name is absent | The page adds no name | `app_picker_not_found` | `AppCatalog` |
| The query fails for another reason | The page accepts the name | None | `AppCatalog` |
| The clipboard is empty | The mode and the list do not change | `app_picker_import_fail` | `parseImportText`, page |
| The clipboard read throws | The mode and the list do not change | `app_picker_import_fail` | page |
| The first import line is not `true` | The mode becomes On | `app_picker_import_ok` | `parseImportText` |
| The import has no newline | The list becomes empty | `app_picker_import_ok` | `parseImportText` |
| The clipboard write fails | No text is written | `app_picker_export_fail` | page |
| Apply Settings cannot read the profile list | No profile is written | `app_picker_export_fail` | `getAllOrNull` |
| Apply Settings cannot write the profile list | The old file stays | `app_picker_export_fail` | `saveAll` |
| The VPN list is over the cap | The list is cut to 64 | None | `vpnApplicationLists` |
| The VPN config creation fails | The status becomes failed | The platform message | VPN extension |
| A stored name is not installed | The extension skips it and logs its name | A warning in hilog | `installedNames` |
| Both VPN lists would be non-empty | The helper returns one list | None | `vpnApplicationLists` |
| The service mode is Proxy | The editor row is disabled | `profile_edit_proxy_apps_vpn_only` | `ProfileEdit` |
| The profile is an active subscription | The editor row stays enabled | None | `ProfileEdit` |
| The profile is new and has no id | The draft holds the values until Save | None | `PerAppDraft` |

The extension logs the count of skipped names and each skipped name.
The log never includes a password or a profile secret.

### Test plan

All host tests run with `./test-arkts-host.sh`.
The suite name is `U07`. Each test name is `<slug>`, so the anchor is `entry/src/test/ParityU07.test.ets::U07#<slug>`.
Register the suite in `entry/src/test/List.test.ets`:

```ts
import parityU07Test from './ParityU07.test';
// inside testsuite()
parityU07Test();
```

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| TC-U07-01 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#opening-forces-mode-on` | unit (host) |
| TC-U07-02 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#mode-group-exclusive` | unit (host) |
| TC-U07-03, TC-U07-21 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#mode-off-keeps-bypass-and-list` | unit (host) |
| R-UG-09 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#mode-start-from-stored-flags` | unit (host) |
| TC-U07-05, TC-U07-06 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#toggle-adds-and-removes-name` | unit (host) |
| R-UG-02 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#list-round-trips-newline-joined` | unit (host) |
| TC-U07-07 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#search-matches-label-and-bundle` | unit (host) |
| TC-U07-07 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#search-empty-lists-every-entry` | unit (host) |
| R-UG-13 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#sort-selected-first-then-label` | unit (host) |
| R-UG-14 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#toggle-keeps-visible-order` | unit (host) |
| TC-U07-11 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#export-flag-and-list` | unit (host) |
| TC-U07-13, TC-U07-22 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#import-splits-flag-and-names` | unit (host) |
| TC-U07-15 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#import-without-newline-clears-list` | unit (host) |
| TC-U07-14 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#import-empty-changes-nothing` | unit (host) |
| R-UG-23 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#import-dedupes-and-trims` | unit (host) |
| TC-U07-19 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#draft-survives-until-save` | unit (host) |
| TC-U07-10, TC-U07-23 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#apply-to-all-copies-and-keeps-enabled` | integration (host) |
| F-U07-07 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#vpn-lists-mode-off-empty` | unit (host) |
| TC-U07-16 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#vpn-lists-on-trusted` | unit (host) |
| TC-U07-17 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#vpn-lists-on-empty-adds-none` | unit (host) |
| TC-U07-18 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#vpn-lists-bypass-blocks-list-and-client` | unit (host) |
| R-UG-29 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#vpn-lists-bypass-empty-blocks-client` | unit (host) |
| platform cap | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#vpn-lists-cap-at-64` | unit (host) |
| TC-U07-20 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#proxy-apps-json-on-export` | integration (host) |
| TC-U07-20 | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#proxy-apps-json-on-import` | integration (host) |
| validation | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#bundle-name-validation` | unit (host) |
| persistence | `entry/src/test/ParityU07.test.ets` | `entry/src/test/ParityU07.test.ets::U07#profile-store-round-trips-per-app-fields` | integration (host) |
| O-JOURNEY-07 | `entry/src/ohosTest/ets/test/ParityE2e.test.ets` | `entry/src/ohosTest/ets/test/ParityE2e.test.ets::U07Journey#flow` | e2e (device) |

The device cases TC-U07-16 and TC-U07-18 need two apps, a real device, and the VPN consent row.
The host specs cover the computed lists. The platform enforces them.
The E2E journey covers the screen flow in TC-U07-01, TC-U07-02, TC-U07-03, TC-U07-19, and TC-U07-21.

Test detail:

| Test name | Input | Expected |
| --- | --- | --- |
| `U07#opening-forces-mode-on` | A profile with enabled false, then one with enabled true | The first draft is enabled and dirty. The second stays clean. |
| `U07#mode-group-exclusive` | On, then Bypass, then On | Each mode leaves one flag pair. The list stays unchanged. |
| `U07#mode-off-keeps-bypass-and-list` | Bypass with `a\nb`, then Off | Enabled false, bypass true, list `a\nb`. |
| `U07#mode-start-from-stored-flags` | The four flag pairs | Off, Off, On, Bypass. |
| `U07#toggle-adds-and-removes-name` | An empty list, then `a`, then `b`, then `a` again | `a`, then `a\nb`, then `b`. |
| `U07#list-round-trips-newline-joined` | `a\n\n b \na` | `a\nb`. An empty list gives `''`. |
| `U07#search-matches-label-and-bundle` | `Cam`, `cam`, `com.example.camera` | The Camera entry stays for each. `mail` hides it. |
| `U07#search-empty-lists-every-entry` | `''` with three entries | All three stay. |
| `U07#sort-selected-first-then-label` | `Zebra` selected, `Alpha` not | `Zebra`, then `Alpha`. |
| `U07#toggle-keeps-visible-order` | A sorted list and a row tap | The array order stays. Only the selected set changes. |
| `U07#export-flag-and-list` | `true` with `a\nb`, then `false` with `''` | `true\na\nb`, then `false\n`. |
| `U07#import-splits-flag-and-names` | `true\na\nb`, then `false\na` | Bypass with `a\nb`, then On with `a`. |
| `U07#import-without-newline-clears-list` | `true`, then `false` | Bypass with `''`, then On with `''`. |
| `U07#import-empty-changes-nothing` | `''` | `null`. |
| `U07#import-dedupes-and-trims` | `true\n a \n\n a \nb` | Bypass with `a\nb`. |
| `U07#draft-survives-until-save` | Open an off profile, enable it, add `a`, discard | The reopened draft is off and empty. After a save the profile holds on and `a`. |
| `U07#apply-to-all-copies-and-keeps-enabled` | Two profiles, one enabled, one off | Both hold the bypass and the list. The enabled flags do not change. |
| `U07#vpn-lists-mode-off-empty` | Enabled false with `a` | Both lists are empty. |
| `U07#vpn-lists-on-trusted` | On with `a\nb` | `trusted = [a, b]`, `blocked = []`. |
| `U07#vpn-lists-on-empty-adds-none` | On with `''` | Both lists are empty. Every app uses the VPN. |
| `U07#vpn-lists-bypass-blocks-list-and-client` | Bypass with `a` and client `com.xbt.project` | `blocked = [com.xbt.project, a]`, `trusted = []`. |
| `U07#vpn-lists-bypass-empty-blocks-client` | Bypass with `''` | `blocked = [com.xbt.project]`. |
| `U07#vpn-lists-cap-at-64` | 70 names in On, then Bypass | 64 trusted names, then 64 blocked names with the client first. `selectionCap` is 64 and 63. |
| `U07#proxy-apps-json-on-export` | One enabled profile with `a`, one disabled | The first has `enabled`, `bypass`, and `android_list`. The second has `enabled: false` only. |
| `U07#proxy-apps-json-on-import` | A record with the three keys, then one with `enabled: false` plus names | The first reads all three. The second reads no list. |
| `U07#bundle-name-validation` | `com.example.a`, `''`, `com example`, `com`, `.a`, `a..b` | True, then five false values. |
| `U07#profile-store-round-trips-per-app-fields` | A stored record with the three fields, then a legacy record | The values survive. The legacy record gets false, false, `''`. |

Case disposition after this unit:

| Cases | Result |
| --- | --- |
| TC-U07-01, 02, 03, 05, 06, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 25, 28 | implemented |
| TC-U07-04, 07 | partial |
| TC-U07-08, 09, 24, 26, 27 | android-only or not portable |

The parity tags change in `docs/versions/5.4.0/machine/U07.json` and `docs/versions/5.4.0/e2e/U07.md`.

### Platform notes

- `ohos.permission.GET_BUNDLE_INFO` is normal and system-granted. The app holds it at install. No runtime prompt appears.
- `GET_BUNDLE_INFO_PRIVILEGED`, `GET_INSTALLED_BUNDLE_LIST`, `LISTEN_BUNDLE_CHANGE`, and `GET_RUNNING_INFO` are system-basic. A third-party HAP cannot hold them. The app does not declare them.
- `bundleManager.getBundleInfo(bundleName, flags)` is public since API 14. `getBundleInfoForSelf` is public since API 9. The deprecated `@ohos.bundle.getAllBundleInfo` needs `GET_BUNDLE_INFO_PRIVILEGED`.
- The query resolves a bundle name the app already knows. It does not list bundles. HQ-1 and AQ-1 stay partly open for a future public list API.
- A bundle name replaces an Android UID. Two packages that share a UID have no shared identity. An app clone has a different identity.
- The row label is the bundle name. `ApplicationInfo.label` is a resource descriptor, not a resolved label. Resolving another app's label needs a privileged API.
- The page shows no app icon. The public API returns no cross-bundle drawable.
- The platform grants INTERNET to every app. The Android INTERNET filter has no counterpart.
- The platform has no retained-package view and no `android` system package for this query.
- `trustedApplications` and `blockedApplications` are mutually exclusive. The code sets at most one.
- The list cap is 64 before API 23 and 256 since. The code uses 64 on every API. The page prevents an overrun.
- The platform excludes the VPN extension's own bundle from the tunnel. The code also removes the client from the trusted list and adds it to the blocked list.
- `protectProcessNet` (API 22+) keeps the extension's server sockets outside the tunnel. The per-app lists do not change it.
- The platform reads the lists at `create()`. An edit applies on the next connect.
- The extension queries up to 64 stored names before `create()`. The calls are local inter-process calls and return fast. No timeout is set. A slow query delays the start, and the UI connect timeout applies.
- The draft lives in the UI process memory. A process death discards unsaved edits.
- One draft exists per UI process. The app opens one profile editor at a time. A second editor would replace the first draft.
- The page reloads the bundle records on show and after an edit. No public package-change listener exists with a normal permission.
- ArkUI `List` has no fast-scroll popup. The page uses the system scroll bar.
- `TextInput` has no search-submit action in this page. The filter runs on each change. The keyboard action does nothing.
- HarmonyOS phones have no menu key. The overflow button is the only menu entry point. Hardware keyboard shortcuts are not planned.
- A `Toggle` with `hitTestBehavior(HitTestMode.None)` renders normally and ignores taps. The parent row handles the tap. This keeps the switch state read-only, as the Android row does.
- The `ForEach` key includes the selected state. Without it, a toggle leaves a stale switch.
- The page uses the theme tokens for every color. It does not use a literal color.
- API 12 lacks `bundleManager.getBundleInfo`. The page and the extension fall back to name-only behavior. The platform may reject an unknown name in the VPN config. See OQ-U07-1.
- The E2E journey needs a real device with the VPN consent row. The per-app enforcement cases need two apps.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| OQ-U07-1 | Does `VpnConfig.create()` reject a bundle name that is not installed, or does it ignore the name? The API 12 path cannot filter names. | VPN extension owner |
| OQ-U07-2 | Does the platform exclude the VPN extension's own bundle when no application list is set? If not, On mode with an empty list routes the client UI through the tunnel. | HarmonyOS platform owner |
| OQ-U07-3 | Does the OpenHarmony sample signing profile include `ohos.permission.GET_BUNDLE_INFO`? Verify with the debug HAP. | Release owner |
| OQ-U07-4 | Should the cap follow the platform (64 before API 23, 256 since) or stay at 64 on every API? The plan uses 64. | Product owner |
| OQ-U07-5 | Should a replace file import honor `proxy_apps` from the file, or keep the local values? The plan honors the file when it carries per-app settings. | Product owner |
| OQ-U07-6 | Is the manual add field acceptable for the app picker while the platform cannot list apps? HQ-1 and AQ-1 stay open for a future API. | Product owner |
| OQ-U07-7 | Should the picker show apps that do not request INTERNET? HarmonyOS grants INTERNET by default, so the Android filter has no counterpart. | Product owner |
| OQ-U07-8 | Does `bundleManager.getBundleInfo` return a permission error on API 14 with a normal-grant permission and the sample profile? A device check decides the fallback text. | HarmonyOS platform owner |

<a id="u08"></a>
## U08 Plugins

### Scope

This unit ports the Android plugin picker and the plugin options editor.

In scope:

- The built-in plugin catalogue: Disabled, `obfs-local` (aliases `simple-obfs` and `obfs`), and `v2ray-plugin`.
- The Plugin row, the Configure… row, and the plugin picker sheet in the profile editor.
- The options editor and its validation.
- Per-plugin options storage.
- The unknown-plugin start error.
- The Plugin line in the profile list row.

Out of scope:

- Plugin APK discovery, plugin app icons, and plugin signatures. HarmonyOS has no plugin APK mechanism.
- External `ACTION_CONFIGURE` and `ACTION_HELP` activities.
- The UDP fallback start path. `Profile.udpFallbackId` exists and nothing reads it.
- The rest of the profile form. U03 owns the name, host, port, password, method, and route fields.

The unit covers 16 of the 30 E2E cases. The other 14 cases are android-only. The section "Test plan" maps every case.

The Rust files `native/sslocal-ffi/src/plugin.rs`, `native/sslocal-ffi/src/obfs.rs`, and `native/sslocal-ffi/src/v2ray_plugin.rs` stay unchanged. They already parse the options and reject an unknown name with `SSLOCAL_ERR_BAD_CONFIG`. The catalogue in this unit must match their name list.

### Files to change

| File | Change |
| --- | --- |
| `entry/src/main/ets/model/PluginOptions.ets` | New. Plugin catalogue, structured options, validation, picker order. |
| `entry/src/main/ets/model/Profile.ets` | Add `pluginConfigs` and the plugin methods. Set `mode` to `tcp_only` for a plugin profile. Seed the map on URL import. |
| `entry/src/main/ets/model/ProfileStore.ets` | Copy `pluginConfigs` on load. Normalize the plugin fields. |
| `entry/src/main/ets/model/ProfilesFile.ets` | Normalize an imported profile. |
| `entry/src/main/ets/model/Subscription.ets` | Keep the local plugin entries and take the incoming entry for the selected plugin. |
| `entry/src/main/ets/model/ProxyService.ets` | Refuse an unknown plugin before the native start. |
| `entry/src/main/ets/vpnability/SsVpnExtensionAbility.ets` | Refuse an unknown plugin before the VPN start. |
| `entry/src/main/ets/pages/ProfileEdit.ets` | Replace the inline plugin select and options field with the Plugin row, the Configure… row, the picker sheet, and the options editor. |
| `entry/src/main/ets/pages/Index.ets` | Add the Plugin line to the profile row. |
| `entry/src/main/resources/base/element/string.json` | Add 10 English strings. |
| `entry/src/main/resources/zh_CN/element/string.json` | Add the 10 Chinese strings. |
| `entry/src/test/ParityU08.test.ets` | New. 16 host tests. |
| `entry/src/test/List.test.ets` | Register the U08 suite. |

### Implementation plan

### 1. `model/PluginOptions.ets` (new)

This file holds no reference to `Profile`. `Profile.ets` imports this file, so the dependency runs one way.

Constants:

```ts
export const PLUGIN_OBFS_LOCAL: string = 'obfs-local';
export const PLUGIN_V2RAY: string = 'v2ray-plugin';
export const PLUGIN_STATE_DISABLED: string = 'disabled';
export const PLUGIN_STATE_KNOWN: string = 'known';
export const PLUGIN_STATE_UNKNOWN: string = 'unknown';
export const PLUGIN_OPTIONS_OK: string = '';
export const PLUGIN_OPTIONS_CONTROL: string = 'control';
export const PLUGIN_OPTIONS_OBFS_MODE: string = 'obfs-mode';
export const PLUGIN_OPTIONS_V2RAY_MODE: string = 'v2ray-mode';
```

Interfaces:

```ts
export interface PluginDefinition {
  id: string;
  aliases: string[];
  label: string;
  defaultOptions: string;
}

export interface PluginOptionEntry {
  key: string;
  value: string | null;
}

export interface PluginChoice {
  id: string;
  current: boolean;
}
```

`BUILTIN_PLUGINS: PluginDefinition[]` holds two entries. The order is the Android discovery order after Disabled. The `label` field is plugin data for tests. The page does not render it. The page chooses a string resource by id, so the Chinese UI keeps its own text.

| id | aliases | label | defaultOptions |
| --- | --- | --- | --- |
| `obfs-local` | `simple-obfs`, `obfs` | `simple-obfs` | `obfs=tls` |
| `v2ray-plugin` | none | `v2ray-plugin` | `mode=websocket` |

Functions:

```ts
export function findPlugin(id: string): PluginDefinition | null
export function isKnownPlugin(id: string): boolean
export function samePlugin(first: string, second: string): boolean
export function pluginDefaultOptions(id: string): string
export function pluginStateOf(id: string): string
export function pluginChoices(currentId: string): PluginChoice[]
```

Rules for these functions:

- `findPlugin` matches the id and every alias. It returns `null` for an empty id and for an unknown id.
- `isKnownPlugin` returns `findPlugin(id) !== null`.
- `samePlugin` returns true when the two ids are equal. It also returns true when both ids resolve to the same definition. A known id and an unknown id never match.
- `pluginDefaultOptions` resolves an alias to its definition and returns `defaultOptions`. It returns `''` for an unknown id.
- `pluginStateOf` returns `PLUGIN_STATE_DISABLED` for `''`. It returns `PLUGIN_STATE_KNOWN` for a known id. It returns `PLUGIN_STATE_UNKNOWN` for any other id.
- `pluginChoices` returns Disabled first, then the two built-in definitions. It marks the row whose id resolves to the current value. It moves a marked row to position 0 and keeps the order of the other rows. An unknown current id marks no row and moves no row. An alias current id marks the canonical row.

Class `PluginOptions`:

```ts
export class PluginOptions {
  static readonly CONTROL_MESSAGE: string = 'No control characters allowed.';
  static check(text: string): string
  static parse(text: string): PluginOptionEntry[]
  static serialize(entries: PluginOptionEntry[]): string
  static canonical(text: string): string
  static validate(pluginId: string, text: string): string
}
```

`check` returns `CONTROL_MESSAGE` when the text holds an ISO control character. The test covers the ranges U+0000 to U+001F and U+007F to U+009F. `check` returns `''` otherwise.

`parse` first calls `check` and throws `Error(CONTROL_MESSAGE)` on a control character. It then copies the Android tokenizer in `PluginOptions.kt`:

- A backslash escapes the next character.
- The first unescaped `=` splits a token into key and value. A later `=` stays in the value.
- `;` ends a token.
- A token with a key stores `key=value`.
- A token without `=` stores a bare key with a `null` value.
- An empty token is skipped.
- A trailing backslash consumes the appended terminator. The last pair drops. The change is accepted with that pair missing, as on Android.
- Keys and values keep their spaces. Android does not trim them.

`serialize` joins the entries with `;`. It writes `key` for a `null` value and `key=value` otherwise. It escapes `\`, `=`, and `;` in keys and values, as Android does. The entry order is kept.

`canonical` returns `serialize(parse(text))`. `canonical('')` returns `''`.

`validate` returns one code:

1. A control character returns `PLUGIN_OPTIONS_CONTROL`.
2. The parse cannot fail in another way. A text that is not well formed still parses into entries, as on Android.
3. An `obfs-local` entry needs an `obfs` key. The key and value are trimmed for this check only. A missing key or a bare key returns `PLUGIN_OPTIONS_OBFS_MODE`. A value other than `http` or `tls` returns `PLUGIN_OPTIONS_OBFS_MODE`.
4. A `v2ray-plugin` entry with a `mode` key needs `websocket` or `ws`, in any case. A bare key or another value returns `PLUGIN_OPTIONS_V2RAY_MODE`. A missing `mode` key is valid, because the native parser defaults to websocket.
5. A known key with an unknown name does not fail. The native parser logs the key and ignores it.
6. An unknown plugin id passes the schema check. The editor cannot open for that case.

### 2. `model/Profile.ets`

Add the import from `./PluginOptions`:

```ts
import {
  PLUGIN_STATE_DISABLED, PLUGIN_STATE_KNOWN,
  findPlugin, isKnownPlugin, pluginDefaultOptions, pluginStateOf, samePlugin,
} from './PluginOptions';
```

Add the field after `pluginOpts`:

```ts
/**
 * Options per plugin id, so a switch away from a plugin and back keeps its
 * options. The selected entry always agrees with `pluginOpts`. A missing
 * entry means the plugin default applies. The field never goes to an ss URL
 * or to an exported JSON file.
 */
pluginConfigs: Record<string, string> = {};
```

Add these methods to `Profile`:

```ts
pluginState(): string
hasPlugin(): boolean
isSubscriptionLocked(): boolean
canEditPlugin(): boolean
canConfigurePlugin(): boolean
pluginError(): string
pluginOptionsFor(id: string): string
setPluginOptions(id: string, text: string): void
selectPlugin(id: string): void
seedPluginConfigs(): void
normalizePluginOptions(): void
private existingPluginKey(id: string): string
```

Behaviour:

- `pluginState` returns `pluginStateOf(this.plugin)`.
- `hasPlugin` returns `this.plugin.length > 0`.
- `isSubscriptionLocked` returns true when `subscriptionId` is non-empty and `subscriptionStatus === STATUS_ACTIVE`. It replaces the inline test in `ProfileEdit.aboutToAppear`.
- `canEditPlugin` returns `!isSubscriptionLocked()`.
- `canConfigurePlugin` returns `canEditPlugin() && pluginState() === PLUGIN_STATE_KNOWN`.
- `pluginError` returns `''` for an empty plugin and for a known plugin. It returns `Unknown plugin <id>` for an unknown plugin.
- `pluginOptionsFor(id)` returns `''` for an empty id. It returns the stored entry when one exists. It returns `pluginDefaultOptions(id)` otherwise.
- `setPluginOptions(id, text)` writes the entry. It also writes `pluginOpts` when `id` equals `this.plugin`. It does nothing for an empty id.
- `selectPlugin(id)` runs these steps:
  1. An empty id sets `plugin` to `''` and `pluginOpts` to `''`. The entries stay in `pluginConfigs`.
  2. `samePlugin(id, this.plugin)` returns without a change. This keeps an alias id and its options.
  3. `existingPluginKey(id)` returns the id of an existing entry that resolves to the same plugin. A stored entry for the requested id wins. Otherwise the first stored key that resolves to the same plugin wins.
  4. The new selected id is the existing key, or `id` when no key exists.
  5. `plugin` takes the new selected id. `pluginOpts` takes `pluginOptionsFor(newId)`. `pluginConfigs[newId]` takes that value. A first selection therefore stores the default.
- `seedPluginConfigs()` writes `pluginConfigs[plugin] = pluginOpts` when both are non-empty. It writes nothing otherwise. A bare `?plugin=obfs-local` URL therefore keeps `pluginOpts === ''`, and the existing `Profile.test.ets` case with a bare plugin URL stays true.
- `normalizePluginOptions()` runs these steps:
  1. An empty plugin clears `pluginOpts` and returns.
  2. A non-empty `pluginOpts` wins and writes `pluginConfigs[plugin]`.
  3. An empty `pluginOpts` with a stored entry takes the entry.
  4. An empty `pluginOpts` without an entry takes `pluginDefaultOptions(plugin)`.
- `existingPluginKey(id)` checks `pluginConfigs[id]` first. It then scans `Object.keys(pluginConfigs)` for a key with `samePlugin(key, id)`. It returns `''` when no key matches.

`Profile.parseUrl` calls `profile.seedPluginConfigs()` after it sets `plugin` and `pluginOpts`. It does not fill the default, because the URL carries no options. The default applies when a profile loads through the store, the file importer, or a subscription merge, and when the user selects the plugin in the editor.

`Profile.toTunConfig` changes the mode line:

```ts
'mode': this.plugin.length > 0 ? 'tcp_only' : 'tcp_and_udp',
```

`Profile.toLocalConfig`, `Profile.toUri`, and the `plugin` / `plugin_opts` output fields stay unchanged.

### 3. `model/ProfileStore.ets`

In `ProfileStore.fromJson`:

```ts
profile.pluginConfigs = parsed.pluginConfigs ?? {};
```

Call `profile.normalizePluginOptions()` after `plugin` and `pluginOpts` are copied and before the return. An old file has no `pluginConfigs`. An old file with a known plugin and empty `pluginOpts` gets the plugin default.

### 4. `model/ProfilesFile.ets`

In `profileFromJson`, call `profile.normalizePluginOptions()` before the return. The import path seeds `pluginConfigs[plugin]` from a non-empty `plugin_opts`. An empty `plugin_opts` gets the plugin default.

`exportProfiles` stays unchanged. It writes `plugin` and `plugin_opts` only. It does not write `pluginConfigs`.

### 5. `model/Subscription.ets`

In `mergeSubscription`, after the two existing plugin copies:

```ts
matched.seedPluginConfigs();
matched.normalizePluginOptions();
```

`seedPluginConfigs` keeps the local entries for the other plugins and takes the incoming entry for the selected plugin. The normalize call fills the default when the subscription URL carries no options.

### 6. `model/ProxyService.ets`

At the start of `ProxyService.start`, after the `ProxyService.running` check and before `profile.toLocalConfig`:

```ts
const pluginError = profile.pluginError();
if (pluginError.length > 0) {
  throw new Error(pluginError);
}
```

The caller already shows `index_could_not_start_proxy` with the error message.

### 7. `vpnability/SsVpnExtensionAbility.ets`

In `onCreate`, after the empty-profile check and before `VpnStatusStore.markStarting`:

```ts
const pluginError = profile.pluginError();
if (pluginError.length > 0) {
  await VpnStatusStore.markFailed(this.context, profile.id, profile.name, pluginError, '');
  return;
}
```

`markFailed` takes the reason as its fourth argument. `Index.ets` shows `status.reason` when it is non-empty (line 743). The plugin error therefore goes in the reason, not in the detail. The UI shows `Failed: Unknown plugin kcptun`.

### 8. `pages/ProfileEdit.ets`

Remove:

- `PLUGINS`
- `PLUGIN_OPTS_HINTS`
- `@State pluginIndex`
- `@State pluginOptions`
- The `STATUS_ACTIVE` import. Use `Profile.isSubscriptionLocked()`.

Keep `@State pluginOpts`. Add:

```ts
@State plugin: string = '';
@State pluginPickerShown: boolean = false;
@State optionsDraft: string = '';
private pluginConfigs: Record<string, string> = {};
private optionsDialog: CustomDialogController = new CustomDialogController({
  builder: PluginOptionsDialog({
    draft: $optionsDraft,
    onCommit: (text: string) => this.commitPluginOptions(text),
  }),
  autoCancel: true,
});
```

Methods to add or change:

```ts
private pluginLabel(id: string): Resource
private pluginSummary(): ResourceStr
private pluginOptionsSummary(): string
private canOpenOptions(): boolean
private pluginConfigSnapshot(): string
private pluginDraft(): Profile
private pickPlugin(id: string): void
private openOptionsEditor(): void
private commitPluginOptions(text: string): void
private optionsErrorText(code: string): ResourceStr
@Builder PluginPickerSheet()
```

Behaviour:

- `pluginLabel` maps the canonical definition to a resource. `obfs-local` uses `plugin_label_simple_obfs`. `v2ray-plugin` uses `plugin_label_v2ray`. Any other id uses `profile_edit_plugin_disabled`.
- `pluginSummary` returns `profile_edit_plugin_disabled` for an empty id. It returns `profile_edit_plugin_unknown` with the id for an unknown id. It returns `pluginLabel` otherwise.
- `pluginOptionsSummary` returns `pluginOpts` when the plugin is known. It returns `''` otherwise. A locked row still shows its text, as the Android row does.
- `canOpenOptions` returns `!this.readOnly && pluginStateOf(this.plugin) === PLUGIN_STATE_KNOWN`.
- `pluginConfigSnapshot` sorts `Object.keys(this.pluginConfigs)` and joins each `key=value` pair. `formSnapshot` adds this string and replaces `pluginIndex` with `plugin`.
- `pluginDraft` returns a new `Profile` with `plugin`, `pluginOpts`, and `pluginConfigs` from the page state. No other field takes part in the plugin rules.
- `pickPlugin` closes the sheet first. It then runs the tested model rule on a draft profile:

```ts
private pickPlugin(id: string): void {
  this.pluginPickerShown = false;
  const draft = this.pluginDraft();
  draft.selectPlugin(id);
  this.plugin = draft.plugin;
  this.pluginOpts = draft.pluginOpts;
  this.pluginConfigs = draft.pluginConfigs;
}
```

The page keeps no second copy of the selection rule.

- `openOptionsEditor` returns when `canOpenOptions()` is false. It sets `optionsDraft = this.pluginOpts` and calls `this.optionsDialog.open()`.
- `commitPluginOptions` validates and writes through the model:

```ts
private commitPluginOptions(text: string): void {
  const draft = this.pluginDraft();
  const code = PluginOptions.validate(draft.plugin, text);
  if (code !== PLUGIN_OPTIONS_OK) {
    promptAction.showToast({ message: this.optionsErrorText(code), duration: 3000 });
    return;
  }
  draft.setPluginOptions(draft.plugin, PluginOptions.canonical(text));
  this.pluginOpts = draft.pluginOpts;
  this.pluginConfigs = draft.pluginConfigs;
}
```

An error code shows the toast and writes nothing. The dialog closes in both cases because the dialog calls this method and then closes.
- `optionsErrorText` maps `PLUGIN_OPTIONS_CONTROL`, `PLUGIN_OPTIONS_OBFS_MODE`, and `PLUGIN_OPTIONS_V2RAY_MODE` to their resources.
- `PluginPickerSheet` builds a `Column` with one row per `pluginChoices(this.plugin)`. Each row shows `pluginLabel(choice.id)`. The current row uses `FontWeight.Bold`. A tap calls `pickPlugin(choice.id)`. The `ForEach` key is `` `${choice.id}:${choice.current}` ``. The live value is in the key because the framework reuses a cached child for an unchanged key.

`aboutToAppear` changes:

```ts
profile.normalizePluginOptions();
this.plugin = profile.plugin;
this.pluginOpts = profile.pluginOpts;
this.pluginConfigs = profile.pluginConfigs;
this.readOnly = profile.isSubscriptionLocked();
```

`buildProfile` changes:

```ts
profile.plugin = this.plugin;
profile.pluginConfigs = this.pluginConfigs;
profile.pluginOpts = this.plugin.length > 0 ? this.pluginOpts : '';
```

`build()` replaces the plugin `LabeledSelect` and the options `TextInput` with:

1. A category `Text` with `profile_edit_plugin_category`.
2. A Plugin row. It shows `profile_edit_plugin` and `pluginSummary()`. It is disabled when `readOnly` is true. It opens the sheet with `bindSheet(this.pluginPickerShown, this.PluginPickerSheet(), { height: SheetSize.FIT_CONTENT })`.
3. A Configure… row. It shows `profile_edit_plugin_configure` and `pluginOptionsSummary()`. It is disabled when `canOpenOptions()` is false. It opens the editor.

Add the dialog struct at the end of the file:

```ts
@CustomDialog
struct PluginOptionsDialog {
  controller: CustomDialogController;
  @Link draft: string;
  onCommit: (text: string) => void = () => {
  };
}
```

The dialog shows:

- A title with `profile_edit_plugin_configure`.
- A `TextInput` with the existing `profile_edit_plugin_options` placeholder, `.fontFamily('monospace')`, and `.onChange((value) => this.draft = value)`.
- A Cancel button with `common_cancel`. It closes the dialog.
- An OK button with `common_ok`. It calls `this.onCommit(this.draft)` and closes the dialog. The page validates inside `commitPluginOptions`. The dialog closes after an error, as TC-U08-10 expects.

The dialog has no `?` button. HarmonyOS has no plugin help activity.

### 9. `pages/Index.ets`

In `ProfileRow.build()`, after the host and method row and before the traffic row:

```ts
if (this.profile.hasPlugin()) {
  Text($r('app.string.index_profile_plugin', this.profile.plugin))
    .fontSize(11)
    .fontColor($r('app.color.text_secondary'))
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
}
```

### 10. Resources

Add these keys to both string files. The two files must hold the same names and the same number of `%s` arguments.

| Name | English | Chinese |
| --- | --- | --- |
| `profile_edit_plugin_category` | Plugin | 插件 |
| `profile_edit_plugin_configure` | Configure… | 配置… |
| `profile_edit_plugin_disabled` | Disabled | 禁用 |
| `profile_edit_plugin_unknown` | Unknown plugin %s | 未知插件 %s |
| `plugin_label_simple_obfs` | simple-obfs | simple-obfs |
| `plugin_label_v2ray` | v2ray-plugin | v2ray-plugin |
| `plugin_options_control_chars` | No control characters allowed. | 不允许控制字符。 |
| `plugin_options_obfs_mode` | The obfs option must be http or tls | obfs 选项必须是 http 或 tls |
| `plugin_options_v2ray_mode` | Only the websocket mode is supported | 仅支持 websocket 模式 |
| `index_profile_plugin` | Plugin: %s | 插件：%s |

The existing `profile_edit_plugin` stays as the Plugin row label. The existing `profile_edit_plugin_options` stays as the editor placeholder.

### 11. Tests

Add `entry/src/test/ParityU08.test.ets`. Export one default suite function. Import `PluginOptions.ets` and `Profile.ets` from `../main/ets/model/`.

Add the import and the call to `entry/src/test/List.test.ets`.

### State and data

The profile record gains one persisted field. The selected pair stays the same.

| Field | Type | Persisted in `profiles.json` | Exported to ss and JSON | Meaning |
| --- | --- | --- | --- | --- |
| `plugin` | `string` | Yes | Yes | Selected plugin id, `''` for Disabled. An alias id is kept as stored. |
| `pluginOpts` | `string` | Yes | Yes | Effective options of the selected plugin. |
| `pluginConfigs` | `Record<string, string>` | Yes | No | Options per plugin id. |

Example record:

```json
{
  "plugin": "obfs-local",
  "pluginOpts": "obfs=tls",
  "pluginConfigs": {
    "obfs-local": "obfs=tls",
    "v2ray-plugin": "mode=websocket"
  }
}
```

Invariants:

1. `plugin === ''` implies `pluginOpts === ''`.
2. When `plugin` is non-empty and `pluginConfigs[plugin]` exists, the two values are equal.
3. A missing `pluginConfigs` entry means the catalogue default applies.
4. A switch to another plugin keeps the old entry until the new selection overwrites its own entry.
5. A stored empty entry stays empty. The default does not replace it.
6. The map is never written to an ss URL or to an exported JSON file.
7. An old file without the map loads with `{}` and normalizes to the selected plugin and its default.

Page state:

| State | Owner | Lifetime | Purpose |
| --- | --- | --- | --- |
| `plugin` | `ProfileEdit` | While the profile editor is open | Selected plugin id. |
| `pluginOpts` | `ProfileEdit` | While the profile editor is open | Effective options of the selected plugin. |
| `pluginConfigs` | `ProfileEdit` | While the profile editor is open | Draft of the per-plugin entries. |
| `pluginPickerShown` | `ProfileEdit` | While the profile editor is open | Sheet visibility. |
| `optionsDraft` | `ProfileEdit` | While the options editor is open | Typed text. It is discarded on Cancel, on back, and on an outside tap. |

Plugin state transitions:

| From | Event | To | Effect |
| --- | --- | --- | --- |
| Disabled | Picks a known plugin | Known | The default options are stored. Configure… becomes enabled. |
| Known | Picks another known plugin | Known | The old entry stays. The new entry takes its stored value or its default. |
| Known | Picks Disabled | Disabled | `plugin` and `pluginOpts` become `''`. The entries stay. Configure… becomes disabled. |
| Known | The id resolves to no definition | Unknown | The row reads Unknown plugin. Configure… becomes disabled. |
| Unknown | Picks a known plugin | Known | The new entry takes its stored value or its default. |
| Unknown | Picks Disabled | Disabled | The id and the selected options clear. |
| Any | The profile belongs to an active subscription | Locked | The Plugin and Configure… rows are disabled. |

### Validation and errors

| Condition | Code | Message | Effect |
| --- | --- | --- | --- |
| Text holds U+0000 to U+001F or U+007F to U+009F | `control` | No control characters allowed. | The editor closes. The stored options stay. |
| `obfs-local` has no `obfs` key or a bare `obfs` key | `obfs-mode` | The obfs option must be http or tls | The editor closes. The stored options stay. |
| `obfs-local` has an `obfs` value other than `http` or `tls` | `obfs-mode` | The obfs option must be http or tls | The editor closes. The stored options stay. |
| `v2ray-plugin` has a bare `mode` key or a `mode` value other than `websocket` or `ws` | `v2ray-mode` | Only the websocket mode is supported | The editor closes. The stored options stay. |
| A key is unknown to the plugin | none | none | The entry is kept and serialized. The native parser ignores it. |
| The text ends with a backslash | none | none | The last pair drops. The change is accepted, as on Android. |
| The plugin id is unknown | none | Unknown plugin `<id>` | Configure… is disabled. The start is refused. |

Unsupported-name error flow:

1. The profile loads with `plugin = kcptun`.
2. `pluginStateOf('kcptun')` returns `unknown`.
3. The Plugin row reads `Unknown plugin kcptun`.
4. `Profile.canConfigurePlugin()` returns false. Configure… is disabled.
5. The connect path calls `Profile.pluginError()` and gets `Unknown plugin kcptun`.
6. `ProxyService.start` throws before the native call.
7. `SsVpnExtensionAbility.onCreate` writes a failed status before it creates the VPN interface.
8. The user sees `Failed: Unknown plugin kcptun`, or `Could not start the proxy: Unknown plugin kcptun`.
9. If a start reaches the native core, `plugin::parse_plugin` returns `PluginError::Unsupported` and `sslocal_start` returns `SSLOCAL_ERR_BAD_CONFIG`. The native message stays as the backstop.

The app adds no native error code. `SSLOCAL_OK`, `SSLOCAL_ERR_BAD_CONFIG`, and `SSLOCAL_ERR_RUNTIME` keep their meanings.

### Test plan

The host tests run through `./test-arkts-host.sh`. `model` means the host spec. `model + device` means the host spec plus the E2E case with the same ID in `docs/versions/5.4.0/e2e/U08.md`. `android-only` means no plan, because HarmonyOS has no mechanism for that case.

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| TC-U08-01 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#pluginRowShowsKnownLabel` | model + device |
| TC-U08-02 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#unknownPluginReadsUnknown` | model |
| TC-U08-03 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#pickerMovesCurrentFirst` | model + device |
| TC-U08-04 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#disabledKeepsStoredOptions` | model |
| TC-U08-05 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#switchKeepsEachOptions` | model |
| TC-U08-06 | none | none | android-only |
| TC-U08-07 | none | none | android-only |
| TC-U08-08 | none | none | android-only |
| TC-U08-09 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#editorStoresTypedOptions` | model + device |
| TC-U08-10 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#editorRejectsControlCharacters` | model + device |
| TC-U08-11 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#cancelKeepsStoredOptions` | model + device |
| TC-U08-12 | none | none | android-only |
| TC-U08-13 | none | none | android-only |
| TC-U08-14 | none | none | android-only |
| TC-U08-15 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#unknownPluginFailsStart` | model + device |
| TC-U08-16 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#subscriptionLocksPluginControls` | model + device |
| TC-U08-17 | none | none | android-only |
| TC-U08-18 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#pluginRoundTrip` | model |
| TC-U08-19 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#firstSelectionUsesDefault` | model |
| TC-U08-20 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#profileRowAddsPluginLine` | model + device |
| TC-U08-21 | none | none | android-only |
| TC-U08-22 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#tunRunsTcpOnlyWithPlugin` | model |
| TC-U08-23 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#optionsSyntaxRoundTrip` | model |
| TC-U08-24 | none | none | android-only |
| TC-U08-25 | none | none | android-only |
| TC-U08-26 | none | none | android-only |
| TC-U08-27 | none | none | android-only |
| TC-U08-28 | none | none | android-only |
| TC-U08-29 | none | none | android-only |
| TC-U08-30 | `entry/src/test/ParityU08.test.ets` | `entry/src/test/ParityU08.test.ets::U08#dismissKeepsStoredOptions` | model + device |

Test contents:

1. `pluginRowShowsKnownLabel` asserts `pluginStateOf('obfs-local') === 'known'`, the label `simple-obfs`, `Profile.hasPlugin()`, and `canEditPlugin()` on a manual profile.
2. `unknownPluginReadsUnknown` asserts `pluginStateOf('kcptun') === 'unknown'`, `canConfigurePlugin() === false`, and `pluginError()` for the same id.
3. `pickerMovesCurrentFirst` asserts the order and the current flags for `v2ray-plugin`, `obfs-local`, `''`, and `kcptun`. It asserts that `selectPlugin` with the current id leaves the profile unchanged.
4. `disabledKeepsStoredOptions` asserts that `selectPlugin('')` clears the selection but keeps the entry, and that a later selection restores `obfs=tls`.
5. `switchKeepsEachOptions` asserts the entries for `obfs-local` and `v2ray-plugin` across four switches. It also asserts the alias rule: a stored `simple-obfs` entry is selected when the user picks the `obfs-local` row.
6. `editorStoresTypedOptions` asserts `validate('v2ray-plugin', 'mode=websocket;tls;host=example.com') === ok`, the canonical text, `setPluginOptions`, and the value after `ProfileStore.fromJson`.
7. `editorRejectsControlCharacters` asserts the control code for a newline, a U+0001 character, and U+0080. It asserts that the stored options do not change.
8. `cancelKeepsStoredOptions` starts from `obfs=tls`, changes a local draft, and writes nothing. The stored value stays `obfs=tls`.
9. `unknownPluginFailsStart` asserts `pluginError() === 'Unknown plugin kcptun'`. It asserts `''` for an empty plugin and for `obfs-local`.
10. `subscriptionLocksPluginControls` asserts `isSubscriptionLocked()`, `canEditPlugin()`, and `canConfigurePlugin()` for an active subscription profile, a manual profile with a known plugin, and a manual profile with Disabled.
11. `pluginRoundTrip` asserts the ss URL query, the JSON export fields, the import back to the same plugin and options, the seeded entry for a URL with options, the empty options and empty entry for a bare plugin URL, and the absence of `pluginConfigs` from the exported JSON.
12. `firstSelectionUsesDefault` asserts `obfs=tls` for a first `obfs-local` selection, `mode=websocket` for a first `v2ray-plugin` selection, and `''` as the default for an unknown id.
13. `profileRowAddsPluginLine` asserts `hasPlugin()` for a profile with a plugin and `false` without one.
14. `tunRunsTcpOnlyWithPlugin` asserts `mode === 'tcp_only'` in the tun config with a plugin and `tcp_and_udp` without one.
15. `optionsSyntaxRoundTrip` asserts these cases: `obfs=http;obfs-host=example.com`, bare flags `a;b`, the escaped value `obfs=va\;lue`, the trailing backslash, an unknown key, a bare `obfs` key, an invalid obfs mode, a bare `mode` key, and an invalid v2ray mode. The last four return `obfs-mode`, `obfs-mode`, `v2ray-mode`, and `v2ray-mode`.
16. `dismissKeepsStoredOptions` starts from `obfs=tls`, changes a local draft, drops the draft without a commit, and asserts that the stored value and the stored entry stay `obfs=tls`.

### Platform notes

- HarmonyOS has no plugin APK package, no content provider discovery, and no `ACTION_NATIVE_PLUGIN`. The catalogue replaces discovery. The picker always lists three rows: Disabled, simple-obfs, and v2ray-plugin.
- Built-in plugins have no app icon and no package. The Plugin row shows the label only. TC-U08-01 stays partial for the icon.
- HarmonyOS has no `ACTION_CONFIGURE`, `ACTION_HELP`, or application-details intent for a plugin. Cases TC-U08-06, 07, 08, 12, 13, 14, 17, 21, 24, 25, 26, 27, 28, and 29 stay android-only.
- The plugin signature trust check has no meaning for a built-in plugin. No warning snackbar is planned.
- Android keeps the per-plugin options in the app settings, not in the profile. This app keeps them in the profile, so a profile copy and a subscription carry them. The exported pair stays the standard `plugin` and `plugin_opts`.
- Android stores the options in a `HashMap`, so its summary reorders the pairs. This app stores an ordered list and keeps the typed order. The text the user sees is the text the core receives. TC-U08-09 step 4 records the Android order as a boundary.
- A plugin profile uses `tcp_only` in the tun config. The plugin forwarder carries TCP only. The DNS gateway in the tun still answers UDP queries locally.
- `Profile.udpFallbackId` is stored and unused. No UDP fallback start path exists, so the Android refusal `UDP fallback cannot have plugins` has no counterpart yet.
- The catalogue must stay in step with `parse_plugin` in `native/sslocal-ffi/src/plugin.rs`. The names are `obfs-local`, `simple-obfs`, `obfs`, and `v2ray-plugin`.
- The options editor is a single-line `TextInput` with the `monospace` font family. A paste can still carry a control character, so the validation stays.
- `bindSheet` needs API 11 or later. The app targets API 12.
- A `ForEach` over plain objects caches a child by its key. The picker key includes `choice.current`, or the bold state freezes.
- The new model file is pure ArkTS. It uses no `util` codec, so the host runner can execute it.
- Every new view uses a colour token. Buttons set both `backgroundColor` and `fontColor`. User-visible text comes from a resource.
- The options editor closes on OK, on Cancel, on back, and on an outside tap. Only OK with a valid text writes to the profile.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| UQ-1 | Is `mode=websocket` the correct default config for `v2ray-plugin`? The Android default comes from the plugin package metadata, and the spec gives no value. | Product owner |
| UQ-2 | Does the app keep the typed options order, or reproduce the Android hash-map order? This plan keeps the typed order. | Product owner |
| UQ-3 | Does an imported unknown plugin id appear as a disabled row in the picker? This plan shows it in the summary only. | Product owner |
| UQ-4 | Does the editor validate `obfs` and `mode`, or leave that check to the core? This plan validates both and keeps the core as the final authority. | Rust core owner |
| UQ-5 | Does the profile list line show the plugin id or the plugin label? R-UH-27 and TC-U08-20 ask for the id. | Product owner |
| UQ-6 | Does a profile export and re-import keep the other plugins' entries? This plan loses them, because the export carries only the selected pair. | Product owner |
| UQ-7 | Does a subscription refresh keep the local entries for the other plugins? This plan keeps them and replaces the selected entry only. | Subscription owner |

<a id="u09"></a>
## U09 Settings

This document plans the HarmonyOS implementation of unit U09, global settings.

### Scope

The unit ports the Android global settings screen to `pages/Settings.ets`.
The plan adds four rows, the Advanced expansion, the service state gating, and the port dialogs.
The existing diagnostics fields stay below the settings rows.

In scope:

- The screen shows the rows in this order: Auto Connect, Service mode, SOCKS5 proxy port, Local DNS port.
- The collapsed view shows the Advanced row. The expanded view shows all four rows.
- The service mode menu has two entries, Proxy only and VPN. It marks the stored entry.
- The page stores both ports as text. The port dialogs and the read-time fallback use that text.
- The page seeds absent keys when it opens.
- The service mode row and the port rows follow the live service state.
- The Local DNS port becomes the `dns_gateway` port of the tun.
- The SOCKS5 port becomes the proxy mode listener port.

Out of scope:

- The Allow Toggling in Lock Screen row is out of scope. HarmonyOS has no direct boot storage.
- The Transproxy mode and the Transproxy port are out of scope. HarmonyOS has no redsocks and no root redirection.
- The boot receiver is out of scope. HarmonyOS has no public startup subscriber for this app.
- The service rebind is out of scope. HarmonyOS has no bound service class.
- A local SOCKS5 listener in VPN mode is out of scope. The core's tun stack terminates the flows.
- The drawer entry is out of scope. Unit U01 owns the main shell.
- A notification setting is out of scope. The notification permission stays on the connect paths.

The plan leaves these parity gaps:

| Area | After U09 | Residual difference | Cases |
| --- | --- | --- | --- |
| Row list | Four rows and the Advanced row | No lock-screen row, no Transproxy row | TC-U09-01, TC-U09-18 |
| Auto Connect | The switch stores the value | No startup hook, so no receiver state follows | TC-U09-16, TC-U09-17, TC-U09-21, TC-U09-22 |
| Service mode | A two-entry menu marks the stored entry | No Transproxy entry, no service rebind | TC-U09-03, TC-U09-04, TC-U09-05, TC-U09-06, TC-U09-24 |
| Ports | Text dialogs and the read-time fallback | No Transproxy port. The caret position needs a device check. | TC-U09-09 to TC-U09-15 |
| Gating | The rows follow the live service state while the page shows | The Android state listener has no equivalent. The visible behavior matches. | TC-U09-07, TC-U09-08, TC-U09-20 |
| Local DNS port | It becomes the tun `dns_gateway` port | No parity gap. The value applies on the next start. | TC-U09-15 |
| SOCKS5 port | The proxy listener uses it | No VPN-mode listener, because the core owns the tun flows | TC-U09-25 |
| Lock screen | The row is absent | Android-only surface | TC-U09-19, TC-U09-23 |
| Transproxy | The mode and the port are absent | Android-only surface | TC-U09-05, TC-U09-26 |

Target parity after this unit: 9 cases implemented, 12 cases partial, 5 cases android-only.

### Files to change

| File | Type | Change |
| --- | --- | --- |
| `entry/src/main/ets/model/Diagnostics.ets` | code | Add the settings defaults, the row keys, the port helpers, the seed helpers, and the service gating function. Change the settings interfaces. |
| `entry/src/main/ets/model/Settings.ets` | code | Add `SettingsStore.loadSeeded`. Update the class comment. |
| `entry/src/main/ets/pages/Settings.ets` | code | Add the rows, the menu, the port dialog, the gating poll, and the page state. Keep the header and the diagnostics section. |
| `entry/src/main/ets/model/Profile.ets` | code | Add the `dnsPort` parameter to `toTunConfig`. Replace the fixed `DNS_PORT` constant. |
| `entry/src/main/ets/vpnability/SsVpnExtensionAbility.ets` | code | Read the local DNS port from the settings store and pass it to `toTunConfig`. |
| `entry/src/main/ets/pages/Index.ets` | code | Read the proxy port text as a number through `portNumber`. |
| `entry/src/main/resources/base/element/string.json` | resource | Add six strings. Change two values. |
| `entry/src/main/resources/zh_CN/element/string.json` | resource | Add the same six strings. Change the same two values. |
| `entry/src/test/ParityU09.test.ets` | test | New host spec for the U09 logic. |
| `entry/src/test/List.test.ets` | test | Register the new spec. |
| `entry/src/test/Profile.test.ets` | test | Change the two `5453` expectations to `5450`. |

Documentation update:

- `AGENTS.md` line 175. Replace the fixed `127.0.0.1:5453` with the configured local DNS port and its default of 5450.

`model/ProxyService.ets` and `model/ConnectionNotification.ets` need no change. The Settings page uses the existing `ProxyService.isRunning()`.

### Implementation plan

### `model/Diagnostics.ets`

This file stays free of kit imports. The page and the host specs both use it.

Add these constants:

```ts
export const DEFAULT_LOCAL_DNS_PORT: number = 5450;
export const PORT_UNSET: string = 'not-set';

export const SETTINGS_ROW_AUTO_CONNECT: string = 'auto-connect';
export const SETTINGS_ROW_SERVICE_MODE: string = 'service-mode';
export const SETTINGS_ROW_PROXY_PORT: string = 'proxy-port';
export const SETTINGS_ROW_LOCAL_DNS_PORT: string = 'local-dns-port';

export const SERVICE_MODE_CHOICES: string[] = [MODE_PROXY, MODE_VPN];
```

The order of `SERVICE_MODE_CHOICES` matches the Android menu order.

Change `AppSettings` to this shape:

```ts
export interface AppSettings {
  probeUrl: string;
  speedTestUrl: string;
  /** A stored mode value. A value other than MODE_VPN or MODE_PROXY is kept. */
  serviceMode: string;
  /** The port text as the user typed it. '' means Not set. */
  proxyPort: string;
  /** The local DNS port text as the user typed it. '' means Not set. */
  localDnsPort: string;
  /** Stored for a future startup hook. No HarmonyOS hook exists yet. */
  autoConnect: boolean;
  shareOverLan: boolean;
}
```

Change `AppSettingsJson` to this shape:

```ts
export interface AppSettingsJson {
  probeUrl?: string;
  speedTestUrl?: string;
  serviceMode?: string;
  proxyPort?: string | number;
  localDnsPort?: string | number;
  autoConnect?: boolean;
  shareOverLan?: boolean;
}
```

The union on the two port fields reads a `settings.json` file written by 5.3.5, where `proxyPort` is a number.

Add a private helper `portText(value: string | number | undefined): string`.
It returns `''` for `undefined` and for any other non-string, non-number value.
It returns a string input unchanged.
It returns the decimal text of a number input.

Change `settingsFromJson`:

- Set `serviceMode` to `MODE_VPN` when the stored value is absent or empty.
- Keep a non-empty stored `serviceMode` string. An unknown value stays in the result. A non-string value falls back to `MODE_VPN`.
- Set `proxyPort` to `portText(parsed.proxyPort)` when the value exists. A missing value keeps `'1080'`.
- Set `localDnsPort` to `portText(parsed.localDnsPort)` when the value exists. A missing value keeps `'5450'`.
- Set `autoConnect` to `parsed.autoConnect === true`.
- Keep the existing probe URL, speed URL, and share-over-LAN rules.

Add these pure functions:

```ts
export function settingsRows(expanded: boolean): string[]
export function advancedSummaryRows(): string[]
export function serviceModeEntry(serviceMode: string): string
export function portSummary(text: string): string
export function portNumber(text: string, fallback: number): number
export function sanitizePortInput(text: string): string
export function settingsNeedSeed(parsed: AppSettingsJson | null): boolean
export function settingsJsonFrom(settings: AppSettings): AppSettingsJson
export function isServiceStopped(status: VpnStatus | null, statsTimestamp: number,
  nowMs: number, proxyUp: boolean): boolean
```

`settingsRows(false)` returns `[SETTINGS_ROW_AUTO_CONNECT]`.
`settingsRows(true)` returns all four row keys in display order.
`advancedSummaryRows()` returns the three hidden row keys in display order.
Both functions return a new array on each call.

`serviceModeEntry` returns `MODE_VPN`, `MODE_PROXY`, or `''`.
It recognizes only the two modes that HarmonyOS offers.
A stored `transproxy` value returns `''`.

`portSummary` returns the text when the text is not empty.
It returns `PORT_UNSET` when the text is empty.

`portNumber` returns the fallback for an empty text, a text with a non-digit, a value below 1025, and a value above 65535.
It returns the value for 1025 through 65535.
Use `Number.parseInt` and `Number.isNaN`.

`sanitizePortInput` keeps digits only.
It keeps at most five characters.

`settingsNeedSeed` returns true for `null`.
It returns true when `serviceMode`, `proxyPort`, `localDnsPort`, or `autoConnect` is `undefined`.
It returns false otherwise.
A stored empty port is a deliberate clear and does not need a seed.

`settingsJsonFrom` returns all seven keys of `AppSettings`.
The two port fields are strings in the result.
This function is the only writer shape for the store.

`isServiceStopped` returns true when no tunnel is active:

1. Return false when `proxyUp` is true.
2. Return true when `status` is null.
3. Return true when the state is `VPN_STATE_STOPPED` or `VPN_STATE_FAILED`.
4. Compute `statusRecent` as `!isStale(status.timestamp, nowMs, CONNECT_TIMEOUT_MS + STATS_STALE_MS)`.
5. Compute `statsLive` as `statsTimestamp > 0 && !isStale(statsTimestamp, nowMs, STATS_STALE_MS)`.
6. Return `!(statusRecent || statsLive)`.

Step 5 uses the same liveness rule as `Index.resumeStatus`.

### `model/Settings.ets`

Keep `load` and `save` as they are.

Add this method:

```ts
static async loadSeeded(context: common.Context): Promise<AppSettings>
```

The method does this:

1. Read `JsonStore.exists(context, 'settings')`.
2. Read the file with `JsonStore.read`.
3. Parse the text when it is not empty. Set `parsed` to null on a parse error.
4. Build the settings with `settingsFromJson(parsed)`.
5. Write `settingsJsonFrom(settings)` when the file is absent.
6. Write the same object when the file is readable and `settingsNeedSeed(parsed)` is true.
7. Do not write when the file exists and the read returned an empty text.
8. Do not write when the file exists and the parse failed.
9. Log a write failure with `hilog.warn` and return the settings.

The load path never throws.
The VPN extension must call `load`, not `loadSeeded`. The extension process must not write the store.

Update the class comment. The VPN extension now reads the local DNS port before a start.

### `pages/Settings.ets`

Keep the header row, the diagnostics fields, the Custom rules button, the About button, the Reset to defaults button, and the Save button.

Add these page state properties:

| Property | Type | Initial | Purpose |
| --- | --- | --- | --- |
| `proxyPort` | `string` | `'1080'` | The stored SOCKS5 port text |
| `localDnsPort` | `string` | `'5450'` | The stored local DNS port text |
| `autoConnect` | `boolean` | `false` | The stored Auto Connect value |
| `expanded` | `boolean` | `false` | The page-local expansion state |
| `serviceStopped` | `boolean` | `false` | The live gating state |

The existing `proxyPort` state becomes the stored text.
The save path no longer converts it to a number and clamps it.
Keep `probeUrl`, `speedTestUrl`, `serviceMode`, and `shareOverLan`.

Add these private members:

```ts
private stateTimer: number = -1;
private polling: boolean = false;
private portDialog: CustomDialogController | null = null;
```

Add these methods:

```ts
aboutToAppear(): void
onPageShow(): void
onPageHide(): void
aboutToDisappear(): void
private async refresh(): Promise<void>
private startStatePolling(): void
private stopStatePolling(): void
private async pollServiceState(): Promise<void>
private settingsValue(): AppSettings
private async persist(): Promise<boolean>
private async save(): Promise<void>
private async chooseMode(mode: string): Promise<void>
private async toggleAutoConnect(on: boolean): Promise<void>
private async applyPort(row: string, text: string): Promise<void>
private openPortDialog(row: string): void
private text(value: ResourceStr): string
private rowTitle(row: string): ResourceStr
private advancedSummary(): string
private modeSummary(): ResourceStr
private portSummaryText(text: string): ResourceStr
private modeMenuLabel(mode: string): string
```

`aboutToAppear` calls `refresh()` and `startStatePolling()`.
`refresh()` calls `SettingsStore.loadSeeded(abilityContext())` and copies the seven fields into the state.
`onPageShow` calls `startStatePolling()` and `pollServiceState()`.
`onPageHide` and `aboutToDisappear` call `stopStatePolling()`.
`startStatePolling` calls `stopStatePolling()` first.
The timer runs every 1000 ms.
The timer callback sets `polling`, calls `pollServiceState()`, and clears `polling` in `finally`.

`pollServiceState` loads the VPN status with `VpnStatusStore.load` and the traffic sample with `TrafficStatsStore.load`.
It sets `serviceStopped` to `isServiceStopped(status, stats !== null ? stats.timestamp : 0, Date.now(), ProxyService.isRunning())`.

`settingsValue` builds an `AppSettings` from the page state.
It trims the two URLs and applies the existing defaults for a blank URL.
It stores the two port texts unchanged.
It stores `serviceMode` and `autoConnect` unchanged.

`persist` saves `settingsValue()` with `SettingsStore.save`.
It returns true on success.
It logs the error and shows `$r('app.string.common_save_failed', message)` on failure.
It returns false on failure.

`save` calls `persist()` and calls `router.back()` only on success.
This method keeps the current behavior for the two URL fields.

`chooseMode` returns when the mode equals `this.serviceMode`.
It stores the previous value, sets the new value, and calls `persist()`.
It restores the previous value when `persist()` returns false.

`toggleAutoConnect` returns when the value equals `this.autoConnect`.
It follows the same set, persist, and restore pattern.

`applyPort` sanitizes the text with `sanitizePortInput`.
It returns when the result equals the stored text.
It follows the same set, persist, and restore pattern.
The port text is stored unchanged, including an empty text.

`openPortDialog` returns when `serviceStopped` is false.
It creates a `CustomDialogController` with a `PortDialog` builder.
It sets the title with `rowTitle(row)`.
It sets the initial text to `this.proxyPort` or `this.localDnsPort`.
It sets `onConfirm` to `applyPort(row, text)`.
It keeps the controller in `this.portDialog` and calls `open()`.

`rowTitle` maps the four row keys to the existing and new string resources.

`advancedSummary` joins the titles of `advancedSummaryRows()` with `', '`.

`modeSummary` maps the result of `serviceModeEntry` to `settings_vpn`, `settings_proxy`, or `settings_not_set`.

`portSummaryText` returns `settings_not_set` for `PORT_UNSET`.
It returns the stored text otherwise.

`modeMenuLabel` prefixes the entry with `'✓ '` when the mode equals `serviceModeEntry(this.serviceMode)`.

Add these builders:

```ts
@Builder SettingsRow(title: ResourceStr, summary: ResourceStr, enabled: boolean,
  onTap: () => void)
@Builder SwitchRow(title: ResourceStr, summary: ResourceStr, isOn: boolean,
  enabled: boolean, onChange: (on: boolean) => void)
@Builder ModeRow(title: ResourceStr, summary: ResourceStr, enabled: boolean)
@Builder ModeMenu()
```

`SettingsRow` is one row with a title, a summary, and a chevron.
It uses `$r('app.color.surface')` for the fill and `$r('app.color.text_body')` and `$r('app.color.text_secondary')` for the text.
It applies `.enabled(enabled)` and calls `onTap` on a click.

`SwitchRow` is one row with a title, a summary, and a `Toggle` of type `Switch`.
It applies `.enabled(enabled)` to the row.
It calls `onChange` on a toggle change.
It calls `onChange(!isOn)` on a row click, as the Android two-state preference does.

`ModeRow` is a `SettingsRow` shape with `.bindMenu(this.ModeMenu())`.
It applies `.enabled(enabled)`.

`ModeMenu` lists two `MenuItem` entries in the order of `SERVICE_MODE_CHOICES`.
The entries read `settings_proxy` and `settings_vpn`.
Each entry calls `chooseMode`.

The `build()` method keeps the header and the diagnostics section.
It renders the settings group in this order:

1. Render `SwitchRow` for Auto Connect. It is always enabled.
2. When `expanded` is false, render `SettingsRow` for Advanced with `advancedSummary()`. It sets `expanded` to true on a tap.
3. When `expanded` is true, render `ModeRow` for Service mode. Then render `SettingsRow` for SOCKS5 proxy port. Then render `SettingsRow` for Local DNS port. All three use `serviceStopped` as `enabled`.
4. When `expanded` is true and `serviceMode` is `MODE_PROXY`, render the proxy explainer, the Share over LAN switch, and the warning. The switch uses `serviceStopped` as `enabled`.

The Reset to defaults button keeps its current behavior. It resets the two URL fields only.
The Save button keeps its current behavior. It writes all current fields, which the immediate control writes already store.

Do not use `ForEach` for these rows.
The row summary changes while the row key is constant.
The cached child would keep the old summary.
This is the same trap as the profile rows in `Index.ets`.

Add a `@CustomDialog struct PortDialog` at the end of the file, in the style of `ConfirmDialog` in `Index.ets`.

The struct has these properties:

```ts
controller: CustomDialogController;
title: ResourceStr = '';
initial: string = '';
onConfirm: (text: string) => void = () => {};
@State text: string = '';
```

`aboutToAppear` sets `text` to `initial`.
The body has the title, one `TextInput`, and two buttons.

The `TextInput` uses `$r('app.string.settings_port_number')` as the placeholder and `InputType.Number`.
It uses `.maxLength(5)`.
`onChange` sets `text` to `sanitizePortInput(value)`.

The OK button uses `$r('app.string.common_ok')`, `$r('app.color.accent_container')`, and `$r('app.color.on_container')`.
It calls `onConfirm(text)` and `controller.close()`.
The Cancel button uses `$r('app.string.common_cancel')`, `$r('app.color.button_neutral')`, and `$r('app.color.on_neutral')`.
It calls `controller.close()` only.

### `model/Profile.ets`

Add the import of `DEFAULT_LOCAL_DNS_PORT` from `./Diagnostics`.
Remove the `DNS_PORT` constant and its comment.

Change the tun serializer signature:

```ts
toTunConfig(aclPath: string = '', tunAddress: string = '',
  localDns: string = '', dnsPort: number = DEFAULT_LOCAL_DNS_PORT): string
```

Use `dnsPort` in the `dns_gateway` value and in the `local_port` of the `dns` local.
The two values must stay equal.
Update the doc comment to say the port comes from the settings store.

`toLocalConfig` does not change.
Proxy mode has no `dns_gateway`.

### `vpnability/SsVpnExtensionAbility.ets`

Add the imports of `SettingsStore`, `DEFAULT_LOCAL_DNS_PORT`, and `portNumber`.

In `onCreate`, after the profile check and before `markStarting`, add:

```ts
const settings = await SettingsStore.load(this.context);
const dnsPort = portNumber(settings.localDnsPort, DEFAULT_LOCAL_DNS_PORT);
```

Pass `dnsPort` as the fourth argument of `profile.toTunConfig(...)`.

The extension calls `load`, not `loadSeeded`.
The extension must not write the settings store.

### `pages/Index.ets`

Add `DEFAULT_PROXY_PORT` and `portNumber` to the `Diagnostics` import.

In `connectProxy`, compute the listener port once:

```ts
const listenPort = portNumber(settings.proxyPort, DEFAULT_PROXY_PORT);
```

Pass `listenPort` to `ProxyService.start`.
Use `listenPort` in the `$r('app.string.index_proxy_on', host, listenPort)` toast.

No other change.

### Strings

Add these keys to `resources/base/element/string.json`:

| Name | Value |
| --- | --- |
| `settings_auto_connect` | `Auto Connect` |
| `settings_auto_connect_summary` | `Enable Shadowsocks on startup/app update if it was running before` |
| `settings_local_dns_port` | `Local DNS port` |
| `settings_advanced` | `Advanced` |
| `settings_not_set` | `Not set` |
| `settings_port_number` | `Port number` |

Add the same keys to `resources/zh_CN/element/string.json`:

| Name | Value |
| --- | --- |
| `settings_auto_connect` | `自动连接` |
| `settings_auto_connect_summary` | `如果之前正在运行，则在启动或应用更新时启用 Shadowsocks` |
| `settings_local_dns_port` | `本地 DNS 端口` |
| `settings_advanced` | `高级` |
| `settings_not_set` | `未设置` |
| `settings_port_number` | `端口号` |

Change two existing values in both files:

| Name | Old English | New English | New Chinese |
| --- | --- | --- | --- |
| `settings_proxy` | `Proxy` | `Proxy only` | `仅代理` |
| `settings_socks_port` | `SOCKS5 port (%d)` | `SOCKS5 proxy port` | `SOCKS5 代理端口` |

`settings_socks_port` loses its `%d`. The page uses it as the row title and the dialog title.
No format arguments follow it.

### Tests

Create `entry/src/test/ParityU09.test.ets` with `describe('U09', ...)` and test names without the prefix.
Each anchor is `entry/src/test/ParityU09.test.ets::U09#<name>`.

Add the import and the call to `entry/src/test/List.test.ets`.

Change the two `5453` values in `entry/src/test/Profile.test.ets` to `5450`.

### State and data

`store/settings.json` keeps the same file name and the same keys for the existing fields.
The new shape is this:

```json
{
  "probeUrl": "http://connectivitycheck.gstatic.com/generate_204",
  "speedTestUrl": "https://speed.cloudflare.com/__down?bytes=10000000",
  "serviceMode": "vpn",
  "proxyPort": "1080",
  "localDnsPort": "5450",
  "autoConnect": false,
  "shareOverLan": false
}
```

| Key | Type | Default | Writer | Reader |
| --- | --- | --- | --- | --- |
| `probeUrl` | string | `DEFAULT_PROBE_URL` | Settings page | Settings page, `Index` |
| `speedTestUrl` | string | `DEFAULT_SPEED_URL` | Settings page | Settings page, `Index` |
| `serviceMode` | string | `vpn` | Settings page | Settings page, `Index` |
| `proxyPort` | string | `1080` | Settings page | Settings page, `Index` |
| `localDnsPort` | string | `5450` | Settings page | Settings page, VPN extension |
| `autoConnect` | boolean | `false` | Settings page | Settings page |
| `shareOverLan` | boolean | `false` | Settings page | Settings page, `Index` |

Migration rules:

- A 5.3.5 file has a number in `proxyPort`. `settingsFromJson` converts it to decimal text.
- A missing `localDnsPort` becomes `'5450'`.
- A missing `autoConnect` becomes `false`.
- The next write from the Settings page stores the new text shape.

Page state:

| State | Type | Initial | Source | Lifetime |
| --- | --- | --- | --- | --- |
| `expanded` | boolean | `false` | Advanced tap | The page instance only |
| `serviceStopped` | boolean | `false` | 1 s poll | The page instance only |
| `autoConnect` | boolean | `false` | Store, switch | The page instance only |
| `serviceMode` | string | `vpn` | Store, menu | The page instance only |
| `proxyPort` | string | `1080` | Store, dialog OK | The page instance only |
| `localDnsPort` | string | `5450` | Store, dialog OK | The page instance only |
| `probeUrl` | string | `''` | Store, edits | The page instance only |
| `speedTestUrl` | string | `''` | Store, edits | The page instance only |
| `shareOverLan` | boolean | `false` | Store, switch | The page instance only |
| Port dialog draft | string | Row text at open | Input | The dialog lifetime |

The expansion state has no store key.
A new page instance starts collapsed.

Service state sources:

| Source | Producer | Use |
| --- | --- | --- |
| `store/vpn_status.json` | VPN extension | The VPN state and its timestamp |
| `store/traffic_stats.json` | VPN extension | The liveness of a running tunnel |
| `ProxyService.isRunning()` | UI process | The proxy mode state |

The page writes `settings.json` only.
The extension reads it.
The extension never writes it.

A write from one control stores the current page state of every field.
An unsaved edit in a URL field is stored by the next control write.
This keeps one writer path and one object shape.

### Validation and errors

| Condition | Behavior | Owner |
| --- | --- | --- |
| A port input contains a letter | `sanitizePortInput` drops the letter | `PortDialog` |
| A port input has more than five digits | The field keeps five digits | `PortDialog` |
| A stored port is empty | The row reads Not set and the read path uses the default | `portSummary`, `portNumber` |
| A stored port is below 1025 | The read path uses the default | `portNumber` |
| A stored port is above 65535 | The read path uses the default | `portNumber` |
| The user taps Cancel | The page writes nothing | `PortDialog` |
| The user taps OK with the current text | The page writes nothing | `applyPort` |
| A settings write fails | The page shows the save failed toast and restores the control | `persist` callers |
| The settings file is absent | The page writes the default object | `loadSeeded` |
| The settings file is unreadable | The page uses the defaults and does not write | `loadSeeded` |
| The settings file is corrupt | The page uses the defaults and does not write | `loadSeeded` |
| `serviceMode` holds an unknown string | The summary reads Not set and `Index` starts VPN mode | `serviceModeEntry`, `Index.connect` |
| The VPN status file is absent or corrupt | The first poll treats the service as stopped and unlocks the rows | `isServiceStopped` |
| The tunnel is starting or running with a recent status or a live sample | The service mode row and the port rows are locked | `isServiceStopped` |
| The proxy is running | The service mode row and the port rows are locked | `isServiceStopped` |
| The local DNS port is already in use | The core start fails and the extension records the failure with the core text | VPN extension |
| The local DNS port changes while the VPN runs | The change applies on the next start | Settings page |

The core validates the port at bind time.
The app does not probe the port before a start.

### Test plan

Each anchor is `entry/src/test/ParityU09.test.ets::U09#<name>`.
All planned tests are host unit tests.
They cover the pure functions and the two config serializers.
The dialog chrome, the page rendering, the file writes, and the poll need a device E2E run.

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| TC-U09-01, TC-U09-02 | `entry/src/test/ParityU09.test.ets` | `U09#collapsed-rows` | unit (host) |
| TC-U09-02, TC-U09-03 | `entry/src/test/ParityU09.test.ets` | `U09#expanded-rows` | unit (host) |
| TC-U09-02 | `entry/src/test/ParityU09.test.ets` | `U09#advanced-summary` | unit (host) |
| TC-U09-02 | `entry/src/test/ParityU09.test.ets` | `U09#no-expansion-key` | unit (host) |
| TC-U09-03, TC-U09-24 | `entry/src/test/ParityU09.test.ets` | `U09#mode-entry-mark` | unit (host) |
| TC-U09-17 | `entry/src/test/ParityU09.test.ets` | `U09#mode-default-and-unknown` | unit (host) |
| TC-U09-24 | `entry/src/test/ParityU09.test.ets` | `U09#settings-round-trip` | unit (host) |
| TC-U09-09, TC-U09-10, TC-U09-13 | `entry/src/test/ParityU09.test.ets` | `U09#port-text-unchanged` | unit (host) |
| TC-U09-11, TC-U09-12, TC-U09-13 | `entry/src/test/ParityU09.test.ets` | `U09#port-read-default` | unit (host) |
| TC-U09-12 | `entry/src/test/ParityU09.test.ets` | `U09#port-bounds` | unit (host) |
| TC-U09-13 | `entry/src/test/ParityU09.test.ets` | `U09#port-summary-unset` | unit (host) |
| TC-U09-14 | `entry/src/test/ParityU09.test.ets` | `U09#port-input-filter` | unit (host) |
| TC-U09-17 | `entry/src/test/ParityU09.test.ets` | `U09#settings-defaults` | unit (host) |
| TC-U09-17 | `entry/src/test/ParityU09.test.ets` | `U09#seed-missing-keys` | unit (host) |
| R-UI-27, R-UI-31 | `entry/src/test/ParityU09.test.ets` | `U09#legacy-number-port` | unit (host) |
| TC-U09-07, TC-U09-08 | `entry/src/test/ParityU09.test.ets` | `U09#rows-locked-when-running` | unit (host) |
| TC-U09-08 | `entry/src/test/ParityU09.test.ets` | `U09#rows-unlock-when-stale` | unit (host) |
| TC-U09-15 | `entry/src/test/ParityU09.test.ets` | `U09#dns-port-in-tun-config` | unit (host) |
| R-UI-32 | `entry/src/test/ParityU09.test.ets` | `U09#proxy-config-has-no-dns-gateway` | unit (host) |

These rules have no host anchor:

- The boot receiver rules R-UI-08, R-UI-10, and R-UI-11 need an Android component that HarmonyOS does not have.
- The direct boot rules R-UI-12 to R-UI-14 and R-UI-35 need Android device-protected storage.
- The dialog rules R-UI-25 and R-UI-27 need the page and the dialog on a device.
- The rebind rule R-UI-23 needs the main page and a device E2E run.

### Platform notes

- ArkUI has no `PreferenceFragment`, `EditTextPreference`, or `ListPreference`. The page uses rows, `bindMenu`, and a `CustomDialog`.
- HarmonyOS has no public startup subscriber for this app. The platform lists `BOOT_COMPLETED` and `STATIC_SUBSCRIBER`, but the ability class is not in the public SDK. The Auto Connect value is stored and not consumed. Unit U11 owns the boot decision.
- HarmonyOS has no direct boot storage and no per-user encryption state. The lock-screen row is absent and the store has no `directBootAware` key.
- HarmonyOS has no redsocks and no root redirection. The Transproxy entry and the Transproxy port are absent.
- HarmonyOS has no bound service class. `Index.onPageShow` reloads the settings and the next connect uses the new mode.
- The VPN mode has no local SOCKS5 listener. The core's smoltcp stack terminates the tun flows. The SOCKS5 port applies to proxy mode only.
- The Android port defaults add `Binder.getCallingUserHandle().hashCode()`. HarmonyOS has no equivalent index here. The defaults are 1080 and 5450.
- The local DNS port moves from the fixed 5453 in 5.3.5 to 5450. The tun e2e must run again on a Linux host with root or on a real device.
- The DNS local binds on loopback inside the extension process. A port conflict fails the start and does not fall back.
- The port field uses `InputType.Number`, `.maxLength(5)`, and `sanitizePortInput`. The device E2E run checks the caret position after a rejected character.
- The Settings page polls two JSON files per second while it shows. It stops on `onPageHide` and on `aboutToDisappear`.
- A `Toggle` can fire `onChange` when the bound state is set from the store. `toggleAutoConnect` ignores a value equal to the current state.
- Do not use `ForEach` for the settings rows. The row summary changes while the key does not, and the cached child would keep the old text.
- Every row uses the existing color tokens. Disabled titles use `text_secondary`. Every button carries its own `backgroundColor` and `fontColor`.
- The page calls `abilityContext()`. It does not declare a `context` property.
- The new strings are in both `resources/base` and `resources/zh_CN`.
- No manifest change and no new permission are needed.
- The share-over-LAN switch is a HarmonyOS extra. It is not part of the Android global settings list. It stays under the proxy details and follows the same gating.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| Q-U09-1 | Should the Auto Connect row show before unit U11 adds a startup hook? The row stores a value that nothing reads yet. | Product owner |
| Q-U09-2 | Should an unknown stored `serviceMode` block Connect, as the Android service bind throws, or fall back to VPN mode as planned? | Product owner, U01 owner |
| Q-U09-3 | Should the Transproxy entry appear disabled to keep the three-entry menu shape? The plan omits it. | Product owner |
| Q-U09-4 | Is 5450 approved as the local DNS default in place of the shipped 5453? The change moves the DNS gateway port of every tun start. | Product owner, platform owner |
| Q-U09-5 | Should the diagnostics fields move off the Settings page? They stay below the parity rows, so the collapsed view is not identical to the Android screen. | Product owner |

<a id="u10"></a>
## U10 QR and About

### Scope

This unit covers two areas.

1. The QR scanner. The unit decides how a profile arrives from a QR code and builds that path.
2. The About page. The unit shows the app version in the title, the license body, and the links.

In scope:

- The QR scan decision, the camera path, and the image import path.
- The import of scanned text into the profile store.
- The About title, body, links, and selectable text.
- The English and Chinese strings for the two areas.
- The host unit tests for the pure logic.

Out of scope:

- An in-app camera analyzer. The platform has no frame callback for a preview stream.
- A QR decoder written in ArkTS.
- A launcher shortcut for the scanner. U11 owns that surface.
- The Google Play open source license screen. HarmonyOS has no equivalent.
- The navigation drawer. U01 records the drawer as missing, and the About page keeps its Back control.

The rules covered are R-UJ-01 to R-UJ-28. The cases covered are TC-U10-01 to TC-U10-25.

### Files to change

| Path | Kind | Change |
| --- | --- | --- |
| `entry/src/main/ets/model/QrImport.ets` | new | Pure scan import: feature copy and URL grouping |
| `entry/src/main/ets/model/QrScanner.ets` | new | Platform adapter over `@kit.ScanKit` and the photo picker |
| `entry/src/main/ets/model/AboutLinks.ets` | new | Pure link classification, body split, title format, URL constants |
| `entry/src/main/ets/model/AboutOpener.ets` | new | Platform adapter that opens a web or mail link |
| `entry/src/main/ets/model/ProfilesFile.ets` | edit | Export the URL-only parser that the scanner uses |
| `entry/src/main/ets/pages/Index.ets` | edit | Scan and import actions, the shared profile write, two menu items |
| `entry/src/main/ets/pages/About.ets` | edit | Version title, body, links, scroll area |
| `entry/src/main/resources/base/element/string.json` | edit | New English strings |
| `entry/src/main/resources/zh_CN/element/string.json` | edit | New Chinese strings |
| `entry/src/test/ParityU10.test.ets` | new | Host unit tests for the pure logic |
| `entry/src/test/List.test.ets` | edit | Register the new spec |
| `docs/versions/5.4.0/machine/U10.json` | edit | Case parity tags |
| `docs/versions/5.4.0/e2e/U10.md` | edit | Case parity tags |

The application code changes 9 files. The tests change 2 files. The parity records change 2 files.

`entry/src/main/module.json5` does not change. The app does not request `ohos.permission.CAMERA`, because the system scanner owns the camera.

`entry/src/main/resources/base/profile/main_pages.json` does not change. The unit adds no page.

### Implementation plan

### D-U10-01: Use the system Scan Kit. Do not ship a decoder.

The OpenHarmony public SDK has no barcode decoder. The installed HarmonyOS SDK exposes `@kit.ScanKit` from `sdk/default/hms/ets/kits/@kit.ScanKit.d.ts`. It gives two functions that cover the unit.

1. `scanBarcode.startScanForResult(context, options)` opens the system scanning UI. The UI owns the camera preview, the camera permission, the up action, and the album entry. The system pre-grants the camera to that UI. The app does not request the permission.
2. `detectBarcode.decode({ uri }, options)` reads one code from an image URI. The photo picker returns such URIs.

Consequences:

- No `pages/QrScan.ets` is added. The scanner screen is the system UI.
- No camera frame analyzer is written. R-UJ-05 is system behavior.
- No barcode decoder is written.
- The app imports the returned text through the same parser that the `ss://` link import uses.
- If Scan Kit is absent or fails, the page reports a failure. The text, clipboard, and link import paths still work.

This decision answers open architecture question AQ-3 with "yes, the system scanner is the external scanner". The product owner confirms the HMS dependency. See OQ-U10-1.

### `entry/src/main/ets/model/QrImport.ets`

This file is pure ArkTS. It imports only `Profile` and `parseProfileUrls`, so the host specs can run it.

Types and functions:

- `export function copyFeatureSettings(target: Profile, current: Profile | null): void`
  - Return when `current` is `null`.
  - Copy `route`, `ipv6`, `udpdns`, and `remoteDns` from `current` to `target`.
  - Do not copy `id`, `name`, `host`, `remotePort`, `password`, `method`, `plugin`, `pluginOpts`, `udpFallbackId`, `subscriptionId`, counters, or order.
  - Comment: `metered` and `proxy_apps` are not fields of the HarmonyOS `Profile`. `exportProfiles` writes both as false. U07 owns the per-app model.
- `export function profilesFromScan(text: string, current: Profile | null): Profile[]`
  - Call `parseProfileUrls(text)`. This parser accepts `ss://` URLs only, as the Android analyzer does.
  - Call `copyFeatureSettings` for each profile.
  - Return the profiles in text order.
  - A malformed URL is dropped by `Profile.parseUrl`. The other URLs still import.
- `export function profilesFromScanTexts(texts: string[], current: Profile | null): Profile[]`
  - Concatenate `profilesFromScan(text, current)` for each text, in array order.
  - The page uses this for a batch of images.

### `entry/src/main/ets/model/QrScanner.ets`

This file is the platform adapter. It imports `common` from `@kit.AbilityKit`, `scanBarcode`, `scanCore`, and `detectBarcode` from `@kit.ScanKit`, `photoAccessHelper` from `@kit.MediaLibraryKit`, and `BusinessError` from `@kit.BasicServicesKit`.

Constants:

- `const SCAN_CANCELLED: number = 1000500002;` This is the documented Scan Kit cancel code.
- `const MAX_IMAGES: number = 20;` The upper bound for one image batch.

Types:

- `export interface ScanText { text: string; cancelled: boolean; }`
- `export interface ImageScan { texts: string[]; error: string; }`

Functions:

- `export async function scanWithSystemUi(context: common.Context): Promise<ScanText>`
  - Build `const options: scanBarcode.ScanOptions = { scanTypes: [scanCore.ScanType.QR_CODE], enableMultiMode: false, enableAlbum: true };`
  - Call `scanBarcode.startScanForResult(context, options)`.
  - Return `{ text: result.originalValue, cancelled: false }`.
  - Catch a `BusinessError` with code `SCAN_CANCELLED` and return `{ text: '', cancelled: true }`.
  - Rethrow every other error.
- `export async function pickQrImages(): Promise<string[]>`
  - Build `const options = new photoAccessHelper.PhotoSelectOptions();`.
  - Set `options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;`.
  - Set `options.maxSelectNumber = MAX_IMAGES;`.
  - Call `new photoAccessHelper.PhotoViewPicker().select(options)`.
  - Return `result.photoUris`.
- `export async function decodeQrImages(uris: string[]): Promise<ImageScan>`
  - For each URI, call `detectBarcode.decode({ uri }, { scanTypes: [scanCore.ScanType.QR_CODE] })`.
  - Append `found[0].originalValue` when the array is not empty.
  - Catch an error for one URI. Keep the first readable message in `error` and continue with the next URI. This matches Android, which tries every chosen image.
  - Return `{ texts, error }`.

### `entry/src/main/ets/model/ProfilesFile.ets`

- Rename the private `profilesFromUrls` function to `export function parseProfileUrls(text: string): Profile[]`.
- Keep its behavior. Split on whitespace, keep tokens that start with `ss://`, call `Profile.parseUrl`, and drop null results.
- Update `parseProfilesText` to call `parseProfileUrls`.
- Update the comment. The scanner uses this function because Android imports only `ss://` URLs from a scan.

### `entry/src/main/ets/pages/Index.ets`

New imports:

- `profilesFromScan`, `profilesFromScanTexts` from `../model/QrImport`.
- `decodeQrImages`, `pickQrImages`, `scanWithSystemUi` from `../model/QrScanner`.

New state:

- `@State scanning: boolean = false;` It guards one scan or image batch at a time.

Refactor:

- `private async applyProfiles(imported: Profile[], replace: boolean): Promise<number>`
  - Return `0` when `imported.length === 0`.
  - Read `ProfileStore.getAll(context)`, call `applyImport(existing, imported, replace)`, and write the result with `ProfileStore.saveAll`.
  - Set the current id to the first profile when the store has no current id.
  - Call `this.reload()`.
  - Return `imported.length`.
  - The method shows no toast. The caller owns the message.
- `private async importText(text: string, source: ResourceStr, replace: boolean = false): Promise<void>`
  - Keep the current behavior.
  - Parse with `parseProfilesText`.
  - Show `index_nothing_to_import` when the parse is empty.
  - Call `applyProfiles` and show `index_imported_n` or `index_replaced_n` when the count is not zero.

New methods:

- `private async scanQrCode(): Promise<void>`
  - Return when `this.scanning` is true.
  - Set `this.scanning = true`.
  - Loop: call `scanWithSystemUi(abilityContext())`.
  - On a cancel, end the loop with no message.
  - On a result, call `profilesFromScan(result.text, this.currentProfile())`.
  - When the array is not empty, call `applyProfiles(profiles, false)` and end the loop. Show no message.
  - When the array is empty, open the scanner again. Stop after three empty results and show `qr_no_profiles`.
  - Catch every other error and call `reportFailure($r('app.string.index_op_scan'), e as Object)`.
  - Clear `this.scanning` in `finally`.
- `private async importQrImages(): Promise<void>`
  - Call `pickQrImages()`.
  - Return with no message when the URI list is empty.
  - Call `decodeQrImages(uris)`.
  - Call `profilesFromScanTexts(decoded.texts, this.currentProfile())` and `applyProfiles(profiles, false)`.
  - When `decoded.error` is not empty, show that message in a long toast (`duration: 3000`) and stop. The readable images are already imported, as Android does.
  - Otherwise show `qr_import_success` when the count is not zero, and `qr_import_failed` when it is zero.
  - Catch an error and call `reportFailure($r('app.string.index_op_import'), e as Object)`.

Menu:

- Add two `MenuItem` entries at the top of `AddMenu()`.
  - `$r('app.string.index_scan_qr_code')` calls `this.scanQrCode()`.
  - `$r('app.string.index_import_qr_image')` calls `this.importQrImages()`.
- U02 owns the Android control C-U02-004, "Scan QR code". If the U02 change adds that item first, U10 only supplies the handler and the string. Do not add a second item.

### `entry/src/main/ets/model/AboutLinks.ets`

This file is pure ArkTS. It imports nothing, so the host specs can run it.

Constants:

- `export const ABOUT_LINK_WEB: string = 'web';`
- `export const ABOUT_LINK_EMAIL: string = 'email';`
- `export const ABOUT_LINK_OSS: string = 'oss';`
- `export const ABOUT_URL_SHADOWSOCKS: string = 'http://shadowsocks.org';`
- `export const ABOUT_URL_GNU: string = 'http://www.gnu.org/licenses/';`
- `export const ABOUT_MAIL_MAX_LV: string = 'mailto:max.c.lv@gmail.com';`
- `export const ABOUT_MAIL_MYGOD: string = 'mailto:contact-shadowsocks-android@mygod.be';`
- `export const ABOUT_LICENCE_URLS: string[]` with the seven URLs from `mobile/src/main/res/raw/about.html`, in order:
  1. `https://github.com/shadowsocks/redsocks/blob/shadowsocks-android/README`
  2. `https://github.com/shadowsocks/libevent/blob/master/LICENSE`
  3. `https://github.com/shadowsocks/badvpn/blob/shadowsocks-android/COPYING`
  4. `https://github.com/shadowsocks/shadowsocks-rust/blob/master/LICENSE`
  5. `https://github.com/jedisct1/libsodium/blob/master/LICENSE`
  6. `https://www.openssl.org/source/license-openssl-ssleay.txt`
  7. `#other-licenses`

Functions:

- `export function classifyAboutLink(url: string): string`
  - A value that starts with `#` returns `ABOUT_LINK_OSS`.
  - A value that starts with `mailto:` returns `ABOUT_LINK_EMAIL`.
  - Every other value returns `ABOUT_LINK_WEB`.
- `export function aboutTitle(appName: string, version: string): string`
  - Return `appName + ' ' + version` when `version.length > 0`.
  - Return `appName` when the version is empty.
- `export function splitAboutBody(text: string): string[]`
  - Split on one blank line: `text.split(/\n\s*\n/)`.
  - Trim each block and drop an empty block.
  - Return the remaining blocks in order. An empty text returns an empty array.

### `entry/src/main/ets/model/AboutOpener.ets`

This file is the platform adapter for links.

- Imports: `common` and `Want` from `@kit.AbilityKit`, `hilog` from `@kit.PerformanceAnalysisKit`, and `ABOUT_LINK_EMAIL`, `ABOUT_LINK_OSS`, `classifyAboutLink` from `./AboutLinks`.
- `export const ABOUT_OPENED: string = 'opened';`
- `export const ABOUT_NO_HANDLER: string = 'no_handler';`
- `export const ABOUT_UNSUPPORTED: string = 'unsupported';`
- `export async function openAboutLink(context: common.UIAbilityContext, url: string): Promise<string>`
  - Return `ABOUT_UNSUPPORTED` when `classifyAboutLink(url)` is `ABOUT_LINK_OSS`.
  - Build a `Want`:
    - For `ABOUT_LINK_EMAIL`, `{ action: 'ohos.want.action.sendToData', uri: url }`.
    - Otherwise, `{ action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: url }`.
  - Call `context.startAbility(want)`.
  - Return `ABOUT_OPENED`.
  - Catch the error, log it with `hilog.warn`, and return `ABOUT_NO_HANDLER`.

The action strings are the documented Want actions `ACTION_SEND_TO_DATA` and `ACTION_VIEW_DATA`. The literal strings keep the code compatible with API 12.

### `entry/src/main/ets/pages/About.ets`

New imports:

- `promptAction` from `@kit.ArkUI`.
- `abilityContext` from `../model/AppContext`.
- `aboutTitle`, `splitAboutBody`, and the URL constants from `../model/AboutLinks`.
- `ABOUT_NO_HANDLER`, `ABOUT_UNSUPPORTED`, `openAboutLink` from `../model/AboutOpener`.

New state:

- `@State paragraphs: string[] = [];`

New helpers:

- `private text(value: ResourceStr): string` resolves a resource through `abilityContext().resourceManager.getStringSync(value.id)`. Copy the helper from `Index.ets`.
- `private title(): string` returns `aboutTitle(this.text($r('app.string.app_name')), this.versions.app)`.
- `private async follow(url: string): Promise<void>`
  - Call `openAboutLink(abilityContext(), url)`.
  - On `ABOUT_NO_HANDLER`, show a toast with the raw URL. This is the R-UJ-25 fallback.
  - On `ABOUT_UNSUPPORTED`, show `about_other_licences_unavailable`.

`aboutToAppear`:

- Keep `this.versions = AboutPage.read();`.
- Build the body text as `this.text($r('app.string.about_about_text')) + '\n\n' + this.text($r('app.string.about_body_notice'))`.
- Set `this.paragraphs = splitAboutBody(bodyText)`.

Top-level row arrays:

- `interface AboutRow { label: ResourceStr; url: string; }`
- `const ABOUT_LINKS: AboutRow[]` with four rows: Shadowsocks, Max Lv, Mygod Studio, GNU licenses.
- `const ABOUT_LICENCES: AboutRow[]` with seven rows. The labels are `about_link_redsocks`, `about_link_libevent`, `about_link_tun2socks`, `about_link_shadowsocks_rust`, `about_link_libsodium`, `about_link_openssl`, and `about_link_other`. The URLs come from `ABOUT_LICENCE_URLS`.

Build:

- Replace the header title `Text($r('app.string.about_about'))` with `Text(this.title())`. Keep the Back control and the centered layout.
- Change the first version line label to `about_app_version`.
- Keep the native core line and the license line.
- Wrap the body in `if (this.paragraphs.length > 0)`.
- Put the body in a `Scroll` with `layoutWeight(1)`.
- Render each paragraph as a `Text` with `copyOption(CopyOptions.LocalDevice)` and `fontColor($r('app.color.text_body'))`.
- Render each link row through a `@Builder LinkRow(label: ResourceStr, url: string)`. The text uses `$r('app.color.accent')`, `copyOption(CopyOptions.LocalDevice)`, and `onClick(() => this.follow(url))`.
- Render the heading `about_heading_licences` as bold text.
- Render the seven license rows through the same builder.
- Keep the page background `$r('app.color.background')` and the 16 vp padding. Add 16 vp bottom padding inside the scroll content, so the last line clears the navigation bar.

### Strings

Add these names to `resources/base/element/string.json` and `resources/zh_CN/element/string.json`.

| Name | English |
| --- | --- |
| `index_scan_qr_code` | Scan QR code |
| `index_import_qr_image` | Import QR image |
| `index_op_scan` | QR scan |
| `qr_no_profiles` | No profile found in this code. |
| `qr_import_success` | Successfully import! |
| `qr_import_failed` | Failed to import. |
| `about_app_version` | App version |
| `about_body_notice` | Copyright and GNU GPL paragraphs |
| `about_heading_licences` | Open Source Licenses |
| `about_link_shadowsocks` | Shadowsocks |
| `about_link_max_lv` | max.c.lv@gmail.com |
| `about_link_mygod` | contact-shadowsocks-android@mygod.be |
| `about_link_gnu` | http://www.gnu.org/licenses/ |
| `about_link_redsocks` | redsocks: APL 2.0 |
| `about_link_libevent` | libevent: BSD |
| `about_link_tun2socks` | tun2socks: BSD |
| `about_link_shadowsocks_rust` | shadowsocks-rust: MIT |
| `about_link_libsodium` | libsodium: ISC |
| `about_link_openssl` | OpenSSL: OpenSSL License |
| `about_link_other` | Other licenses |
| `about_other_licences_unavailable` | The other license list is not available on this device. |

`about_body_notice` holds the two copyright lines, the GPL grant paragraph, the warranty paragraph, and the "You should have received" paragraph from `about.html`. Separate the paragraphs with a blank line.

`qr_import_success` and `qr_import_failed` keep the Android text exactly, including the grammar.

The strings use three dot-separated parts. The existing `about_licence` and `about_licence_value` names stay.

### Tests

- Add `import parityU10Test from './ParityU10.test';` and `parityU10Test();` to `entry/src/test/List.test.ets`.
- The spec imports only `QrImport.ets` and `AboutLinks.ets`. Those two files import no `@kit` module, so the host runner needs no new stub.

### State and data

No new persistent store and no new JSON field.

| Data | Owner | Lifetime |
| --- | --- | --- |
| `store/profiles.json` | `ProfileStore` | Across restarts. Scanned profiles are written here through `applyImport` and `saveAll`. |
| `@State scanning` | `Index` | One scan or image batch |
| `@State paragraphs`, `@State versions` | `About` | One page visit |

Scanner phases:

| Phase | Enter | Exit |
| --- | --- | --- |
| idle | The page is shown | The user taps Scan QR code or Import QR image |
| scanning | `scanWithSystemUi` is called | A result, a cancel, or an error |
| picking | `pickQrImages` is called | An image list or an empty list |
| decoding | `decodeQrImages` runs | One text per readable image |
| importing | `applyProfiles` runs | The store write ends |

The `scanning` flag covers the four active phases. A second tap returns at once.

Import rules:

- `profilesFromScan` accepts `ss://` URLs only. It keeps text order.
- `copyFeatureSettings` copies `route`, `ipv6`, `udpdns`, and `remoteDns` from the current profile.
- The scanned host, name, port, password, method, plugin, and plugin options always win.
- `applyImport` assigns the id and order and clears the subscription id.
- A profile with the same address is not merged. A scan appends, as Android appends.

About data:

- The title is the app name plus the bundle `versionName`. `AppScope/app.json5` holds `5.3.5`.
- The body comes from two string resources. `splitAboutBody` turns the text into paragraphs.
- The link rows are static. The URLs are constants in `AboutLinks.ets`.

### Validation and errors

| Condition | Detection | Result |
| --- | --- | --- |
| The decoded text holds no `ss://` URL | `profilesFromScan` returns an empty array | Reopen the scanner. After three empty results, show `qr_no_profiles`. No store write. |
| The decoded text holds a malformed URL | `Profile.parseUrl` returns null | Skip that URL. Import the other URLs. |
| The user cancels the scanner | `BusinessError` code `1000500002` | End with no message. |
| Scan Kit is missing or fails | Any other error | `reportFailure` shows "QR scan failed". |
| The user cancels the photo picker | `photoUris` is empty | End with no message. |
| An image holds no code | `detectBarcode.decode` returns an empty array | That image adds no text. The other images still import. |
| An image cannot be read | `detectBarcode.decode` rejects | Show the first message in a 3000 ms toast. Do not show the success or failure toast. The readable images are still imported. |
| The store write fails | `ProfileStore.saveAll` rejects | `reportFailure` shows "Import failed". |
| A web or mail link has no handler | `startAbility` rejects | Show the raw URL in a toast. |
| The `#other-licenses` link is tapped | `classifyAboutLink` returns `ABOUT_LINK_OSS` | Show `about_other_licences_unavailable`. |
| The bundle version read fails | `bundleManager` throws | The title shows the app name. The version line is empty. |
| The core version read fails | `sslocal.version` throws | The core line is empty. |

The scan cancel is not an error. It writes no message and no store entry.

The About link failure shows the raw URL. This is the R-UJ-25 fallback, moved from a snackbar to a toast.

### Test plan

All planned tests are host unit tests. They run with `./test-arkts-host.sh`, which needs no HarmonyOS SDK. The spec file uses `describe('U10', ...)`, so each anchor is `entry/src/test/ParityU10.test.ets::U10#<name>`.

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| U10-01 | `entry/src/test/ParityU10.test.ets` | `U10#scanCreatesProfilesInTextOrder` | unit |
| U10-02 | `entry/src/test/ParityU10.test.ets` | `U10#scanCreatesProfilePerOccurrence` | unit |
| U10-03 | `entry/src/test/ParityU10.test.ets` | `U10#scanSkipsMalformedUrl` | unit |
| U10-04 | `entry/src/test/ParityU10.test.ets` | `U10#scanReturnsNothingForPlainText` | unit |
| U10-05 | `entry/src/test/ParityU10.test.ets` | `U10#scanCopiesFeatureSettings` | unit |
| U10-06 | `entry/src/test/ParityU10.test.ets` | `U10#scanKeepsScannedHostAndName` | unit |
| U10-07 | `entry/src/test/ParityU10.test.ets` | `U10#scanKeepsScannedPlugin` | unit |
| U10-08 | `entry/src/test/ParityU10.test.ets` | `U10#scanWithoutCurrentKeepsDefaults` | unit |
| U10-09 | `entry/src/test/ParityU10.test.ets` | `U10#batchImportsEveryDecodedImage` | unit |
| U10-10 | `entry/src/test/ParityU10.test.ets` | `U10#batchReturnsNothingWithoutUrls` | unit |
| U10-11 | `entry/src/test/ParityU10.test.ets` | `U10#aboutTitleJoinsNameAndVersion` | unit |
| U10-12 | `entry/src/test/ParityU10.test.ets` | `U10#aboutTitleOmitsMissingVersion` | unit |
| U10-13 | `entry/src/test/ParityU10.test.ets` | `U10#classifiesWebLink` | unit |
| U10-14 | `entry/src/test/ParityU10.test.ets` | `U10#classifiesMailtoLink` | unit |
| U10-15 | `entry/src/test/ParityU10.test.ets` | `U10#classifiesOssLink` | unit |
| U10-16 | `entry/src/test/ParityU10.test.ets` | `U10#splitsAboutBodyIntoParagraphs` | unit |
| U10-17 | `entry/src/test/ParityU10.test.ets` | `U10#dropsEmptyAboutBody` | unit |
| U10-18 | `entry/src/test/ParityU10.test.ets` | `U10#licenceLinksFollowAboutHtml` | unit |

Test contents:

- `scanCreatesProfilesInTextOrder` scans `#One` then `#Two` and asserts the host and name order.
- `scanCreatesProfilePerOccurrence` scans the same URL twice and asserts two profiles.
- `scanSkipsMalformedUrl` scans a malformed `ss://%%%@bad.example:8388` line and a valid line. It asserts one profile with the valid host.
- `scanReturnsNothingForPlainText` scans `hello world` and asserts an empty array.
- `scanCopiesFeatureSettings` sets `bypass-lan`, IPv6 on, UDP DNS on, and a remote DNS on the current profile. It asserts all four values on the scanned profile.
- `scanKeepsScannedHostAndName` uses a current profile with another host and name. It asserts the scanned host and `#Scanned` name. It also scans a URL without a fragment and asserts the host becomes the name.
- `scanKeepsScannedPlugin` scans a URL with `?plugin=v2ray-plugin%3Bmode%3Dwebsocket` and asserts the plugin and options survive the feature copy.
- `scanWithoutCurrentKeepsDefaults` passes `null` and compares the fields with a fresh `new Profile()`.
- `batchImportsEveryDecodedImage` passes two texts. The first holds two URLs and the second holds plain text. It asserts two profiles.
- `batchReturnsNothingWithoutUrls` passes two plain texts and asserts an empty array.
- `aboutTitleJoinsNameAndVersion` asserts `Shadowsocks 5.3.5`.
- `aboutTitleOmitsMissingVersion` asserts `Shadowsocks`.
- `classifiesWebLink` asserts `http://shadowsocks.org` and an `https` URL return `ABOUT_LINK_WEB`.
- `classifiesMailtoLink` asserts a `mailto:` URL returns `ABOUT_LINK_EMAIL`.
- `classifiesOssLink` asserts `#other-licenses` returns `ABOUT_LINK_OSS`.
- `splitsAboutBodyIntoParagraphs` asserts three trimmed paragraphs from a text with blank lines.
- `dropsEmptyAboutBody` asserts an empty array for `''` and for a text of blank lines.
- `licenceLinksFollowAboutHtml` asserts seven URLs, the last one `#other-licenses`, and the OpenSSL file name.

The E2E journey oracle stays `entry/src/ohosTest/ets/test/ParityE2e.test.ets::U10Journey#flow`. The scanner UI and the link handlers need a real device. The host tests cover the import rules, not the system UI.

### Platform notes

- Scan Kit is an HMS kit. It is not in the OpenHarmony public SDK. The installed HarmonyOS SDK provides it under `sdk/default/hms`. The build product sets `runtimeOS: 'HarmonyOS'`, so the compiler resolves `@kit.ScanKit`.
- The OpenHarmony emulator image has no HMS. A static import of `@kit.ScanKit` may fail to load there. Verify the app on the emulator before the merge. If the import fails, move the two Scan Kit calls behind a dynamic import or a device-only module. See OQ-U10-2.
- The system scanner pre-grants the camera to its own UI. The app adds no `ohos.permission.CAMERA` and no permission prompt. R-UJ-01 and R-UJ-02 become system behavior.
- The system scanner owns the preview, the back and front camera choice, and the frame handling. R-UJ-05 is not app code.
- The system mail chooser controls its own title. The app cannot set "Send email".
- HarmonyOS has no Google Play open source license screen. The `#other-licenses` row stays visible for display parity and shows a message on tap.
- The About page keeps a Back control. U01 records the navigation drawer as missing, so C-U10-015 has no counterpart.
- ArkUI lays the page out above the navigation bar. The scroll content adds 16 vp bottom padding. Verify TC-U10-25 on a three-button device.
- A `Text` needs an explicit `fontColor` when it sits on a colored surface. The body uses `text_body`, the links use `accent`.
- The body text is selectable through `copyOption(CopyOptions.LocalDevice)`. This is the HarmonyOS equivalent of the selectable Android view.
- The `#` and `mailto:` tests on the host cover classification only. The `startAbility` calls need a device.

Case disposition after this unit:

| Cases | Result |
| --- | --- |
| TC-U10-01, 02, 07, 08, 09, 11, 14, 15, 16, 17, 19, 20, 22 | implemented |
| TC-U10-03, 12, 21, 23 | partial |
| TC-U10-04, 05, 06, 10, 13, 18, 24 | android-only or not portable |

The parity tags change in `docs/versions/5.4.0/machine/U10.json` and `docs/versions/5.4.0/e2e/U10.md`.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| OQ-U10-1 | Does the product owner accept the HMS Scan Kit as the external scanner for AQ-3? If not, the scan and image import cases stay blocked. | Product owner |
| OQ-U10-2 | Does the OpenHarmony emulator load a HAP that statically imports `@kit.ScanKit`? If not, use a dynamic import or a device-only module. | HarmonyOS platform owner |
| OQ-U10-3 | Does `photoAccessHelper.PhotoViewPicker.select` return an empty list or reject when the user cancels? The plan assumes an empty list. | HarmonyOS platform owner |
| OQ-U10-4 | Does `detectBarcode.decode` return an empty array or reject for an image with no code? The plan treats a rejection as an error toast. | HarmonyOS platform owner |
| OQ-U10-5 | TC-U10-14 expects `Shadowsocks 5.3.5-nightly`. The HarmonyOS bundle reports `5.3.5`. Confirm the expected text for the case. | Requirements owner |
| OQ-U10-6 | Should the "Other licenses" row stay visible when its target is unavailable? The plan keeps it for display parity and shows a message on tap. | Product owner |

<a id="u11"></a>
## U11 System surfaces

### Scope

This document is the low-level design (LLD) for unit U11 of the HarmonyOS 5.4.0 parity batch.
U11 covers the system surfaces: the connection notification, the Quick Settings tile, launcher shortcuts, start at boot, and Tasker.
It follows the contracts in `../hld.md`, especially C-07 Notification.

The text uses these abbreviations:

- application programming interface (API)
- software development kit (SDK)
- user interface (UI)
- virtual private network (VPN)
- quick response (QR) code
- GNU General Public License version 3 (GPL-3.0)
- identifier (ID)

In scope:

- Notification content. The title becomes the profile name. The body shows the rates. The second line shows the session totals.
- Notification actions. A body tap opens the main screen. The Stop action keeps the current ability-based stop path.
- Screen state. The notification stops updating while the screen is off and resumes when the screen is on.
- A start without a profile. The extension posts a starting notification and removes it on failure.
- The notification slot. The notification uses the low-priority content slot.

Out of scope:

- The Quick Settings tile. The public SDK has no tile API. This unit records the decision.
- Launcher shortcuts. Static shortcuts start at API 20. The Scan QR code shortcut needs a decoder. This unit records the decision.
- Start at boot. The public SDK has no static subscriber ability class. This unit records the decision.
- Tasker and Locale. HarmonyOS has no equivalent host. This unit records the decision.
- Direct boot storage. HarmonyOS has no Android device-protected storage split.
- Notification channels per service mode. HarmonyOS uses one app-level slot.
- Proxy mode notifications. The system continuous-task notification remains.

### Files to change

| File | Change |
| --- | --- |
| `entry/src/main/ets/model/NotificationContent.ets` | New. Pure content and traffic logic for the notification. |
| `entry/src/main/ets/model/ConnectionNotification.ets` | Add the body tap agent, the starting notification, the slot type, and the totals line. |
| `entry/src/main/ets/vpnability/SsVpnExtensionAbility.ets` | Post the notification at start, clear it on failure, and gate the traffic line on the screen state. |
| `entry/src/main/ets/entryability/EntryAbility.ets` | Bring the main screen forward on the notification body tap. |
| `entry/src/main/resources/base/element/string.json` | Add the notification Stop label. |
| `entry/src/main/resources/zh_CN/element/string.json` | Add the notification Stop label. |
| `entry/src/test/ParityU11.test.ets` | New. Host specs for the pure notification logic. |
| `entry/src/test/List.test.ets` | Register the new spec suite. |

No change to `entry/src/main/module.json5`. The notification APIs in this plan need no new permission.
No change to `entry/src/main/ets/model/ProxyService.ets`. Proxy mode keeps the system continuous-task notification.
No change to `entry/src/main/ets/pages/Index.ets`. The page already calls `ensureEnabled` before both connect paths.

### Implementation plan

### 1. `model/NotificationContent.ets` (new)

Add the GPL-3.0 header block used by the other ArkTS files.
Add no kit imports. The host test runner loads this module directly.

Add these types:

```ts
export interface TrafficSample { tx: number; rx: number; at: number; }
export interface TrafficRates { up: number; down: number; }
export interface TrafficUpdate { sample: TrafficSample; rates: TrafficRates; publish: boolean; }
export interface NotificationText { title: string; text: string; totals: string; }
```

Add these functions:

- `notificationTitle(profileName: string, appName: string): string`
  - Return `profileName` when it is not empty.
  - Return `appName` otherwise.
- `notificationText(profileName: string, appName: string, fallbackText: string, rates: string, totals: string): NotificationText`
  - Set the title from `notificationTitle`.
  - Set the text to `rates` when `rates` is not empty.
  - Set the text to `fallbackText` when `rates` is empty and `fallbackText` is not empty.
  - Set the text to `appName` when both are empty.
  - Pass `totals` through unchanged.
- `trafficUpdate(previous: TrafficSample, tx: number, rx: number, now: number, screenActive: boolean): TrafficUpdate`
  - When `screenActive` is false, return `{ sample: { tx: -1, rx: -1, at: 0 }, rates: { up: 0, down: 0 }, publish: false }`.
  - When `previous.tx < 0`, `previous.rx < 0`, `previous.at <= 0`, or `now <= previous.at`, return the new sample with zero rates and `publish: false`.
  - Otherwise compute `up = max(0, (tx - previous.tx) * 1000 / (now - previous.at))`.
  - Compute `down` in the same way.
  - Return the new sample, the two rates, and `publish: true`.

The screen-off branch clears the baseline.
This mirrors the Android behavior that unregisters the traffic callback on screen off and registers it again on screen on.

### 2. `model/ConnectionNotification.ets`

Add the content intent constant:

```ts
export const ACTION_OPEN = 'com.xbt.project.open';
```

Add the cached body-tap agent:

- Add `let cachedOpenAgent: WantAgent | undefined = undefined;`.
- Add `async function openAgent(): Promise<WantAgent>`.
- Build one want with `bundleName: BUNDLE`, `abilityName: ENTRY_ABILITY`, and `action: ACTION_OPEN`.
- Set `actionType` to `wantAgent.OperationType.START_ABILITY`.
- Set `requestCode` to 1. The disconnect agent keeps request code 0.
- Set `actionFlags` to `[wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]`.
- Cache the result and return it.

Add a private publish helper:

- `async function publish(context: common.Context, title: string, text: string, totals: string): Promise<void>`
- Build a `notificationManager.NotificationRequest` with these fields:
  - `id: NOTIFICATION_ID`, which stays 1.
  - `content.notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT`.
  - `content.normal: { title, text, additionalText: totals }`.
  - `wantAgent` from `openAgent()`. When the agent call fails, log a warning and omit the field.
  - `tapDismissed: false`. This keeps the notification after a body tap.
  - `isOngoing: true`.
  - `notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION`.
  - `actionButtons`: one button in a `notificationManager.NotificationActionButton[]`. Its title is `$r('app.string.notification_stop')`. Its agent comes from `disconnectAgent()`. When the agent call fails, send an empty array.
- Publish in a try/catch. Log a warning on failure. Do not throw.

Add the starting notification:

- `export async function showStarting(context: common.Context): Promise<void>`
- Resolve `app_name` and `index_connecting` from `context.resourceManager`.
- Call `publish` with the app name as the title, the connecting label as the text, and an empty totals string.

Change `showConnected`:

- Signature: `showConnected(context: common.Context, profileName: string, detail: ResourceStr = '', totals: ResourceStr = '')`.
- Resolve `app_name` and `index_connected` from `context.resourceManager`.
- Call `notificationText(profileName, appName, connectedLabel, resolve(context, detail), resolve(context, totals))`.
- Call `publish` with the three returned fields.

Change the action button title from `index_disconnect` to `notification_stop`.
Keep `ensureEnabled`, `clear`, `disconnectAgent`, `resolve`, and `NOTIFICATION_ID`.
Remove the comment that says the slot type cannot be set. The request now sets `notificationSlotType`.

The notification actions are:

- Body tap. The `wantAgent` field starts `EntryAbility` with `ACTION_OPEN`.
- Stop. The action button starts `EntryAbility` with `ACTION_DISCONNECT`. `EntryAbility` stops the extension, waits for its teardown, settles the session counters, and only then returns. The extension clears the notification in `onDestroy`.

### 3. `vpnability/SsVpnExtensionAbility.ets`

Change the imports:

- Change the BasicServicesKit import to `import { BusinessError, power } from '@kit.BasicServicesKit';`.
- Change the ConnectionNotification import to `import { clear as clearNotification, showConnected, showStarting } from '../model/ConnectionNotification';`.
- Change the TrafficStats import to include `formatBytes`.
- Add `import { TrafficSample, trafficUpdate } from '../model/NotificationContent';`.

Change the fields:

- Remove `lastSampleTx`, `lastSampleRx`, and `lastSampleAt`.
- Add `private sample: TrafficSample = { tx: -1, rx: -1, at: 0 };`.
- Keep `lastNotificationAt`.

Change `onCreate`:

- After `ProfileStore.getCurrent`, keep the null and empty-host check.
- In that failure branch, call `await showStarting(this.context);` first.
- Then call the existing `VpnStatusStore.markFailed` with the text "No profile configured".
- Then call `await clearNotification();` and return.
- After `VpnStatusStore.markStarting`, call `await showConnected(this.context, profile.name, $r('app.string.index_connecting'));`.
  This posts the notification before the VPN interface is created, as Android does.
- Keep the existing success-path `await showConnected(this.context, profile.name);`.
  The text falls back to "Connected".
- Before `VpnStatusStore.markRunning`, wait until the core reports its first traffic sample (5 s budget). With no stat endpoint, wait 1.5 s. If the endpoint exists but no report comes, wait the same 5 s budget. A fallback requires a live instance with no new native error and records the session with the heartbeat (`stats` false). A failed wait writes `failed` with the running profile id.

Change `teardown`:

- Add `await clearNotification();` as the first statement.
- Keep the rest of the method. The status file stays untouched, as `VpnStatusStore` requires.
- Do not clear the traffic record. Only the UI process marks it settled, after it added the counters; the next session overwrites it.

Change `watchCoreLiveness`:

- In the failure branch, after `markFailed`, call `clearNotification().catch(() => {})`.
  A dead core must not leave a notification behind.

Change `updateNotification(tx, rx, now)`:

- Read the screen state. Wrap `power.isActive()` in a try/catch. Use `true` when the call throws.
- Call `trafficUpdate(this.sample, tx, rx, now, screenActive)`.
- Assign `this.sample = update.sample`.
- Return when `update.publish` is false.
- Return when `now - this.lastNotificationAt < NOTIFICATION_INTERVAL_MS`.
- Set `this.lastNotificationAt = now`.
- Call `showConnected` with these arguments:
  - `this.runningProfileName`.
  - `$r('app.string.notification_traffic', formatRate(update.rates.up), formatRate(update.rates.down))`.
  - `$r('app.string.notification_traffic', formatBytes(tx), formatBytes(rx))`.
- Keep the existing `.catch(() => {})` on the call.

`onStatConnection` keeps its signature and its call to `updateNotification`.

### 4. `entryability/EntryAbility.ets`

Change the import to `import { ACTION_DISCONNECT, ACTION_OPEN } from '../model/ConnectionNotification';`.

Add a window stage field:

- `private windowStage: window.WindowStage | null = null;`

Change `onWindowStageCreate`:

- Assign `this.windowStage = windowStage;` before `loadContent`.
- Keep the existing `loadContent('pages/Index', ...)` call.

Change `onNewWant`:

- Keep `handleAction(want, this.context)` and `takeImportUri(want)`.
- When `want.action === ACTION_OPEN`, call `this.showMainScreen()`.

Add `private showMainScreen(): void`:

- Return when `this.windowStage === null`.
- Call `this.windowStage.loadContent('pages/Index', ...)`.
- Log an error when the call reports one.

A cold start from the notification runs `onCreate`, then `onWindowStageCreate`, which already loads `pages/Index`.
The new branch covers a warm start where the app shows another page.

### 5. Resources

Add one string to each file:

| Resource | English | Chinese |
| --- | --- | --- |
| `app.string.notification_stop` | Stop | 停止 |

Keep `notification_connected_to` and `notification_traffic`.
The traffic string serves the rates line and the totals line, as it does on Android.

### 6. Tile decision

The public SDK declares no Quick Settings tile API.
A search of the SDK for `TileService`, `quickSettings`, and `tile` finds no tile service type.
The `statusBarView` extension type is a status-bar view. It is not a toggle tile.

Decision: do not port the tile in this batch.
Record the decision for the HarmonyOS platform owner.
Add no extension ability and no code.

### 7. Shortcut decision

Static shortcuts are documented from API 20 in `module.json5` and `resources/base/profile/shortcuts.json`.
The app's `compatibleSdkVersion` is 5.0.0(12).

The `Scan QR code` shortcut needs a barcode decoder. The public SDK has none. U10 records the same gap.
The `Toggle` shortcut needs a headless toggle. A static shortcut starts a UIAbility. The app has no headless trampoline ability. `START_SERVICE` is for the Feature Ability (FA) model.

Decision: do not port the shortcuts in this batch.
Record the decision. Revisit when the minimum runtime is API 20 or later and a headless toggle path exists.
Add no shortcut configuration and no code.

### 8. Boot decision

The platform publishes `usual.event.BOOT_COMPLETED` and `usual.event.LOCKED_BOOT_COMPLETED`.
A static subscriber must extend `StaticSubscriberExtensionAbility`.
The `STATIC_SUBSCRIBER` extension type exists in `bundleManager`, but the public SDK does not declare the ability class.
A runtime subscriber cannot run before the app starts.

Decision: do not port start at boot in this batch.
Record the decision for the HarmonyOS platform owner.
Revisit when the class is public and a device experiment shows that a VPN extension can start without user action.
U09 owns the Auto Connect setting. This unit adds no setting and no receiver.

### 9. Tasker decision

Tasker and Locale use the Android `EDIT_SETTING` and `FIRE_SETTING` plugin protocol.
HarmonyOS has no Tasker host and no equivalent plugin protocol.
A future equivalent needs an exported automation action and a host application that sends it.

Decision: do not port Tasker in this batch.
Record the decision for the product owner.
Add no activity, no exported action, and no code.

### State and data

Notification states:

| State | Enter | Notification fields |
| --- | --- | --- |
| hidden | Before start, after a stop, after a failure | None. |
| posted, starting | `showStarting` on a start without a profile | Title is the app name. Text is Connecting. No totals. |
| posted, connecting | `showConnected` after `markStarting` | Title is the profile name. Text is Connecting. No totals. |
| posted, connected | `showConnected` after `markRunning` | Title is the profile name. Text is Connected. No totals. |
| posted, live | A sample while the screen is on, after the 2 s throttle | Title is the profile name. Text is the rates. Totals line is the session totals. |
| posted, frozen | A sample while the screen is off | The fields do not change. |

The user can dismiss the notification.
The next update publishes it again with the same id, which is 1.

Traffic reducer states:

| Previous sample | Screen | New sample | Rates | Publish |
| --- | --- | --- | --- | --- |
| None | On | Current counters | 0 | false |
| Valid | On | Current counters | Computed | true |
| Any | Off | Cleared | 0 | false |
| Valid | On, counters lower | Current counters | 0 | true |

Stored data:

- No new store file.
- `store/settings.json` does not change.
- The extension keeps the traffic sample in memory.
- The two want agents are cached in memory in the UI process and in the extension process.

### Validation and errors

- The platform rejects an empty notification title and an empty notification text. `notificationText` always returns a non-empty title and text when the app name is not empty. The app name is a resource and is never empty.
- A profile name longer than 1024 bytes is truncated by the platform. The app does not reject it.
- A failed `notificationManager.publish` is logged and does not stop the tunnel. The main screen still shows the state and the Disconnect button.
- A notification permission refusal is handled by `ensureEnabled` before the start. The extension does not ask again.
- A failed `wantAgent.getWantAgent` call omits the body tap or the Stop button. The notification still publishes.
- A `power.isActive()` failure counts as screen on. The notification keeps updating.
- A start without a profile writes the failed status "No profile configured" and removes the notification.
- A Stop from the notification stops the extension, waits until it is gone, then calls `settleSessionTraffic`. The extension stops its core and writes its final traffic record before it records `stopped`, so the settle cannot race a live writer. A second Stop adds no traffic because the record is marked settled.
- A dismissed notification returns at the next 2 s update while the screen is on. While the screen is off, it returns at the first update after the screen turns on.
- Errors from `clearNotification` are caught and logged.

### Test plan

| Case ID | Test file | Test name | Level |
| --- | --- | --- | --- |
| U11-UT-01 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#title-uses-the-profile-name` | host unit |
| U11-UT-02 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#title-falls-back-to-the-app-name` | host unit |
| U11-UT-03 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#starting-notification-uses-the-app-name` | host unit |
| U11-UT-04 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#text-shows-rates-and-totals` | host unit |
| U11-UT-05 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#text-falls-back-before-a-sample` | host unit |
| U11-UT-06 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#body-is-never-empty` | host unit |
| U11-UT-07 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#first-sample-is-a-baseline` | host unit |
| U11-UT-08 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#second-sample-computes-both-rates` | host unit |
| U11-UT-09 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#zero-elapsed-time-yields-no-rate` | host unit |
| U11-UT-10 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#counters-going-backwards-yield-zero` | host unit |
| U11-UT-11 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#screen-off-clears-the-rate-baseline` | host unit |
| U11-UT-12 | `entry/src/test/ParityU11.test.ets` | `entry/src/test/ParityU11.test.ets::U11#screen-on-after-off-needs-a-fresh-baseline` | host unit |

What each spec asserts:

- U11-UT-01: `notificationTitle('Tokyo', 'Shadowsocks')` returns `Tokyo`.
- U11-UT-02: `notificationTitle('', 'Shadowsocks')` returns `Shadowsocks`.
- U11-UT-03: `notificationText('', 'Shadowsocks', 'Connecting…', '', '')` returns the app name as the title and `Connecting…` as the text.
- U11-UT-04: `notificationText` puts the rates in the text and the totals in the totals field.
- U11-UT-05: `notificationText` uses the fallback label when the rates are empty.
- U11-UT-06: `notificationText('', 'Shadowsocks', '', '', '')` returns a non-empty title and text.
- U11-UT-07: `trafficUpdate` with no previous sample returns the current counters as the sample, zero rates, and `publish: false`.
- U11-UT-08: `trafficUpdate` computes both rates from the two samples and the elapsed time.
- U11-UT-09: `trafficUpdate` with zero elapsed time returns zero rates and `publish: false`.
- U11-UT-10: `trafficUpdate` with lower counters returns zero rates and `publish: true`.
- U11-UT-11: `trafficUpdate` with the screen off returns the cleared sample `{-1, -1, 0}` and `publish: false`.
- U11-UT-12: after the screen turns on, the first sample is a new baseline and the second sample publishes rates.

Device cases stay in `docs/versions/5.4.0/e2e/U11.md`.
TC-U11-01, TC-U11-02, TC-U11-04, TC-U11-05, and TC-U11-06 are the real-device checks for this batch.
TC-U11-03 and TC-U11-27 need a manual screen off and screen on.
The tile, shortcut, boot, and Tasker cases stay android-only. This batch adds no code for them.

### Platform notes

- `NotificationRequest.normal.title` and `normal.text` cannot be empty. The SDK states this rule. The design uses the app name and a fallback label to satisfy it.
- `additionalText` is the only field near Android's subtext. The SDK comment says the notification center does not show it. A device check must confirm the actual behavior.
- HarmonyOS has no ticker, no notification category, and no per-mode notification channels.
- `isOngoing` is marked "Not supported currently" in the SDK. `tapDismissed: false` stops auto-clear on a tap. The user can still dismiss the notification.
- Action buttons are always visible. HarmonyOS has no invisible action. The notification shows one Stop button.
- The Stop action starts `EntryAbility`. The public SDK has no static subscriber ability for an app-scoped broadcast. The app opens. Android's Stop action shows no user interface.
- The body tap uses `NotificationRequest.wantAgent`. `tapDismissed: false` keeps the notification after the tap.
- The screen gate uses `power.isActive()` at the traffic stat cadence. This avoids a system common event subscription. Android registers and unregisters a traffic callback.
- The slot type is `CONTENT_INFORMATION`, which maps to level MIN. The platform creates the slot automatically when the request carries `notificationSlotType`.
- The Quick Settings tile has no public API. Do not add a `statusBarView` extension in this batch.
- Static shortcuts start at API 20. The app floor is API 12. The Scan QR code shortcut also needs a decoder.
- Start at boot needs `StaticSubscriberExtensionAbility`. The class is absent from the public SDK.
- Tasker and Locale are Android-only. HarmonyOS has no host.
- Proxy mode keeps the system continuous-task notification. The app does not publish a second notification.

### Open questions

| ID | Question | Owner |
| --- | --- | --- |
| OQ-U11-1 | Does `power.isActive()` return the screen state in a `VpnExtensionAbility` process on the 6.1.1 emulator and on retail devices? | Platform |
| OQ-U11-2 | Does `WindowStage.loadContent('pages/Index')` from `onNewWant` replace the current page without an error on API 12? | App |
| OQ-U11-3 | Does the system show `additionalText` in the notification shade on HarmonyOS 5? If not, should the totals move into the text line? | Product |
| OQ-U11-4 | Does `tapDismissed: false` keep the ongoing notification after a body tap? | Platform |
| OQ-U11-5 | Can the system coalesce the short-lived no-profile notification so that the user never sees it? | Product |
| OQ-U11-6 | Should a home-screen widget replace the Quick Settings tile? | Product |
| OQ-U11-7 | When the minimum runtime reaches API 20, do we add the Toggle shortcut? What is the headless toggle path? | Product |
| OQ-U11-8 | Does the platform permit a VPN extension start from a static subscriber without user action? | Platform |
| OQ-U11-9 | Does the product want an exported automation action for a future HarmonyOS automation host? | Product |
