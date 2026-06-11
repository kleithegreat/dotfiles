import Quickshell
import QtQuick
import QtQuick.Layouts
import ".." as Root

Item {
    id: root

    property string themeName: ""
    property bool active: false
    property bool disabled: false
    property bool pending: false

    signal clicked()

    readonly property var config: root.themeConfig(root.themeName)
    readonly property var previewIconSources: root.previewIconSourcesForTheme(root.themeName)
    readonly property bool interactive: root.themeName !== "" && !root.disabled

    implicitWidth: Math.max(Root.Theme.fontSize * 10.5, 160)
    implicitHeight: Math.max(Root.Theme.btnHeight * 3.9, 112)
    opacity: root.disabled ? 0.55 : (root.pending && root.active ? 0.72 : 1)
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }

    function formattedName(value) {
        let text = String(value || "").trim();

        if (text === "")
            return "";

        let parts = text.replace(/[_-]+/g, " ").split(/\s+/);
        for (let i = 0; i < parts.length; i++) {
            let part = parts[i];
            if (part.length === 0)
                continue;
            parts[i] = part.charAt(0).toUpperCase() + part.slice(1);
        }

        return parts.join(" ");
    }

    function baseThemeName(value) {
        let text = String(value || "").trim();

        if (text.endsWith("-Dark"))
            return text.slice(0, text.length - 5);
        if (text.endsWith("-Light"))
            return text.slice(0, text.length - 6);
        return text;
    }

    function variantLabel(value) {
        let text = String(value || "").trim();

        if (text.endsWith("-Dark"))
            return "Dark";
        if (text.endsWith("-Light"))
            return "Light";

        switch (text) {
        case "Neuwaita":
            return "Default";
        case "Adwaita":
            return "GNOME";
        case "hicolor":
            return "Fallback";
        default:
            return "";
        }
    }

    readonly property string iconThemeRoot: {
        let user = Quickshell.env("USER");
        if (user !== null && user !== undefined && String(user).trim() !== "")
            return "/etc/profiles/per-user/" + String(user).trim() + "/share/icons";

        return "";
    }

    function fileUrl(path) {
        return "file://" + path;
    }

    function themeConfig(value) {
        let text = String(value || "").trim();

        switch (text) {
        case "Neuwaita":
            return {
                title: "Neuwaita",
                variant: "Default",
                accent: "#8ab4f8"
            };
        case "Colloid":
            return {
                title: "Colloid",
                variant: "Default",
                accent: "#8aa4ff"
            };
        case "Colloid-Dark":
            return {
                title: "Colloid",
                variant: "Dark",
                accent: "#7aa2f7"
            };
        case "Colloid-Light":
            return {
                title: "Colloid",
                variant: "Light",
                accent: "#5b7cfa"
            };
        case "Papirus-Dark":
            return {
                title: "Papirus",
                variant: "Dark",
                accent: "#4ecdc4"
            };
        case "Papirus":
            return {
                title: "Papirus",
                variant: "Default",
                accent: "#1eb4d4"
            };
        case "Papirus-Light":
            return {
                title: "Papirus",
                variant: "Light",
                accent: "#11a7c7"
            };
        case "Adwaita":
            return {
                title: "Adwaita",
                variant: "GNOME",
                accent: "#3584e4"
            };
        case "hicolor":
            return {
                title: "Hicolor",
                variant: "Fallback",
                accent: "#808a9c"
            };
        default: {
            let variant = root.variantLabel(text);
            return {
                title: root.formattedName(root.baseThemeName(text)),
                variant: variant,
                accent: variant === "Light" ? "#5b7cfa" : "#7aa2f7"
            };
        }
        }
    }

    function previewIconSourcesForTheme(value) {
        if (root.iconThemeRoot === "")
            return [];

        let rootPath = root.iconThemeRoot + "/" + String(value || "").trim();

        switch (String(value || "").trim()) {
        case "Neuwaita":
            return [
                root.fileUrl(rootPath + "/scalable/places/folder.svg"),
                root.fileUrl(rootPath + "/scalable/places/user-home.svg"),
                root.fileUrl(rootPath + "/scalable/mimetypes/text-x-generic.svg")
            ];
        case "Colloid":
            return [
                root.fileUrl(rootPath + "/places/scalable/default-folder.svg"),
                root.fileUrl(rootPath + "/places/scalable/default-user-home.svg"),
                root.fileUrl(rootPath + "/mimetypes/scalable/text-x-generic.svg")
            ];
        case "Colloid-Dark":
        case "Colloid-Light":
            return [
                root.fileUrl(rootPath + "/places/scalable/folder.svg"),
                root.fileUrl(rootPath + "/places/scalable/user-home.svg"),
                root.fileUrl(rootPath + "/mimetypes/scalable/text-x-generic.svg")
            ];
        case "Papirus":
        case "Papirus-Dark":
        case "Papirus-Light":
            return [
                root.fileUrl(rootPath + "/48x48/places/folder.svg"),
                root.fileUrl(rootPath + "/48x48/places/user-home.svg"),
                root.fileUrl(rootPath + "/48x48/mimetypes/text-x-generic.svg")
            ];
        case "Adwaita":
            return [
                root.fileUrl(rootPath + "/scalable/places/folder.svg"),
                root.fileUrl(rootPath + "/scalable/places/user-home.svg"),
                root.fileUrl(rootPath + "/scalable/mimetypes/text-x-generic.svg")
            ];
        case "hicolor":
            return [
                root.fileUrl(rootPath + "/48x48/apps/chromium.png"),
                root.fileUrl(rootPath + "/48x48/apps/org.gnome.gedit.png"),
                root.fileUrl(rootPath + "/48x48/apps/thunderbird.png")
            ];
        default:
            return [];
        }
    }

    StyledRect {
        id: cardBackground
        anchors.fill: parent
        radius: Root.Theme.btnRadius + 4
        color: cardArea.containsMouse ? Root.Theme.bg2 : Root.Theme.bg1
        border.width: root.active ? 2 : 1
        border.color: root.active
            ? root.config.accent
            : (cardArea.containsMouse ? Root.Theme.fg4 : Root.Theme.bg3)
        scale: cardArea.pressed ? 0.985 : 1.0
        transformOrigin: Item.Center

        Behavior on border.color {
            CAnim {
                duration: Root.Theme.animSpring
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Root.Theme.animCurveStandard
            }
        }

        Behavior on scale {
            Anim {
                duration: Root.Theme.animMicro
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Root.Theme.animCurveStandard
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 4

                    StyledText {
                        text: root.config.title
                        color: Root.Theme.fg
                        font.family: Root.Theme.systemFamily
                        font.pixelSize: Root.Theme.fontSize
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: root.config.variant !== ""
                        implicitWidth: chipText.implicitWidth + 12
                        implicitHeight: chipText.implicitHeight + 4
                        radius: height / 2
                        color: Root.Theme.bg
                        border.width: 1
                        border.color: Root.Theme.bg3

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: root.config.variant
                            color: Root.Theme.fg3
                            font.family: Root.Theme.systemFamily
                            font.pixelSize: Root.Theme.fontSizeSmall - 1
                            font.bold: true
                        }
                    }
                }

                Icon {
                    visible: root.active
                    source: "../icons/circle-check-filled.svg"
                    color: root.config.accent
                    iconSize: Math.max(Root.Theme.iconSize * 0.95, 16)
                    Layout.alignment: Qt.AlignTop
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                radius: Root.Theme.btnRadius + 2
                color: Root.Theme.bg
                border.width: 1
                border.color: cardArea.containsMouse ? Root.Theme.fg4 : Root.Theme.bg3

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    Repeater {
                        model: root.previewIconSources

                        delegate: Rectangle {
                            id: previewTile
                            required property var modelData

                            width: 30
                            height: 30
                            radius: 8
                            color: Root.Theme.bg1
                            border.width: 1
                            border.color: Root.Theme.bg3

                            Image {
                                id: previewImage
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                source: previewTile.modelData
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                asynchronous: true
                                sourceSize.width: previewImage.width * 2
                                sourceSize.height: previewImage.height * 2
                            }
                        }
                    }
                }
            }
        }

        HoverLayer {
            id: cardArea
            anchors.fill: parent
            disabled: !root.interactive
            hoverEnabled: true
            hoverOpacity: 0
            pressedOpacity: 0
            pressedScale: 1.0
            onClicked: root.clicked()
        }
    }
}
