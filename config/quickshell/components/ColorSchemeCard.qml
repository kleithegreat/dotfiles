import QtQuick
import QtQuick.Layouts
import ".." as Root

Item {
    id: root

    property var scheme: ({})
    property bool active: false
    property bool disabled: false
    property bool pending: false

    signal clicked()

    readonly property bool interactive: !!root.scheme && !!root.scheme.schemeName && !root.disabled

    readonly property color accentColor: root.scheme.accent || root.scheme.blue || Root.Theme.accent
    readonly property color secondaryForegroundColor: root.scheme.fg2 || root.scheme.fg || Root.Theme.fg4
    readonly property color previewBorderColor: root.scheme.bg3 || root.scheme.fg4 || Root.Theme.bg3
    readonly property color swatchBorderColor: root.scheme.appearance === "light"
        ? Qt.rgba(0, 0, 0, 0.18)
        : Qt.rgba(1, 1, 1, 0.1)

    implicitWidth: Math.max(Root.Theme.fontSize * 11, 168)
    implicitHeight: Math.max(Root.Theme.btnHeight * 2.15, 90)
    opacity: root.disabled ? 0.55 : (root.pending && root.active ? 0.72 : 1)
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }

    function formattedName(value) {
        let text = String(value || "").trim();
        let overrides = {
            "tokyonight": "Tokyo Night",
            "rosepine": "Rose Pine"
        };

        if (text === "")
            return "";
        if (overrides[text] !== undefined)
            return overrides[text];

        let parts = text.replace(/[_-]+/g, " ").split(/\s+/);
        for (let i = 0; i < parts.length; i++) {
            let part = parts[i];
            if (part.length === 0)
                continue;
            parts[i] = part.charAt(0).toUpperCase() + part.slice(1);
        }

        return parts.join(" ");
    }

    function familyLabel() {
        return root.formattedName(root.scheme.family || root.scheme.schemeName || "");
    }

    function variantLabel() {
        return root.formattedName(root.scheme.variant || "");
    }

    function foregroundColor() {
        return root.scheme.fg || Root.Theme.fg;
    }

    function previewSurfaceColor() {
        return root.scheme.bg1 || root.scheme.bg || Root.Theme.bg1;
    }

    function swatchColors() {
        let colors = [];
        let keys = ["accent", "red", "orange", "yellow", "green", "blue", "purple", "cyan"];

        for (let i = 0; i < keys.length; i++) {
            let color = root.scheme[keys[i]];
            if (!color || colors.indexOf(color) >= 0)
                continue;
            colors.push(color);
        }

        if (!colors.length && Array.isArray(root.scheme.palette)) {
            for (let index = 1; index < root.scheme.palette.length && colors.length < 8; index++) {
                let paletteColor = root.scheme.palette[index];
                if (!paletteColor || colors.indexOf(paletteColor) >= 0)
                    continue;
                colors.push(paletteColor);
            }
        }

        if (!colors.length)
            return [
                Root.Theme.accent,
                Root.Theme.red,
                Root.Theme.orange,
                Root.Theme.yellow,
                Root.Theme.green,
                Root.Theme.blue,
                Root.Theme.purple,
                Root.Theme.aqua
            ];

        return colors.slice(0, 8);
    }

    StyledRect {
        anchors.fill: parent
        radius: Root.Theme.btnRadius + 4
        color: root.scheme.bg || Root.Theme.bg1
        border.width: root.active ? 2 : 1
        border.color: root.active
            ? root.accentColor
            : (cardArea.containsMouse ? root.secondaryForegroundColor : Root.Theme.bg3)
        scale: cardArea.pressed ? 0.985 : 1.0
        transformOrigin: Item.Center

        Behavior on border.color {
            StdCAnim { duration: Root.Theme.animSpring }
        }

        Behavior on scale {
            StdAnim { duration: Root.Theme.animMicro }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0

                    StyledText {
                        text: root.familyLabel()
                        color: root.foregroundColor()
                        font.family: Root.Theme.fontFamily
                        font.pixelSize: Root.Theme.fontSize
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: root.variantLabel()
                        color: root.secondaryForegroundColor
                        opacity: 0.82
                        font.family: Root.Theme.fontFamily
                        font.pixelSize: Root.Theme.fontSizeSmall
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                Icon {
                    visible: root.active
                    source: "../icons/circle-check-filled.svg"
                    color: root.accentColor
                    iconSize: Math.max(Root.Theme.iconSize * 0.95, 16)
                    Layout.alignment: Qt.AlignTop
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: Root.Theme.btnRadius
                color: root.previewSurfaceColor()
                border.width: 1
                border.color: root.previewBorderColor

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Repeater {
                        model: root.swatchColors()

                        delegate: StyledRect {
                            required property var modelData

                            width: 11
                            height: 11
                            radius: 5.5
                            color: modelData
                            border.width: 1
                            border.color: root.swatchBorderColor
                        }
                    }
                }
            }
        }

        HoverLayer {
            id: cardArea
            disabled: !root.interactive
            flat: true
            onClicked: root.clicked()
        }
    }
}
