import QtQuick
import QtQuick.Layouts
import ".." as Root

ColumnLayout {
    id: root

    property string currentCurveName: ""
    property var basePoints: null
    property bool showSaveInput: false

    readonly property bool isModified: {
        if (!basePoints) return false;
        let c = canvas;
        return Math.abs(c.x1 - basePoints[0]) > 0.001
            || Math.abs(c.y1 - basePoints[1]) > 0.001
            || Math.abs(c.x2 - basePoints[2]) > 0.001
            || Math.abs(c.y2 - basePoints[3]) > 0.001;
    }

    readonly property bool isCustom: Root.HyprlandConfigService.isUserCurve(currentCurveName)

    spacing: 10

    function selectCurve(name) {
        let pts = Root.HyprlandConfigService.getCurvePoints(name);
        if (!pts) return;
        currentCurveName = name;
        basePoints = [pts[0], pts[1], pts[2], pts[3]];
        canvas.setPoints(pts[0], pts[1], pts[2], pts[3]);
        preview.x1 = pts[0]; preview.y1 = pts[1];
        preview.x2 = pts[2]; preview.y2 = pts[3];
        showSaveInput = false;
    }

    function revert() {
        if (!basePoints) return;
        canvas.setPoints(basePoints[0], basePoints[1], basePoints[2], basePoints[3]);
        preview.x1 = basePoints[0]; preview.y1 = basePoints[1];
        preview.x2 = basePoints[2]; preview.y2 = basePoints[3];
    }

    function doSave(name) {
        let pts = [canvas.x1, canvas.y1, canvas.x2, canvas.y2];
        Root.HyprlandConfigService.saveUserCurve(name, pts);
        currentCurveName = name;
        basePoints = pts.slice();
        showSaveInput = false;
    }

    function doDelete() {
        Root.HyprlandConfigService.deleteUserCurve(currentCurveName);
        let allNames = Root.HyprlandConfigService.getAllCurveNames();
        selectCurve(allNames.length > 0 ? allNames[0] : "ease");
    }

    InlineDropdown {
        Layout.fillWidth: true
        model: Root.HyprlandConfigService.getAllCurveNames()
        currentValue: root.currentCurveName
        textForValue: (v) => {
            return Root.HyprlandConfigService.isUserCurve(v) ? "\u2605 " + v : v;
        }
        onActivated: (value) => root.selectCurve(value)
    }

    BezierCanvas {
        id: canvas
        Layout.fillWidth: true
        Layout.preferredHeight: width
        Layout.maximumHeight: 240

        onPointsChanged: (nx1, ny1, nx2, ny2) => {
            preview.x1 = nx1; preview.y1 = ny1;
            preview.x2 = nx2; preview.y2 = ny2;
        }
    }

    AnimPreviewDot {
        id: preview
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Text {
            text: "P1: " + canvas.x1.toFixed(2) + ", " + canvas.y1.toFixed(2)
            color: Root.Theme.fg3
            font.family: Root.Theme.fontFamily
            font.pixelSize: Root.Theme.fontSizeSmall
            Layout.fillWidth: true
        }

        Text {
            text: "P2: " + canvas.x2.toFixed(2) + ", " + canvas.y2.toFixed(2)
            color: Root.Theme.fg3
            font.family: Root.Theme.fontFamily
            font.pixelSize: Root.Theme.fontSizeSmall
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.showSaveInput
        spacing: 4

        Rectangle {
            Layout.fillWidth: true
            height: Root.Theme.btnHeight
            radius: Root.Theme.btnRadius
            color: Root.Theme.bg1
            border.width: 1
            border.color: saveNameInput.activeFocus ? Root.Theme.accent : Root.Theme.bg3

            TextInput {
                id: saveNameInput
                anchors.fill: parent
                anchors.leftMargin: Root.Theme.listItemPadding
                anchors.rightMargin: Root.Theme.listItemPadding
                verticalAlignment: TextInput.AlignVCenter
                color: Root.Theme.fg
                font.family: Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeSmall
                clip: true
                onAccepted: {
                    if (text.trim() !== "")
                        root.doSave(text.trim());
                }
            }
        }

        ActionButton {
            fixedWidth: 56
            text: "Save"
            baseColor: Root.Theme.bg2
            hoverColor: Root.Theme.accent
            hoverTextColor: Root.Theme.bg
            onClicked: {
                let name = saveNameInput.text.trim();
                if (name !== "") root.doSave(name);
            }
        }

        ActionButton {
            fixedWidth: Root.Theme.btnHeight
            text: "\u00d7"
            fontPixelSize: Root.Theme.fontSize
            onClicked: root.showSaveInput = false
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !root.showSaveInput
        spacing: 4

        ActionButton {
            visible: root.isModified
            text: "Revert"
            onClicked: root.revert()
        }

        ActionButton {
            visible: root.isModified && root.isCustom
            text: "Save"
            baseColor: Root.Theme.bg2
            hoverColor: Root.Theme.accent
            hoverTextColor: Root.Theme.bg
            onClicked: root.doSave(root.currentCurveName)
        }

        ActionButton {
            visible: root.isModified
            text: "Save as\u2026"
            baseColor: Root.Theme.bg2
            hoverColor: Root.Theme.accent
            hoverTextColor: Root.Theme.bg
            onClicked: {
                root.showSaveInput = true;
                saveNameInput.text = Root.HyprlandConfigService.nextCustomName();
                saveNameInput.forceActiveFocus();
                saveNameInput.selectAll();
            }
        }

        Item { Layout.fillWidth: true }

        ActionButton {
            visible: root.isCustom && !root.isModified
            text: "Delete"
            hoverColor: Root.Theme.red
            textColor: Root.Theme.red
            hoverTextColor: Root.Theme.fg
            onClicked: root.doDelete()
        }
    }

    Component.onCompleted: {
        let names = Root.HyprlandConfigService.getAllCurveNames();
        if (names.length > 0)
            selectCurve(names[0]);
        else
            selectCurve("ease");
    }
}
