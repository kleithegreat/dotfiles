import QtQuick

// Canonical metadata for the desktopctl-managed Hyprland appearance options.
// Shared by the settings host (SettingsPopup) and the preset editor so
// labels, fallbacks, and minimums cannot diverge.
QtObject {
    readonly property var optionInfo: ({
        "general:gaps_in": { label: "Inner gaps", type: "int", fallback: 4, minimum: 0, step: 1, stateKey: "hypr_gaps_in" },
        "general:gaps_out": { label: "Outer gaps", type: "int", fallback: 6, minimum: 0, step: 1, stateKey: "hypr_gaps_out" },
        "general:border_size": { label: "Border size", type: "int", fallback: 0, minimum: 0, step: 1, stateKey: "hypr_border_size" },
        "decoration:rounding": { label: "Rounding", type: "int", fallback: 8, minimum: 0, step: 1, stateKey: "hypr_rounding" },
        "decoration:blur:enabled": { label: "Enable blur", type: "bool", fallback: false, stateKey: "hypr_blur_enabled" },
        "decoration:blur:size": { label: "Blur size", type: "int", fallback: 3, minimum: 1, step: 1, stateKey: "hypr_blur_size" },
        "decoration:blur:passes": { label: "Blur passes", type: "int", fallback: 4, minimum: 1, step: 1, stateKey: "hypr_blur_passes" },
        "animations:enabled": { label: "Enable animations", type: "bool", fallback: true, stateKey: "hypr_animations_enabled" }
    })

    // Int options keyed by theme-state key, for panes that edit preset fields.
    readonly property var intOptions: {
        let result = [];
        let keys = Object.keys(optionInfo);
        for (let i = 0; i < keys.length; i++) {
            let meta = optionInfo[keys[i]];
            if (meta.type !== "int")
                continue;
            result.push({ key: meta.stateKey, label: meta.label, fallback: meta.fallback, minimum: meta.minimum, step: meta.step });
        }
        return result;
    }
}
