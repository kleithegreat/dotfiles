import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var presets
    required property var themeState
    required property var colorFamilies
    required property var monoFontSizeOffsetTargets
    required property bool presetCommandRunning
    required property string presetCommandAction
    required property string presetCommandTargetName
    required property string presetCommandError
    required property int presetMutationToken

    signal presetActivated(string name)
    signal presetSaveRequested(string name, var presetData)
    signal presetDeleteRequested(string name)

    property bool editorOpen: false
    property string editorMode: "create"
    property string editorName: ""
    property var editorPreset: ({})
    property int editorRevision: 0
    property string pendingDeleteName: ""
    property int handledMutationToken: presetMutationToken

    function familyDisplayName(name) {
        if (name === "tokyonight")
            return "Tokyo Night";
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function cloneMap(source) {
        let next = {};
        let keys = Object.keys(source || {});

        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = source[keys[i]];

        return next;
    }

    function presetSummary(preset) {
        let lines = [];
        let keys = Object.keys(preset || {});

        for (let i = 0; i < keys.length; i++) {
            if (keys[i] !== "name")
                lines.push(keys[i].replace(/_/g, " ") + ":  " + preset[keys[i]]);
        }

        return lines.join("\n");
    }

    function editorPresetFor(preset) {
        let next = root.cloneMap(preset || {});
        delete next.name;
        return next;
    }

    function closeEditor() {
        root.editorOpen = false;
        root.editorMode = "create";
        root.editorName = "";
        root.editorPreset = ({});
    }

    function openCreateEditor() {
        root.pendingDeleteName = "";
        root.editorMode = "create";
        root.editorName = "";
        root.editorPreset = ({});
        root.editorRevision += 1;
        root.editorOpen = true;
    }

    function openEditEditor(preset) {
        root.pendingDeleteName = "";
        root.editorMode = "edit";
        root.editorName = preset.name || "";
        root.editorPreset = root.editorPresetFor(preset);
        root.editorRevision += 1;
        root.editorOpen = true;
    }

    onPresetMutationTokenChanged: {
        if (presetMutationToken === handledMutationToken)
            return;

        handledMutationToken = presetMutationToken;
        pendingDeleteName = "";
        closeEditor();
    }

    anchors.fill: parent
    contentHeight: presetsCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: presetsCol
        width: parent.width
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                Text {
                    text: "PRESETS"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Text {
                    text: "Click a preset card to apply it. Edit and delete are inline."
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Rectangle {
                width: createLabel.implicitWidth + 20
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: createArea.containsMouse ? Theme.greenBright : Theme.accent
                border.width: 1
                border.color: Theme.accent
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                scale: createArea.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                transformOrigin: Item.Center

                Text {
                    id: createLabel
                    anchors.centerIn: parent
                    text: "Save Current State"
                    color: Theme.bg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                MouseArea {
                    id: createArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.openCreateEditor()
                }
            }
        }

        Text {
            visible: !root.editorOpen
            text: "Create presets as deltas: include only the fields you want to override."
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        SettingsPresetEditor {
            visible: root.editorOpen
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            mode: root.editorMode
            initialName: root.editorName
            initialPreset: root.editorPreset
            revision: root.editorRevision
            themeState: root.themeState
            colorFamilies: root.colorFamilies
            monoFontSizeOffsetTargets: root.monoFontSizeOffsetTargets
            busy: root.presetCommandRunning
            busyAction: root.presetCommandAction
            busyTargetName: root.presetCommandTargetName
            errorMessage: root.presetCommandError
            onSaveRequested: (name, presetData) => root.presetSaveRequested(name, presetData)
            onCancelRequested: root.closeEditor()
        }

        Text {
            visible: !root.editorOpen && root.presetCommandError !== ""
            text: root.presetCommandError
            color: Theme.redBright
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.presets.length

            delegate: Rectangle {
                id: presetCard
                required property int index
                property var preset: root.presets[index] || ({})
                property string presetName: preset.name || ""

                Layout.fillWidth: true
                Layout.preferredHeight: presetContent.implicitHeight + 24
                radius: Theme.btnRadius + 2
                color: presetCardArea.containsMouse ? Theme.bg2 : Theme.bg1
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                border.width: 1
                border.color: presetCardArea.containsMouse ? Theme.accent : Theme.bg3
                Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
                scale: presetCardArea.pressed ? 0.98 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                transformOrigin: Item.Center

                MouseArea {
                    id: presetCardArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.presetActivated(presetCard.presetName)
                }

                ColumnLayout {
                    id: presetContent
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            spacing: 2
                            Layout.fillWidth: true

                            Text {
                                text: root.familyDisplayName(presetCard.presetName)
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                text: "Click to apply"
                                color: Theme.fg4
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        Rectangle {
                            width: editLabel.implicitWidth + 18
                            height: Theme.btnHeight
                            radius: Theme.btnRadius
                            color: editArea.containsMouse ? Theme.bg3 : Theme.bg
                            border.width: 1
                            border.color: Theme.bg3
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            scale: editArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Text {
                                id: editLabel
                                anchors.centerIn: parent
                                text: "Edit"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            MouseArea {
                                id: editArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: root.openEditEditor(presetCard.preset)
                            }
                        }

                        Rectangle {
                            width: deleteLabel.implicitWidth + 18
                            height: Theme.btnHeight
                            radius: Theme.btnRadius
                            color: {
                                if (root.presetCommandRunning && root.presetCommandAction === "delete" && root.presetCommandTargetName === presetCard.presetName)
                                    return Theme.redBright;
                                if (root.pendingDeleteName === presetCard.presetName)
                                    return Theme.redBright;
                                return deleteArea.containsMouse ? Theme.bg2 : Theme.bg;
                            }
                            border.width: 1
                            border.color: root.pendingDeleteName === presetCard.presetName ? Theme.redBright : Theme.bg3
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
                            scale: deleteArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Text {
                                id: deleteLabel
                                anchors.centerIn: parent
                                text: {
                                    if (root.presetCommandRunning && root.presetCommandAction === "delete" && root.presetCommandTargetName === presetCard.presetName)
                                        return "Deleting...";
                                    return root.pendingDeleteName === presetCard.presetName ? "Confirm" : "Delete";
                                }
                                color: root.pendingDeleteName === presetCard.presetName ? Theme.bg : Theme.fg4
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: root.pendingDeleteName === presetCard.presetName
                            }

                            MouseArea {
                                id: deleteArea
                                anchors.fill: parent
                                enabled: !root.presetCommandRunning
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                hoverEnabled: true
                                onClicked: {
                                    if (root.pendingDeleteName === presetCard.presetName)
                                        root.presetDeleteRequested(presetCard.presetName);
                                    else
                                        root.pendingDeleteName = presetCard.presetName;
                                }
                            }
                        }
                    }

                    Text {
                        text: root.presetSummary(presetCard.preset)
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        lineHeight: 1.4
                    }
                }
            }
        }
    }
}
