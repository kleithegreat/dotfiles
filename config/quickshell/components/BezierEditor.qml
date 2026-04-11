import QtQuick
import QtQuick.Layouts
import ".." as Root

ColumnLayout {
    id: root

    property string currentCurveName: ""
    property var basePoints: null
    property bool showSaveInput: false
    property string saveInputText: ""

    readonly property bool isModified: {
        if (!basePoints) return false;
        let c = canvas;
        return Math.abs(c.x1 - basePoints[0]) > 0.001
            || Math.abs(c.y1 - basePoints[1]) > 0.001
            || Math.abs(c.x2 - basePoints[2]) > 0.001
            || Math.abs(c.y2 - basePoints[3]) > 0.001;
    }

    readonly property bool isCustom: Root.HyprlandConfigService.isUserCurve(currentCurveName)

    signal curveChanged(real x1, real y1, real x2, real y2)
    signal curveSaved(string name)
    signal curveDeleted(string name)

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
        curveSaved(name);
    }

    function doDelete() {
        let name = currentCurveName;
        Root.HyprlandConfigService.deleteUserCurve(name);
        curveDeleted(name);
        let allNames = Root.HyprlandConfigService.getAllCurveNames();
        selectCurve(allNames.length > 0 ? allNames[0] : "ease");
    }

    // ── Preset dropdown ──
    InlineDropdown {
        Layout.fillWidth: true
        model: Root.HyprlandConfigService.getAllCurveNames()
        currentValue: root.currentCurveName
        textForValue: (v) => {
            return Root.HyprlandConfigService.isUserCurve(v) ? "\u2605 " + v : v;
        }
        onActivated: (value) => root.selectCurve(value)
    }

    // ── Canvas ──
    BezierCanvas {
        id: canvas
        Layout.fillWidth: true
        Layout.preferredHeight: width
        Layout.maximumHeight: 240

        onPointsChanged: (nx1, ny1, nx2, ny2) => {
            preview.x1 = nx1; preview.y1 = ny1;
            preview.x2 = nx2; preview.y2 = ny2;
            root.curveChanged(nx1, ny1, nx2, ny2);
        }
    }

    // ── Preview ──
    AnimPreviewDot {
        id: preview
        Layout.fillWidth: true
        Layout.preferredHeight: 32
    }

    // ── Values display ──
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

    // ── Save input (inline, shown when Save As clicked) ──
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
                font.family: Root.Theme.systemFamily
                font.pixelSize: Root.Theme.fontSizeSmall
                clip: true
                onAccepted: {
                    if (text.trim() !== "")
                        root.doSave(text.trim());
                }
            }
        }

        Rectangle {
            width: 56; height: Root.Theme.btnHeight
            radius: Root.Theme.btnRadius
            color: saveConfirmArea.containsMouse ? Root.Theme.accent : Root.Theme.bg2
            border.width: 1; border.color: Root.Theme.bg3
            Behavior on color { CAnim { duration: Root.Theme.animHover } }

            Text {
                anchors.centerIn: parent; text: "Save"
                color: saveConfirmArea.containsMouse ? Root.Theme.bg : Root.Theme.fg
                font.family: Root.Theme.systemFamily; font.pixelSize: Root.Theme.fontSizeSmall
            }

            HoverLayer {
                id: saveConfirmArea
                hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                onClicked: {
                    let name = saveNameInput.text.trim();
                    if (name !== "") root.doSave(name);
                }
            }
        }

        Rectangle {
            width: Root.Theme.btnHeight; height: Root.Theme.btnHeight
            radius: Root.Theme.btnRadius
            color: saveCancelArea.containsMouse ? Root.Theme.bg2 : Root.Theme.bg1
            border.width: 1; border.color: Root.Theme.bg3
            Behavior on color { CAnim { duration: Root.Theme.animHover } }

            Text {
                anchors.centerIn: parent; text: "\u00d7"
                color: Root.Theme.fg; font.pixelSize: Root.Theme.fontSize
            }

            HoverLayer {
                id: saveCancelArea
                hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                onClicked: root.showSaveInput = false
            }
        }
    }

    // ── Action buttons ──
    RowLayout {
        Layout.fillWidth: true
        visible: !root.showSaveInput
        spacing: 4

        // Revert
        Rectangle {
            visible: root.isModified
            Layout.preferredWidth: revertText.implicitWidth + Root.Theme.btnPaddingH * 2
            height: Root.Theme.btnHeight; radius: Root.Theme.btnRadius
            color: revertArea.containsMouse ? Root.Theme.bg2 : Root.Theme.bg1
            border.width: 1; border.color: Root.Theme.bg3
            Behavior on color { CAnim { duration: Root.Theme.animHover } }
            Text { id: revertText; anchors.centerIn: parent; text: "Revert"; color: Root.Theme.fg; font.family: Root.Theme.systemFamily; font.pixelSize: Root.Theme.fontSizeSmall }
            HoverLayer { id: revertArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.revert() }
        }

        // Save (update existing custom curve)
        Rectangle {
            visible: root.isModified && root.isCustom
            Layout.preferredWidth: saveText.implicitWidth + Root.Theme.btnPaddingH * 2
            height: Root.Theme.btnHeight; radius: Root.Theme.btnRadius
            color: saveArea.containsMouse ? Root.Theme.accent : Root.Theme.bg2
            border.width: 1; border.color: Root.Theme.bg3
            Behavior on color { CAnim { duration: Root.Theme.animHover } }
            Text { id: saveText; anchors.centerIn: parent; text: "Save"; color: saveArea.containsMouse ? Root.Theme.bg : Root.Theme.fg; font.family: Root.Theme.systemFamily; font.pixelSize: Root.Theme.fontSizeSmall }
            HoverLayer { id: saveArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.doSave(root.currentCurveName) }
        }

        // Save As
        Rectangle {
            visible: root.isModified
            Layout.preferredWidth: saveAsText.implicitWidth + Root.Theme.btnPaddingH * 2
            height: Root.Theme.btnHeight; radius: Root.Theme.btnRadius
            color: saveAsArea.containsMouse ? Root.Theme.accent : Root.Theme.bg2
            border.width: 1; border.color: Root.Theme.bg3
            Behavior on color { CAnim { duration: Root.Theme.animHover } }
            Text { id: saveAsText; anchors.centerIn: parent; text: "Save as\u2026"; color: saveAsArea.containsMouse ? Root.Theme.bg : Root.Theme.fg; font.family: Root.Theme.systemFamily; font.pixelSize: Root.Theme.fontSizeSmall }
            HoverLayer {
                id: saveAsArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                onClicked: {
                    root.showSaveInput = true;
                    saveNameInput.text = Root.HyprlandConfigService.nextCustomName();
                    saveNameInput.forceActiveFocus();
                    saveNameInput.selectAll();
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Delete
        Rectangle {
            visible: root.isCustom && !root.isModified
            Layout.preferredWidth: deleteText.implicitWidth + Root.Theme.btnPaddingH * 2
            height: Root.Theme.btnHeight; radius: Root.Theme.btnRadius
            color: deleteArea.containsMouse ? Root.Theme.red : Root.Theme.bg1
            border.width: 1; border.color: Root.Theme.bg3
            Behavior on color { CAnim { duration: Root.Theme.animHover } }
            Text { id: deleteText; anchors.centerIn: parent; text: "Delete"; color: deleteArea.containsMouse ? Root.Theme.fg : Root.Theme.red; font.family: Root.Theme.systemFamily; font.pixelSize: Root.Theme.fontSizeSmall }
            HoverLayer { id: deleteArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.doDelete() }
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
