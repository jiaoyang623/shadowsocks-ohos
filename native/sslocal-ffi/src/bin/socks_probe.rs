/*******************************************************************************
 *                                                                             *
 *  Copyright (C) 2026 by Max Lv <max.c.lv@gmail.com>                          *
 *                                                                             *
 *  This program is free software: you can redistribute it and/or modify       *
 *  it under the terms of the GNU General Public License as published by       *
 *  the Free Software Foundation, either version 3 of the License, or          *
 *  (at your option) any later version.                                        *
 *                                                                             *
 *  This program is distributed in the hope that it will be useful,            *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 *  GNU General Public License for more details.                               *
 *                                                                             *
 *  You should have received a copy of the GNU General Public License          *
 *  along with this program. If not, see <http://www.gnu.org/licenses/>.       *
 *                                                                             *
 *******************************************************************************/

//! Runs the embedded core in SOCKS mode from a JSON config, on the host.
//!
//! The app drives this same core through the same C ABI, but on a phone the
//! only observable is a byte counter and a hanging request. Running it here
//! against the same server and credentials separates "the server is not
//! answering" from "the tun layer is not delivering", which is otherwise
//! indistinguishable from the device.
//!
//!     cargo run --example socks_probe -- <config.json>
//!
//! The config is an ordinary sslocal local config; point `local_port` at
//! something free and drive it with `curl --socks5-hostname`.

use std::ffi::{CStr, CString};

fn main() {
    let path = match std::env::args().nth(1) {
        Some(path) => path,
        None => {
            eprintln!("usage: socks_probe <config.json>");
            std::process::exit(2);
        }
    };
    let json = std::fs::read_to_string(&path).expect("read config");
    let config = CString::new(json).expect("config contains a NUL byte");

    let code = sslocal_core::sslocal_start(config.as_ptr());
    if code != 0 {
        let error = sslocal_core::sslocal_last_error();
        let message = if error.is_null() {
            String::new()
        } else {
            unsafe { CStr::from_ptr(error) }.to_string_lossy().into_owned()
        };
        eprintln!("sslocal_start failed: {code} {message}");
        std::process::exit(1);
    }
    println!("sslocal started; drive it with curl --socks5-hostname 127.0.0.1:<local_port>");
    loop {
        std::thread::sleep(std::time::Duration::from_secs(3600));
    }
}
