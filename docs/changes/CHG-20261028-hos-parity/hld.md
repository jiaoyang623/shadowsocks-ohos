# HLD — HarmonyOS 5.4.0 Android parity

This document covers 模块、接口、时序、数据、装配 for the parity increment.
Fields: 模块职责、接口契约、装配与测试边界.
It reuses the subsystem split in `architecture.md`.

## Module decomposition

| Module | Responsibility | Files |
| --- | --- | --- |
| Pages | Render state, collect input, navigate | `pages/Index.ets`, `ProfileEdit.ets`, `ProfileQr.ets`, `Subscription.ets`, `CustomRules.ets`, `Settings.ets`, `About.ets` |
| Profile model | Parse, write, serialize a profile | `model/Profile.ets`, `model/ProfilesFile.ets` |
| Store | Multi-profile list, selection, order, counters | `model/ProfileStore.ets`, `model/JsonStore.ets`, `model/SessionTraffic.ets` |
| Subscription | Fetch, parse, merge a subscription | `model/Subscription.ets` |
| ACL | Parse, sync and compose ACL rules | `model/Acl.ets`, `model/AclSync.ets`, `model/CustomRules.ets`, `model/Routes.ets` |
| Settings | Service mode, ports, test URLs | `model/Settings.ets` |
| Diagnostics | Latency, HTTP probe, speed test | `model/Diagnostics.ets` |
| Traffic | Cross-process counters and rates | `model/TrafficStats.ets` |
| Proxy service | SOCKS listener and continuous task | `model/ProxyService.ets` |
| Notification | Permission, publish, disconnect action | `model/ConnectionNotification.ets` |
| VPN extension | Consent, tun, ACL deployment, stats host | `vpnability/SsVpnExtensionAbility.ets` |
| Native bridge | NAPI surface | `cpp/napi_init.cpp`, `types/libsslocal/Index.d.ts` |
| Rust core | Tunnel, DNS, plugins, stats | `native/sslocal-ffi/` |

## Contracts

### C-01 Profile record
- Input: name, host, port, password, method, route, plugin, plugin options, remote DNS, UDP fallback, IPv6, per-app mode and lists.
- Output: a profile object and a serialized JSON object for the core.
- Errors: a missing host, port or password is rejected before save. An unknown method stays in the custom field and fails at core start.
- Timing: a save is atomic through `JsonStore`.
- Owner: profile model.

### C-02 Start request
- Input: a config JSON, an optional tun fd, a stat address.
- Output: `0` on success or a negative code. `lastError()` returns the message.
- Errors: `SSLOCAL_ERR_BAD_CONFIG` for an invalid profile or an unknown plugin. `SSLOCAL_ERR_ALREADY_RUNNING` for a second start.
- Timing: the call returns after the listener or tun is ready, or after the start fails. The native call returns when the runtime is spawned, so the model's start request waits for the core's first traffic sample, or for a liveness window with no new native error, before it writes `running`. A live core that sends no report runs on the heartbeat and is not reported as running before that proof either.
- Owner: model.

### C-03 Tun handover
- Input: a tun descriptor from the VPN framework.
- Output: the core owns a duplicate. The extension keeps its own copy.
- Errors: an invalid fd returns a negative code. The extension destroys the connection and reports a failure.
- Timing: the fd is passed once per start. The core closes its copy on stop.
- Owner: VPN extension.

### C-04 Traffic sample
- Input: none. The core pushes a 16-byte sample every 500 ms to the stat address.
- Output: two little-endian u64 values. The extension persists at most one sample per second. Each record carries the profile id, a session token, a closed flag and a settled flag.
- Errors: a missing endpoint does not clear the record. The session is recorded with `stats` false and no counters, so the UI does not read the missing counters as a dead core. A malformed sample is ignored. A start that finds another session's unsettled record moves it aside for the settler instead of overwriting it.
- Timing: the UI polls the persisted record once per second. Only the UI process settles a record: it claims the record and writes the session token to the settlement receipt before it adds the counters.
- Owner: VPN extension and traffic model.

### C-05 Subscription merge
- Input: a body with base64 `ss://` lines, plain lines or SIP008 JSON.
- Output: an upsert by name plus host:port. New profiles get the current feature settings. Missing profiles become obsolete.
- Errors: a malformed body returns an error and keeps the old list. A duplicate keeps the first.
- Timing: one refresh at a time. A manual refresh can run while idle.
- Owner: subscription model.

### C-06 ACL composition
- Input: a route constant, a profile, and an optional custom rules file.
- Output: an ACL file path in the core config.
- Errors: a missing bundled file falls back to `all`. An import failure keeps the cached file.
- Timing: deploy before core start. Refresh asynchronously for the next start.
- Owner: ACL model.

### C-07 Notification
- Input: a profile name, traffic values, a service state.
- Output: a published notification with a disconnect action.
- Errors: code 110004 means the permission is off. The app asks once and retries.
- Timing: publish on connect and update about every 2 s.
- Owner: notification adapter.

### C-08 App selection
- Input: an app list mode and a set of bundle names.
- Output: trusted or blocked application lists in the VPN config.
- Errors: an unavailable app query keeps the stored names and returns a reason, because the names are exact bundle names, the platform ignores an unmatched name, and an empty list would change which apps use the tunnel. A name the query reports absent is dropped.
- Timing: read before the VPN connection is created.
- Owner: model and VPN extension.

## Sequences

### Connect
1. The user taps Connect.
2. The page asks the model to start the selected profile.
3. The model ensures the notification permission.
4. The model asks the VPN extension to start.
5. The extension requests consent when needed.
6. The extension creates the VPN with the tun address, DNS and application lists.
7. The extension calls the native bridge with the config and the tun fd.
8. The bridge returns a code. The extension writes the status file.
9. The page reads the status and moves to Connected or Failed.

Failure: a consent deny or a native error writes a failed status with the message. The page shows it and offers Connect again.

### Profile switch
1. The user selects another profile while connected.
2. The page stops the current tunnel.
3. The model waits until the status is `stopped`. The extension stops the core and writes the session's final traffic record before it records `stopped`.
4. The model settles the session counters. The record carries the profile id and a session token, and the claim is written before the counters are added, so a second settle adds nothing.
5. The model starts the new profile.
6. The page shows Connecting, then Connected.

Failure: a stop timeout leaves the old status. The page reports the timeout and does not start the new profile.

### Subscription refresh
1. The user taps Refresh on one subscription.
2. The model fetches the body.
3. The parser reads the format and returns profiles.
4. The merge keeps ids and counters for re-listed profiles.
5. Missing profiles become obsolete.
6. The page shows the updated count and date.

Failure: the fetch or parse error leaves the old list and shows the message.

## Data design

| Store | Owner | Contents | Lifecycle |
| --- | --- | --- | --- |
| `store/profiles.json` | Profile store | Profile list, order, selection, counters | Lives across restarts |
| `store/subscriptions.json` | Subscription model | URL, name, last update, owned profile keys | Lives across restarts |
| `store/settings.json` | Settings | Service mode, ports, test URLs | Lives across restarts |
| `store/status.json` | VPN extension and model | Phase, profile id, message, error | Rewritten per state change |
| `store/traffic.json` | VPN extension and traffic model | Last sample, profile id, session token, closed and settled flags | Marked settled after settlement. The next session overwrites it. |
| `store/traffic_settled.json` | Traffic model | The token of the last session added to the profile counters | Written before the counters, so a second settle adds nothing. Never written by the extension. |
| `store/traffic_pending.json` | VPN extension and traffic model | An unsettled record that a later start moved aside | Settled first, then removed. Never written by the settler. |
| `filesDir/acl/` | ACL model | Deployed ACL and imported lists | Rebuilt on start and sync |

Consistency: JSON writes use a temporary file and rename. The UI process is the only writer of profiles, subscriptions and settings. The extension is the only writer of status and traffic. Only the UI process settles a traffic record: it claims the record and writes the receipt before it adds the counters.

## Assembly and test boundaries

| Boundary | Entry |
| --- | --- |
| Model unit tests | `entry/src/test/*.test.ets`, host runner |
| Native bridge tests | `entry/src/ohosTest/ets/test/Ability.test.ets` |
| SOCKS e2e | `entry/src/ohosTest/ets/test/SocksE2e.test.ets` |
| VPN e2e | `entry/src/ohosTest/ets/test/VpnE2e.test.ets` |
| Rust core | `native/sslocal-ffi/tests/` |
| Host parity tests | `entry/src/test/Parity*.test.ets` |

## Constraints and gaps

- The tun e2e needs a real device.
- The app picker needs a permission decision.
- The barcode decoder is absent from the public SDK.
- The notification connect action cannot wake the UI process without a platform API.

## Open HLD questions

| ID | Question | Owner |
| --- | --- | --- |
| HQ-1 | Which permission does the app picker need on API 12? | HarmonyOS platform owner |
| HQ-2 | Can the extension write the status file before the first await? | VPN extension owner |
| HQ-3 | Which subscription formats must 5.4.0 accept? | Product owner |
