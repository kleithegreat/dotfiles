//! Fn+Esc flips the laptop's top row between F1–F12 and media keys, and the
//! firmware records which. Hyprland runs `desktopctl fn-lock` on each press;
//! the daemon reads the mode and the shell announces it ([[desktopctl]]).

use crate::{Result, ipc};
use std::{fs, io, time::Duration};

const MODE: &str =
    "/sys/devices/virtual/firmware-attributes/dell-wmi-sysman/attributes/FnLockMode/current_value";

/// Whether the top row sends media keys without Fn.
pub fn media_keys() -> io::Result<bool> {
    parse(&fs::read_to_string(MODE)?)
}

fn parse(mode: &str) -> io::Result<bool> {
    match mode.trim() {
        "EnableSecondary" => Ok(true),
        "DisableStandard" => Ok(false),
        other => Err(io::Error::other(format!("unknown Fn-lock mode {other:?}"))),
    }
}

pub fn run() -> Result<()> {
    ipc::mutate::<serde_json::Value>(
        ipc::methods::FN_LOCK_ANNOUNCE,
        serde_json::Value::Null,
        ipc::DEFAULT_TIMEOUT,
        Duration::ZERO,
    )
    .map(drop)
}

#[cfg(test)]
mod tests {
    use super::parse;

    #[test]
    fn reads_both_firmware_modes() {
        assert!(parse("EnableSecondary\n").expect("media"));
        assert!(!parse("DisableStandard\n").expect("standard"));
        assert!(parse("Unknown").is_err());
    }
}
