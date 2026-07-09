//! Platform-independent Nameplate identity, configuration, and IPC semantics.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::{CStr, c_char};

pub const PALETTE: [&str; 8] = [
    "#E24B30", "#EF9F27", "#8BC34A", "#1D9E75", "#22B8CF", "#378ADD", "#7F77DD", "#D4537E",
];

pub fn short_hostname(host: &str) -> String {
    let lowered = host.trim().to_lowercase();
    lowered
        .split('.')
        .next()
        .filter(|part| !part.is_empty())
        .unwrap_or(&lowered)
        .to_owned()
}

pub fn current_hostname() -> String {
    let mut buffer = [0 as c_char; 256];
    // SAFETY: writable fixed-size buffer; gethostname is capped below its capacity.
    if unsafe { libc_gethostname(buffer.as_mut_ptr(), buffer.len() - 1) } != 0 {
        return "linux".to_owned();
    }
    // SAFETY: buffer starts zeroed and the final byte remains zero.
    let host = unsafe { CStr::from_ptr(buffer.as_ptr()) }.to_string_lossy();
    if host.is_empty() {
        "linux".to_owned()
    } else {
        host.into_owned()
    }
}

#[cfg(unix)]
unsafe fn libc_gethostname(name: *mut c_char, len: usize) -> i32 {
    unsafe extern "C" {
        fn gethostname(name: *mut c_char, len: usize) -> i32;
    }
    // SAFETY: caller supplies a valid writable buffer of `len` bytes.
    unsafe { gethostname(name, len) }
}

#[cfg(not(unix))]
unsafe fn libc_gethostname(_name: *mut c_char, _len: usize) -> i32 {
    -1
}

pub fn palette_index(host: &str) -> usize {
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    for byte in short_hostname(host).as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    (hash % PALETTE.len() as u64) as usize
}

pub fn default_color(host: &str) -> &'static str {
    PALETTE[palette_index(host)]
}

pub fn normalize_hex(raw: &str) -> Option<String> {
    let raw = raw.trim().strip_prefix('#').unwrap_or(raw.trim());
    if !raw.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    match raw.len() {
        3 => {
            Some(format!("#{0}{0}{1}{1}{2}{2}", &raw[0..1], &raw[1..2], &raw[2..3]).to_uppercase())
        }
        6 => Some(format!("#{raw}").to_uppercase()),
        _ => None,
    }
}

pub fn rgb(hex: &str) -> Option<(f64, f64, f64)> {
    let normalized = normalize_hex(hex)?;
    let value = u32::from_str_radix(&normalized[1..], 16).ok()?;
    Some((
        f64::from((value >> 16) & 0xff) / 255.0,
        f64::from((value >> 8) & 0xff) / 255.0,
        f64::from(value & 0xff) / 255.0,
    ))
}

pub fn relative_luminance(hex: &str) -> f64 {
    let Some((red, green, blue)) = rgb(hex) else {
        return 0.0;
    };
    let channel = |value: f64| {
        if value <= 0.03928 {
            value / 12.92
        } else {
            ((value + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
}

pub fn prefers_dark_text(hex: &str) -> bool {
    relative_luminance(hex) > 0.4
}

#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq, Serialize)]
pub struct FleetEntry {
    pub name: Option<String>,
    pub color: Option<String>,
    pub glyph: Option<String>,
}

pub type Fleet = HashMap<String, FleetEntry>;

pub fn parse_fleet(data: &[u8]) -> Result<Fleet, serde_json::Error> {
    let decoded: Fleet = serde_json::from_slice(data)?;
    Ok(decoded
        .into_iter()
        .map(|(key, value)| (short_hostname(&key), value))
        .collect())
}

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum Corner {
    TopLeft,
    TopRight,
    #[default]
    BottomLeft,
    BottomRight,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub name: Option<String>,
    pub color: Option<String>,
    pub glyph: Option<String>,
    pub use_fleet_file: bool,
    pub frame_enabled: bool,
    pub frame_thickness: f64,
    pub frame_opacity: f64,
    pub frame_corner_radius: f64,
    pub frame_round_top_left: bool,
    pub frame_round_top_right: bool,
    pub frame_round_bottom_left: bool,
    pub frame_round_bottom_right: bool,
    pub tag_enabled: bool,
    pub tag_corner: Corner,
    pub tag_shows_glyph: bool,
    pub watermark_enabled: bool,
    pub watermark_corner: Corner,
    pub watermark_opacity: f64,
    pub splash_enabled: bool,
    pub splash_duration: f64,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            name: None,
            color: None,
            glyph: None,
            use_fleet_file: true,
            frame_enabled: true,
            frame_thickness: 4.0,
            frame_opacity: 1.0,
            frame_corner_radius: 16.0,
            frame_round_top_left: false,
            frame_round_top_right: false,
            frame_round_bottom_left: false,
            frame_round_bottom_right: false,
            tag_enabled: true,
            tag_corner: Corner::BottomLeft,
            tag_shows_glyph: true,
            watermark_enabled: false,
            watermark_corner: Corner::BottomRight,
            watermark_opacity: 0.12,
            splash_enabled: true,
            splash_duration: 1.8,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Identity {
    pub name: String,
    pub color: String,
    pub glyph: String,
    pub hostname: String,
}

pub fn resolve_identity(host: &str, settings: &Settings, fleet: Option<&FleetEntry>) -> Identity {
    let fleet = settings.use_fleet_file.then_some(fleet).flatten();
    let default_name = short_hostname(host);
    let name = fleet
        .and_then(|entry| entry.name.as_deref())
        .or(settings.name.as_deref())
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .unwrap_or(default_name.as_str())
        .to_owned();
    let configured_color = fleet
        .and_then(|entry| entry.color.as_deref())
        .or(settings.color.as_deref());
    let color = configured_color
        .and_then(normalize_hex)
        .unwrap_or_else(|| default_color(host).to_owned());
    let glyph = fleet
        .and_then(|entry| entry.glyph.as_deref())
        .or(settings.glyph.as_deref())
        .unwrap_or_default()
        .trim()
        .to_owned();
    Identity {
        name,
        color,
        glyph,
        hostname: host.to_owned(),
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "command", rename_all = "lowercase")]
pub enum DaemonCommand {
    Splash,
    Attention {
        message: String,
        title: Option<String>,
        duration: Option<f64>,
        color: Option<String>,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn color_parity_vectors() {
        let vectors = [
            ("megaclaw", 0),
            ("clawmac", 5),
            ("studio-1", 1),
            ("win-fleet-07", 6),
            ("ubuntu", 2),
            ("desktop-3xk9", 5),
            ("peters-mac-studio-1", 7),
        ];
        for (host, expected) in vectors {
            assert_eq!(palette_index(host), expected, "{host}");
        }
    }

    #[test]
    fn hostname_shortening_matches_macos() {
        assert_eq!(short_hostname(" Megaclaw.local \n"), "megaclaw");
        assert_eq!(short_hostname("CLAWMAC.fritz.box"), "clawmac");
        assert_eq!(short_hostname("ubuntu"), "ubuntu");
        assert_eq!(short_hostname(""), "");
    }

    #[test]
    fn fleet_parses_and_normalizes_keys() {
        let fleet = parse_fleet(
            r##"{"MEGACLAW.local":{"name":"MEGACLAW","color":"#1D9E75","glyph":"🦞"}}"##.as_bytes(),
        )
        .unwrap();
        assert_eq!(fleet["megaclaw"].name.as_deref(), Some("MEGACLAW"));
    }

    #[test]
    fn malformed_fleet_is_an_error() {
        assert!(parse_fleet(br#"{"megaclaw": "#).is_err());
        assert!(parse_fleet(br#"[]"#).is_err());
    }

    #[test]
    fn fleet_unknown_fields_are_ignored() {
        let fleet = parse_fleet(br#"{"ubuntu":{"name":"Ubuntu","site":"lab"}}"#).unwrap();
        assert_eq!(fleet["ubuntu"].name.as_deref(), Some("Ubuntu"));
    }

    #[test]
    fn hex_normalization() {
        assert_eq!(normalize_hex(" #3fA \n").as_deref(), Some("#33FFAA"));
        assert_eq!(normalize_hex("33ffaa").as_deref(), Some("#33FFAA"));
        assert_eq!(normalize_hex("#12345"), None);
        assert_eq!(normalize_hex("#xyz"), None);
        assert_eq!(normalize_hex(""), None);
    }

    #[test]
    fn luminance_text_decision_matches_macos() {
        assert!(!prefers_dark_text("#E24B30"));
        assert!(prefers_dark_text("#EF9F27"));
        assert!(prefers_dark_text("#8BC34A"));
        assert!(!prefers_dark_text("#1D9E75"));
        assert!(!prefers_dark_text("#378ADD"));
        assert!(prefers_dark_text("#FFFFFF"));
        assert!(!prefers_dark_text("#000000"));
    }

    #[test]
    fn settings_default_to_square_frame_corners() {
        let settings: Settings = serde_json::from_str("{}").unwrap();

        assert!(!settings.frame_round_top_left);
        assert!(!settings.frame_round_top_right);
        assert!(!settings.frame_round_bottom_left);
        assert!(!settings.frame_round_bottom_right);
    }

    #[test]
    fn fleet_identity_precedes_local_settings() {
        let settings = Settings {
            name: Some("Local".into()),
            color: Some("#fff".into()),
            glyph: Some("L".into()),
            ..Settings::default()
        };
        let fleet = FleetEntry {
            name: Some("Fleet".into()),
            color: Some("#123456".into()),
            glyph: Some("F".into()),
        };
        let identity = resolve_identity("Ubuntu.local", &settings, Some(&fleet));
        assert_eq!(identity.name, "Fleet");
        assert_eq!(identity.color, "#123456");
        assert_eq!(identity.glyph, "F");
    }
}
