//! Same-family appearance-pair resolution shared by targets that need the
//! light/dark counterpart of the active color scheme (qt, gtksourceview,
//! vicinae).

use crate::theme::{
    resolve,
    schema::{ColorScheme, ColorSchemeAppearance},
};
use std::fs;

#[derive(Clone)]
pub(crate) struct SchemeEntry {
    pub(crate) name: String,
    pub(crate) colors: ColorScheme,
}

pub(crate) fn load_scheme_catalog() -> crate::Result<Vec<SchemeEntry>> {
    let colors_dir = resolve::colors_dir()?;
    let mut names = fs::read_dir(&colors_dir)?
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let path = entry.path();
            if path
                .extension()
                .is_some_and(|extension| extension == "json")
            {
                path.file_stem()
                    .and_then(|stem| stem.to_str())
                    .map(str::to_owned)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();
    names.sort();

    let mut catalog = Vec::with_capacity(names.len());
    for name in names {
        catalog.push(SchemeEntry {
            colors: resolve::load_colors(&name, &colors_dir)?,
            name,
        });
    }
    Ok(catalog)
}

/// Resolve the same-family scheme matching the desired appearance.
///
/// Returns `None` when the current scheme already matches or no same-family
/// counterpart exists. The explicit `dark_scheme` pairing declared in scheme
/// data wins; otherwise a conventional variant-name preference order decides,
/// falling back to the alphabetically first candidate.
pub(crate) fn scheme_for_appearance<'a>(
    catalog: &'a [SchemeEntry],
    current_colors: &ColorScheme,
    desired_appearance: ColorSchemeAppearance,
) -> Option<&'a SchemeEntry> {
    if current_colors.appearance == desired_appearance {
        return None;
    }

    let mut candidates = catalog
        .iter()
        .filter(|entry| {
            entry.colors.family == current_colors.family
                && entry.colors.appearance == desired_appearance
        })
        .collect::<Vec<_>>();

    if candidates.is_empty() {
        return None;
    }

    candidates.sort_by(|left, right| left.name.cmp(&right.name));

    if desired_appearance == ColorSchemeAppearance::Dark
        && let Some(paired_name) = current_colors.dark_scheme.as_deref()
        && let Some(entry) = candidates.iter().find(|entry| entry.name == paired_name)
    {
        return Some(entry);
    }

    let preferred_variants = match desired_appearance {
        ColorSchemeAppearance::Dark => ["dark", "night", "mocha", "macchiato", "frappe"].as_slice(),
        ColorSchemeAppearance::Light => ["light", "dawn", "latte"].as_slice(),
    };

    for variant in preferred_variants {
        if let Some(entry) = candidates
            .iter()
            .find(|entry| entry.colors.variant == *variant)
        {
            return Some(entry);
        }
    }

    Some(candidates[0])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::targets::testsupport::dummy_colors;

    pub(crate) fn scheme_entry(
        name: &str,
        family: &str,
        variant: &str,
        appearance: ColorSchemeAppearance,
    ) -> SchemeEntry {
        let mut colors = dummy_colors();
        colors.family = family.to_owned();
        colors.variant = variant.to_owned();
        colors.appearance = appearance;
        colors.dark_scheme = None;
        SchemeEntry {
            name: name.to_owned(),
            colors,
        }
    }

    fn catalog_fixture() -> Vec<SchemeEntry> {
        vec![
            scheme_entry(
                "gruvbox-dark",
                "gruvbox",
                "dark",
                ColorSchemeAppearance::Dark,
            ),
            scheme_entry(
                "gruvbox-light",
                "gruvbox",
                "light",
                ColorSchemeAppearance::Light,
            ),
            scheme_entry(
                "catppuccin-latte",
                "catppuccin",
                "latte",
                ColorSchemeAppearance::Light,
            ),
            scheme_entry(
                "catppuccin-frappe",
                "catppuccin",
                "frappe",
                ColorSchemeAppearance::Dark,
            ),
            scheme_entry(
                "catppuccin-macchiato",
                "catppuccin",
                "macchiato",
                ColorSchemeAppearance::Dark,
            ),
            scheme_entry(
                "catppuccin-mocha",
                "catppuccin",
                "mocha",
                ColorSchemeAppearance::Dark,
            ),
        ]
    }

    fn colors_for_name(catalog: &[SchemeEntry], name: &str) -> ColorScheme {
        catalog
            .iter()
            .find(|entry| entry.name == name)
            .expect("scheme fixture exists")
            .colors
            .clone()
    }

    #[test]
    fn returns_none_when_appearance_already_matches() {
        let catalog = catalog_fixture();
        let current = colors_for_name(&catalog, "gruvbox-dark");
        assert!(scheme_for_appearance(&catalog, &current, ColorSchemeAppearance::Dark).is_none());
    }

    #[test]
    fn picks_unique_light_pair() {
        let catalog = catalog_fixture();
        let current = colors_for_name(&catalog, "gruvbox-dark");
        let entry = scheme_for_appearance(&catalog, &current, ColorSchemeAppearance::Light)
            .expect("light pair exists");
        assert_eq!(entry.name, "gruvbox-light");
    }

    #[test]
    fn explicit_dark_scheme_pairing_wins_over_variant_preference() {
        let catalog = catalog_fixture();
        let mut current = colors_for_name(&catalog, "catppuccin-latte");
        current.dark_scheme = Some("catppuccin-macchiato".to_owned());
        let entry = scheme_for_appearance(&catalog, &current, ColorSchemeAppearance::Dark)
            .expect("dark pair exists");
        assert_eq!(entry.name, "catppuccin-macchiato");
    }

    #[test]
    fn falls_back_to_conventional_dark_variant_order() {
        let catalog = catalog_fixture();
        let current = colors_for_name(&catalog, "catppuccin-latte");
        let entry = scheme_for_appearance(&catalog, &current, ColorSchemeAppearance::Dark)
            .expect("dark pair exists");
        assert_eq!(entry.name, "catppuccin-mocha");
    }

    #[test]
    fn returns_none_when_no_same_family_pair_exists() {
        let current = scheme_entry(
            "gruvbox-dark",
            "gruvbox",
            "dark",
            ColorSchemeAppearance::Dark,
        )
        .colors;
        let catalog = vec![SchemeEntry {
            name: "gruvbox-dark".to_owned(),
            colors: current.clone(),
        }];
        assert!(scheme_for_appearance(&catalog, &current, ColorSchemeAppearance::Light).is_none());
    }
}
