# Main-screen UI parity

Baseline: shadowsocks-android v5.3.5-nightly (`ae28fd9`).

The Android reference is a running build, not only its source. The APK ran
on a HUAWEI DCO-AL00 with the Chinese UI. `android-main.png` in this directory
is its main screen. The Android source files are `layout_main.xml`,
`layout_profile.xml`, `menu/navigation_main.xml`,
`menu/profile_manager_menu.xml`, `menu/profile_share_popup.xml`,
`ProfilesFragment.kt`, `ServiceButton.kt`, `widget/StatsBar.kt`, and the
colour files in `plugin/src/main/res/values` and `values-night`.

The HarmonyOS capture is the HVPhone emulator at 1256x2760:
`harmony-main.jpeg` and `harmony-main.json` in this directory. The capture is
a fresh install with no stored profile. `harmony-main-dark.jpeg` is the same
screen with the system dark theme on. `harmony-connected-dark.jpeg` is a
HUAWEI Pura X (VDE-AL00) with the tunnel up, dark theme, two seconds after
the connect tap. The profile's server address is blurred in that capture.

The Android phone ran a test server only once, so the connected-state facts
come from the Android source: `StatsBar.kt` (show on `Connected`, tap to
test), `layout_main.xml` (bar contents, FAB anchored to the bar) and
`ServiceButton.kt` (checked state).

## Controls

| # | Control | Android | HarmonyOS rendered | Match |
| --- | --- | --- | --- | --- |
| 1 | Drawer toggle | white menu icon on the app bar | `Text('☰')` [56,185][129,316], white | yes |
| 2 | Title | white, 20sp, app bar | `Text('Profiles')` [185,210][849,292], white 20vp medium | yes |
| 3 | Add profile | `ic_action_note_add`, white, 24dp | `notepad_badge_plus` [849,209][934,293], white | glyph differs |
| 4 | Export | `ic_file_file_upload`, white, 24dp | `arrow_up_to_line` [990,212][1067,289], white | glyph differs |
| 5 | Search | `ic_action_search`, white, 24dp | `magnifyingglass` [1123,212][1200,289], white | yes |
| 6 | Row title | `text1`, bold, `textColorPrimary`, empty name shows host:port | `Text('example.shadowsocks.org:8388')` [84,407][926,473], bold | yes |
| 7 | Row address | `text2`, shown only when a name exists | row `Text`, same rule | yes |
| 8 | Row plugin line | `text2` appends the plugin id | row plugin `Text`, same rule | yes |
| 9 | Row traffic | `R.id.traffic`, right-aligned, hidden at zero | traffic `Text`, same rule | yes |
| 10 | Edit icon | `ic_image_edit`, top right, half alpha while blocked | `pencil_line` [1046,412][1116,482], half alpha while blocked | yes |
| 11 | Subscription icon | `ic_file_cloud_queue` replaces edit for an active subscription | `cloud`, same rule | yes |
| 12 | Share icon | `ic_social_share`, popup with QR and export | `share` [1158,412][1228,482] with the QR and copy menu | glyph differs |
| 13 | Row band | 8dp left band, green 700 when selected, blue grey 300 otherwise | left border 8vp, `#388E3C` selected, `#90A4AE` otherwise | yes |
| 14 | Row background | window background, white in the light theme | `main_page`, `#FFFFFF` | yes |
| 15 | Row divider | 1dp line under the row | bottom border 1vp, `divider` | yes |
| 16 | Connect control | `ServiceButton` FAB, centred; blue grey, green when checked | `ServiceButtonView`, centred, `main_fab`; green as soon as the extension reports running; its lower half sits in the bar when the bar shows | yes |
| 17 | Stats bar | `StatsBar`: tx and tx rate, rx and rx rate, status line; shown on `Connected`; tap tests the connection | `StatsBarView`, same order and fill; shown from the `verifying` phase; tap runs the probe. Capture: 2 s after the connect tap, `已连接，点击测试连接` | yes |
| 18 | First-run list | one default profile, selected, `example.shadowsocks.org:8388` | same profile, selected | yes |
| 19 | Drawer items | Profiles, Subscriptions, Custom rules, Settings, FAQ, About, with icons | the same six entries, with icons | icons differ |
| 20 | System bars | status bar `colorPrimaryDark`; navigation area takes the page colour | `main_status_bar` for the status bar; `main_page` for the navigation area; set after the page loads | yes |

## Colours

| Use | Android | HarmonyOS token |
| --- | --- | --- |
| Status bar | `colorPrimaryDark` `#455A64` | `main_status_bar` |
| App bar | `colorPrimary` `#607D8B` | `main_toolbar` |
| App bar content | white | `main_toolbar_text` |
| Selected row band | `material_green_700` `#388E3C` | `main_row_band_selected` |
| Other row band | `material_primary_300` `#90A4AE` | `main_row_band` |
| Row and page fill | `colorBackground` white | `main_page` |
| FAB idle | `material_primary_500` `#607D8B` | `main_fab` |
| FAB connected | `material_green_700` `#388E3C` | `main_fab_connected` |
| FAB icon | white | `main_fab_text` |
| Stats bar | `material_primary_300` `#90A4AE` | `main_stats` |

The dark theme uses Android's night colours: `#263238` status bar, `#37474F`
app bar, `#546E7A` row band and stats bar, `#121212` page fill. The selected
band and the FAB stay green in both themes, as they do in Android.

## Fixes in this round

| Fault | Cause | Fix |
| --- | --- | --- |
| The edit pencil did nothing | The row's tap selected the profile and the icon had no handler of its own | The icon opens the editor, and a failed open reports itself |
| A fresh install had no row and no selection | `JsonStore.exists` treated `fileIo.accessSync`'s boolean answer as a throw, so the seed path always returned early | `exists` returns that boolean |
| Test and speed controls had no Android counterpart | Extra HarmonyOS controls | Both removed. The connection test stays on the stats-bar tap, as in Android. |
| Starting the tunnel left the button grey and the bar hidden until the probe verdict | `statsVisible` and the checked fill covered only `connected` and `probe-failed`, but the page spends the probe in `verifying` | `verifying` counts as up: the fill turns green and the bar shows as soon as the extension reports running |
| A black strip under the content | The window refuses bar changes before its content exists (`1300002`), so the status and navigation colours never applied; the platform's own bar stayed black | The colours are set in the `loadContent` callback, with the navigation area on the page colour |
| The button did not ride the bar | The FAB was laid out above the bar | It is offset down by half its height when the bar shows, as Android's anchored FAB |

## Differences that remain

| Difference | Reason |
| --- | --- |
| The add, export and share glyphs differ in shape. | The HarmonyOS symbol set has no exact match for Android's drawables. |
| The search action sits on the app bar. Android shows it on the app bar too in this build. | Same placement now. The field opens under the bar. |
| The add menu also offers QR-image import, an ss:// URL and Subscriptions. | Extra HarmonyOS routes for the same import actions. Android keeps some in the overflow menu. |
| Text metrics follow the HarmonyOS theme. | Platform typography. |
| The title shows the system language. Android shows Chinese here because the reference phone runs Chinese. | Both apps follow the system language. |
