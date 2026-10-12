//! Multi-role helper for the Linux tun packet-routing e2e (see
//! `harmony/native/tun-e2e-linux.sh`). One static musl binary plays every role
//! so the orchestrating script can drop it into different network namespaces.
//!
//! Subcommands:
//!   echo   <bind_addr>            TCP echo server
//!   server <config_json>         shadowsocks server (shadowsocks_service::run_server)
//!   tun    <config_json> <ifname>  open the persistent tun device <ifname> and
//!                                  route it through the tunnel via the C ABI
//!   client <host:port> <message> connect, send, expect the same bytes back
//!   dns    <bind_addr> <answer_ip>  fake resolver, answering A queries over
//!                                  UDP and TCP — the tun's DNS gateway in the
//!                                  e2e, where the real one would need a name
//!                                  to resolve through the tunnel
//!   dnstest <udp|tcp> <host:port> <name> <expect_ip> <timeout_secs>
//!                                  query `name` there and expect `expect_ip`
//!
//! Not compiled into the shipped library — it is a test/dev tool only.

use std::env;
use std::ffi::CString;
use std::io::{Read, Write};
use std::net::{Ipv4Addr, TcpListener, TcpStream, UdpSocket};
use std::os::fd::RawFd;
use std::process::exit;
use std::thread;
use std::time::Duration;

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: net_helper <echo|server|tun|client> ...");
        exit(2);
    }
    match args[1].as_str() {
        "echo" => run_echo(arg(&args, 2, "echo <bind_addr>")),
        "server" => run_server(arg(&args, 2, "server <config_json>")),
        "tun" => run_tun(
            arg(&args, 2, "tun <config_json> <ifname>"),
            arg(&args, 3, "tun <config_json> <ifname>"),
        ),
        "client" => run_client(
            arg(&args, 2, "client <host:port> <message>"),
            arg(&args, 3, "client <host:port> <message>"),
        ),
        "dns" => run_dns(
            arg(&args, 2, "dns <bind_addr> <answer_ip>"),
            arg(&args, 3, "dns <bind_addr> <answer_ip>"),
        ),
        "dnstest" => {
            const USAGE: &str = "dnstest <udp|tcp> <host:port> <name> <expect_ip> <timeout_secs>";
            if args.len() < 7 {
                eprintln!("usage: net_helper {USAGE}");
                exit(2);
            }
            run_dnstest(&args[2], &args[3], &args[4], &args[5], &args[6])
        }
        other => {
            eprintln!("unknown subcommand: {other}");
            exit(2);
        }
    }
}

/// Positional argument `index`, or a usage error — a missing argument should
/// print what the subcommand expects, not an index-out-of-bounds panic.
fn arg<'a>(args: &'a [String], index: usize, usage: &str) -> &'a str {
    match args.get(index) {
        Some(value) => value,
        None => {
            eprintln!("usage: net_helper {usage}");
            exit(2);
        }
    }
}

fn run_echo(bind: &str) -> ! {
    let listener = TcpListener::bind(bind).expect("echo bind");
    eprintln!("[echo] listening on {bind}");
    for stream in listener.incoming() {
        thread::spawn(move || {
            let mut stream = match stream {
                Ok(s) => s,
                Err(_) => return,
            };
            let mut buf = [0u8; 4096];
            loop {
                match stream.read(&mut buf) {
                    Ok(0) | Err(_) => return,
                    Ok(n) => {
                        if stream.write_all(&buf[..n]).is_err() {
                            return;
                        }
                    }
                }
            }
        });
    }
    exit(0);
}

fn run_server(config_json: &str) -> ! {
    use shadowsocks_service::config::{Config, ConfigType};
    let config = Config::load_from_str(config_json, ConfigType::Server).expect("server config");
    let runtime = tokio::runtime::Runtime::new().expect("runtime");
    eprintln!("[server] starting");
    runtime
        .block_on(shadowsocks_service::run_server(config))
        .expect("run_server");
    exit(0);
}

fn run_tun(config_json: &str, ifname: &str) -> ! {
    let fd = open_tun(ifname).expect("open tun");
    eprintln!("[tun] opened {ifname} as fd {fd}");
    let config = CString::new(config_json).unwrap();
    let code = sslocal_core::sslocal_start_tun_fd(config.as_ptr(), fd);
    if code != 0 {
        let err = sslocal_core::sslocal_last_error();
        let msg = if err.is_null() {
            "<none>".to_owned()
        } else {
            unsafe { std::ffi::CStr::from_ptr(err) }
                .to_string_lossy()
                .into_owned()
        };
        eprintln!("[tun] sslocal_start_tun_fd failed: {code} {msg}");
        exit(1);
    }
    eprintln!("[tun] routing started");
    loop {
        thread::sleep(Duration::from_secs(3600));
    }
}

/// Opens the existing persistent tun device `ifname` (created by
/// `ip tuntap add`) and returns a raw fd with IFF_TUN | IFF_NO_PI, matching
/// the raw L3 packet framing the shadowsocks tun stack expects.
fn open_tun(ifname: &str) -> std::io::Result<RawFd> {
    use std::os::fd::IntoRawFd;

    const TUNSETIFF: u64 = 0x400454ca;
    const IFF_TUN: libc::c_short = 0x0001;
    const IFF_NO_PI: libc::c_short = 0x1000;

    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open("/dev/net/tun")?;
    let fd = file.into_raw_fd();

    let mut ifr: libc::ifreq = unsafe { std::mem::zeroed() };
    let name = ifname.as_bytes();
    for (i, b) in name.iter().enumerate().take(libc::IFNAMSIZ - 1) {
        ifr.ifr_name[i] = *b as libc::c_char;
    }
    ifr.ifr_ifru.ifru_flags = IFF_TUN | IFF_NO_PI;

    let rc = unsafe { libc::ioctl(fd, TUNSETIFF as _, &ifr) };
    if rc < 0 {
        let err = std::io::Error::last_os_error();
        unsafe { libc::close(fd) };
        return Err(err);
    }
    Ok(fd)
}

fn run_client(target: &str, message: &str) -> ! {
    // retry: the tun route + core need a moment to come up
    for attempt in 0..30 {
        match try_client(target, message) {
            Ok(true) => {
                println!("OK");
                exit(0);
            }
            Ok(false) => eprintln!("[client] attempt {attempt}: payload mismatch"),
            Err(e) => eprintln!("[client] attempt {attempt}: {e}"),
        }
        thread::sleep(Duration::from_millis(500));
    }
    eprintln!("[client] FAILED after retries");
    exit(1);
}

fn try_client(target: &str, message: &str) -> std::io::Result<bool> {
    let mut stream = TcpStream::connect(target)?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    stream.set_write_timeout(Some(Duration::from_secs(5)))?;
    stream.write_all(message.as_bytes())?;
    let mut buf = vec![0u8; message.len()];
    stream.read_exact(&mut buf)?;
    Ok(buf == message.as_bytes())
}

// ---------------------------------------------------------------------------
// DNS: a resolver to answer through, and a client to ask with
// ---------------------------------------------------------------------------

/// Answers every query with one A record for `answer`, over UDP and TCP.
///
/// Standing in for the core's own resolver, which is what the app points the
/// tun's `dns_gateway` at: a real one would have to resolve a name through the
/// tunnel to answer, which would make this test depend on the internet.
fn run_dns(bind: &str, answer: &str) -> ! {
    let answer: Ipv4Addr = answer.parse().expect("answer_ip");

    let listener = TcpListener::bind(bind).expect("dns tcp bind");
    thread::spawn(move || serve_dns_tcp(listener, answer));

    let socket = UdpSocket::bind(bind).expect("dns udp bind");
    eprintln!("[dns] listening on {bind} (udp and tcp), answering A {answer}");

    let mut buf = vec![0u8; 4096];
    loop {
        let (n, peer) = match socket.recv_from(&mut buf) {
            Ok(v) => v,
            Err(err) => {
                eprintln!("[dns] recv failed: {err}");
                continue;
            }
        };
        match dns_response(&buf[..n], answer) {
            Some(response) => match socket.send_to(&response, peer) {
                Ok(_) => eprintln!("[dns] answered {} bytes to {peer}", response.len()),
                Err(err) => eprintln!("[dns] send to {peer} failed: {err}"),
            },
            None => eprintln!("[dns] could not parse the query from {peer}"),
        }
    }
}

/// DNS over TCP is the same message behind a two-byte length prefix, in both
/// directions — a stream the tun relays without looking inside it.
fn serve_dns_tcp(listener: TcpListener, answer: Ipv4Addr) -> ! {
    for stream in listener.incoming() {
        let Ok(mut stream) = stream else { continue };
        thread::spawn(move || {
            let mut len = [0u8; 2];
            if stream.read_exact(&mut len).is_err() {
                return;
            }
            let mut query = vec![0u8; u16::from_be_bytes(len) as usize];
            if stream.read_exact(&mut query).is_err() {
                return;
            }
            if let Some(response) = dns_response(&query, answer) {
                let mut framed = (response.len() as u16).to_be_bytes().to_vec();
                framed.extend_from_slice(&response);
                match stream.write_all(&framed) {
                    Ok(()) => eprintln!("[dns] answered {} bytes over tcp", response.len()),
                    Err(err) => eprintln!("[dns] tcp write failed: {err}"),
                }
            }
        });
    }
    exit(0)
}

/// Where the first question ends, or `None` if this is not one uncompressed
/// question. Every query is written that way; compression pointers belong to
/// answers, which this side never has to read.
fn question_end(message: &[u8]) -> Option<usize> {
    if message.len() < 12 {
        return None;
    }
    let mut end = 12;
    loop {
        match *message.get(end)? {
            0 => {
                // the root label, then QTYPE and QCLASS
                end += 5;
                break;
            }
            // a compression pointer, or one of the reserved label types
            n if (n & 0xc0) != 0 => return None,
            n => end += 1 + n as usize,
        }
    }
    (end <= message.len()).then_some(end)
}

/// A reply to `query`: the question echoed, one A record pointing at `answer`,
/// and nothing after it. `check_response` relies on that last part.
fn dns_response(query: &[u8], answer: Ipv4Addr) -> Option<Vec<u8>> {
    let end = question_end(query)?;

    let mut response = Vec::with_capacity(end + 16);
    response.extend_from_slice(&query[0..2]); // the transaction id
    response.extend_from_slice(&[0x81, 0x80]); // QR, RD, RA, NOERROR
    response.extend_from_slice(&1u16.to_be_bytes()); // qdcount
    response.extend_from_slice(&1u16.to_be_bytes()); // ancount
    response.extend_from_slice(&0u16.to_be_bytes()); // nscount
    response.extend_from_slice(&0u16.to_be_bytes()); // arcount
    response.extend_from_slice(&query[12..end]); // the question
    response.extend_from_slice(&[0xc0, 0x0c]); // name: pointer to the question
    response.extend_from_slice(&1u16.to_be_bytes()); // type A
    response.extend_from_slice(&1u16.to_be_bytes()); // class IN
    response.extend_from_slice(&60u32.to_be_bytes()); // ttl
    response.extend_from_slice(&4u16.to_be_bytes()); // rdlength
    response.extend_from_slice(&answer.octets());
    Some(response)
}

/// A recursive query for the A record of `name`.
fn dns_query(id: u16, name: &str) -> Vec<u8> {
    let mut query = Vec::new();
    query.extend_from_slice(&id.to_be_bytes());
    query.extend_from_slice(&[0x01, 0x00]); // RD
    query.extend_from_slice(&1u16.to_be_bytes()); // qdcount
    query.extend_from_slice(&0u16.to_be_bytes()); // ancount
    query.extend_from_slice(&0u16.to_be_bytes()); // nscount
    query.extend_from_slice(&0u16.to_be_bytes()); // arcount
    for label in name.trim_end_matches('.').split('.') {
        query.push(label.len() as u8);
        query.extend_from_slice(label.as_bytes());
    }
    query.push(0); // the root label
    query.extend_from_slice(&1u16.to_be_bytes()); // type A
    query.extend_from_slice(&1u16.to_be_bytes()); // class IN
    query
}

fn run_dnstest(proto: &str, server: &str, name: &str, expect: &str, timeout_secs: &str) -> ! {
    const ID: u16 = 0x4242;
    let expect: Ipv4Addr = expect.parse().expect("expect_ip");
    let timeout = Duration::from_secs(timeout_secs.parse().expect("timeout_secs"));
    let query = dns_query(ID, name);

    let answer = match proto {
        "udp" => dnstest_udp(server, &query, timeout),
        "tcp" => dnstest_tcp(server, &query, timeout),
        other => {
            eprintln!("[dnstest] unknown transport {other} (want udp or tcp)");
            exit(2);
        }
    };

    // A transport failure and an answer that is not the one expected are both
    // just "this did not work"; only the text differs.
    let checked = match answer {
        Ok(response) => check_response(ID, &response, expect),
        Err(err) => Err(err.to_string()),
    };

    match checked {
        Ok(()) => {
            println!("OK");
            exit(0);
        }
        Err(err) => {
            eprintln!("[dnstest] {proto} {name} -> {server}: {err}");
            exit(1);
        }
    }
}

fn dnstest_udp(server: &str, query: &[u8], timeout: Duration) -> std::io::Result<Vec<u8>> {
    // Connected, the way a resolver does it: the answer arrives with the
    // address the query was sent *to* as its source, and only something
    // answering in the tun's stead can arrange that.
    let socket = UdpSocket::bind("0.0.0.0:0")?;
    socket.set_read_timeout(Some(timeout))?;
    socket.connect(server)?;
    socket.send(query)?;

    let mut buf = vec![0u8; 4096];
    let n = socket.recv(&mut buf)?;
    buf.truncate(n);
    Ok(buf)
}

fn dnstest_tcp(server: &str, query: &[u8], timeout: Duration) -> std::io::Result<Vec<u8>> {
    let mut stream = TcpStream::connect(server)?;
    stream.set_read_timeout(Some(timeout))?;
    stream.set_write_timeout(Some(timeout))?;

    let mut framed = (query.len() as u16).to_be_bytes().to_vec();
    framed.extend_from_slice(query);
    stream.write_all(&framed)?;

    let mut len = [0u8; 2];
    stream.read_exact(&mut len)?;
    let mut response = vec![0u8; u16::from_be_bytes(len) as usize];
    stream.read_exact(&mut response)?;
    Ok(response)
}

/// Checks that `response` answers `id` and carries `expect`. The responder
/// appends its one answer last and puts nothing after it, which is what makes
/// the tail of the message the address rather than a guess at an offset.
fn check_response(id: u16, response: &[u8], expect: Ipv4Addr) -> Result<(), String> {
    if response.len() < 12 {
        return Err(format!(
            "reply of {} bytes is too short to be a DNS message",
            response.len()
        ));
    }
    if response[0..2] != id.to_be_bytes() {
        return Err("reply carries a different transaction id".to_owned());
    }
    if (response[2] & 0x80) == 0 {
        return Err("reply does not have the response bit set".to_owned());
    }
    if response[response.len() - 4..] != expect.octets() {
        return Err(format!(
            "reply does not end with the expected address {expect}"
        ));
    }
    Ok(())
}
