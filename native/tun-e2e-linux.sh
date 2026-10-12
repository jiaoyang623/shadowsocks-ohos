#!/usr/bin/env bash
#
# Genuine tun packet-routing e2e (Linux, root/CAP_NET_ADMIN required).
#
# Proves that IP packets sent into a tun device are terminated by the
# shadowsocks tun stack and re-established through the encrypted tunnel:
#
#   client ──▶ tun sstun0 ──▶ sslocal (tun mode) ──ss──▶ ss server ──▶ echo
#            (root netns)                                  (server netns)
#
# The shadowsocks server runs in a separate network namespace so its outbound
# connection to the echo target does not loop back into the tun. The client and
# the sslocal core (fed the tun fd via the same C ABI the HarmonyOS NAPI layer
# uses) run in the root namespace.
#
# Then the same thing for DNS, which the core answers itself rather than
# relaying: a query addressed to a public resolver is answered by the gateway
# named in the tun config, over both UDP and TCP. The control run at the end
# starts the core without one and asserts the same query goes unanswered —
# which is the control that makes the first assertion mean something, since a
# tunnel that simply relays UDP would look identical from the client's side
# until the answer failed to arrive.
#
# Run it inside a privileged container: see run-tun-e2e-docker.sh.
set -euo pipefail

HELPER="${NET_HELPER:-/work/net_helper}"
PASSWORD="tun-e2e-password"
METHOD="aes-256-gcm"
MESSAGE="hello-through-the-tun-packet-router"

# TEST-NET-3 (RFC 5737): unroutable on purpose. An answer addressed from here
# can only have come from the gateway, and the server namespace — which has no
# route off its veth — cannot produce one either, which is what the control
# relies on.
DNS_TARGET=203.0.113.53
DNS_NAME=www.example.com
DNS_ANSWER=203.0.113.7
DNS_GATEWAY=127.0.0.1:5453

[[ -x "$HELPER" ]] || { echo "helper binary not found/executable: $HELPER" >&2; exit 1; }

PIDS=()
TUN_PID=""
# Invoked by the EXIT trap below, which shellcheck cannot see: older versions
# call the body unreachable (SC2317), newer ones call the function unused
# (SC2329).
# shellcheck disable=SC2317,SC2329
cleanup() {
    for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
    ip netns pids ssns 2>/dev/null | xargs -r kill 2>/dev/null || true
    ip netns del ssns 2>/dev/null || true
    ip link del sstun0 2>/dev/null || true
    ip link del veth-r 2>/dev/null || true
}
trap cleanup EXIT

fail() {
    echo "" >&2
    echo "  TUN PACKET ROUTING E2E FAILED: $1" >&2
    exit 1
}

# Idempotent on purpose: the tun device is kept alive by the descriptors the
# core holds, and the second start below re-runs this over whatever survives
# the first core being killed.
set_up_tun() {
    ip tuntap add dev sstun0 mode tun 2>/dev/null || true
    ip addr replace 10.10.0.1/24 dev sstun0
    ip link set sstun0 up
    # only the echo target and the DNS target are routed into the tun; the ss
    # server (10.0.0.2) stays on veth
    ip route replace 10.9.9.9/32 dev sstun0
    ip route replace "$DNS_TARGET/32" dev sstun0
}

# Start sslocal on the tun. $1: extra fields for the tun local, empty for none.
# They belong inside `locals[]`, which is where the per-instance options live —
# a top-level `dns_gateway` is ignored without complaint, and the tun then
# quietly relays DNS instead, which is exactly what this test is here to catch.
start_tun() {
    local config="{\"locals\":[{\"protocol\":\"tun\"$1}],\"server\":\"10.0.0.2\",\"server_port\":8388,\"password\":\"$PASSWORD\",\"method\":\"$METHOD\",\"mode\":\"tcp_and_udp\"}"
    RUST_LOG="${RUST_LOG:-info}" "$HELPER" tun "$config" sstun0 &
    TUN_PID=$!
    PIDS+=("$TUN_PID")
}

echo "=== setting up server network namespace ==="
ip netns add ssns
ip link add veth-r type veth peer name veth-s
ip link set veth-s netns ssns
ip addr add 10.0.0.1/24 dev veth-r
ip link set veth-r up
ip netns exec ssns ip addr add 10.0.0.2/24 dev veth-s
ip netns exec ssns ip link set veth-s up
ip netns exec ssns ip link set lo up
ip netns exec ssns ip addr add 10.9.9.9/32 dev lo

echo "=== creating tun device in root namespace ==="
set_up_tun

echo "=== starting echo + shadowsocks server in server namespace, dns gateway in root ==="
ip netns exec ssns "$HELPER" echo 10.9.9.9:9 &
PIDS+=($!)
SRV_CFG="{\"server\":\"10.0.0.2\",\"server_port\":8388,\"password\":\"$PASSWORD\",\"method\":\"$METHOD\"}"
ip netns exec ssns "$HELPER" server "$SRV_CFG" &
PIDS+=($!)
"$HELPER" dns "$DNS_GATEWAY" "$DNS_ANSWER" &
PIDS+=($!)

echo "=== starting sslocal in tun mode (root namespace) ==="
start_tun ",\"dns_gateway\":\"$DNS_GATEWAY\""

sleep 2

echo "=== client: TCP round-trip to 10.9.9.9:9 through the tun ==="
"$HELPER" client 10.9.9.9:9 "$MESSAGE" || fail "no TCP round-trip through the tun"

echo "=== client: DNS for $DNS_NAME at $DNS_TARGET answered by the gateway ==="
"$HELPER" dnstest udp "$DNS_TARGET:53" "$DNS_NAME" "$DNS_ANSWER" 8 || fail "DNS over UDP was not answered from the tun"
"$HELPER" dnstest tcp "$DNS_TARGET:53" "$DNS_NAME" "$DNS_ANSWER" 8 || fail "DNS over TCP was not answered from the tun"

echo "=== control: with no dns_gateway the same query must go unanswered ==="
kill "$TUN_PID" 2>/dev/null || true
wait "$TUN_PID" 2>/dev/null || true
set_up_tun
start_tun ""
sleep 2

# Without this the control could pass for the wrong reason: a query that never
# entered the tun — no device, no route — is unanswered too.
ip route get "$DNS_TARGET" | grep -q sstun0 || fail "$DNS_TARGET is not routed into the tun"
if "$HELPER" dnstest udp "$DNS_TARGET:53" "$DNS_NAME" "$DNS_ANSWER" 3; then
    fail "a DNS query was answered although no gateway was configured"
fi

echo ""
echo "========================================"
echo "  TUN PACKET ROUTING E2E PASSED"
echo "========================================"
