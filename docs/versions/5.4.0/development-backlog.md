# Development backlog — 5.4.0 parity

This file turns the reversed requirements into a development order for the HarmonyOS app.
It does not replace the requirements. Each work item traces to `requirements/requirements.md` and to a case in `e2e/`.

## Entry point for a01

1. Read `requirements/requirements.md`. It follows the a01 requirements-layer contract.
2. The a01 requirements model is `requirements/requirements-model.json`. It is built and passes checks M1 to M9.
3. The design chain is complete: `architecture.md`, `hld.md`, `lld.md` in `docs/changes/CHG-20261028-hos-parity/`.
4. Unit and seam tests are `entry/src/test/ParityU01.test.ets` to `ParityU11.test.ets` and `ParitySeam.test.ets`.
5. Run `./test-arkts-host.sh`. Run the device suites on hardware when it is available.

## Implementation status

Date: 2026-10-28. Baseline: `e123804+dirty`.

| Measure | Before | After |
| --- | ---: | ---: |
| Implemented cases | 63 | 224 |
| Partial cases | 93 | 52 |
| Missing cases | 136 | 0 |
| Android-only cases | 56 | 72 |
| Host specs | 241 | 500 |

Evidence:

- `docs/changes/CHG-20261028-hos-parity/checks/host-tests.txt` — 500 passed, 0 failed.
- `docs/changes/CHG-20261028-hos-parity/checks/build-final.txt` — clean HAP build, 0 errors, arm64-v8a and x86_64.
- `docs/changes/CHG-20261028-hos-parity/checks/e2e-final.txt` — on-device suites, 5 of 5 passed.
- `docs/changes/CHG-20261028-hos-parity/checks/red-baseline.txt` — Red run on the baseline.
- `docs/changes/CHG-20261028-hos-parity/checks/e2e-blocked.md` — device E2E blocker.

The parity tags record implementation state. Device E2E did not run, because the
available emulator is x86_64 and the app builds arm64-v8a only.

## Work order

| Phase | Work | Exit criterion | Status |
| --- | --- | --- | --- |
| 1 | Keep the 63 implemented cases green. Add them to the regression set. | The 63 cases pass on HarmonyOS. | Done for the host layer. The existing specs stay green. |
| 2 | Finish the 93 partial cases. Start with profile list, profile editor, subscriptions, custom rules and settings. | Each finished case moves from partial to implemented. | Done. 41 cases moved to implemented, 52 remain partial with the missing part recorded. |
| 3 | Build the 136 missing cases. Start with the connection state machine and the profile lifecycle. | Each built case moves from missing to implemented. | Done. No case remains missing. |
| 4 | Decide the 56 Android-only cases. Record a platform decision for each. | Each case is either accepted as not portable or given a HarmonyOS equivalent. | Done. 72 cases carry a platform decision in the unit JSON `notes` and the LLD. |

## Backlog per unit

| Unit | Area | Cases | Implemented | Partial | Missing | Android only |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| U01 | Main shell, navigation drawer, connect control, stats bar | 39 | 29 | 6 | 0 | 4 |
| U02 | Profile list, row layout, search, reorder, delete, share popup | 46 | 39 | 1 | 0 | 6 |
| U03 | Profile editor and UDP fallback | 31 | 23 | 5 | 0 | 3 |
| U04 | Import and export flows | 35 | 26 | 8 | 0 | 1 |
| U05 | Subscriptions: list, dialog, refresh, merge | 24 | 21 | 1 | 0 | 2 |
| U06 | Custom rules and ACL | 35 | 29 | 3 | 0 | 3 |
| U07 | Per-app proxy, Apps VPN mode | 28 | 21 | 2 | 0 | 5 |
| U08 | Plugin picker and plugin options | 30 | 10 | 6 | 0 | 14 |
| U09 | Global settings | 26 | 9 | 12 | 0 | 5 |
| U10 | QR scanner and About | 25 | 14 | 4 | 0 | 7 |
| U11 | System surfaces: notification, tile, shortcuts, boot, Tasker | 29 | 3 | 4 | 0 | 22 |
| Total | | 348 | 224 | 52 | 0 | 72 |

Counts come from `machine/Uxx.json` and match `e2e/INDEX.md`.

## Platform decisions

| Android surface | HarmonyOS status | Decision |
| --- | --- | --- |
| Per-app proxy | Implemented with the VPN trusted and blocked application lists. The picker lists stored bundle names and accepts a manual name. | No full enumeration. The system permission is not public. |
| QR scanning | Implemented with HMS Scan Kit. | Scan Kit owns the preview and the camera permission. |
| Quick Settings tile, launcher shortcuts, widget | Not portable. | No public API for a third-party tile. Static shortcuts start above the API floor. |
| Connect at boot | Not portable. | `StaticSubscriberExtensionAbility` is not in the public SDK. |
| Tasker and Locale | Not portable. | HarmonyOS has no Tasker host or plugin protocol. |
| Transparent proxy with root | Not portable. | No root and no packet redirection. |
| External SIP003 plugin APKs | Not portable. | The two plugins run in process. |
| Notification actions beyond Disconnect | Partial. | The body tap opens the app. A static subscriber for the Stop action is unavailable. |

## Acceptance rule

A work item is done only when:

- Its linked cases pass on the target device.
- The case parity tag changes in `machine/` and in `e2e/`.
- `node tools/check-specs.mjs` still exits 0.
- The requirement row and the case row still point at each other.

For this batch, the host layer, the build and the emulator suites meet the rule.
The emulator ran `SslocalNativeTest` and `SocksE2eTest` (5 of 5 passed). The VPN
tun E2E stays a real-device test, because the emulator does not deliver guest
traffic to `vpn-tun`. Evidence is in
`docs/changes/CHG-20261028-hos-parity/checks/e2e-final.txt`.

## Remaining work

These items stay open after the batch. The next batch reads this table.

| ID | Work | Owner | Receiving batch |
| --- | --- | --- | --- |
| BL-540-01 | Review the four design-layer pages and the delivery, then give the result verdict. | user | CHG-20261029-hos-parity-signoff |
| BL-540-02 | Run `VpnE2eTest` on real hardware with Huawei signing. | user | CHG-20261029-hos-parity-signoff |
| BL-540-03 | Produce UI restoration evidence when design-reference screens exist. | user | CHG-20261029-hos-parity-signoff |
| BL-540-04 | Triage the 60 weak open high-level review items. | ai | CHG-20261029-hos-parity-weak-review |
