pragma Singleton

import QtQuick

// The option lists settings surfaces offer: data only, never read from the system.
QtObject {
    readonly property var systemFonts: ["SF Pro", "Geist", "Inter", "Overpass", "IBM Plex Sans", "Rubik", "Noto Sans", "Cantarell", "Source Sans 3"]

    // The value the backend wants differs from the name a person recognises.
    readonly property var monoFonts: [
        { label: "JetBrains Mono", value: "JetBrainsMono Nerd Font" },
        { label: "Berkeley Mono", value: "Berkeley Mono" },
        { label: "Commit Mono", value: "CommitMono" },
        { label: "Recursive Mono", value: "RecMonoLinear Nerd Font" },
        { label: "Cozette", value: "Cozette" },
        { label: "Fira Code", value: "FiraCode Nerd Font" },
        { label: "Iosevka", value: "Iosevka Nerd Font" }
    ]

    readonly property var iconThemes: ["Neuwaita", "Colloid", "Colloid-Dark", "Colloid-Light", "Papirus-Dark", "Papirus", "Papirus-Light", "Adwaita", "hicolor"]

    readonly property var cursorThemes: ["Adwaita", "BreezeX-RosePine-Linux", "BreezeX-RosePineDawn-Linux", "Bibata-Modern-Classic", "Bibata-Modern-Ice", "Bibata-Original-Classic", "Bibata-Original-Ice"]

    readonly property var installed: {
        const families = Qt.fontFamilies();
        const index = {};
        for (let i = 0; i < families.length; i++)
            index[families[i].replace(/ /g, "").toLowerCase()] = true;
        return index;
    }

    function available(family) {
        return installed[String(family || "").replace(/ /g, "").toLowerCase()] === true;
    }
}
