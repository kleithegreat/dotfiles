//! `#rrggbb` colour maths shared by the schema and every target.

/// WCAG AA for normal text.
pub const WCAG_AA_NORMAL_TEXT: f64 = 4.5;

pub fn parse_hex(value: &str) -> Result<[u8; 3], String> {
    let digits = value.strip_prefix('#').unwrap_or(value);
    let malformed = || format!("expected a #rrggbb color, got '{value}'");
    if digits.len() != 6 || !digits.is_ascii() {
        return Err(malformed());
    }

    let mut channels = [0_u8; 3];
    for (index, channel) in channels.iter_mut().enumerate() {
        let start = index * 2;
        *channel = u8::from_str_radix(&digits[start..start + 2], 16).map_err(|_| malformed())?;
    }
    Ok(channels)
}

fn channels(hex_color: &str) -> [u8; 3] {
    parse_hex(hex_color).expect("scheme colors are validated #rrggbb")
}

fn srgb_channel_to_linear(channel: u8) -> f64 {
    let value = channel as f64 / 255.0;
    if value <= 0.04045 {
        value / 12.92
    } else {
        ((value + 0.055) / 1.055).powf(2.4)
    }
}

fn linear(hex_color: &str) -> [f64; 3] {
    channels(hex_color).map(srgb_channel_to_linear)
}

pub fn relative_luminance(hex_color: &str) -> f64 {
    let [red, green, blue] = linear(hex_color);
    0.2126 * red + 0.7152 * green + 0.0722 * blue
}

pub fn contrast_ratio(first: &str, second: &str) -> f64 {
    let first_luminance = relative_luminance(first);
    let second_luminance = relative_luminance(second);
    let lighter = first_luminance.max(second_luminance);
    let darker = first_luminance.min(second_luminance);
    (lighter + 0.05) / (darker + 0.05)
}

fn linear_to_srgb_channel(linear: f64) -> u8 {
    let clamped = linear.clamp(0.0, 1.0);
    let encoded = if clamped <= 0.003_130_8 {
        12.92 * clamped
    } else {
        1.055 * clamped.powf(1.0 / 2.4) - 0.055
    };
    (encoded.clamp(0.0, 1.0) * 255.0).round() as u8
}

/// Oklab (Björn Ottosson) — perceptually uniform lightness and hue for
/// plate separation checks and smooth dark/light color mixing.
fn srgb_to_oklab(hex_color: &str) -> (f64, f64, f64) {
    let [r, g, b] = linear(hex_color);

    let l = (0.412_221_470_8 * r + 0.536_332_536_3 * g + 0.051_445_992_9 * b).cbrt();
    let m = (0.211_903_498_2 * r + 0.680_699_545_1 * g + 0.107_396_956_6 * b).cbrt();
    let s = (0.088_302_461_9 * r + 0.281_718_837_6 * g + 0.629_978_700_5 * b).cbrt();

    (
        0.210_454_255_3 * l + 0.793_617_785_0 * m - 0.004_072_046_8 * s,
        1.977_998_495_1 * l - 2.428_592_205_0 * m + 0.450_593_709_9 * s,
        0.025_904_037_1 * l + 0.782_771_766_2 * m - 0.808_675_766_0 * s,
    )
}

fn oklab_to_srgb(lab: (f64, f64, f64)) -> String {
    let (big_l, a, b) = lab;
    let l = (big_l + 0.396_337_777_4 * a + 0.215_803_757_3 * b).powi(3);
    let m = (big_l - 0.105_561_345_8 * a - 0.063_854_172_8 * b).powi(3);
    let s = (big_l - 0.089_484_177_5 * a - 1.291_485_548_0 * b).powi(3);

    let r = linear_to_srgb_channel(4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s);
    let g =
        linear_to_srgb_channel(-1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s);
    let b =
        linear_to_srgb_channel(-0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701_0 * s);
    format!("#{r:02x}{g:02x}{b:02x}")
}

/// Euclidean distance in Oklab (~0.02 subtle tint, >=0.09 distinct hue/plate).
pub fn color_difference(first: &str, second: &str) -> f64 {
    let (l1, a1, b1) = srgb_to_oklab(first);
    let (l2, a2, b2) = srgb_to_oklab(second);
    ((l1 - l2).powi(2) + (a1 - a2).powi(2) + (b1 - b2).powi(2)).sqrt()
}

/// Mix two colours in Oklab at `ratio` (0 keeps `from`, 1 reaches `to`).
pub fn blend(from: &str, to: &str, ratio: f64) -> String {
    let t = ratio.clamp(0.0, 1.0);
    let (l1, a1, b1) = srgb_to_oklab(from);
    let (l2, a2, b2) = srgb_to_oklab(to);
    oklab_to_srgb((l1 + (l2 - l1) * t, a1 + (a2 - a1) * t, b1 + (b2 - b1) * t))
}

/// First of `ink` that clears AA on `plate`, else black or white, whichever
/// reads better. See docs/theming.md.
pub fn readable_on(plate: &str, ink: &[&str]) -> String {
    if let Some(candidate) = ink
        .iter()
        .find(|candidate| contrast_ratio(plate, candidate) >= WCAG_AA_NORMAL_TEXT)
    {
        return (*candidate).to_owned();
    }
    if contrast_ratio(plate, "#000000") >= contrast_ratio(plate, "#ffffff") {
        "#000000".to_owned()
    } else {
        "#ffffff".to_owned()
    }
}

/// [`readable_on`] for a plate, using whichever of the scheme's two ends reads better.
pub fn readable_on_ends(plate: &str, background: &str, foreground: &str) -> String {
    let best = if contrast_ratio(plate, background) >= contrast_ratio(plate, foreground) {
        background
    } else {
        foreground
    };
    readable_on(plate, &[best])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_hex_validates_six_digit_rgb_strings() {
        assert_eq!(parse_hex("#1a2B3c"), Ok([0x1a, 0x2b, 0x3c]));
        assert_eq!(parse_hex("00ff80"), Ok([0x00, 0xff, 0x80]));
        assert!(parse_hex("#fff").is_err());
        assert!(parse_hex("#zzzzzz").is_err());
        assert!(parse_hex("#12345g").is_err());
        assert!(parse_hex("ééé").is_err());
    }

    #[test]
    fn relative_luminance_and_contrast_follow_wcag_endpoints_and_knee() {
        assert_eq!(relative_luminance("#000000"), 0.0);
        assert!((relative_luminance("#ffffff") - 1.0).abs() < 1e-12);
        assert!((contrast_ratio("#000000", "#ffffff") - 21.0).abs() < 1e-9);
        assert_eq!(contrast_ratio("#282828", "#282828"), 1.0);

        // 10/255 = 0.0392 <= 0.04045 linear segment; 11/255 = 0.0431 > 0.04045 gamma segment.
        let linear_side = relative_luminance("#0a0a0a");
        let gamma_side = relative_luminance("#0b0b0b");
        assert!((linear_side - (10.0 / 255.0) / 12.92).abs() < 1e-12);
        assert!((gamma_side - (((11.0_f64 / 255.0) + 0.055) / 1.055).powf(2.4)).abs() < 1e-12);
    }

    #[test]
    fn oklab_blend_preserves_endpoints_and_perceptual_midpoints() {
        assert_eq!(blend("#282828", "#fbf1c7", 0.0), "#282828");
        assert_eq!(blend("#282828", "#fbf1c7", 1.0), "#fbf1c7");
        assert_eq!(blend("#282828", "#fbf1c7", -0.5), "#282828");
        assert_eq!(blend("#282828", "#fbf1c7", 2.0), "#fbf1c7");

        // Perceptual Oklab midpoint between black and white sits near L = 0.5 (~#636363),
        // darker than sRGB #808080 whose encoded midpoint overshoots linear luminance.
        let gray_mid = blend("#000000", "#ffffff", 0.5);
        assert_eq!(gray_mid, "#636363");

        // Blending saturated red and green in Oklab passes near bright gold instead of muddy #808000.
        let rg_mid = blend("#ff0000", "#00ff00", 0.5);
        assert!(
            relative_luminance(&rg_mid) > 0.38,
            "expected bright yellow-green midpoint, got {rg_mid}"
        );
    }

    #[test]
    fn color_difference_is_symmetric_identity_free_and_metric() {
        assert_eq!(color_difference("#d79921", "#d79921"), 0.0);
        let d_ab = color_difference("#ebdbb2", "#d79921");
        let d_ba = color_difference("#d79921", "#ebdbb2");
        assert!((d_ab - d_ba).abs() < 1e-12);
        let d_bc = color_difference("#d79921", "#282828");
        let d_ac = color_difference("#ebdbb2", "#282828");
        assert!(d_ac <= d_ab + d_bc + 1e-12);
        assert!(color_difference("#000000", "#ffffff") > 0.99);
    }

    #[test]
    fn readable_on_picks_first_aa_ink_or_falls_back_to_black_or_white() {
        assert_eq!(
            readable_on("#282828", &["#3c3836", "#ebdbb2", "#fbf1c7"]),
            "#ebdbb2"
        );
        assert_eq!(readable_on("#282828", &["#3c3836"]), "#ffffff");
        assert_eq!(readable_on("#fbf1c7", &["#ebdbb2"]), "#000000");

        // Neither #000000 nor #f0f0f0 clears 4.5 on #3366ff, so fallback picks #ffffff.
        assert_eq!(readable_on_ends("#3366ff", "#000000", "#f0f0f0"), "#ffffff");
    }
}
