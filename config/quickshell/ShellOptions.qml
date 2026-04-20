pragma Singleton
import QtQuick

QtObject {
    readonly property var systemFontOptions: [
        "Overpass",
        "Inter",
        "Geist",
        "IBM Plex Sans",
        "Rubik",
        "Noto Sans",
        "Cantarell",
        "Source Sans 3",
        "Outfit",
        "SF Pro"
    ]

    readonly property var presetMonoFontOptions: [
        "JetBrains Mono Nerd Font",
        "Berkeley Mono",
        "Commit Mono",
        "Recursive Mono",
        "Fira Code Nerd Font",
        "Iosevka Nerd Font"
    ]

    readonly property var fontPaneMonoFontOptions: [
        "JetBrains Mono Nerd Font",
        "Berkeley Mono",
        "Commit Mono",
        "CozetteVector",
        "Recursive Mono",
        "Fira Code Nerd Font",
        "Iosevka Nerd Font"
    ]

    readonly property var iconThemeOptions: [
        "Neuwaita",
        "Colloid",
        "Colloid-Dark",
        "Colloid-Light",
        "Papirus-Dark",
        "Papirus",
        "Papirus-Light",
        "Adwaita",
        "hicolor"
    ]

    readonly property var cursorThemeOptions: [
        "Adwaita",
        "BreezeX-RosePine-Linux",
        "BreezeX-RosePineDawn-Linux",
        "Bibata-Modern-Classic",
        "Bibata-Modern-Ice",
        "Bibata-Original-Classic",
        "Bibata-Original-Ice"
    ]

    readonly property var installedFamilies: {
        let families = Qt.fontFamilies();
        let normalized = {};
        for (let i = 0; i < families.length; i++)
            normalized[families[i].replace(/ /g, "").toLowerCase()] = true;
        return normalized;
    }

    function isFontUnavailable(familyName) {
        return !installedFamilies[String(familyName || "").replace(/ /g, "").toLowerCase()];
    }

    function monoFontValue(fontName) {
        switch (fontName) {
        case "JetBrains Mono Nerd Font":
            return "JetBrainsMono Nerd Font";
        case "Fira Code Nerd Font":
            return "FiraCode Nerd Font";
        case "Commit Mono":
            return "CommitMono";
        default:
            return fontName;
        }
    }

    function monoFontOptionMatchesCurrent(fontName, currentValue) {
        return monoFontValue(fontName) === monoFontValue(currentValue);
    }

    function monoFontLabel(fontName) {
        switch (monoFontValue(fontName)) {
        case "JetBrainsMono Nerd Font":
            return "JetBrains Mono";
        case "FiraCode Nerd Font":
            return "Fira Code";
        case "CommitMono":
            return "Commit Mono";
        default:
            return monoFontValue(fontName).replace(" Nerd Font", "");
        }
    }

    function isMonoFontUnavailable(fontName) {
        return isFontUnavailable(monoFontValue(fontName));
    }
}
