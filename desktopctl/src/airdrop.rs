//! AirDrop with iPhones through Owly: owlyd lends the Wi-Fi radio, and
//! owly-airdrop speaks the protocol on the `awdl0` it brings up. The daemon
//! half is `daemon/airdrop.rs`; see [[airdrop]].

use crate::{Result, ipc};
use serde::Serialize;
use std::{net::Ipv6Addr, path::PathBuf, time::Duration};

/// How long Everyone stays on, as on an iPhone.
pub const VISIBLE_FOR: Duration = Duration::from_secs(600);

/// What the shell sees.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Status {
    /// How the radio runs here (`shared`, `exclusive`, …); `None` when there
    /// is no radio AirDrop can use.
    pub mode: Option<String>,
    /// The radio is being lent or given back.
    pub busy: bool,
    /// When Everyone ends, in Unix seconds.
    pub visible_until: Option<u64>,
    pub requests: Vec<Ask>,
    pub share: Option<Share>,
}

/// An incoming offer, waiting for an answer or, once accepted, arriving.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Ask {
    pub id: u64,
    pub sender: String,
    pub files: Vec<String>,
    pub urls: Vec<String>,
    pub accepted: bool,
}

/// An outgoing share: what it holds, who can take it, and how sending goes.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Share {
    pub items: Vec<String>,
    pub receivers: Vec<Receiver>,
    pub sending: Option<Sending>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Receiver {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Sending {
    pub to: String,
    /// `asking` · `sending` · `sent` · `declined` · `failed`
    pub state: &'static str,
    pub sent: u64,
    pub total: u64,
    pub error: Option<String>,
}

/// An AWDL peer's IPv6 link-local address, from its MAC (EUI-64).
pub fn link_local(mac: &str) -> Option<Ipv6Addr> {
    let bytes: Vec<u8> = mac
        .split(':')
        .map(|part| u8::from_str_radix(part, 16).ok())
        .collect::<Option<_>>()?;
    let [a, b, c, d, e, f] = bytes[..] else {
        return None;
    };
    let pair = |high: u8, low: u8| u16::from_be_bytes([high, low]);
    Some(Ipv6Addr::new(
        0xfe80,
        0,
        0,
        0,
        pair(a ^ 0x02, b),
        pair(c, 0xff),
        pair(0xfe, d),
        pair(e, f),
    ))
}

/// Where received files go: the XDG download directory.
pub fn downloads() -> Result<PathBuf> {
    match std::env::var_os("XDG_DOWNLOAD_DIR") {
        Some(dir) if !dir.is_empty() => Ok(dir.into()),
        _ => Ok(crate::paths::home_dir()?.join("Downloads")),
    }
}

pub fn run(command: crate::AirDropCommand) -> Result<()> {
    use crate::AirDropCommand::*;
    let (method, params) = match command {
        Status(args) => {
            let status: serde_json::Value = ipc::send_request::<(), _>(
                ipc::methods::AIRDROP_STATUS,
                None,
                ipc::DEFAULT_TIMEOUT,
            )?;
            match args.json {
                true => println!("{status}"),
                false => println!("{}", serde_json::to_string_pretty(&status)?),
            }
            return Ok(());
        }
        Visible { enabled } => (
            ipc::methods::AIRDROP_VISIBLE,
            serde_json::json!({ "enabled": enabled }),
        ),
        Answer { id, accept } => (
            ipc::methods::AIRDROP_ANSWER,
            serde_json::json!({ "id": id, "accept": accept }),
        ),
        Share { paths, url } => {
            let paths = paths
                .iter()
                .map(std::path::absolute)
                .collect::<std::io::Result<Vec<_>>>()?;
            if paths.is_empty() == url.is_empty() {
                return Err(crate::invalid_input("share either files or --url, not both").into());
            }
            (
                ipc::methods::AIRDROP_SHARE,
                serde_json::json!({ "paths": paths, "urls": url }),
            )
        }
        Send { receiver } => (
            ipc::methods::AIRDROP_SEND,
            serde_json::json!({ "receiver": receiver }),
        ),
        Cancel => (ipc::methods::AIRDROP_CANCEL, serde_json::Value::Null),
    };
    ipc::mutate::<serde_json::Value>(method, params, ipc::DEFAULT_TIMEOUT, Duration::ZERO).map(drop)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn link_local_flips_the_universal_bit_and_inserts_fffe() {
        assert_eq!(
            link_local("aa:bb:cc:dd:ee:01"),
            Some("fe80::a8bb:ccff:fedd:ee01".parse().expect("address"))
        );
        assert_eq!(link_local("aa:bb:cc:dd:ee"), None);
        assert_eq!(link_local("aa:bb:cc:dd:ee:zz"), None);
    }
}
