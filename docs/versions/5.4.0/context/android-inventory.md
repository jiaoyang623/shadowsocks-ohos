# Android feature inventory — mobile module

Baseline: shadowsocks-android tag v5.3.5-nightly, commit ae28fd91931fe4d2d5aab044de9ceaf9ed07ad56.
Scope: the `mobile` module and the `core` files it shows.
This file is a quick reference. The unit specs are the authority.

## App identity

| Item | Value |
| --- | --- |
| versionName | 5.3.5-nightly |
| versionCode | 5030550 |
| minSdk | 23 |
| targetSdk | 36 |
| applicationId | com.github.shadowsocks |

## Main shell

- Drawer entries: Profiles, Subscriptions, Custom rules, Settings, FAQ, About.
- Connect button in the main screen. States: Idle, Connecting, Connected, Stopping.
- Stats bar shows live tx and rx rates plus session totals. A tap runs an HTTPS test through the proxy.
- First launch seeds one sample profile when the profile store is empty.

## Profile list

- Order is the stored user order. No sort control.
- Long-press drag reorders rows. Enabled only while the service can stop.
- Search filters by name and host. Case-insensitive.
- Swipe left deletes a row. A snackbar offers Undo. The delete commits when the snackbar closes.
- Tapping a row selects the profile. A connected service reloads with the new profile.
- Row shows lifetime traffic plus live session traffic.
- Share popup offers QR code and Export to clipboard.

## Profile editor

Fields: Profile Name, Server, Remote Port, Password, Encrypt Method, Route, IPv6 Route, Apps VPN mode, Metered Hint, Remote DNS, Plugin, Configure, UDP Fallback.
IPv6 and Apps VPN mode are enabled in VPN mode only. Metered Hint is VPN mode and Android 9+ only.
Subscription-managed profiles lock the transport fields.
Apply saves. Back with changes asks about unsaved changes. Delete asks for confirmation.

## Import and export

- Clipboard import scans for all `ss://` URLs.
- External `ss://` link opens a confirmation dialog, then imports.
- Clipboard export writes all active profiles as newline-separated `ss://` URLs.
- JSON file import appends. Replace mode clears the list first and keeps traffic counters for matching host:port.
- JSON file export writes a `profiles.json` array.
- QR image import through the scanner gallery picker.

## Subscriptions

- Add, edit, delete with Undo.
- Manual refresh only. Downloads all URLs concurrently with a progress notification.
- Accepts SIP008 or arbitrary JSON holding profile objects. Classic base64 lists are not accepted in this revision.
- Merge key is name plus host:port. Missing profiles become obsolete and hide from the list.
- No auto-update, no grouping, no drag reorder. Order is by URL.

## Routing

| Route | Behavior |
| --- | --- |
| all | Proxy everything |
| bypass-lan | Proxy all except LAN subnets |
| bypass-china | Proxy all except China IP ranges |
| bypass-lan-china | Proxy all except LAN and China ranges |
| gfwlist | Bypass all except GFW-listed entries |
| china-list | Bypass all except China ranges as shipped |
| custom-rules | User rules. Unmatched traffic bypasses |

- Built-in ACL files refresh from shadowsocks.org when unmetered and charging.
- ACL format supports `#IMPORT_URL` includes.

## Custom rules

- Three rule templates: Generic, Domain, URL.
- Tap a row to edit. Long-press to multi-select. Swipe left to delete with Undo.
- Bulk actions: Select all, Cut, Copy, Delete.
- Import from clipboard. Load the local GFW list into custom rules.
- Editing is disabled while the running profile uses custom-rules.

## Per-app proxy

- Modes: Off, On, Bypass. Per profile.
- App picker lists apps with INTERNET permission. Search by label, package or UID.
- Bulk action: Apply Settings to All Profiles.
- Clipboard format: `bypass` plus package names.

## Service modes

- VPN, Proxy only, Transproxy.
- Mode and ports change only while stopped.
- Share over LAN appears in the TV settings only in this revision.
- Auto Connect starts the service on boot when it ran before.
- Direct boot support is optional and warns about weaker protection.

## Plugins

- No plugin binaries ship with the app.
- Plugins are separate APKs found through a content provider.
- Documented plugins: v2ray, kcptun, obfs-local.
- With a plugin the main proxy runs TCP only. An optional UDP Fallback profile runs UDP.

## Settings

Mobile global settings: Auto Connect, Allow Toggling in Lock Screen, Service mode, SOCKS5 proxy port, Local DNS port, Transproxy port.
No notification page, no theme switch, no language picker.

## Theme and language

- DayNight theme follows the system.
- Locales: en, ar, de, es, fa, fr, ja, ko, ru, tr, uk, zh-CN, zh-TW.

## System surfaces

- Foreground notification with profile name, live speed, totals and a Stop action.
- Quick Settings tile.
- Launcher shortcuts: Toggle and Scan QR code.
- Tasker and Locale action plugin.
- Boot receiver.
- No home-screen widget.

## Android-only surfaces

VPN per-app allow and disallow lists, transproxy with root and iptables, Tasker, Quick Settings tile, launcher shortcuts, boot receiver, CameraX and ML Kit scanning, external plugin APKs, Google Play OSS licence UI.
