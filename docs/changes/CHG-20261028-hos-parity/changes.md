# Change review

| 变更 | 内容 | 理由 |
| --- | --- | --- |
| Profile record | Added metered, proxyAppsEnabled, proxyAppsBypass, proxyAppsList, pluginConfigs; added displayName/displaySecondary, feature and transport copy, manual defaults, plugin state and validation; `toTunConfig` takes the local DNS port. | Carry the Android profile fields and the 11 unit rules. |
| Profile store and files | Added sorted/filter/indexOf/getAllOrNull, new field defaults, plugin normalization, subscription status migration, strict and lenient import, the batch collector, fallback reuse and the Android export shape. | Keep the store and the import/export paths in step with Android. |
| Diagnostics and settings | Added PHASE_STOPPING, row keys, port helpers, the seeded store, settings gating, traffic formatting and the 5450 DNS default. | One settings record for the pages, the proxy and the VPN extension. |
| Subscriptions | Added URL validation and sort, the edit dialog model, the body parser with feature inheritance, the batch merge, the fetch path and the refresh run with its notification. | Finish the subscription lifecycle from URL entry to profile merge. |
| ACL and custom rules | Added rule templates, validation, editor helpers, undo, copy text, the GFW List import, the bypass default and the ten-level import depth. | Match Android's custom-rule editor and its ACL semantics. |
| Main page | Added the drawer, the service button and ring, the stats bar, search, swipe delete with undo, drag reorder, import and export menus, QR scan, share dialog and the store-aware row. | Bring the main screen to Android parity. |
| Main-screen parity follow-up | Removed the Test connection and Speed test buttons. Rebuilt the screen on Android's palette and geometry: a blue-grey app bar with white content, a status bar in Android's colour, an 8vp row band that turns green for the selected row, a white list with dividers, a centred FAB that turns green and rides the stats bar once the tunnel is up, the stats bar in Android's field order with its tap-to-test line, and drawer icons. The bar and the green fill now appear as soon as the extension reports running, without waiting for the probe verdict. The system bars take their colours once the page loads, which removes the platform's black strip under the content. A fresh install seeds Android's default profile and selects it. The edit icon opens the editor, and a blocked edit tells the user why. `JsonStore.exists` now reads the boolean that `fileIo.accessSync` returns. Evidence: `checks/ui-parity/`. | The user asked for the Android main screen exactly and reported the edit action did nothing, a missing connection status area, a black strip and a floating button that did not ride the bar. |
| Profile editor | Added IPv6 and metered switches, the UDP fallback chooser, the app-picker entry, the plugin picker and options editor, validation and the load gate. | Bring the editor to Android parity. |
| App picker | Added Off/On/Bypass, search, stored-name resolution, manual add, apply to all and the clipboard exchange. | Implement per-app proxy with the public bundle API. |
| Other pages | Added subscription edit and refresh, rule editing and GFW import, the settings rows, the About links and the QR share dialog. | Close the remaining page-level gaps. |
| VPN extension | Added per-app trusted and blocked lists, the DNS port, plugin refusal, failure text and notification start/clear. | Pass the 5.4.0 fields to the platform and the core. |
| Notification and entry | Added the body tap, the Stop label, the totals line, the screen gate and the 110004 retry path; EntryAbility opens the main page and survives a failed settle. | Make the notification usable and the Stop action reliable. |
| Resources and manifest | Added 147 strings in English and Chinese, success_container and scrim, the AppPicker and UdpFallback routes, querySchemes and GET_BUNDLE_INFO. | Support the new pages and the link and bundle queries. |
| Tests | Added ParitySeam and ParityU01 to ParityU11, 249 host cases, and the single-suite runner mode. | Guard every new model rule on the host. |
| Documentation | Updated AGENTS.md, the version README, the development backlog, the case tags and the E2E index. | Keep the delivered facts in step with the code. |

## Reason summary

The batch aligns the HarmonyOS app with the Android 5.3.5-nightly mobile app.
Each change traces to a unit plan in `lld.md` and to a case in `e2e/`.
The parity tag changes are in `machine/Uxx.json` and `e2e/Uxx.md`.
