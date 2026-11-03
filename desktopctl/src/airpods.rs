//! AirPods: Apple's accessory protocol (AAP) over L2CAP for a connected
//! pair, and the proximity advert a case broadcasts over BLE while its lid is
//! open. Wire formats are LibrePods' (`AAP Definitions.md`, `Proximity
//! Pairing Message.md` and its `blemanager.cpp`, which wins where the two
//! disagree). The daemon half is `daemon/airpods.rs`; see [[airpods]].

use crate::{Result, ipc};
use serde::{Deserialize, Serialize};

pub const PSM: u16 = 0x1001;
/// The service BlueZ lists for a device that speaks AAP.
pub const SERVICE_UUID: &str = "74ec2172-0bad-4d01-8f77-997b2be0722a";
pub const APPLE: u16 = 0x004c;
/// Manufacturer-data prefix of the proximity advert, after the company ID.
pub const PROXIMITY: u8 = 0x07;

pub const HANDSHAKE: [u8; 16] = [
    0x00, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];
/// Unlocks adaptive transparency, and conversational awareness during playback.
pub const FEATURES: [u8; 14] = [
    0x04, 0x00, 0x04, 0x00, 0x4d, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];
pub const NOTIFY: [u8; 10] = [0x04, 0x00, 0x04, 0x00, 0x0f, 0x00, 0xff, 0xff, 0xff, 0xff];

const HEADER: [u8; 4] = [0x04, 0x00, 0x04, 0x00];
const BATTERY: u8 = 0x04;
const EARS: u8 = 0x06;
const CONTROL: u8 = 0x09;
const NOISE: u8 = 0x0d;
const AWARENESS: u8 = 0x28;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, clap::ValueEnum)]
#[serde(rename_all = "snake_case")]
pub enum NoiseMode {
    Off,
    Anc,
    Transparency,
    Adaptive,
}

impl NoiseMode {
    fn byte(self) -> u8 {
        match self {
            Self::Off => 1,
            Self::Anc => 2,
            Self::Transparency => 3,
            Self::Adaptive => 4,
        }
    }

    fn from_byte(byte: u8) -> Option<Self> {
        [Self::Off, Self::Anc, Self::Transparency, Self::Adaptive]
            .into_iter()
            .find(|mode| mode.byte() == byte)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Pod {
    InEar,
    OutOfEar,
    InCase,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Cell {
    pub level: u8,
    pub charging: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Batteries {
    pub left: Option<Cell>,
    pub right: Option<Cell>,
    pub case: Option<Cell>,
}

/// A pair holding an AAP channel. Fields stay `None` until the pair reports them.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct Link {
    pub address: String,
    pub name: String,
    pub battery: Batteries,
    /// Primary pod first; the primary is whichever holds the microphone.
    pub ears: Option<[Pod; 2]>,
    pub noise: Option<NoiseMode>,
    pub awareness: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Update {
    Battery(Batteries),
    Ears([Pod; 2]),
    Noise(NoiseMode),
    Awareness(bool),
}

pub fn parse(packet: &[u8]) -> Option<Update> {
    let body = packet.strip_prefix(&HEADER)?;
    match *body {
        [BATTERY, 0x00, count, ref cells @ ..] => {
            let mut battery = Batteries::default();
            for &[component, _, level, status, _] in cells.as_chunks().0.iter().take(count.into()) {
                let slot = match component {
                    0x02 => &mut battery.right,
                    0x04 => &mut battery.left,
                    0x08 => &mut battery.case,
                    _ => continue,
                };
                // 0x04 is "disconnected": the component is not there to report.
                if status != 0x04 {
                    *slot = Some(Cell {
                        level: level.min(100),
                        charging: status == 0x01,
                    });
                }
            }
            Some(Update::Battery(battery))
        }
        [EARS, 0x00, primary, secondary, ..] => {
            Some(Update::Ears([pod(primary)?, pod(secondary)?]))
        }
        [CONTROL, 0x00, NOISE, mode, ..] => NoiseMode::from_byte(mode).map(Update::Noise),
        [CONTROL, 0x00, AWARENESS, 0x01, ..] => Some(Update::Awareness(true)),
        [CONTROL, 0x00, AWARENESS, 0x02, ..] => Some(Update::Awareness(false)),
        _ => None,
    }
}

fn pod(byte: u8) -> Option<Pod> {
    match byte {
        0x00 => Some(Pod::InEar),
        0x01 => Some(Pod::OutOfEar),
        0x02 => Some(Pod::InCase),
        _ => None,
    }
}

impl Link {
    pub fn apply(&mut self, update: Update) {
        match update {
            Update::Battery(battery) => self.battery = battery,
            Update::Ears(ears) => self.ears = Some(ears),
            Update::Noise(mode) => self.noise = Some(mode),
            Update::Awareness(on) => self.awareness = Some(on),
        }
    }
}

fn control(setting: u8, value: u8) -> [u8; 11] {
    [
        0x04, 0x00, 0x04, 0x00, CONTROL, 0x00, setting, value, 0x00, 0x00, 0x00,
    ]
}

pub fn set_noise(mode: NoiseMode) -> [u8; 11] {
    control(NOISE, mode.byte())
}

pub fn set_awareness(on: bool) -> [u8; 11] {
    control(AWARENESS, if on { 0x01 } else { 0x02 })
}

/// A case seen through its proximity advert.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Nearby {
    /// The BR/EDR product ID, as BlueZ's `Modalias` spells it once paired.
    pub product: u16,
    pub model: &'static str,
    pub lid_open: bool,
    pub battery: Batteries,
    /// The address of a pair with this product ID already paired here; the
    /// advert itself only carries a rotating random address.
    pub paired: Option<String>,
    pub rssi: i16,
}

/// `data` is Apple's manufacturer data, company ID already stripped.
pub fn proximity(data: &[u8], rssi: i16) -> Option<Nearby> {
    let [PROXIMITY, _, _, high, low, status, pods, flags, lid, ..] = *data else {
        return None;
    };
    let product = u16::from_le_bytes([high, low]);
    let left_primary = status & 0x20 != 0;
    let (left, right) = match left_primary {
        true => (pods & 0x0f, pods >> 4),
        false => (pods >> 4, pods & 0x0f),
    };
    let charge = flags >> 4;
    let (left_charging, right_charging) = match left_primary {
        true => (charge & 0x01 != 0, charge & 0x02 != 0),
        false => (charge & 0x02 != 0, charge & 0x01 != 0),
    };
    Some(Nearby {
        product,
        model: model(product)?,
        lid_open: lid & 0x08 == 0,
        battery: Batteries {
            left: cell(left, left_charging),
            right: cell(right, right_charging),
            case: cell(flags & 0x0f, charge & 0x04 != 0),
        },
        paired: None,
        rssi,
    })
}

/// Levels come in tenths; 0xf is "unknown".
fn cell(nibble: u8, charging: bool) -> Option<Cell> {
    (nibble != 0x0f).then(|| Cell {
        level: (nibble * 10).min(100),
        charging,
    })
}

fn model(product: u16) -> Option<&'static str> {
    Some(match product {
        0x2002 | 0x200f | 0x2013 => "AirPods",
        0x2019 | 0x201b => "AirPods 4",
        0x200a | 0x201f => "AirPods Max",
        0x200e | 0x2014 | 0x2024 => "AirPods Pro",
        _ => return None,
    })
}

/// The product ID in a BlueZ `Modalias` of an Apple device.
pub fn modalias_product(modalias: &str) -> Option<u16> {
    let rest = modalias.strip_prefix("bluetooth:v004Cp")?;
    u16::from_str_radix(rest.get(..4)?, 16).ok()
}

pub fn run(command: crate::AirPodsCommand) -> Result<()> {
    let (method, params) = match command {
        crate::AirPodsCommand::Status(args) => {
            let status: serde_json::Value = ipc::send_request::<(), _>(
                ipc::methods::AIRPODS_STATUS,
                None,
                ipc::DEFAULT_TIMEOUT,
            )?;
            if args.json {
                println!("{status}");
            } else {
                println!("{}", serde_json::to_string_pretty(&status)?);
            }
            return Ok(());
        }
        crate::AirPodsCommand::Noise { mode } => (
            ipc::methods::AIRPODS_NOISE,
            serde_json::json!({ "mode": mode }),
        ),
        crate::AirPodsCommand::Awareness { enabled } => (
            ipc::methods::AIRPODS_AWARENESS,
            serde_json::json!({ "enabled": enabled }),
        ),
    };
    ipc::mutate::<serde_json::Value>(
        method,
        params,
        ipc::DEFAULT_TIMEOUT,
        std::time::Duration::ZERO,
    )
    .map(drop)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn packet(hex: &str) -> Vec<u8> {
        hex.split_whitespace()
            .map(|byte| u8::from_str_radix(byte, 16).expect("hex byte"))
            .collect()
    }

    #[test]
    fn battery_reports_each_component_and_skips_disconnected_ones() {
        let update = parse(&packet(
            "04 00 04 00 04 00 03 02 01 64 02 01 04 01 63 01 01 08 01 11 04 01",
        ));
        assert_eq!(
            update,
            Some(Update::Battery(Batteries {
                left: Some(Cell {
                    level: 99,
                    charging: true
                }),
                right: Some(Cell {
                    level: 100,
                    charging: false
                }),
                case: None,
            }))
        );
    }

    #[test]
    fn control_packets_round_trip_through_the_encoders() {
        for mode in [
            NoiseMode::Off,
            NoiseMode::Anc,
            NoiseMode::Transparency,
            NoiseMode::Adaptive,
        ] {
            assert_eq!(parse(&set_noise(mode)), Some(Update::Noise(mode)));
        }
        assert_eq!(parse(&set_awareness(true)), Some(Update::Awareness(true)));
        assert_eq!(parse(&set_awareness(false)), Some(Update::Awareness(false)));
    }

    #[test]
    fn ear_state_is_primary_first() {
        assert_eq!(
            parse(&packet("04 00 04 00 06 00 00 02")),
            Some(Update::Ears([Pod::InEar, Pod::InCase]))
        );
        assert_eq!(parse(&packet("04 00 04 00 06 00 00 07")), None);
    }

    #[test]
    fn unknown_and_foreign_packets_are_ignored() {
        assert_eq!(parse(&HANDSHAKE), None);
        assert_eq!(parse(&packet("04 00 04 00 1d 00 41 69 72")), None);
        assert_eq!(parse(&[]), None);
    }

    #[test]
    fn proximity_maps_nibbles_by_primary_pod() {
        // LibrePods' example: AirPods Pro, right primary, lid closed.
        let nearby = proximity(&packet("07 12 01 0e 20 62 a7 b3 09 02 04"), -50).expect("advert");
        assert_eq!(nearby.product, 0x200e);
        assert_eq!(nearby.model, "AirPods Pro");
        assert!(!nearby.lid_open);
        assert_eq!(
            nearby.battery.left,
            Some(Cell {
                level: 70,
                charging: true
            })
        );
        assert_eq!(
            nearby.battery.right,
            Some(Cell {
                level: 100,
                charging: true
            })
        );
        assert_eq!(
            nearby.battery.case,
            Some(Cell {
                level: 30,
                charging: false
            })
        );

        let open = proximity(&packet("07 12 01 14 20 22 f5 0f 01 00 04"), -40).expect("advert");
        assert!(open.lid_open);
        assert_eq!(
            open.battery.left,
            Some(Cell {
                level: 50,
                charging: false
            })
        );
        assert_eq!(open.battery.right, None);
        assert_eq!(open.battery.case, None);
    }

    #[test]
    fn proximity_rejects_other_adverts_and_unknown_models() {
        assert_eq!(proximity(&packet("10 05 01 18 0c 5a 2e"), -40), None);
        assert_eq!(
            proximity(&packet("07 12 01 99 99 22 f5 f3 01 00 04"), -40),
            None
        );
    }

    #[test]
    fn modalias_yields_the_apple_product() {
        assert_eq!(modalias_product("bluetooth:v004Cp2014d0A30"), Some(0x2014));
        assert_eq!(modalias_product("usb:v1D6Bp0246d0557"), None);
    }
}
