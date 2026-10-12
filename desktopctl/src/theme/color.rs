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

/// CIE L*a*b* under D65; contrast ratio cannot tell equal-luminance hues apart.
fn cielab(hex_color: &str) -> (f64, f64, f64) {
    let [red, green, blue] = linear(hex_color);

    let x = (0.4124 * red + 0.3576 * green + 0.1805 * blue) / 0.95047;
    let y = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    let z = (0.0193 * red + 0.1192 * green + 0.9505 * blue) / 1.08883;

    fn f(t: f64) -> f64 {
        const EPSILON: f64 = 216.0 / 24389.0;
        if t > EPSILON {
            t.cbrt()
        } else {
            (841.0 / 108.0) * t + 4.0 / 29.0
        }
    }

    let (fx, fy, fz) = (f(x), f(y), f(z));
    (116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))
}

/// CIE76 colour difference. Roughly: under 2 is imperceptible, under 10 reads
/// as a shade of the same colour, over 20 reads as a different colour.
pub fn color_difference(first: &str, second: &str) -> f64 {
    let (first_l, first_a, first_b) = cielab(first);
    let (second_l, second_a, second_b) = cielab(second);
    ((first_l - second_l).powi(2) + (first_a - second_a).powi(2) + (first_b - second_b).powi(2))
        .sqrt()
}

/// Mix two colours in sRGB at `ratio` (0 keeps `from`, 1 reaches `to`).
pub fn blend(from: &str, to: &str, ratio: f64) -> String {
    blend_rounded(from, to, ratio, f64::round)
}

/// [`blend`] with a chosen channel rounding; spicetify's tie-breaking is half-to-even.
pub fn blend_rounded(from: &str, to: &str, ratio: f64, round: fn(f64) -> f64) -> String {
    let (from, to) = (channels(from), channels(to));
    let channel = |index: usize| {
        let start = f64::from(from[index]);
        round(start + (f64::from(to[index]) - start) * ratio) as u8
    };
    format!("#{:02x}{:02x}{:02x}", channel(0), channel(1), channel(2))
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
