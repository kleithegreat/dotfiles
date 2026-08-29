use super::{
    Assembly, GeneratedContent, TargetMetadata,
    color_utils::{blend, color_difference, contrast_ratio},
};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata =
    TargetMetadata::new("starship", Assembly::Concat, &["color_scheme"])
        .output("~/.config/starship.toml")
        .base("bases/starship.toml")
        .comment("#");

const WCAG_AA_NORMAL_TEXT: f64 = 4.5;
/// The prompt character is a glyph, not a run of text, so it is held to the
/// non-text contrast bar rather than the reading one.
const WCAG_AA_NON_TEXT: f64 = 3.0;

/// CIE76 separation two adjacent plates need before the chevron between them
/// reads as a seam rather than as one continuous bar.
const MIN_PLATE_SEPARATION: f64 = 20.0;

/// The two trailing plates are neutral surfaces mixed from the scheme's own
/// background towards its own foreground rather than lifted from its `bg1` /
/// `bg3` slots. Those slots are authored as *panel* surfaces: across the
/// fourteen schemes here `bg1` sits between 1.07 and 1.37 contrast from `bg`,
/// which on a panel is a deliberate whisper and on a powerline plate is an
/// invisible one. Mixing guarantees the same visible step in every scheme.
const TOOL_PLATE_MIX: f64 = 0.18;
const TIME_PLATE_MIX: f64 = 0.38;

/// Readable ink for a plate, preferring colours the scheme already contains so
/// the prompt stays inside its own palette. Pure black/white is the last resort
/// for plates no palette entry clears AA against.
fn readable_on(plate: &str, colors: &ColorScheme) -> String {
    let candidates = [
        colors.fg.as_str(),
        colors.bg.as_str(),
        colors.fg2.as_str(),
        colors.fg3.as_str(),
        colors.fg4.as_str(),
        colors.bg_dim.as_str(),
        colors.bg1.as_str(),
        colors.bg2.as_str(),
        colors.bg3.as_str(),
    ];
    for candidate in candidates {
        if contrast_ratio(plate, candidate) >= WCAG_AA_NORMAL_TEXT {
            return candidate.to_owned();
        }
    }

    let black = "#000000";
    let white = "#ffffff";
    if contrast_ratio(plate, black) >= contrast_ratio(plate, white) {
        black.to_owned()
    } else {
        white.to_owned()
    }
}

/// First candidate far enough from every plate already placed, falling back to
/// whichever candidate is furthest from its nearest neighbour.
///
/// The rainbow's hues cannot be taken straight from the palette, because
/// schemes disagree about how many distinct hues they even have: rose-pine
/// defines its orange and its yellow as one colour, so the first two plates
/// would be a single bar with an invisible chevron down the middle.
fn distinct_plate(candidates: &[&str], placed: &[String]) -> String {
    let separation = |candidate: &str| {
        placed
            .iter()
            .map(|plate| color_difference(candidate, plate))
            .fold(f64::INFINITY, f64::min)
    };

    let mut best = candidates[0];
    let mut best_separation = f64::NEG_INFINITY;
    for candidate in candidates {
        let distance = separation(candidate);
        if distance >= MIN_PLATE_SEPARATION {
            return (*candidate).to_owned();
        }
        if distance > best_separation {
            best_separation = distance;
            best = candidate;
        }
    }
    best.to_owned()
}

/// The prompt character sits on the terminal background rather than on a plate,
/// so it keeps the base hue while that hue is legible and only reaches for the
/// bright variant when it is not.
///
/// Preferring whichever variant simply carries further would misname the
/// colour: solarized defines its bright red as an orange, so a
/// highest-contrast rule turns the error prompt orange in a scheme whose red is
/// perfectly readable.
fn on_background<'a>(base: &'a str, bright: &'a str, colors: &ColorScheme) -> &'a str {
    if contrast_ratio(base, &colors.bg) >= WCAG_AA_NON_TEXT {
        return base;
    }
    if contrast_ratio(bright, &colors.bg) > contrast_ratio(base, &colors.bg) {
        bright
    } else {
        base
    }
}

/// The six plates, in the order the prompt draws them.
struct Plates {
    identity: String,
    path: String,
    git: String,
    lang: String,
    tool: String,
    time: String,
}

fn plates(colors: &ColorScheme) -> Plates {
    // Identity resolves against the yellow the path plate intends to take, not
    // against nothing: it is the warm pair that collides ([[theming]]).
    let identity = distinct_plate(
        &[
            &colors.orange,
            &colors.red,
            &colors.orange_bright,
            &colors.red_bright,
        ],
        std::slice::from_ref(&colors.yellow),
    );
    let mut placed = vec![identity.clone()];

    let path = distinct_plate(&[&colors.yellow, &colors.yellow_bright], &placed);
    placed.push(path.clone());

    // "aqua" in gruvbox's names, which is this palette's cyan slot.
    let git = distinct_plate(
        &[
            &colors.cyan,
            &colors.cyan_bright,
            &colors.green,
            &colors.green_bright,
        ],
        &placed,
    );
    placed.push(git.clone());

    let lang = distinct_plate(
        &[
            &colors.blue,
            &colors.blue_bright,
            &colors.purple,
            &colors.purple_bright,
        ],
        &placed,
    );

    Plates {
        identity,
        path,
        git,
        lang,
        tool: blend(&colors.bg, &colors.fg, TOOL_PLATE_MIX),
        time: blend(&colors.bg, &colors.fg, TIME_PLATE_MIX),
    }
}

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    let plates = plates(colors);

    Ok(GeneratedContent::text(format!(
        concat!(
            "\n[palettes.current]\n",
            "color_identity = '{}'\n",
            "color_identity_fg = '{}'\n",
            "color_path = '{}'\n",
            "color_path_fg = '{}'\n",
            "color_git = '{}'\n",
            "color_git_fg = '{}'\n",
            "color_lang = '{}'\n",
            "color_lang_fg = '{}'\n",
            "color_tool = '{}'\n",
            "color_tool_fg = '{}'\n",
            "color_time = '{}'\n",
            "color_time_fg = '{}'\n",
            "color_ok = '{}'\n",
            "color_err = '{}'\n",
            "color_warn = '{}'\n",
            "color_mode = '{}'\n",
        ),
        plates.identity,
        readable_on(&plates.identity, colors),
        plates.path,
        readable_on(&plates.path, colors),
        plates.git,
        readable_on(&plates.git, colors),
        plates.lang,
        readable_on(&plates.lang, colors),
        plates.tool,
        readable_on(&plates.tool, colors),
        plates.time,
        readable_on(&plates.time, colors),
        on_background(&colors.green, &colors.green_bright, colors),
        on_background(&colors.red, &colors.red_bright, colors),
        on_background(&colors.yellow, &colors.yellow_bright, colors),
        on_background(&colors.purple, &colors.purple_bright, colors),
    )))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        test_support::{ScopedEnvVar, env_lock, repo_root},
        theme::targets::testsupport::load_repo_colors,
    };
    use std::fs;

    fn repo_schemes() -> Vec<String> {
        let mut names = fs::read_dir(repo_root().join("styling/colors"))
            .expect("colors dir")
            .filter_map(|entry| {
                let path = entry.ok()?.path();
                if path.extension()? != "json" {
                    return None;
                }
                Some(path.file_stem()?.to_str()?.to_owned())
            })
            .collect::<Vec<_>>();
        names.sort();
        names
    }

    #[test]
    fn every_scheme_keeps_plate_text_above_aa() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        for name in repo_schemes() {
            let colors = load_repo_colors(&name);
            let plates = plates(&colors);
            for (label, plate) in [
                ("identity", &plates.identity),
                ("path", &plates.path),
                ("git", &plates.git),
                ("lang", &plates.lang),
                ("tool", &plates.tool),
                ("time", &plates.time),
            ] {
                let ratio = contrast_ratio(plate, &readable_on(plate, &colors));
                assert!(
                    ratio >= WCAG_AA_NORMAL_TEXT,
                    "{name} {label} plate {plate} has contrast {ratio:.2}"
                );
            }
        }
    }

    #[test]
    fn every_scheme_keeps_the_coloured_plates_apart() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        for name in repo_schemes() {
            let colors = load_repo_colors(&name);
            let plates = plates(&colors);
            let coloured = [
                ("identity", &plates.identity),
                ("path", &plates.path),
                ("git", &plates.git),
                ("lang", &plates.lang),
            ];
            for (index, (left_label, left)) in coloured.iter().enumerate() {
                for (right_label, right) in &coloured[index + 1..] {
                    let distance = color_difference(left, right);
                    assert!(
                        distance >= MIN_PLATE_SEPARATION,
                        "{name}: {left_label} {left} and {right_label} {right} \
                         are only {distance:.1} apart"
                    );
                }
            }
        }
    }

    #[test]
    fn every_scheme_keeps_the_neutral_plates_stepping_away_from_the_background() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        for name in repo_schemes() {
            let colors = load_repo_colors(&name);
            let plates = plates(&colors);
            // The scheme's own bg1 gets as close as 1.07 to bg; the mixed
            // plates are what buy the trailing segments a visible edge.
            assert!(
                contrast_ratio(&plates.tool, &colors.bg) > 1.15,
                "{name}: tool plate is flush with the background"
            );
            assert!(
                contrast_ratio(&plates.time, &plates.tool) > 1.15,
                "{name}: time plate is flush with the tool plate"
            );
            assert!(
                contrast_ratio(&plates.time, &colors.bg) > 1.4,
                "{name}: time plate is flush with the background"
            );
        }
    }

    #[test]
    fn gruvbox_reproduces_the_powerline_preset_the_order_came_from() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        let colors = load_repo_colors("gruvbox-dark");
        let plates = plates(&colors);
        assert_eq!(plates.identity, colors.orange);
        assert_eq!(plates.path, colors.yellow);
        assert_eq!(plates.git, colors.cyan);
        assert_eq!(plates.lang, colors.blue);
    }

    /// rose-pine defines one warm hue under both `orange` and `yellow`, so the
    /// identity plate has to leave the pair rather than repeat the path plate.
    #[test]
    fn a_scheme_whose_orange_is_its_yellow_moves_the_identity_plate() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        let colors = load_repo_colors("rose-pine");
        assert_eq!(colors.orange, colors.yellow, "fixture assumption");

        let plates = plates(&colors);
        assert_eq!(plates.path, colors.yellow);
        assert_eq!(plates.identity, colors.red);
    }
}
