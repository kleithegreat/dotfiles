//! The Kvantum theme, generated whole from the scheme.
//!
//! Kvantum draws every widget surface from SVG elements, so a borrowed SVG
//! pins the desktop to whatever palette that theme was drawn in. Generating
//! the SVG alongside the kvconfig is what lets an arbitrary scheme reach the
//! pixels rather than only the text colours.

use super::color_utils::blend;
use crate::theme::schema::ColorScheme;

/// Width of every painted border, in SVG units. Kvantum scales frame tiles to
/// the configured frame size, so this stays 1 only because tile size equals
/// the radius it is drawn for.
const BORDER: f64 = 1.0;

/// Edge tiles are stretched along their length; the cross-axis is what matters.
const TILE: f64 = 8.0;

pub struct Palette {
    window: String,
    base: String,
    button: String,
    button_hover: String,
    button_press: String,
    line: String,
    line_soft: String,
    track: String,
    thumb: String,
    accent: String,
    on_accent: String,
}

impl Palette {
    pub fn new(colors: &ColorScheme) -> Self {
        let window = colors.bg1.clone();
        let button = blend(&colors.bg1, &colors.bg, 0.55);
        Self {
            base: colors.bg.clone(),
            button_hover: blend(&button, &colors.bg, 0.45),
            button_press: colors.bg2.clone(),
            line: blend(&window, &colors.fg, 0.20),
            line_soft: blend(&window, &colors.fg, 0.11),
            track: blend(&window, &colors.fg, 0.13),
            thumb: blend(&window, &colors.fg, 0.32),
            accent: colors.accent.clone(),
            on_accent: super::color_utils::readable_on(&colors.accent, &colors.bg, &colors.fg),
            button,
            window,
        }
    }
}

/// One drawn surface: a rounded rect with an optional hairline border.
/// `fill`/`border` of `None` paint nothing, which is how flat and transparent
/// states are expressed without a second code path.
struct Surface {
    radius: f64,
    fill: Option<String>,
    border: Option<String>,
}

impl Surface {
    fn flat(radius: f64, fill: &str) -> Self {
        Self {
            radius,
            fill: Some(fill.to_owned()),
            border: None,
        }
    }

    fn bordered(radius: f64, fill: &str, border: &str) -> Self {
        Self {
            radius,
            fill: Some(fill.to_owned()),
            border: Some(border.to_owned()),
        }
    }

    fn outline(radius: f64, border: &str) -> Self {
        Self {
            radius,
            fill: None,
            border: Some(border.to_owned()),
        }
    }

    fn empty(radius: f64) -> Self {
        Self {
            radius,
            fill: None,
            border: None,
        }
    }
}

fn rect(x: f64, y: f64, width: f64, height: f64, fill: &str) -> String {
    format!(
        r#"<rect x="{x}" y="{y}" width="{width}" height="{height}" fill="{fill}"/>"#,
        x = fmt(x),
        y = fmt(y),
        width = fmt(width),
        height = fmt(height),
    )
}

/// Trailing zeros in SVG numbers make the file noisy to diff for no gain.
fn fmt(value: f64) -> String {
    let rounded = (value * 1000.0).round() / 1000.0;
    if rounded.fract() == 0.0 {
        format!("{}", rounded as i64)
    } else {
        format!("{rounded}")
    }
}

/// Quarter disc filling the inside of a rounded corner, drawn in a
/// `radius`-square tile. `flip_x`/`flip_y` place the arc's centre so one
/// routine covers all four corners.
fn corner_path(radius: f64, inset: f64, flip_x: bool, flip_y: bool, fill: &str) -> String {
    let effective = radius - inset;
    if effective <= 0.0 {
        return String::new();
    }
    let centre_x = if flip_x { 0.0 } else { radius };
    let centre_y = if flip_y { 0.0 } else { radius };
    let start_x = centre_x + if flip_x { effective } else { -effective };
    let end_y = centre_y + if flip_y { effective } else { -effective };
    let sweep = u8::from(flip_x == flip_y);
    format!(
        r#"<path d="M {cx},{cy} L {sx},{cy} A {r},{r} 0 0 {sweep} {cx},{ey} Z" fill="{fill}"/>"#,
        cx = fmt(centre_x),
        cy = fmt(centre_y),
        sx = fmt(start_x),
        ey = fmt(end_y),
        r = fmt(effective),
        sweep = sweep,
    )
}

fn corner(id: &str, surface: &Surface, flip_x: bool, flip_y: bool) -> String {
    let radius = surface.radius;
    let mut body = String::new();
    match (&surface.border, &surface.fill) {
        (Some(border), fill) => {
            body.push_str(&corner_path(radius, 0.0, flip_x, flip_y, border));
            if let Some(fill) = fill {
                body.push_str(&corner_path(radius, BORDER, flip_x, flip_y, fill));
            }
        }
        (None, Some(fill)) => body.push_str(&corner_path(radius, 0.0, flip_x, flip_y, fill)),
        (None, None) => {}
    }
    group(id, radius, radius, &body)
}

/// Straight run between two corners. `vertical` swaps which axis carries the
/// frame thickness; `far` puts the border on the bottom/right instead.
fn edge(id: &str, surface: &Surface, vertical: bool, far: bool) -> String {
    let thickness = surface.radius;
    let (width, height) = if vertical {
        (thickness, TILE)
    } else {
        (TILE, thickness)
    };

    let mut body = String::new();
    if let Some(fill) = &surface.fill {
        body.push_str(&rect(0.0, 0.0, width, height, fill));
    }
    if let Some(border) = &surface.border {
        let offset = if far { thickness - BORDER } else { 0.0 };
        body.push_str(&if vertical {
            rect(offset, 0.0, BORDER, height, border)
        } else {
            rect(0.0, offset, width, BORDER, border)
        });
    }
    group(id, width, height, &body)
}

fn group(id: &str, width: f64, height: f64, body: &str) -> String {
    format!(
        "  <g id=\"{id}\">{pin}{body}</g>\n",
        pin = rect(0.0, 0.0, width, height, "none"),
    )
}

/// Emits the nine ids Kvantum looks up for one element in one state.
fn frame(name: &str, state: &str, surface: &Surface) -> String {
    let base = format!("{name}-{state}");
    let mut svg = String::new();
    for (suffix, flip_x, flip_y) in [
        ("topleft", false, false),
        ("topright", true, false),
        ("bottomleft", false, true),
        ("bottomright", true, true),
    ] {
        svg.push_str(&corner(
            &format!("{base}-{suffix}"),
            surface,
            flip_x,
            flip_y,
        ));
    }
    for (suffix, vertical, far) in [
        ("top", false, false),
        ("bottom", false, true),
        ("left", true, false),
        ("right", true, true),
    ] {
        svg.push_str(&edge(&format!("{base}-{suffix}"), surface, vertical, far));
    }

    let interior = match &surface.fill {
        Some(fill) => rect(0.0, 0.0, TILE, TILE, fill),
        None => String::new(),
    };
    svg.push_str(&group(&base, TILE, TILE, &interior));
    svg
}

/// The four states Kvantum asks for. A missing state renders nothing at all,
/// so every element declares all four even when they look alike.
struct States {
    normal: Surface,
    focused: Surface,
    pressed: Surface,
    toggled: Surface,
}

fn element(name: &str, states: &States) -> String {
    [
        ("normal", &states.normal),
        ("focused", &states.focused),
        ("pressed", &states.pressed),
        ("toggled", &states.toggled),
    ]
    .into_iter()
    .map(|(state, surface)| frame(name, state, surface))
    .collect()
}

/// Chevron rather than a filled triangle: the thin stroked form is what reads
/// as current, and it stays legible at 16px.
fn chevron(id: &str, rotation: i32, color: &str) -> String {
    let body = format!(
        concat!(
            r#"<g transform="rotate({rotation} 8 8)">"#,
            r#"<path d="M 4.5,6.5 L 8,10 L 11.5,6.5" fill="none" stroke="{color}""#,
            r#" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>"#,
            "</g>",
        ),
        rotation = rotation,
        color = color,
    );
    group(id, 16.0, 16.0, &body)
}

fn arrows(palette: &Palette) -> String {
    let mut svg = String::new();
    for (state, color) in [
        ("normal", &palette.line),
        ("pressed", &palette.accent),
        ("focused", &palette.accent),
        ("toggled", &palette.accent),
    ] {
        for (name, rotation) in [
            ("arrow-down", 0),
            ("arrow-up", 180),
            ("arrow-left", 90),
            ("arrow-right", -90),
            // Tree expanders: Kvantum asks for plus/minus and draws its own
            // boxed glyph when they are missing.
            ("arrow-plus", -90),
            ("arrow-minus", 0),
        ] {
            svg.push_str(&chevron(&format!("{name}-{state}"), rotation, color));
        }
    }
    svg
}

/// Rounded square that fills with the accent when checked — the tick is drawn
/// in `on_accent` so it survives a light accent.
fn check_box(id: &str, palette: &Palette, checked: bool, tristate: bool, focused: bool) -> String {
    let border = if focused {
        &palette.accent
    } else {
        &palette.line
    };
    let mut body = if checked || tristate {
        format!(
            r#"<rect x="1" y="1" width="14" height="14" rx="4.5" fill="{}"/>"#,
            palette.accent
        )
    } else {
        format!(
            concat!(
                r#"<rect x="1" y="1" width="14" height="14" rx="4.5" fill="{fill}"/>"#,
                r#"<rect x="1.5" y="1.5" width="13" height="13" rx="4" fill="none""#,
                r#" stroke="{border}" stroke-width="1"/>"#,
            ),
            fill = palette.base,
            border = border,
        )
    };

    if checked {
        body.push_str(&format!(
            concat!(
                r#"<path d="M 4.5,8.2 L 7,10.6 L 11.5,5.6" fill="none" stroke="{color}""#,
                r#" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>"#,
            ),
            color = palette.on_accent,
        ));
    } else if tristate {
        body.push_str(&format!(
            r#"<rect x="4.5" y="7.2" width="7" height="1.6" rx="0.8" fill="{}"/>"#,
            palette.on_accent
        ));
    }
    group(id, 16.0, 16.0, &body)
}

fn radio_button(id: &str, palette: &Palette, checked: bool, focused: bool) -> String {
    let border = if focused {
        &palette.accent
    } else {
        &palette.line
    };
    let mut body = if checked {
        format!(r#"<circle cx="8" cy="8" r="7" fill="{}"/>"#, palette.accent)
    } else {
        format!(
            concat!(
                r#"<circle cx="8" cy="8" r="7" fill="{fill}"/>"#,
                r#"<circle cx="8" cy="8" r="6.5" fill="none" stroke="{border}" stroke-width="1"/>"#,
            ),
            fill = palette.base,
            border = border,
        )
    };
    if checked {
        body.push_str(&format!(
            r#"<circle cx="8" cy="8" r="2.6" fill="{}"/>"#,
            palette.on_accent
        ));
    }
    group(id, 16.0, 16.0, &body)
}

fn indicators(palette: &Palette) -> String {
    let mut svg = arrows(palette);
    for (state, focused) in [
        ("normal", false),
        ("focused", true),
        ("pressed", true),
        ("toggled", false),
    ] {
        svg.push_str(&check_box(
            &format!("checkbox-{state}"),
            palette,
            false,
            false,
            focused,
        ));
        svg.push_str(&check_box(
            &format!("checkbox-checked-{state}"),
            palette,
            true,
            false,
            focused,
        ));
        svg.push_str(&check_box(
            &format!("checkbox-tristate-{state}"),
            palette,
            false,
            true,
            focused,
        ));
        svg.push_str(&radio_button(
            &format!("radio-{state}"),
            palette,
            false,
            focused,
        ));
        svg.push_str(&radio_button(
            &format!("radio-checked-{state}"),
            palette,
            true,
            focused,
        ));
    }
    svg
}

fn elements(palette: &Palette) -> Vec<(&'static str, States)> {
    let selected = |radius: f64| Surface::flat(radius, &palette.accent);

    vec![
        (
            "button",
            States {
                normal: Surface::bordered(8.0, &palette.button, &palette.line_soft),
                focused: Surface::bordered(8.0, &palette.button_hover, &palette.accent),
                pressed: Surface::bordered(8.0, &palette.button_press, &palette.line),
                toggled: Surface::flat(8.0, &palette.accent),
            },
        ),
        (
            "tbutton",
            States {
                normal: Surface::empty(7.0),
                focused: Surface::flat(7.0, &palette.button_hover),
                pressed: Surface::flat(7.0, &palette.button_press),
                toggled: Surface::flat(7.0, &palette.accent),
            },
        ),
        (
            "lineedit",
            States {
                normal: Surface::bordered(8.0, &palette.base, &palette.line_soft),
                focused: Surface::bordered(8.0, &palette.base, &palette.accent),
                pressed: Surface::bordered(8.0, &palette.base, &palette.accent),
                toggled: Surface::bordered(8.0, &palette.base, &palette.accent),
            },
        ),
        (
            "common",
            States {
                normal: Surface::outline(8.0, &palette.line_soft),
                focused: Surface::outline(8.0, &palette.accent),
                pressed: Surface::outline(8.0, &palette.line_soft),
                toggled: Surface::outline(8.0, &palette.line_soft),
            },
        ),
        (
            "itemview",
            States {
                normal: Surface::empty(6.0),
                focused: Surface::flat(6.0, &palette.button_hover),
                pressed: selected(6.0),
                toggled: selected(6.0),
            },
        ),
        (
            "menu",
            States {
                normal: Surface::bordered(12.0, &palette.window, &palette.line_soft),
                focused: Surface::bordered(12.0, &palette.window, &palette.line_soft),
                pressed: Surface::bordered(12.0, &palette.window, &palette.line_soft),
                toggled: Surface::bordered(12.0, &palette.window, &palette.line_soft),
            },
        ),
        (
            "menuitem",
            States {
                normal: Surface::empty(7.0),
                focused: selected(7.0),
                pressed: selected(7.0),
                toggled: selected(7.0),
            },
        ),
        (
            "menubaritem",
            States {
                normal: Surface::empty(7.0),
                focused: Surface::flat(7.0, &palette.button_hover),
                pressed: selected(7.0),
                toggled: selected(7.0),
            },
        ),
        (
            "tab",
            States {
                normal: Surface::empty(7.0),
                focused: Surface::flat(7.0, &palette.button_hover),
                pressed: Surface::flat(7.0, &palette.button_press),
                toggled: Surface::bordered(7.0, &palette.button, &palette.line_soft),
            },
        ),
        (
            "tabframe",
            States {
                normal: Surface::outline(8.0, &palette.line_soft),
                focused: Surface::outline(8.0, &palette.line_soft),
                pressed: Surface::outline(8.0, &palette.line_soft),
                toggled: Surface::outline(8.0, &palette.line_soft),
            },
        ),
        (
            "toolbar",
            States {
                normal: Surface::flat(1.0, &palette.window),
                focused: Surface::flat(1.0, &palette.window),
                pressed: Surface::flat(1.0, &palette.window),
                toggled: Surface::flat(1.0, &palette.window),
            },
        ),
        (
            "tooltip",
            States {
                normal: Surface::bordered(10.0, &palette.window, &palette.line_soft),
                focused: Surface::bordered(10.0, &palette.window, &palette.line_soft),
                pressed: Surface::bordered(10.0, &palette.window, &palette.line_soft),
                toggled: Surface::bordered(10.0, &palette.window, &palette.line_soft),
            },
        ),
        (
            "progress",
            States {
                normal: Surface::flat(3.0, &palette.track),
                focused: Surface::flat(3.0, &palette.track),
                pressed: Surface::flat(3.0, &palette.track),
                toggled: Surface::flat(3.0, &palette.track),
            },
        ),
        (
            "progress-pattern",
            States {
                normal: Surface::flat(3.0, &palette.accent),
                focused: Surface::flat(3.0, &palette.accent),
                pressed: Surface::flat(3.0, &palette.accent),
                toggled: Surface::flat(3.0, &palette.accent),
            },
        ),
        (
            "slider",
            States {
                normal: Surface::flat(2.0, &palette.track),
                focused: Surface::flat(2.0, &palette.track),
                pressed: Surface::flat(2.0, &palette.track),
                toggled: Surface::flat(2.0, &palette.accent),
            },
        ),
        (
            "slidercursor",
            States {
                normal: Surface::bordered(9.0, &palette.base, &palette.line),
                focused: Surface::bordered(9.0, &palette.base, &palette.accent),
                pressed: Surface::bordered(9.0, &palette.base, &palette.accent),
                toggled: Surface::bordered(9.0, &palette.base, &palette.line),
            },
        ),
        (
            "scrollbargroove",
            States {
                normal: Surface::empty(5.0),
                focused: Surface::empty(5.0),
                pressed: Surface::empty(5.0),
                toggled: Surface::empty(5.0),
            },
        ),
        (
            "scrollbarslider",
            States {
                normal: Surface::flat(5.0, &palette.thumb),
                focused: Surface::flat(5.0, &palette.thumb),
                pressed: Surface::flat(5.0, &palette.accent),
                toggled: Surface::flat(5.0, &palette.thumb),
            },
        ),
        (
            "group",
            States {
                normal: Surface::outline(10.0, &palette.line_soft),
                focused: Surface::outline(10.0, &palette.line_soft),
                pressed: Surface::outline(10.0, &palette.line_soft),
                toggled: Surface::outline(10.0, &palette.line_soft),
            },
        ),
        (
            "header",
            States {
                normal: Surface::bordered(1.0, &palette.window, &palette.line_soft),
                focused: Surface::bordered(1.0, &palette.button_hover, &palette.line_soft),
                pressed: Surface::bordered(1.0, &palette.button_press, &palette.line_soft),
                toggled: Surface::bordered(1.0, &palette.button, &palette.line_soft),
            },
        ),
        (
            "titlebar",
            States {
                normal: Surface::flat(1.0, &palette.window),
                focused: Surface::flat(1.0, &palette.window),
                pressed: Surface::flat(1.0, &palette.window),
                toggled: Surface::flat(1.0, &palette.window),
            },
        ),
        (
            "dock",
            States {
                normal: Surface::flat(1.0, &palette.window),
                focused: Surface::flat(1.0, &palette.window),
                pressed: Surface::flat(1.0, &palette.window),
                toggled: Surface::flat(1.0, &palette.window),
            },
        ),
        (
            "statusbar",
            States {
                normal: Surface::flat(1.0, &palette.window),
                focused: Surface::flat(1.0, &palette.window),
                pressed: Surface::flat(1.0, &palette.window),
                toggled: Surface::flat(1.0, &palette.window),
            },
        ),
        (
            "splitter",
            States {
                normal: Surface::empty(1.0),
                focused: Surface::flat(1.0, &palette.accent),
                pressed: Surface::flat(1.0, &palette.accent),
                toggled: Surface::empty(1.0),
            },
        ),
    ]
}

pub fn svg(colors: &ColorScheme) -> String {
    let palette = Palette::new(colors);
    let mut body = String::new();
    for (name, states) in elements(&palette) {
        body.push_str(&element(name, &states));
    }
    body.push_str(&indicators(&palette));

    format!(
        concat!(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
            "<!-- Generated by desktopctl theme \u{2014} {family}-{variant} -->\n",
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"256\" height=\"256\">\n",
            "{body}",
            "</svg>\n",
        ),
        family = colors.family,
        variant = colors.variant,
        body = body,
    )
}

/// `frame.expansion` is deliberately 0 everywhere: Kvantum's pill expansion
/// overrides the radius the SVG was drawn at and reintroduces the rounding
/// mismatch this generator exists to remove.
fn widget(
    section: &str,
    element: &str,
    frame_size: f64,
    text: &[(&str, &str)],
    extra: &[(&str, String)],
) -> String {
    let mut out = format!("[{section}]\n");
    out.push_str("frame=true\n");
    out.push_str(&format!("frame.element={element}\n"));
    for side in ["top", "bottom", "left", "right"] {
        out.push_str(&format!("frame.{side}={}\n", fmt(frame_size)));
    }
    out.push_str("frame.expansion=0\n");
    out.push_str("interior=true\n");
    out.push_str(&format!("interior.element={element}\n"));
    for (key, value) in text {
        out.push_str(&format!("{key}={value}\n"));
    }
    for (key, value) in extra {
        out.push_str(&format!("{key}={value}\n"));
    }
    out.push('\n');
    out
}

fn general(colors: &ColorScheme, palette: &Palette) -> String {
    format!(
        concat!(
            "[%General]\n",
            "author=desktopctl\n",
            "comment=Generated from {family}-{variant}\n",
            "x11drag=menubar_and_primary_toolbar\n",
            "alt_mnemonic=true\n",
            "left_tabs=false\n",
            "attach_active_tab=false\n",
            "mirror_doc_tabs=true\n",
            "group_toolbar_buttons=false\n",
            "toolbar_item_spacing=2\n",
            "toolbar_interior_spacing=4\n",
            "spread_progressbar=true\n",
            "spread_menuitems=true\n",
            "composite=true\n",
            "menu_shadow_depth=0\n",
            "tooltip_shadow_depth=0\n",
            "scroll_width=12\n",
            "scroll_arrows=false\n",
            "scroll_min_extent=48\n",
            "transient_scrollbar=true\n",
            "transient_groove=true\n",
            "slider_width=4\n",
            "slider_handle_width=18\n",
            "slider_handle_length=18\n",
            "tickless_slider_handle_size=18\n",
            "center_toolbar_handle=true\n",
            "check_size=16\n",
            "textless_progressbar=false\n",
            "progressbar_thickness=6\n",
            "menubar_mouse_tracking=true\n",
            "toolbutton_style=1\n",
            "click_behavior=0\n",
            "translucent_windows=false\n",
            "blurring=false\n",
            "popup_blurring=false\n",
            "vertical_spin_indicators=false\n",
            "inline_spin_indicators=true\n",
            "inline_spin_separator=false\n",
            "spin_button_width=28\n",
            "fill_rubberband=false\n",
            "merge_menubar_with_toolbar=true\n",
            "small_icon_size=16\n",
            "large_icon_size=32\n",
            "button_icon_size=16\n",
            "toolbar_icon_size=22\n",
            "combo_as_lineedit=false\n",
            "square_combo_button=false\n",
            "combo_menu=true\n",
            "hide_combo_checkboxes=true\n",
            "combo_focus_rect=false\n",
            "spread_header=true\n",
            "layout_spacing=6\n",
            "layout_margin=8\n",
            "tooltip_delay=-1\n",
            "submenu_overlap=0\n",
            "animate_states=true\n",
            "tree_branch_line=false\n",
            "contrast=1.00\n",
            "dialog_button_layout=2\n",
            "groupbox_top_label=true\n",
            "intensity=1.00\n",
            "joined_inactive_tabs=false\n",
            "no_inactiveness=true\n",
            "no_window_pattern=true\n",
            "reduce_menu_opacity=0\n",
            "reduce_window_opacity=0\n",
            "respect_DE=false\n",
            "saturation=1.00\n",
            "scrollable_menu=true\n",
            "scrollbar_in_view=false\n",
            "submenu_delay=200\n",
            "\n",
            "[GeneralColors]\n",
            "window.color={window}\n",
            "inactive.window.color={window}\n",
            "base.color={base}\n",
            "inactive.base.color={base}\n",
            "alt.base.color={alt_base}\n",
            "inactive.alt.base.color={alt_base}\n",
            "button.color={button}\n",
            "light.color={light}\n",
            "mid.light.color={mid_light}\n",
            "dark.color={dark}\n",
            "mid.color={mid}\n",
            "highlight.color={accent}\n",
            "inactive.highlight.color={inactive_highlight}\n",
            "tooltip.base.color={window}\n",
            "text.color={fg}\n",
            "inactive.text.color={fg2}\n",
            "window.text.color={fg}\n",
            "inactive.window.text.color={fg2}\n",
            "button.text.color={fg}\n",
            "disabled.text.color={fg4}\n",
            "tooltip.text.color={fg}\n",
            "highlight.text.color={on_accent}\n",
            "link.color={blue}\n",
            "link.visited.color={purple}\n",
            "progress.indicator.text.color={fg}\n",
            "\n",
            "[Hacks]\n",
            "transparent_dolphin_view=false\n",
            "transparent_ktitle_label=true\n",
            "transparent_menutitle=true\n",
            "respect_darkness=true\n",
            "kcapacitybar_as_progressbar=true\n",
            "force_size_grip=false\n",
            "iconless_pushbutton=false\n",
            "iconless_menu=false\n",
            "normal_default_pushbutton=true\n",
            "single_top_toolbar=true\n",
            "tint_on_mouseover=0\n",
            "disabled_icon_opacity=45\n",
            "lxqtmainmenu_iconsize=22\n",
            "\n",
        ),
        family = colors.family,
        variant = colors.variant,
        window = palette.window,
        base = palette.base,
        alt_base = blend(&palette.base, &palette.window, 0.5),
        button = palette.button,
        light = blend(&palette.window, &colors.fg, 0.28),
        mid_light = blend(&palette.window, &colors.fg, 0.16),
        dark = colors.bg_dim,
        mid = palette.line,
        accent = palette.accent,
        inactive_highlight = blend(&palette.window, &colors.fg, 0.14),
        fg = colors.fg,
        fg2 = colors.fg2,
        fg4 = colors.fg4,
        on_accent = palette.on_accent,
        blue = colors.blue,
        purple = colors.purple,
    )
}

pub fn kvconfig(colors: &ColorScheme) -> String {
    let palette = Palette::new(colors);
    let fg = colors.fg.as_str();
    let fg2 = colors.fg2.as_str();
    let fg3 = colors.fg3.as_str();
    let on_accent = palette.on_accent.as_str();

    let plain = |color: &str| -> Vec<(&'static str, String)> {
        vec![
            ("text.normal.color", color.to_owned()),
            ("text.focus.color", color.to_owned()),
            ("text.press.color", color.to_owned()),
            ("text.toggle.color", color.to_owned()),
        ]
    };
    let owned = |pairs: Vec<(&'static str, String)>| pairs;

    let mut out = general(colors, &palette);

    out.push_str(&widget(
        "PanelButtonCommand",
        "button",
        8.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg.to_owned()),
            ("text.focus.color", fg.to_owned()),
            ("text.press.color", fg.to_owned()),
            ("text.toggle.color", on_accent.to_owned()),
            ("text.margin.top", "3".to_owned()),
            ("text.margin.bottom", "3".to_owned()),
            ("text.margin.left", "10".to_owned()),
            ("text.margin.right", "10".to_owned()),
            ("indicator.element", "arrow".to_owned()),
            ("indicator.size", "16".to_owned()),
            ("min_height", "+6".to_owned()),
        ]),
    ));

    out.push_str(&widget(
        "PanelButtonTool",
        "tbutton",
        7.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg.to_owned()),
            ("text.focus.color", fg.to_owned()),
            ("text.press.color", fg.to_owned()),
            ("text.toggle.color", on_accent.to_owned()),
            ("text.margin.left", "6".to_owned()),
            ("text.margin.right", "6".to_owned()),
            ("indicator.element", "arrow".to_owned()),
            ("indicator.size", "16".to_owned()),
        ]),
    ));

    out.push_str(&widget(
        "LineEdit",
        "lineedit",
        8.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg.to_owned()),
            ("text.focus.color", fg.to_owned()),
            ("text.margin.top", "3".to_owned()),
            ("text.margin.bottom", "3".to_owned()),
            ("text.margin.left", "6".to_owned()),
            ("text.margin.right", "6".to_owned()),
            ("min_height", "+6".to_owned()),
        ]),
    ));

    out.push_str(&widget("GenericFrame", "common", 8.0, &[], &[]));
    out.push_str(&widget("TabFrame", "tabframe", 8.0, &[], &[]));
    out.push_str(&widget("GroupBox", "group", 10.0, &[], &plain(fg)));

    out.push_str(&widget(
        "ItemView",
        "itemview",
        6.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg.to_owned()),
            ("text.focus.color", fg.to_owned()),
            ("text.press.color", on_accent.to_owned()),
            ("text.toggle.color", on_accent.to_owned()),
            ("text.margin.left", "4".to_owned()),
            ("text.margin.right", "4".to_owned()),
            ("indicator.element", "arrow".to_owned()),
            ("indicator.size", "16".to_owned()),
            ("min_height", "+4".to_owned()),
        ]),
    ));

    out.push_str(&widget(
        "MenuItem",
        "menuitem",
        7.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg.to_owned()),
            ("text.focus.color", on_accent.to_owned()),
            ("text.margin.top", "4".to_owned()),
            ("text.margin.bottom", "4".to_owned()),
            ("text.margin.left", "8".to_owned()),
            ("text.margin.right", "12".to_owned()),
            ("indicator.element", "arrow".to_owned()),
            ("indicator.size", "16".to_owned()),
        ]),
    ));

    out.push_str(&widget(
        "MenuBarItem",
        "menubaritem",
        7.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg.to_owned()),
            ("text.focus.color", fg.to_owned()),
            ("text.press.color", on_accent.to_owned()),
            ("text.margin.left", "8".to_owned()),
            ("text.margin.right", "8".to_owned()),
        ]),
    ));

    out.push_str(&widget(
        "Menu",
        "menu",
        12.0,
        &[],
        &owned(vec![("text.normal.color", fg.to_owned())]),
    ));

    out.push_str(&widget(
        "Tab",
        "tab",
        7.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg3.to_owned()),
            ("text.focus.color", fg.to_owned()),
            ("text.toggle.color", fg.to_owned()),
            ("text.margin.left", "10".to_owned()),
            ("text.margin.right", "10".to_owned()),
            ("text.margin.top", "3".to_owned()),
            ("text.margin.bottom", "3".to_owned()),
        ]),
    ));

    out.push_str(&widget(
        "HeaderSection",
        "header",
        1.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg2.to_owned()),
            ("text.focus.color", fg.to_owned()),
            ("text.toggle.color", fg.to_owned()),
            ("text.margin.left", "6".to_owned()),
            ("text.margin.right", "6".to_owned()),
            ("indicator.element", "arrow".to_owned()),
            ("indicator.size", "12".to_owned()),
        ]),
    ));

    out.push_str(&widget("Toolbar", "toolbar", 1.0, &[], &plain(fg)));
    out.push_str(&widget("TitleBar", "titlebar", 1.0, &[], &plain(fg)));
    out.push_str(&widget("Dock", "dock", 1.0, &[], &plain(fg)));
    out.push_str(&widget("DockTitle", "dock", 1.0, &[], &plain(fg)));
    out.push_str(&widget("StatusBar", "statusbar", 1.0, &[], &plain(fg)));
    out.push_str(&widget("Window", "toolbar", 1.0, &[], &[]));

    out.push_str(&widget(
        "ToolTip",
        "tooltip",
        10.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg.to_owned()),
            ("text.margin.top", "4".to_owned()),
            ("text.margin.bottom", "4".to_owned()),
            ("text.margin.left", "8".to_owned()),
            ("text.margin.right", "8".to_owned()),
        ]),
    ));

    out.push_str(&widget("Progressbar", "progress", 3.0, &[], &plain(fg)));
    out.push_str(&widget(
        "ProgressbarContents",
        "progress-pattern",
        3.0,
        &[],
        &plain(on_accent),
    ));
    out.push_str(&widget("Slider", "slider", 2.0, &[], &[]));
    out.push_str(&widget("SliderCursor", "slidercursor", 9.0, &[], &[]));
    out.push_str(&widget("ScrollbarGroove", "scrollbargroove", 5.0, &[], &[]));
    out.push_str(&widget("ScrollbarSlider", "scrollbarslider", 5.0, &[], &[]));
    out.push_str(&widget(
        "ScrollbarTransientSlider",
        "scrollbarslider",
        5.0,
        &[],
        &[],
    ));
    out.push_str(&widget("Splitter", "splitter", 1.0, &[], &[]));
    out.push_str(&widget("SizeGrip", "splitter", 1.0, &[], &[]));

    out.push_str(&widget(
        "ComboBox",
        "button",
        8.0,
        &[],
        &owned(vec![
            ("text.normal.color", fg.to_owned()),
            ("text.focus.color", fg.to_owned()),
            ("text.margin.left", "10".to_owned()),
            ("text.margin.right", "6".to_owned()),
            ("min_height", "+6".to_owned()),
        ]),
    ));
    out.push_str(&widget(
        "DropDownButton",
        "tbutton",
        7.0,
        &[],
        &owned(vec![
            ("indicator.element", "arrow".to_owned()),
            ("indicator.size", "16".to_owned()),
        ]),
    ));
    out.push_str(&widget(
        "IndicatorSpinBox",
        "tbutton",
        7.0,
        &[],
        &owned(vec![
            ("indicator.element", "arrow".to_owned()),
            ("indicator.size", "14".to_owned()),
        ]),
    ));

    for (section, element) in [("CheckBox", "checkbox"), ("RadioButton", "radio")] {
        out.push_str(&format!(
            concat!(
                "[{section}]\n",
                "frame=false\n",
                "interior=false\n",
                "indicator.element={element}\n",
                "indicator.size=16\n",
                "text.normal.color={fg}\n",
                "text.focus.color={fg}\n",
                "text.margin.left=4\n\n",
            ),
            section = section,
            element = element,
            fg = fg,
        ));
    }

    out.push_str(&format!(
        concat!(
            "[IndicatorArrow]\n",
            "indicator.element=arrow\n",
            "indicator.size=16\n\n",
            "[TreeExpander]\n",
            "indicator.element=arrow\n",
            "indicator.size=14\n\n",
            "[Scrollbar]\n",
            "indicator.element=arrow\n",
            "indicator.size=12\n\n",
            "[ToolboxTab]\n",
            "frame=false\n",
            "interior=false\n",
            "text.normal.color={fg2}\n",
            "text.focus.color={fg}\n",
            "text.toggle.color={fg}\n\n",
            "[TabBarFrame]\n",
            "frame=false\n",
            "interior=false\n\n",
        ),
        fg = fg,
        fg2 = fg2,
    ));

    out
}

#[cfg(test)]
mod tests {
    use super::{kvconfig, svg};
    use crate::test_support::repo_root;
    use crate::theme::resolve;
    use std::collections::HashSet;

    fn scheme(name: &str) -> crate::theme::schema::ColorScheme {
        resolve::load_colors(name, &repo_root().join("styling/colors"))
            .expect("repo color scheme should deserialize")
    }

    fn svg_ids(document: &str) -> HashSet<String> {
        document
            .split("<g id=\"")
            .skip(1)
            .filter_map(|chunk| chunk.split('"').next())
            .map(str::to_owned)
            .collect()
    }

    /// A kvconfig naming an element the SVG lacks does not fail loudly — Kvantum
    /// simply paints nothing, and the widget disappears.
    #[test]
    fn every_element_the_kvconfig_names_exists_in_the_svg() {
        for name in ["gruvbox-dark", "solarized-light", "rose-pine"] {
            let colors = scheme(name);
            let ids = svg_ids(&svg(&colors));
            let config = kvconfig(&colors);

            let referenced = config
                .lines()
                .filter_map(|line| line.strip_prefix("frame.element="))
                .chain(
                    config
                        .lines()
                        .filter_map(|line| line.strip_prefix("interior.element=")),
                )
                .collect::<HashSet<_>>();

            for element in referenced {
                for state in ["normal", "focused", "pressed", "toggled"] {
                    for suffix in [
                        "",
                        "-top",
                        "-bottom",
                        "-left",
                        "-right",
                        "-topleft",
                        "-topright",
                        "-bottomleft",
                        "-bottomright",
                    ] {
                        let id = format!("{element}-{state}{suffix}");
                        assert!(ids.contains(&id), "{name}: SVG is missing {id}");
                    }
                }
            }
        }
    }

    /// Indicators are looked up by a different name shape than frames, so they
    /// need their own guard.
    #[test]
    fn every_indicator_the_kvconfig_names_exists_in_the_svg() {
        let colors = scheme("gruvbox-dark");
        let ids = svg_ids(&svg(&colors));
        let config = kvconfig(&colors);

        for element in config
            .lines()
            .filter_map(|line| line.strip_prefix("indicator.element="))
            .collect::<HashSet<_>>()
        {
            for state in ["normal", "focused", "pressed", "toggled"] {
                let candidates = if element == "arrow" {
                    vec![format!("arrow-down-{state}")]
                } else {
                    vec![format!("{element}-{state}")]
                };
                for id in candidates {
                    assert!(ids.contains(&id), "SVG is missing indicator {id}");
                }
            }
        }
    }
}
