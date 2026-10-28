# HarmonyOS port — current feature inventory

Baseline: shadowsocks-ohos 5.3.5, commit e123804 (2026-10-18).
Use this file to tag each E2E case with the current parity status.
Verify a status against the code before you write it.

## Status values

- `implemented` — the HarmonyOS app has the behavior.
- `partial` — the behavior exists with a known limit.
- `missing` — the behavior does not exist.
- `android-only` — the behavior depends on an Android platform surface. It cannot be ported as-is.

## Implemented

| Area | Behavior | Main source |
| --- | --- | --- |
| Profile list | Name, host, method, latency, traffic, selected mark, row actions | entry/src/main/ets/pages/Index.ets |
| Search | Case-insensitive filter over name and host | Index.ets |
| Reorder | Long-press drag, persisted user order | Index.ets, model/ProfileStore.ets |
| Delete and undo | Immediate delete, then Undo dialog | Index.ets |
| Per-profile traffic | Lifetime counters plus live session counters | model/SessionTraffic.ets, model/TrafficStats.ets |
| Connect and disconnect | Phase machine: connecting, verifying, connected, failed | Index.ets |
| Profile switch | Stops the tunnel, settles counters, starts the new profile | Index.ets |
| Link import | `ss://` link with confirmation dialog | Index.ets, EntryAbility.ets |
| Profile edit | Name, host, port, password, method, route, plugin, remote DNS | pages/ProfileEdit.ets |
| Method picker | AEAD and AEAD-2022 presets plus custom value | ProfileEdit.ets, model/Profile.ets |
| Route picker | all, bypass-lan, bypass-china, bypass-lan-china, gfwlist, china-list, custom-rules | ProfileEdit.ets, model/Routes.ets |
| Plugin fields | obfs-local and v2ray-plugin presets plus options | ProfileEdit.ets |
| Remote resolver | host, host:port, dns:// URL | ProfileEdit.ets |
| QR display | zxing-compatible code on Canvas, copy URL | pages/ProfileQr.ets |
| Unsaved guard | Save, discard, cancel dialog | ProfileEdit.ets |
| Subscription profile lock | Transport fields disabled for subscription profiles | ProfileEdit.ets |
| `ss://` parse and write | SIP002 and legacy forms, plugin query, IPv6 | model/Profile.ets |
| Clipboard import and export | Menu actions | model/ProfilesFile.ets |
| File import and export | Document picker, append and replace modes | model/ProfilesFile.ets |
| Subscription add, update, delete | Base64 list, plain list, SIP008 JSON | pages/Subscription.ets |
| Subscription merge | Key is name plus host:port, obsolete profiles hidden | model/ProfileStore.ets |
| ACL routes | Bundled ACL files and `#IMPORT_URL` sync | model/Acl.ets, model/AclSync.ets |
| Custom rules | Add domain, subnet, list URL, clipboard import, multi-select, undo | pages/CustomRules.ets |
| DNS in tun | Core answers DNS, remote DNS over TCP | vpnability/SsVpnExtensionAbility.ets |
| VPN mode | Default route, tun 172.19.0.1/30, DNS 172.19.0.2 | SsVpnExtensionAbility.ets |
| Proxy mode | SOCKS5 listener in UI process | model/ProxyService.ets |
| Share over LAN | Binds 0.0.0.0 | pages/Settings.ets |
| Notification | VPN-mode ongoing notification with traffic and disconnect | model/ConnectionNotification.ets |
| Traffic stats | 500 ms samples, UI polls once per second | model/TrafficStats.ets |
| Dark theme | System theme, color resources | resources/dark |
| Locales | English and Simplified Chinese | resources/base, resources/zh_CN |
| About | App version, core version, licence | pages/About.ets |
| Connection tests | Latency, HTTP probe, speed test | model/Diagnostics.ets |

## Partial

| Area | Limit | Main source |
| --- | --- | --- |
| Plugin picker | Two built-in families only. Unknown names fail at start. | native/sslocal-ffi/src/plugin.rs |
| SIP008 export | Model function exists. No UI calls it. | model/ProfilesFile.ets |
| Subscription management | No edit, no auto-update, no update-all, no grouping, no ssd:// | pages/Subscription.ets |
| Custom rules editor | No per-rule edit dialog, no one-tap gfwlist import, no route gating | pages/CustomRules.ets |
| IPv6 | Stored but unused. Tun is IPv4 only. | model/Profile.ets |
| UDP fallback | Field is unused. | model/Profile.ets |
| Proxy-mode stats | No app-level counters. | model/ProxyService.ets |
| Notification actions | Disconnect only. No connect or tap action. | model/ConnectionNotification.ets |
| Service-mode change | Applies on the next connect. | pages/Settings.ets |
| Theme and language | Follows the system. No in-app selector. | resources |
| Model failure reasons | English strings. Host specs assert them. | model/Diagnostics.ets |

## Missing

- QR scanning. No barcode decoder in the SDK.
- Per-app proxy. Imported `proxy_apps` is dropped.
- Transparent proxy. Needs root and external redirection.
- Quick Settings tile, launcher shortcuts, home-screen widget, quick connect.
- Connect at boot.
- Traffic counter reset.
- In-app log viewer.
- Share sheet and QR image save.
- Multi-select profile actions.
- Onboarding flow.
- App update check.
- External SIP003 plugin binaries.
- UDP through SIP003 plugins.

## Android-only surfaces

- Tasker and Locale integration.
- Android Quick Settings tile.
- Android launcher shortcuts.
- Android boot receiver and direct-boot storage.
- CameraX and ML Kit QR scanning.
- External plugin APKs and their content providers.
- Transproxy with root and iptables.
- Google Play OSS licence UI.
