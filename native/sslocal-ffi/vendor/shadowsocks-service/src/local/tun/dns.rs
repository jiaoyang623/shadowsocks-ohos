//! Answer DNS queries received on the tun, instead of relaying them as UDP.
//!
//! Relaying only works when the server relays UDP, and plenty do not. Client
//! DNS is the one flow that cannot survive that: a browser resolving names
//! through its own UDP client, or any resolver the system handed out, silently
//! times out, and everything addressed by name becomes unreachable even though
//! the tunnel itself is carrying traffic perfectly well. go-tun2socks answers
//! this with its `dnsgw` option, and this is the same idea — port 53 comes off
//! the relay path and goes to a resolver the caller nominates, over the
//! transport the query arrived on so the client sees the framing it expects.

use std::{
    io::{self, ErrorKind},
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    sync::Arc,
    time::Duration,
};

use bytes::{BufMut, BytesMut};
use etherparse::PacketBuilder;
use log::{debug, trace, warn};
use tokio::{
    io::copy_bidirectional,
    net::{TcpStream, UdpSocket},
    sync::{Semaphore, mpsc},
    time,
};

use super::tcp::TcpConnection;

/// The port that makes a packet a DNS query.
const DNS_PORT: u16 = 53;

/// How long to wait for the gateway's answer before giving up.
///
/// Our gateway resolves through the proxy, which costs a round trip; a UDP DNS
/// client retries on its own, so dropping a query that takes longer than this
/// is better than letting them pile up.
const QUERY_TIMEOUT: Duration = Duration::from_secs(5);

/// Largest answer we will read back. TCP DNS caps at 65535 and EDNS0 keeps UDP
/// well below it, so this is simply as large as it can be.
const MAX_RESPONSE_SIZE: usize = 65535;

/// How many queries may be in flight at once.
///
/// Each one holds an ephemeral socket, so this is what stops a flood of
/// lookups from exhausting descriptors. Past it queries are dropped and the
/// client retries, which is what it would do after a timeout anyway.
const MAX_INFLIGHT: usize = 64;

/// Forwards DNS queries from the tun to a resolver the caller nominated.
#[derive(Clone)]
pub struct DnsTun {
    gateway: Option<SocketAddr>,
    tun_tx: mpsc::Sender<BytesMut>,
    inflight: Arc<Semaphore>,
}

impl DnsTun {
    pub fn new(gateway: Option<SocketAddr>, tun_tx: mpsc::Sender<BytesMut>) -> DnsTun {
        DnsTun {
            gateway,
            tun_tx,
            inflight: Arc::new(Semaphore::new(MAX_INFLIGHT)),
        }
    }

    /// Whether a packet addressed to `dst` is answered here rather than
    /// relayed.
    ///
    /// Without a gateway nothing is intercepted, which is what keeps this
    /// inert for every caller that does not ask for it.
    pub fn intercepts(&self, dst: SocketAddr) -> bool {
        self.gateway.is_some() && dst.port() == DNS_PORT
    }

    /// Hand a UDP query to the gateway and write the answer back into the tun.
    ///
    /// Returns immediately: the query is answered on its own task so a gateway
    /// that is slow — ours resolves through the proxy, which is a round trip —
    /// never stalls the tun's packet loop.
    pub fn forward_udp(&self, src: SocketAddr, dst: SocketAddr, payload: &[u8]) {
        let Some(gateway) = self.gateway else {
            return;
        };

        let Ok(permit) = self.inflight.clone().try_acquire_owned() else {
            warn!("dns gateway busy, dropping query {} -> {}", src, dst);
            return;
        };

        let tun_tx = self.tun_tx.clone();
        let query = BytesMut::from(payload);

        tokio::spawn(async move {
            let _permit = permit;

            let response = match query_udp(gateway, &query).await {
                Ok(response) => response,
                Err(err) => {
                    debug!("dns query {} -> {} failed: {}", src, dst, err);
                    return;
                }
            };

            trace!("dns answer {} -> {}, {} bytes", dst, src, response.len());

            let packet = match build_udp_reply(src, dst, &response) {
                Ok(packet) => packet,
                Err(err) => {
                    debug!("dns answer {} -> {} could not be packed: {}", dst, src, err);
                    return;
                }
            };

            if tun_tx.send(packet).await.is_err() {
                debug!("tun closed before the dns answer {} -> {} was written", dst, src);
            }
        });
    }

    /// Relay a TCP DNS connection to the gateway.
    ///
    /// DNS over TCP is a length-prefixed stream, so a byte copy is all the
    /// translation this needs — including for a client that fell back to TCP
    /// because an answer came back over UDP truncated.
    pub async fn relay_tcp(&self, connection: TcpConnection, src: SocketAddr, dst: SocketAddr) -> io::Result<()> {
        let Some(addr) = self.gateway else {
            return Ok(());
        };

        let Ok(_permit) = self.inflight.clone().try_acquire_owned() else {
            warn!("dns gateway busy, dropping TCP query {} -> {}", src, dst);
            return Ok(());
        };

        let mut gateway = match TcpStream::connect(addr).await {
            Ok(gateway) => gateway,
            Err(err) => {
                debug!("dns gateway {} unreachable, {} -> {}: {}", addr, src, dst, err);
                return Ok(());
            }
        };

        let mut connection = connection;

        debug!("established TCP dns relay {} -> {} via {}", src, dst, addr);

        match copy_bidirectional(&mut connection, &mut gateway).await {
            Ok((up, down)) => trace!("TCP dns relay {} -> {} finished, {} up, {} down", src, dst, up, down),
            Err(err) => debug!("TCP dns relay {} -> {} failed: {}", src, dst, err),
        }

        Ok(())
    }
}

/// Send one query to the gateway and read its answer.
async fn query_udp(gateway: SocketAddr, query: &[u8]) -> io::Result<BytesMut> {
    // A socket per query: the answer comes back to a port nothing else shares,
    // which is what keeps concurrent lookups from having to be matched up by
    // hand. UDP has no handshake, so this is cheap.
    let bind = if gateway.is_ipv4() {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 0)
    } else {
        SocketAddr::new(IpAddr::V6(Ipv6Addr::UNSPECIFIED), 0)
    };

    let socket = UdpSocket::bind(bind).await?;
    socket.connect(gateway).await?;
    socket.send(query).await?;

    let mut buffer = vec![0u8; MAX_RESPONSE_SIZE];
    let n = time::timeout(QUERY_TIMEOUT, socket.recv(&mut buffer)).await??;
    buffer.truncate(n);

    Ok(BytesMut::from(&buffer[..]))
}

/// Wrap an answer in the IP and UDP headers that carry it back to the client.
///
/// The address the query was sent to becomes the source, which is what makes
/// the reply look like it came from the resolver the client chose — whichever
/// one that was.
fn build_udp_reply(src: SocketAddr, dst: SocketAddr, payload: &[u8]) -> io::Result<BytesMut> {
    match (dst, src) {
        (SocketAddr::V4(server), SocketAddr::V4(client)) => {
            let builder = PacketBuilder::ipv4(server.ip().octets(), client.ip().octets(), 20)
                .udp(server.port(), client.port());

            let packet = BytesMut::with_capacity(builder.size(payload.len()));
            let mut packet_writer = packet.writer();
            builder
                .write(&mut packet_writer, payload)
                .expect("PacketBuilder::write");

            Ok(packet_writer.into_inner())
        }
        (SocketAddr::V6(server), SocketAddr::V6(client)) => {
            let builder = PacketBuilder::ipv6(server.ip().octets(), client.ip().octets(), 20)
                .udp(server.port(), client.port());

            let packet = BytesMut::with_capacity(builder.size(payload.len()));
            let mut packet_writer = packet.writer();
            builder
                .write(&mut packet_writer, payload)
                .expect("PacketBuilder::write");

            Ok(packet_writer.into_inner())
        }
        _ => Err(io::Error::new(
            ErrorKind::InvalidData,
            "source and destination type unmatch",
        )),
    }
}

#[cfg(test)]
mod tests {
    use etherparse::{NetSlice, SlicedPacket, TransportSlice};
    use tokio::net::UdpSocket;

    use super::*;

    /// A DNS answer, in the shape a gateway would return one.
    const ANSWER: &[u8] = b"\x12\x34\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00answer";

    /// A gateway that answers every query with [`ANSWER`].
    async fn spawn_gateway() -> SocketAddr {
        let socket = UdpSocket::bind("127.0.0.1:0").await.expect("bind gateway");
        let addr = socket.local_addr().expect("gateway address");

        tokio::spawn(async move {
            let mut buffer = [0u8; 512];
            while let Ok((_, peer)) = socket.recv_from(&mut buffer).await {
                let _ = socket.send_to(ANSWER, peer).await;
            }
        });

        addr
    }

    fn addr(s: &str) -> SocketAddr {
        s.parse().expect("test address")
    }

    #[test]
    fn intercepts_the_dns_port_only_when_a_gateway_is_configured() {
        let (tx, _rx) = mpsc::channel(1);

        let without = DnsTun::new(None, tx.clone());
        assert!(!without.intercepts(addr("223.5.5.5:53")));

        let with = DnsTun::new(Some(addr("127.0.0.1:5353")), tx);
        assert!(with.intercepts(addr("223.5.5.5:53")));
        assert!(with.intercepts(addr("1.1.1.1:53")));
        assert!(!with.intercepts(addr("223.5.5.5:443")));
    }

    #[test]
    fn a_reply_wears_the_address_the_query_was_sent_to() {
        let packet = build_udp_reply(addr("172.19.0.1:40000"), addr("223.5.5.5:53"), ANSWER).expect("reply");

        let sliced = SlicedPacket::from_ip(&packet).expect("reply is not an IP packet");

        match sliced.net {
            Some(NetSlice::Ipv4(ip)) => {
                assert_eq!(ip.header().source(), [223, 5, 5, 5], "source is the resolver");
                assert_eq!(ip.header().destination(), [172, 19, 0, 1], "destination is the client");
            }
            _ => panic!("expected an IPv4 reply, got {:?}", sliced.net),
        }

        match sliced.transport {
            Some(TransportSlice::Udp(udp)) => {
                assert_eq!(udp.source_port(), 53);
                assert_eq!(udp.destination_port(), 40000);
                assert_eq!(udp.payload(), ANSWER);
            }
            _ => panic!("expected a UDP reply, got {:?}", sliced.transport),
        }
    }

    #[test]
    fn a_reply_between_mismatched_families_is_refused() {
        assert!(build_udp_reply(addr("172.19.0.1:40000"), addr("[2001:db8::1]:53"), ANSWER).is_err());
    }

    #[tokio::test]
    async fn a_udp_query_is_answered_and_written_back_to_the_tun() {
        let gateway = spawn_gateway().await;

        let (tun_tx, mut tun_rx) = mpsc::channel(4);
        let dns = DnsTun::new(Some(gateway), tun_tx);

        let src = addr("172.19.0.1:40000");
        let dst = addr("223.5.5.5:53");
        dns.forward_udp(src, dst, b"\x12\x34\x01\x00query");

        let packet = time::timeout(Duration::from_secs(5), tun_rx.recv())
            .await
            .expect("no answer was written back within the timeout")
            .expect("the tun channel closed");

        let sliced = SlicedPacket::from_ip(&packet).expect("not an IP packet");
        match sliced.transport {
            Some(TransportSlice::Udp(udp)) => assert_eq!(udp.payload(), ANSWER),
            _ => panic!("expected a UDP reply, got {:?}", sliced.transport),
        }
    }

    #[tokio::test]
    async fn a_query_with_no_gateway_writes_nothing_back() {
        let (tun_tx, mut tun_rx) = mpsc::channel(4);
        let dns = DnsTun::new(None, tun_tx);

        dns.forward_udp(addr("172.19.0.1:40000"), addr("223.5.5.5:53"), b"query");

        // Nothing was spawned, so there is nothing to wait for: give the
        // runtime a chance to run anything that was, then look.
        tokio::task::yield_now().await;
        assert!(tun_rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn a_query_the_gateway_never_answers_is_dropped() {
        // Bound but never read from, so the answer never comes.
        let silent = UdpSocket::bind("127.0.0.1:0").await.expect("bind gateway");
        let gateway = silent.local_addr().expect("gateway address");

        let (tun_tx, mut tun_rx) = mpsc::channel(4);
        let dns = DnsTun::new(Some(gateway), tun_tx);

        dns.forward_udp(addr("172.19.0.1:40000"), addr("223.5.5.5:53"), b"query");

        // Past the query timeout: the task gives up, and nothing is written.
        time::sleep(QUERY_TIMEOUT + Duration::from_secs(1)).await;
        assert!(tun_rx.try_recv().is_err());
    }
}
