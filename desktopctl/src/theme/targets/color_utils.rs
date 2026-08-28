pub fn srgb_channel_to_linear(channel: u8) -> f64 {
    let value = channel as f64 / 255.0;
    if value <= 0.04045 {
        value / 12.92
    } else {
        ((value + 0.055) / 1.055).powf(2.4)
    }
}

pub fn relative_luminance(hex_color: &str) -> f64 {
    let red = srgb_channel_to_linear(u8::from_str_radix(&hex_color[1..3], 16).unwrap());
    let green = srgb_channel_to_linear(u8::from_str_radix(&hex_color[3..5], 16).unwrap());
    let blue = srgb_channel_to_linear(u8::from_str_radix(&hex_color[5..7], 16).unwrap());
    0.2126 * red + 0.7152 * green + 0.0722 * blue
}

pub fn contrast_ratio(first: &str, second: &str) -> f64 {
    let first_luminance = relative_luminance(first);
    let second_luminance = relative_luminance(second);
    let lighter = first_luminance.max(second_luminance);
    let darker = first_luminance.min(second_luminance);
    (lighter + 0.05) / (darker + 0.05)
}

/// CIE L*a*b* under D65, for perceptual distance. Contrast ratio alone cannot
/// tell two plates apart: a saturated blue and a saturated purple of the same
/// luminance have a contrast ratio of 1.0 against each other while still being
/// obviously different colours, and vice versa.
pub fn cielab(hex_color: &str) -> (f64, f64, f64) {
    let red = srgb_channel_to_linear(u8::from_str_radix(&hex_color[1..3], 16).unwrap());
    let green = srgb_channel_to_linear(u8::from_str_radix(&hex_color[3..5], 16).unwrap());
    let blue = srgb_channel_to_linear(u8::from_str_radix(&hex_color[5..7], 16).unwrap());

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
    let channel = |offset: usize| {
        let start = u8::from_str_radix(&from[offset..offset + 2], 16).unwrap() as f64;
        let end = u8::from_str_radix(&to[offset..offset + 2], 16).unwrap() as f64;
        (start + (end - start) * ratio).round().clamp(0.0, 255.0) as u8
    };
    format!("#{:02x}{:02x}{:02x}", channel(1), channel(3), channel(5))
}

/// WCAG AA for normal text; below this a label on a filled plate stops being
/// readable rather than merely low-contrast.
const WCAG_AA_NORMAL_TEXT: f64 = 4.5;

/// Text colour for a filled plate, preferring the scheme's own ends. Neither
/// `fg` nor `bg` is safe on its own: on a light scheme the accent carries the
/// body grey at ~1.6:1, and some accents clear AA against neither, which is
/// what the black/white fallback is for.
pub fn readable_on(plate: &str, background: &str, foreground: &str) -> String {
    let best = |first: &str, second: &str| -> String {
        if contrast_ratio(plate, first) >= contrast_ratio(plate, second) {
            first.to_owned()
        } else {
            second.to_owned()
        }
    };

    let candidate = best(background, foreground);
    if contrast_ratio(plate, &candidate) >= WCAG_AA_NORMAL_TEXT {
        return candidate;
    }
    best("#000000", "#ffffff")
}
