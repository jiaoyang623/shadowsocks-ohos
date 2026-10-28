# Architecture — HarmonyOS 5.4.0 Android parity

This document covers 子系统、过程、边界 and the key architectural decisions.

## Inputs and reuse

This document covers the increments needed for parity. The existing app structure stays.
Reused without change: the ArkUI page structure, the JSON-file persistence, the NAPI bridge, the Rust core, the in-process SIP003 plugins, and the DNS gateway inside the tun.
The reasons are recorded in `AGENTS.md` and in the 5.3.5 code.

## System context

| Actor or system | Relation |
| --- | --- |
| Phone user | Operates the pages, the drawer and the connect control |
| Android mobile app v5.3.5-nightly | Reference behavior for each page and control |
| HarmonyOS app | The system under design |
| Shadowsocks server | Receives the encrypted tunnel |
| Subscription endpoint | Returns a profile list over HTTP or HTTPS |
| ACL endpoint | Returns an ACL list or an included list |
| HarmonyOS VPN framework | Creates the tun device and shows the consent dialog |
| Notification service | Publishes the ongoing tunnel notification |

## Subsystems

| ID | Subsystem | Responsibility | Main files |
| --- | --- | --- | --- |
| A | Pages | Show state and collect input | `entry/src/main/ets/pages/` |
| B | Model | Profiles, subscriptions, ACL, settings, diagnostics, traffic | `entry/src/main/ets/model/` |
| C | VPN extension | Create the tun, hand the fd to the core, host stats and ACL | `entry/src/main/ets/vpnability/` |
| D | Native bridge | NAPI surface and the C ABI over the Rust core | `entry/src/main/cpp/`, `native/sslocal-ffi/src/` |
| E | Rust core | Shadowsocks client, tun stack, DNS, plugins, stats | `native/sslocal-ffi/vendor/` |
| F | Platform adapters | Notification, continuous task, pickers, clipboard, system consent | `model/ConnectionNotification.ets`, `model/Transfer.ets`, `ProxyService.ets`, `pages/VpnGrant.ts` |

## Allowed dependencies

Pages depend on the model.
The model depends on platform adapters and on the native bridge.
The VPN extension depends on the model, the native bridge and the platform adapter.
The native bridge depends on the Rust core.
The Rust core depends on no ArkTS code.
No page calls the native bridge directly. No model file calls a page.

## Seams

| ID | Seam | Provider | Consumer | Data | Failure owner |
| --- | --- | --- | --- | --- | --- |
| S1 | Profile and selection store | Model | Pages | Profile records, selected id, order, counters | Model |
| S2 | Native start and stop | Model | Native bridge | Config JSON, tun fd, stat address | Model |
| S3 | Tun and stats | VPN extension | Native bridge | Tun fd, 16-byte traffic sample | VPN extension |
| S4 | Cross-process state | UI process | VPN extension | Status file, profile id, traffic sample | Model |
| S5 | Remote lists | Model | Network | Subscription body, ACL body, remote DNS answer | Model |
| S6 | Platform surfaces | Platform | Model | Notification permission, continuous task, picker result, clipboard | Model |
| S7 | VPN consent | Platform | VPN extension | Consent result | VPN extension |
| S8 | Plugin transport | Native bridge | Rust core | Loopback TCP stream with obfuscation | Native bridge |

## Key decisions

| Decision | Chosen option | Alternative | Why | Cost |
| --- | --- | --- | --- | --- |
| Plugin processes | Keep in-process plugins | External plugin processes | HarmonyOS cannot spawn arbitrary executables | Only two plugin families |
| DNS location | Answer DNS inside the tun | Relay UDP DNS to the server | Many servers do not relay UDP | One round trip on first lookup |
| Profile persistence | JSON files under `filesDir/store/` | Preferences | Preferences is unsafe across processes and rejects some contexts | Manual atomic writes |
| Per-app proxy | Use the VPN trusted and blocked application lists | Build a packet filter | The platform exposes the lists | Needs an app picker and a manifest query |
| Subscription refresh | Foreground or connect-time refresh | Background scheduler | Background scheduling needs system approval | No silent refresh |
| QR scanning | Record as blocked or use an external scanner | Ship a decoder | The public SDK ships no barcode decoder | A case stays android-only or partial |
| Notification actions | Disconnect plus a tap to open the app | Connect action | The extension owns the notification | Connect needs the UI process |
| Proxy-mode stats | Add a UI-process counter path | Reuse the VPN stats endpoint | The core already reports counters | New polling path in the UI |

## Quality scenarios

| Scenario | Stimulus | Expected | Risk |
| --- | --- | --- | --- |
| Server unreachable | The user connects with a bad host | The UI reaches a failed phase and shows the reason | The phase may hang without a timeout |
| Tunnel drops | The VPN extension stops while the UI is open | The UI leaves Connected and offers connect again | Counter settlement may miss the live sample |
| Profile switch | The user selects another profile while connected | The old tunnel stops, counters settle, the new one starts | A race between stop and start |
| Subscription fetch fails | The endpoint returns an error | The old profiles stay and the page shows the error | Partial merge on a malformed body |
| Permission denied | The user denies notifications or the VPN | The app still runs or reports the blocker | A silent failure |
| Core crash | The native process dies | The UI shows a failure and can restart | A stale status file |

## Architecture increments for parity

| Unit | Increment | New or changed subsystem |
| --- | --- | --- |
| U01 | Connect and state machine parity, notification tap, per-app entry | A, B, C, F |
| U02 | Share sheet, multi-select actions, profile share | A, B, F |
| U03 | Plugin breadth, IPv6 field, UDP fallback | A, B, D, E |
| U04 | SIP008 export, ssd link handling, import variants | A, B |
| U05 | Subscription edit, auto-refresh, update all, grouping | A, B, F |
| U06 | Per-rule edit, gfwlist import, route gating | A, B |
| U07 | App picker and VPN application lists | A, B, C, F |
| U08 | Plugin option editing and validation | A, B, D |
| U09 | Notification settings, advanced settings | A, B, F |
| U10 | QR scanning decision, About links | A, F |
| U11 | Notification actions, launcher shortcut, boot decision, Tasker decision | C, F |

## Constraints

- HarmonyOS NEXT 5.x, API 12 minimum. `protectProcessNet` needs API 22.
- One core instance at a time.
- arm64-v8a only.
- No external plugin binaries.
- No barcode decoder in the public SDK.
- The public emulator does not deliver guest traffic to the tun. Tun E2E runs on a real device.

## Open architecture questions

| ID | Question | Owner |
| --- | --- | --- |
| AQ-1 | Can the app picker query installed applications without a restricted permission on API 12? | HarmonyOS platform owner |
| AQ-2 | Can a background subscription refresh run without user-visible approval? | Product owner |
| AQ-3 | Is an external QR scanner acceptable for the missing scan case? | Product owner |
| AQ-4 | Can the notification carry a connect action that reaches the UI process? | HarmonyOS platform owner |
