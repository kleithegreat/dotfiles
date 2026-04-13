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
