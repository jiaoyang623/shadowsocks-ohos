# E2E status

Date: 2026-10-28
Baseline: `e123804+dirty`

## Resolved

The first attempts failed for two environment reasons. Both are resolved.

1. **ABI.** The emulator reports `x86_64`; the app built `arm64-v8a` only, and
   the install failed with code 9568347. The Rust core now builds for
   `x86_64-unknown-linux-ohos`:

   ```sh
   TARGET=x86_64-unknown-linux-ohos ABI=x86_64 PROFILE=release native/build-ohos.sh
   ```

   `entry/build-profile.json5` carries `["arm64-v8a", "x86_64"]`, and the HAP
   installs on the emulator.

2. **Locked screen and dead display.** With `-noWindow`, the emulator's display
   service stays invalid (`Default screen id 18446744073709551615`), so
   `uitest dumpLayout`, `snapshot_display` and the unlock swipe fail, and
   `aa test` stops with code 10106102. The emulator must run with a window on
   an X display. On this host that is an Xvfb server owned by `w2h`:

   ```sh
   Xvfb :102 -screen 0 1400x3000x24 -nolisten tcp
   DISPLAY=:102 /opt/harmony/sdk/emulator/Emulator -start HVPhone -bootmode coldboot
   ```

   With the window, the screen id is `0`, the layout dump works, and the swipe
   unlocks the device.

## Result

`ci/hos-emulator-e2e.sh` with `SKIP_EMULATOR=1` ran the emulator-capable
suites against a host-side `ssserver`:

- `SslocalNativeTest`: 3 tests.
- `SocksE2eTest`: 2 tests.

`Tests run: 5, Failure: 0, Error: 0, Pass: 5, Ignore: 0`. The host
`ssserver` logged one established tunnel. The full log is `e2e-final.txt`; the
run log is `e2e-steps.json`; the report is `e2e/index.html`.

## Remaining

- `VpnE2eTest` needs real hardware. The emulator never delivers guest traffic
  to the `vpn-tun` interface (`docs/hos-emulator-vpn.md` §2a).
- The connected real phones and tablets are arm64, and they reject the public
  OpenHarmony sample signing material that `native/sign-hap-debug.sh` uses.
  Installing there needs a Huawei developer account and a release profile.
