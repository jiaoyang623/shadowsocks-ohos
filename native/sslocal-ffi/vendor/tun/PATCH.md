# Vendored `tun` 0.7.22 — OpenHarmony address fix

This directory is an unmodified copy of the `tun` crate 0.7.22 from crates.io,
except for the change described below. It is wired in through
`[patch.crates-io]` in `native/sslocal-ffi/Cargo.toml`.

## Why

`tun`'s OpenHarmony backend (`src/platform/ohos/device.rs`) accepts a
pre-configured file descriptor and then answers `Error::NotImplemented` to
`address()`, `netmask()`, `destination()` and `broadcast()`. It has no way to do
otherwise: OpenHarmony hands the app an fd with no interface name to `ioctl`
against, which is also why `tun_name()` there has always returned `""`.

shadowsocks-service's tun serving loop (`crates/shadowsocks-service/src/local/
tun/mod.rs`, `Tun::run`) queries `address()` and `netmask()` **before** entering
its packet loop and returns the error if either fails. The consequence was
severe and thoroughly misleading:

- `sslocal_start_tun_fd()` returned `SSLOCAL_OK`, because it only spawns
  `run_local` on a tokio runtime and never waits for it.
- The extension logged `shadowsocks tun routing started` and reported the
  tunnel as running.
- `run_local` had in fact already exited with `not implementated`.
- No packet was ever read from the tun, so nothing was forwarded, the flow-stat
  counters never moved, and on-screen traffic stayed at `0 B/s`.
- The actual reason was only visible through `sslocal_last_error()`, which
  nothing was reading.

## The change

`src/platform/ohos/device.rs` only:

- `Device` gains a `Configured` field holding the `name`, `address`,
  `destination`, `broadcast` and `netmask` taken from the `Configuration`.
- The four getters return those configured values instead of
  `Err(Error::NotImplemented)`; they still fail if the caller supplied nothing.
- `tun_name()` returns the configured name rather than a hardcoded empty string.

This is sound because the caller is the authority on these values anyway:
shadowsocks-service fills `Configuration::address`/`netmask` from its own
`tun_interface_address` setting, and the app sets that from the same address it
configured the system VPN with. Reading them back cannot disagree with reality
in the way an ioctl-less guess could.

## Keeping this honest

The patch is minimal so that a future version bump is cheap. If upstream `tun`
implements the OpenHarmony getters properly, delete this directory and the
`[patch.crates-io]` entry and pin the fixed release instead.

## Verified

On a Huawei Pura X (HarmonyOS 7.0.0.109): after this change the core stays up,
the flow-stat counters advance, and the app's connectivity probe reports a real
round trip through the tunnel.
