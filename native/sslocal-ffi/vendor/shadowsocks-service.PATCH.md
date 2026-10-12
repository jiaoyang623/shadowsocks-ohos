# Vendored `shadowsocks-service` 1.23.4 — tun DNS gateway

This directory is a copy of `crates/shadowsocks-service` from the pinned core
checkout, with the change described below applied. `shadowsocks-service.patch`
next to this file is that change, and `native/vendor-shadowsocks-service.sh`
regenerates the directory from the checkout and re-applies the patch.

Everything under `shadowsocks-service/` is replaced wholesale by that script;
this file and the patch sit outside it so that reapplying the change cannot
destroy the record of what the change is.

## Why

`local-tun` relays UDP by handing every datagram to the proxy, and that is only
usable when the shadowsocks server relays UDP. Plenty do not. DNS is what makes
that fatal rather than inconvenient: clients that pick their own resolver —
web browsers above all — send their queries straight at it and wait forever, so
everything addressed by name becomes unreachable while the tunnel itself is
carrying traffic perfectly well. Clients that go through the system resolver
keep working, which makes it look like the tunnel is fine and one application
is broken.

Observed on a Huawei Pura X against a server without UDP relay: the browser
reported `ERR_NAME_NOT_RESOLVED` for google.com while the app's own probe
succeeded. `log` at Debug level showed the two populations side by side — the
core's own DNS server answering a query, and `UDP 172.19.0.1:40444 ->
223.5.5.5:53 payload.size: 32` going out to die in the relay.

Upstream has no answer for this. `grep -rni dnsgw` finds nothing in 1.23.4 or
in master, and `local/tun/` contains no DNS logic at all. Android gets it from
go-tun2socks instead: `shadowsocks-android/.../bg/VpnService.kt` runs
`Executable.TUN2SOCKS` with `--dnsgw 127.0.0.1:<port>`, points clients at the
tun's *router* address (`172.19.0.2`, not the client's own `172.19.0.1`), and
answers them from a local worker. This patch is the same idea, in the core the
HarmonyOS client actually uses.

## The change

`dns_gateway: Option<SocketAddr>` on the local config, and a new
`local/tun/dns.rs` that uses it:

- UDP and TCP packets arriving on the tun with destination port 53 are taken
  off the relay path and sent to the gateway on the transport they arrived on,
  so a truncated UDP answer still makes the client retry over TCP and land back
  here. With no gateway configured nothing is intercepted and the tun behaves
  exactly as before.
- Answers are wrapped in the IP and UDP headers that carry them back, using the
  `etherparse::PacketBuilder` pattern `local/tun/udp.rs` already uses for relayed
  UDP replies. The address the query was sent to becomes the source, so the
  answer looks like it came from whichever resolver the client chose.
- Queries are answered on their own task, bounded by a semaphore and a 5 s
  timeout, so a slow gateway never stalls the packet loop and a flood cannot
  exhaust descriptors.

The interception is checked *before* the `mode` gate. Resolving names is a
property of the tun, not of proxying UDP, and it has to keep working for a
caller that dropped to `tcp_only` precisely because UDP was getting nowhere.

Second, smaller part: `remote_dns_protocol: Option<Mode>` on the local config,
which `DnsBuilder` passes to `DnsClient` as the transport for `lookup_remote`
only — listeners are still chosen by `mode`. `DnsClient::lookup_remote_inner`
otherwise races a UDP query against a TCP one it does not start for another
500–1500 ms, which on a server that cannot relay UDP is a wait that can never
be won, paid by every uncached lookup.

## One consequence of the plumbing

The crate is a path dependency *inside* the FFI's workspace, which makes it a
workspace member. That is deliberate: it is the only way `cargo test
--workspace` builds it with the features the app actually enables, so the tests
above run against the configuration that ships rather than a plausible-looking
one. Adding `exclude` or a nested `[workspace]` would avoid that, at the cost
of having to repeat the feature list at every call site — and repeating it is
how the two drift apart.

The visible price is `Cargo.lock`: member crates are locked with every optional
dependency, so the file grows by ~90 entries (rocksdb, bson, h3, bindgen and
friends) that nothing here ever builds. It costs a few hundred lines of lock
file and nothing at build or download time.

Membership reaches `cargo fmt` too. `cargo fmt --all -- --check` in `lint.yml`
formats every member, so it formats this crate — and this crate is formatted
with settings that live at the root of the shadowsocks-rust checkout rather
than in the crate, most visibly `max_width = 120`. Judged by rustfmt's defaults
instead, upstream disagrees with itself in ~2300 hunks. `rustfmt.toml` here is
a copy of those settings and is refreshed with everything else, so the vendored
tree is checked against the rules it was written to. It is the one file in the
directory that the patch does not create.

## Keeping this honest

- Nothing here is HarmonyOS-specific and the patch is meant to be offered
  upstream. The JSON key is the whole interface the app needs; a CLI flag would
  go in the checkout's own `src/bin/sslocal.rs`, which is not vendored.
- When the pin in `.github/actions/rust-core/action.yml` moves, run
  `native/vendor-shadowsocks-service.sh`; if the patch no longer applies, rebase
  it against the new `crates/shadowsocks-service` and regenerate.
- To regenerate the patch after editing the vendored tree, copy the crate from
  the checkout to `a/` and the vendored tree to `b/` in a temporary directory,
  delete `b/rustfmt.toml` (it is not part of the change), and from that
  directory run

      git diff --no-index --no-prefix a b | sed 's|^diff --git b/|diff --git a/|'

  The two directory names and `--no-prefix` are what make the paths come out as
  the `a/src/...` / `b/src/...` that `git apply` expects; the `sed` is because
  git names both sides after `b` for a file that exists only there. Then run
  the refresh script: it re-derives the directory from the checkout and the new
  patch, so a `git status` that shows nothing afterwards is the proof that the
  two agree.
- The vendored crate must stay in step with the sibling checkout's
  `shadowsocks` crate: the patch only repoints that dependency, it does not pin
  a version of it.
- The one hunk in `Cargo.toml` is vendoring plumbing rather than part of the
  change: it rewrites the in-workspace `path = "../shadowsocks"` dependency to
  reach back out to the checkout, since only this crate is copied. Drop that
  hunk when offering the rest upstream.
- If upstream grows a tun DNS option of its own, delete this directory, the
  patch, the script and the `vendor/shadowsocks-service` path in
  `native/sslocal-ffi/Cargo.toml`, and pin the release that has it.

## Verified

- `cargo test --workspace --lib local::tun::dns` — interception decision, reply
  construction, a real round trip through a UDP gateway, and the no-gateway and
  no-answer paths.
- On a Huawei Pura X (HarmonyOS 7.0.0.109): the core logs `shadowsocks dns TCP
  listening on 127.0.0.1:5453`, the browser's own resolver is answered — the
  core logs `DNS lookup A www.google.com.` and then `lh3.google.com`,
  `play.google.com` as the page loads — and google.com renders in the browser
  over a server that relays no UDP at all.
