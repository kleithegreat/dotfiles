import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../components" as Components

Item {
    id: root
    anchors.fill: parent

    // ── Required properties for Options tab (kept from existing) ──
    required property string hyprRuntimeError
    required property var hyprOptionInfo
    required property var hyprGeneralOptions
    required property var hyprDecorationOptions
    required property var hyprBlurOptions
    required property var hyprDraftState
    required property var themeState

    signal hyprOptionToggled(string option)
    signal hyprOptionAdjusted(string option, int direction)

    // ── Hub state ──
    property string activeTab: "options"
    property var expandedAnimations: ({})

    // ── Keybind state ──
    property string keybindSearch: ""
    property bool _keybindsLoaded: false
    property int editingBindIndex: -1
    property bool captureActive: false
    property var capturedMods: []
    property string capturedKey: ""
    property string _capturePreview: ""

    readonly property var _bindCategoryOrder: [
        { id: "apps", label: "APPLICATIONS" },
        { id: "window_mgmt", label: "WINDOW MANAGEMENT" },
        { id: "workspace_nav", label: "WORKSPACES" },
        { id: "window_focus", label: "FOCUS & MOVE" },
        { id: "session", label: "SESSION" },
        { id: "other", label: "OTHER" }
    ]

    readonly property var _dispatcherCategoryMap: ({
        "exec": "apps", "execr": "apps",
        "killactive": "window_mgmt", "forcekillactive": "window_mgmt",
        "togglefloating": "window_mgmt", "fullscreen": "window_mgmt",
        "pin": "window_mgmt", "centerwindow": "window_mgmt",
        "pseudo": "window_mgmt", "layoutmsg": "window_mgmt",
        "workspace": "workspace_nav", "movetoworkspace": "workspace_nav",
        "movetoworkspacesilent": "workspace_nav", "togglespecialworkspace": "workspace_nav",
        "movefocus": "window_focus", "movewindow": "window_focus",
        "swapwindow": "window_focus", "movewindoworgroup": "window_focus",
        "resizeactive": "window_focus", "cyclenext": "window_focus",
        "swapnext": "window_focus", "focuscurrentorlast": "window_focus",
        "focusurgentorlast": "window_focus",
        "exit": "session", "pass": "session", "global": "session", "submap": "session"
    })

    readonly property var _categorizedBinds: {
        let all = HyprlandConfigService.keybinds;
        let filter = root.keybindSearch.toLowerCase();
        let result = {};
        for (let i = 0; i < all.length; i++) {
            let b = all[i];
            let cat = root._dispatcherCategoryMap[b.dispatcher] || "other";
            if (filter) {
                let combo = root.formatBindCombo(b).toLowerCase();
                let desc = (b.description || "").toLowerCase();
                let disp = b.dispatcher.toLowerCase();
                let arg = (b.arg || "").toLowerCase();
                if (combo.indexOf(filter) < 0 && desc.indexOf(filter) < 0
                        && disp.indexOf(filter) < 0 && arg.indexOf(filter) < 0)
                    continue;
            }
            if (!result[cat]) result[cat] = [];
            result[cat].push({ index: i, bind: b });
        }
        return result;
    }

    function modmaskToNames(mask) {
        let mods = [];
        if (mask & 64) mods.push("SUPER");
        if (mask & 4) mods.push("CTRL");
        if (mask & 8) mods.push("ALT");
        if (mask & 1) mods.push("SHIFT");
        return mods;
    }

    function formatBindCombo(bind) {
        let parts = modmaskToNames(bind.modmask);
        parts.push(bind.key);
        return parts.join(" + ");
    }

    function formatCapturedCombo() {
        let parts = capturedMods.slice();
        parts.push(capturedKey);
        return parts.join(" + ");
    }

    function startEditBind(index) {
        editingBindIndex = index;
        capturedMods = [];
        capturedKey = "";
        _capturePreview = "";
        captureActive = false;
    }

    function cancelBindEdit() {
        if (captureActive) stopCapture();
        editingBindIndex = -1;
    }

    function applyBindEdit() {
        if (capturedKey === "" || editingBindIndex < 0) return;
        HyprlandConfigService.applyBindOverride(editingBindIndex, capturedMods, capturedKey);
        editingBindIndex = -1;
    }

    function startCapture() {
        captureActive = true;
        _capturePreview = "";
        _captureTimer.restart();
        _submapSetupProc.command = ["hyprctl", "--batch",
            "keyword submap hyprmod_capture ; keyword bind , catchall, pass, ; keyword submap reset"];
        _submapSetupProc.running = true;
    }

    function stopCapture() {
        captureActive = false;
        _capturePreview = "";
        _captureTimer.stop();
        _submapResetProc.running = true;
    }

    property Timer _captureTimer: Timer {
        interval: 10000
        onTriggered: {
            if (root.captureActive) root.stopCapture();
        }
    }

    function isModifierKey(key) {
        return key === Qt.Key_Shift || key === Qt.Key_Control
            || key === Qt.Key_Alt || key === Qt.Key_Meta
            || key === Qt.Key_Super_L || key === Qt.Key_Super_R;
    }

    function qtModsToNames(mods) {
        let result = [];
        if (mods & Qt.MetaModifier) result.push("SUPER");
        if (mods & Qt.ControlModifier) result.push("CTRL");
        if (mods & Qt.AltModifier) result.push("ALT");
        if (mods & Qt.ShiftModifier) result.push("SHIFT");
        return result;
    }

    function qtKeyToHyprland(event) {
        let k = event.key;
        if (k === Qt.Key_Left) return "left";
        if (k === Qt.Key_Right) return "right";
        if (k === Qt.Key_Up) return "up";
        if (k === Qt.Key_Down) return "down";
        if (k === Qt.Key_Return || k === Qt.Key_Enter) return "Return";
        if (k === Qt.Key_Space) return "space";
        if (k === Qt.Key_Tab) return "Tab";
        if (k === Qt.Key_Backspace) return "BackSpace";
        if (k === Qt.Key_Delete) return "Delete";
        if (k === Qt.Key_Home) return "Home";
        if (k === Qt.Key_End) return "End";
        if (k === Qt.Key_PageUp) return "Prior";
        if (k === Qt.Key_PageDown) return "Next";
        if (k === Qt.Key_Insert) return "Insert";
        if (k === Qt.Key_Print) return "Print";
        if (k === Qt.Key_Pause) return "Pause";
        if (k === Qt.Key_QuoteLeft) return "grave";
        if (k === Qt.Key_Minus) return "minus";
        if (k === Qt.Key_Equal) return "equal";
        if (k === Qt.Key_BracketLeft) return "bracketleft";
        if (k === Qt.Key_BracketRight) return "bracketright";
        if (k === Qt.Key_Backslash) return "backslash";
        if (k === Qt.Key_Semicolon) return "semicolon";
        if (k === Qt.Key_Apostrophe) return "apostrophe";
        if (k === Qt.Key_Comma) return "comma";
        if (k === Qt.Key_Period) return "period";
        if (k === Qt.Key_Slash) return "slash";
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35)
            return "F" + (k - Qt.Key_F1 + 1);
        if (event.text.length === 1) {
            let c = event.text.charCodeAt(0);
            if ((c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a))
                return String.fromCharCode(c).toUpperCase();
            if (c >= 0x30 && c <= 0x39) return event.text;
        }
        return "";
    }

    property Process _submapSetupProc: Process {
        running: false
        stdout: SplitParser { onRead: (_) => {} }
        onExited: (code) => { if (code === 0) root._submapEnterProc.running = true; }
    }
    property Process _submapEnterProc: Process {
        command: ["hyprctl", "dispatch", "submap", "hyprmod_capture"]
        running: false
        stdout: SplitParser { onRead: (_) => {} }
        onExited: (code) => { if (code === 0 && root.captureActive) captureBox.forceActiveFocus(); }
    }
    property Process _submapResetProc: Process {
        command: ["hyprctl", "dispatch", "submap", "reset"]
        running: false
        stdout: SplitParser { onRead: (_) => {} }
    }

    Component.onDestruction: {
        if (captureActive || _submapEnterProc.running) {
            _captureTimer.stop();
            _submapResetProc.running = true;
        }
    }

    // ── Shared helpers ──
    function hyprOptionMeta(option) { return root.hyprOptionInfo[option] || ({}); }
    function hyprStateKey(option) { return root.hyprOptionMeta(option).stateKey || ""; }
    function hyprThemeStateValue(stateKey, fallback) { let v = root.themeState[stateKey]; return v === undefined || v === null ? fallback : v; }
    function hyprStateValue(stateKey, fallback) { let v = root.hyprDraftState[stateKey]; if (v !== undefined && v !== null) return v; return root.hyprThemeStateValue(stateKey, fallback); }
    function hyprIntValue(option) { let m = root.hyprOptionMeta(option); let v = root.hyprStateValue(root.hyprStateKey(option), m.fallback); let p = parseInt(v, 10); return isNaN(p) ? (m.fallback === undefined ? 0 : m.fallback) : p; }
    function hyprBoolValue(option) { let m = root.hyprOptionMeta(option); let v = root.hyprStateValue(root.hyprStateKey(option), m.fallback); return v === undefined ? !!m.fallback : !!v; }

    function toggleAnimExpanded(name) {
        let next = JSON.parse(JSON.stringify(expandedAnimations));
        next[name] = !next[name];
        expandedAnimations = next;
    }

    function isAnimVisible(name) {
        let info = HyprlandConfigService.getAnimInfo(name);
        if (!info) return false;
        let parent = info.parent;
        while (parent !== "") {
            let parentInfo = HyprlandConfigService.getAnimInfo(parent);
            if (!parentInfo || parentInfo.category !== info.category) break;
            if (!expandedAnimations[parent]) return false;
            parent = parentInfo.parent;
        }
        return true;
    }

    function animIndent(name) {
        let info = HyprlandConfigService.getAnimInfo(name);
        if (!info) return 0;
        let catAnims = HyprlandConfigService.animsForCategory(info.category);
        let minDepth = 99;
        for (let i = 0; i < catAnims.length; i++)
            minDepth = Math.min(minDepth, catAnims[i].depth);
        return (info.depth - minDepth) * 14;
    }

    function hasExpandableKids(name, category) {
        if (!HyprlandConfigService.hasChildren(name)) return false;
        let children = HyprlandConfigService._animChildren[name] || [];
        for (let i = 0; i < children.length; i++) {
            let ci = HyprlandConfigService.getAnimInfo(children[i]);
            if (ci && ci.category === category) return true;
        }
        return false;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 10
            spacing: 8
            Components.Icon { source: "../../icons/layout.svg"; color: Theme.fg }
            Text { text: "Hyprland"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }

            // Undo / Redo
            Rectangle {
                visible: HyprlandConfigService.canUndo
                width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                color: undoArea.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1; border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover } }
                Text { anchors.centerIn: parent; text: "\u21b6"; color: Theme.fg; font.pixelSize: Theme.fontSize }
                Components.HoverLayer { id: undoArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: HyprlandConfigService.undo() }
            }
            Rectangle {
                visible: HyprlandConfigService.canRedo
                width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                color: redoArea.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1; border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover } }
                Text { anchors.centerIn: parent; text: "\u21b7"; color: Theme.fg; font.pixelSize: Theme.fontSize }
                Components.HoverLayer { id: redoArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: HyprlandConfigService.redo() }
            }
        }

        // ── Tab bar ──
        Row {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 4

            Repeater {
                model: [
                    { key: "options", label: "Options" },
                    { key: "animations", label: "Animations" },
                    { key: "beziers", label: "Beziers" },
                    { key: "keybinds", label: "Keybinds" }
                ]

                delegate: Rectangle {
                    required property var modelData
                    property bool isActive: root.activeTab === modelData.key

                    width: tabLabel.implicitWidth + Theme.btnPaddingH * 2
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: isActive ? Theme.accent : (tabArea.containsMouse ? Theme.bg2 : Theme.bg1)
                    border.width: 1
                    border.color: isActive ? Theme.accent : Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: isActive ? Theme.bg : Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Behavior on color { Components.CAnim { duration: Theme.animHover } }
                    }

                    Components.HoverLayer {
                        id: tabArea
                        hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                        onClicked: root.activeTab = modelData.key
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        // ── Content area ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8

            // ═══════════════════════════════════════════
            //  OPTIONS TAB
            // ═══════════════════════════════════════════
            Components.WheelFlickable {
                anchors.fill: parent
                visible: root.activeTab === "options"
                contentHeight: optionsCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: optionsCol
                    width: parent.width
                    spacing: 16

                    Text {
                        visible: root.hyprRuntimeError !== ""
                        text: root.hyprRuntimeError
                        color: Theme.redBright
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }

                    // GENERAL
                    Text { text: "GENERAL"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                    Repeater {
                        model: root.hyprGeneralOptions
                        delegate: RowLayout {
                            required property string modelData
                            property var meta: root.hyprOptionMeta(modelData)
                            Layout.fillWidth: true; spacing: 8
                            Text { text: meta.label; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                            Rectangle {
                                property bool canDec: meta.minimum === undefined || root.hyprIntValue(modelData) > meta.minimum
                                Layout.preferredWidth: 28; Layout.preferredHeight: Theme.btnHeight; radius: Theme.btnRadius
                                color: decArea.containsMouse && canDec ? Theme.bg2 : Theme.bg1; opacity: canDec ? 1 : 0.45
                                border.width: 1; border.color: Theme.bg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Text { anchors.centerIn: parent; text: "\u2212"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                                Components.HoverLayer { id: decArea; enabled: parent.canDec; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.hyprOptionAdjusted(modelData, -1) }
                            }
                            Text { text: String(root.hyprIntValue(modelData)); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignHCenter }
                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: Theme.btnHeight; radius: Theme.btnRadius
                                color: incArea.containsMouse ? Theme.bg2 : Theme.bg1
                                border.width: 1; border.color: Theme.bg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                                Components.HoverLayer { id: incArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.hyprOptionAdjusted(modelData, 1) }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                    // DECORATION
                    Text { text: "DECORATION"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                    Repeater {
                        model: root.hyprDecorationOptions
                        delegate: RowLayout {
                            required property string modelData
                            property var meta: root.hyprOptionMeta(modelData)
                            Layout.fillWidth: true; spacing: 8
                            Text { text: meta.label; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                            Rectangle {
                                property bool canDec: meta.minimum === undefined || root.hyprIntValue(modelData) > meta.minimum
                                Layout.preferredWidth: 28; Layout.preferredHeight: Theme.btnHeight; radius: Theme.btnRadius
                                color: decDecArea.containsMouse && canDec ? Theme.bg2 : Theme.bg1; opacity: canDec ? 1 : 0.45
                                border.width: 1; border.color: Theme.bg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Text { anchors.centerIn: parent; text: "\u2212"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                                Components.HoverLayer { id: decDecArea; enabled: parent.canDec; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.hyprOptionAdjusted(modelData, -1) }
                            }
                            Text { text: String(root.hyprIntValue(modelData)); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignHCenter }
                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: Theme.btnHeight; radius: Theme.btnRadius
                                color: decIncArea.containsMouse ? Theme.bg2 : Theme.bg1
                                border.width: 1; border.color: Theme.bg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                                Components.HoverLayer { id: decIncArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.hyprOptionAdjusted(modelData, 1) }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                    // BLUR
                    Text { text: "BLUR"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: root.hyprOptionMeta("decoration:blur:enabled").label; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                        Text { text: root.hyprBoolValue("decoration:blur:enabled") ? "On" : "Off"; color: root.hyprBoolValue("decoration:blur:enabled") ? Theme.fg3 : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        Components.ToggleSwitch { checked: root.hyprBoolValue("decoration:blur:enabled"); onToggled: root.hyprOptionToggled("decoration:blur:enabled") }
                    }

                    Repeater {
                        model: root.hyprBlurOptions
                        delegate: RowLayout {
                            required property string modelData
                            property var meta: root.hyprOptionMeta(modelData)
                            Layout.fillWidth: true; spacing: 8
                            Text { text: meta.label; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                            Rectangle {
                                property bool canDec: meta.minimum === undefined || root.hyprIntValue(modelData) > meta.minimum
                                Layout.preferredWidth: 28; Layout.preferredHeight: Theme.btnHeight; radius: Theme.btnRadius
                                color: blurDecArea.containsMouse && canDec ? Theme.bg2 : Theme.bg1; opacity: canDec ? 1 : 0.45
                                border.width: 1; border.color: Theme.bg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Text { anchors.centerIn: parent; text: "\u2212"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                                Components.HoverLayer { id: blurDecArea; enabled: parent.canDec; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.hyprOptionAdjusted(modelData, -1) }
                            }
                            Text { text: String(root.hyprIntValue(modelData)); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignHCenter }
                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: Theme.btnHeight; radius: Theme.btnRadius
                                color: blurIncArea.containsMouse ? Theme.bg2 : Theme.bg1
                                border.width: 1; border.color: Theme.bg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                                Components.HoverLayer { id: blurIncArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root.hyprOptionAdjusted(modelData, 1) }
                            }
                        }
                    }

                    Text { text: "Blur size and passes must stay at 1 or above."; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; wrapMode: Text.WordWrap }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                    // ANIMATIONS master toggle
                    Text { text: "ANIMATIONS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: root.hyprOptionMeta("animations:enabled").label; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                        Text { text: root.hyprBoolValue("animations:enabled") ? "On" : "Off"; color: root.hyprBoolValue("animations:enabled") ? Theme.fg3 : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        Components.ToggleSwitch { checked: root.hyprBoolValue("animations:enabled"); onToggled: root.hyprOptionToggled("animations:enabled") }
                    }
                }
            }

            // ═══════════════════════════════════════════
            //  ANIMATIONS TAB
            // ═══════════════════════════════════════════
            Components.WheelFlickable {
                anchors.fill: parent
                visible: root.activeTab === "animations"
                contentHeight: animCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: animCol
                    width: parent.width
                    spacing: 6

                    Text {
                        visible: HyprlandConfigService.loading
                        text: "Loading animation state\u2026"
                        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    }

                    Text {
                        visible: HyprlandConfigService.error !== ""
                        text: HyprlandConfigService.error
                        color: Theme.redBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: HyprlandConfigService.categories

                        delegate: ColumnLayout {
                            id: catDelegate
                            required property string modelData
                            readonly property string categoryName: modelData
                            Layout.fillWidth: true
                            spacing: 2

                            // Category header
                            Text {
                                text: catDelegate.categoryName.toUpperCase()
                                color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                                Layout.topMargin: 10
                            }

                            // Animation rows
                            Repeater {
                                model: HyprlandConfigService.animsForCategory(catDelegate.categoryName)

                                delegate: Item {
                                    id: animRow
                                    required property var modelData
                                    readonly property string animName: modelData.name
                                    readonly property var animState: HyprlandConfigService.animations[animName] || null
                                    readonly property bool isOverridden: animState !== null && animState.overridden
                                    readonly property var effective: HyprlandConfigService.getEffective(animName)
                                    readonly property bool hasKids: root.hasExpandableKids(animName, modelData.category)
                                    readonly property bool rowVisible: root.isAnimVisible(animName)

                                    Layout.fillWidth: true
                                    visible: rowVisible
                                    implicitHeight: rowVisible ? animRowLayout.implicitHeight : 0
                                    clip: true

                                    RowLayout {
                                        id: animRowLayout
                                        width: parent.width
                                        spacing: 6

                                        // Indent
                                        Item { width: root.animIndent(animRow.animName); height: 1; visible: width > 0 }

                                        // Expand chevron
                                        Text {
                                            visible: animRow.hasKids
                                            text: root.expandedAnimations[animRow.animName] ? "\u25be" : "\u25b8"
                                            color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                            Layout.preferredWidth: visible ? 12 : 0

                                            MouseArea {
                                                anchors.fill: parent; anchors.margins: -4
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleAnimExpanded(animRow.animName)
                                            }
                                        }

                                        // Name
                                        Text {
                                            text: animRow.animName
                                            color: animRow.isOverridden ? Theme.fg : Theme.fg3
                                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: animRow.hasKids ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: { if (animRow.hasKids) root.toggleAnimExpanded(animRow.animName); }
                                            }
                                        }

                                        // ── Inherited state ──
                                        Text {
                                            visible: !animRow.isOverridden
                                            text: {
                                                let e = animRow.effective;
                                                let parts = [];
                                                if (e.speed > 0) parts.push(e.speed.toFixed(1));
                                                if (e.curve) parts.push(e.curve);
                                                return parts.length > 0 ? "inherited \u00b7 " + parts.join(" \u00b7 ") : "inherited";
                                            }
                                            color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.italic: true
                                        }

                                        // Override button
                                        Rectangle {
                                            visible: !animRow.isOverridden
                                            width: overrideLabel.implicitWidth + Theme.btnPaddingH * 2
                                            height: Theme.btnHeight; radius: Theme.btnRadius
                                            color: overrideArea.containsMouse ? Theme.bg2 : Theme.bg1
                                            border.width: 1; border.color: Theme.bg3
                                            Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                            Text { id: overrideLabel; anchors.centerIn: parent; text: "Override"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall }
                                            Components.HoverLayer { id: overrideArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: HyprlandConfigService.overrideAnimation(animRow.animName) }
                                        }

                                        // ── Overridden controls ──

                                        // Enabled toggle
                                        Components.ToggleSwitch {
                                            visible: animRow.isOverridden
                                            checked: animRow.effective.enabled
                                            onToggled: HyprlandConfigService.setAnimationField(animRow.animName, "enabled", !checked)
                                        }

                                        // Speed -
                                        Rectangle {
                                            visible: animRow.isOverridden
                                            width: 22; height: Theme.btnHeight; radius: Theme.btnRadius
                                            color: spdDecArea.containsMouse ? Theme.bg2 : Theme.bg1
                                            opacity: animRow.effective.speed > 0.5 ? 1 : 0.45
                                            border.width: 1; border.color: Theme.bg3
                                            Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                            Text { anchors.centerIn: parent; text: "\u2212"; color: Theme.fg; font.pixelSize: Theme.fontSizeSmall }
                                            Components.HoverLayer { id: spdDecArea; enabled: animRow.effective.speed > 0.5; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                                onClicked: { let s = Math.max(0.5, Math.round((animRow.effective.speed - 0.5) * 10) / 10); HyprlandConfigService.setAnimationField(animRow.animName, "speed", s); }
                                            }
                                        }

                                        // Speed value
                                        Text {
                                            visible: animRow.isOverridden
                                            text: animRow.effective.speed.toFixed(1)
                                            color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                            Layout.preferredWidth: 28; horizontalAlignment: Text.AlignHCenter
                                        }

                                        // Speed +
                                        Rectangle {
                                            visible: animRow.isOverridden
                                            width: 22; height: Theme.btnHeight; radius: Theme.btnRadius
                                            color: spdIncArea.containsMouse ? Theme.bg2 : Theme.bg1
                                            border.width: 1; border.color: Theme.bg3
                                            Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                            Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.pixelSize: Theme.fontSizeSmall }
                                            Components.HoverLayer { id: spdIncArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                                onClicked: { let s = Math.round((animRow.effective.speed + 0.5) * 10) / 10; HyprlandConfigService.setAnimationField(animRow.animName, "speed", s); }
                                            }
                                        }

                                        // Curve dropdown
                                        Components.InlineDropdown {
                                            visible: animRow.isOverridden
                                            Layout.preferredWidth: 100
                                            model: HyprlandConfigService.getAllCurveNames()
                                            currentValue: animRow.effective.curve || "default"
                                            onActivated: (value) => HyprlandConfigService.setAnimationField(animRow.animName, "curve", value)
                                        }

                                        // Style dropdown (only for animations with styles)
                                        Components.InlineDropdown {
                                            visible: animRow.isOverridden && animRow.modelData.styles.length > 0
                                            Layout.preferredWidth: 80
                                            model: {
                                                let opts = ["default"];
                                                let styles = animRow.modelData.styles;
                                                for (let i = 0; i < styles.length; i++) opts.push(styles[i]);
                                                return opts;
                                            }
                                            currentValue: {
                                                let s = animRow.effective.style || "";
                                                let base = s.split(" ")[0];
                                                return base || "default";
                                            }
                                            onActivated: (value) => HyprlandConfigService.setAnimationField(animRow.animName, "style", value === "default" ? "" : value)
                                        }

                                        // Reset button (revert to parent values)
                                        Rectangle {
                                            visible: animRow.isOverridden && animRow.animName !== "global"
                                            width: 22; height: Theme.btnHeight; radius: Theme.btnRadius
                                            color: resetArea.containsMouse ? Theme.bg2 : Theme.bg1
                                            border.width: 1; border.color: Theme.bg3
                                            Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                            Text { anchors.centerIn: parent; text: "\u00d7"; color: Theme.fg4; font.pixelSize: Theme.fontSizeSmall }
                                            Components.HoverLayer { id: resetArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: HyprlandConfigService.resetAnimation(animRow.animName) }
                                        }
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 4 }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════════
            //  BEZIERS TAB
            // ═══════════════════════════════════════════
            Components.WheelFlickable {
                anchors.fill: parent
                visible: root.activeTab === "beziers"
                contentHeight: bezierCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: bezierCol
                    width: parent.width
                    spacing: 12

                    Components.BezierEditor {
                        Layout.fillWidth: true
                    }
                }
            }

            // ═══════════════════════════════════════════
            //  KEYBINDS TAB
            // ═══════════════════════════════════════════
            Item {
                anchors.fill: parent
                visible: root.activeTab === "keybinds"

                onVisibleChanged: {
                    if (visible && !root._keybindsLoaded) {
                        root._keybindsLoaded = true;
                        HyprlandConfigService.fetchKeybinds();
                    }
                    if (!visible && root.captureActive)
                        root.stopCapture();
                }

                // ── Bind list ──
                Components.WheelFlickable {
                    anchors.fill: parent
                    visible: root.editingBindIndex < 0
                    contentHeight: keybindsCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: keybindsCol
                        width: parent.width
                        spacing: 6

                        // Search bar
                        Rectangle {
                            Layout.fillWidth: true
                            height: Theme.btnHeight
                            radius: Theme.btnRadius
                            color: Theme.bg1
                            border.width: 1
                            border.color: kbSearchInput.activeFocus ? Theme.accent : Theme.bg3
                            Behavior on border.color { Components.CAnim { duration: Theme.animHover } }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "/"
                                    color: Theme.fg4
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                TextInput {
                                    id: kbSearchInput
                                    width: parent.width - 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.fg
                                    selectionColor: Theme.accent
                                    selectedTextColor: Theme.bg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    clip: true
                                    onTextChanged: root.keybindSearch = text

                                    Text {
                                        visible: !parent.text && !parent.activeFocus
                                        text: "Filter keybinds\u2026"
                                        color: Theme.fg4
                                        font: parent.font
                                    }
                                }
                            }
                        }

                        Text {
                            visible: HyprlandConfigService.keybindsLoading
                            text: "Loading keybinds\u2026"
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        // Category groups
                        Repeater {
                            model: root._bindCategoryOrder

                            delegate: ColumnLayout {
                                id: catBindDelegate
                                required property var modelData
                                property var catBinds: root._categorizedBinds[modelData.id] || []
                                visible: catBinds.length > 0
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: catBindDelegate.modelData.label
                                    color: Theme.fg4
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                    Layout.topMargin: 10
                                }

                                Repeater {
                                    model: catBindDelegate.catBinds

                                    delegate: Rectangle {
                                        id: bindRowRect
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: bindRowLayout.implicitHeight + 8
                                        radius: Theme.btnRadius
                                        color: bindRowHover.containsMouse ? Theme.bg1 : "transparent"
                                        Behavior on color { Components.CAnim { duration: Theme.animHover } }

                                        RowLayout {
                                            id: bindRowLayout
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 4
                                            anchors.rightMargin: 4
                                            spacing: 4

                                            // Modifier pills
                                            Row {
                                                spacing: 3
                                                Repeater {
                                                    model: root.modmaskToNames(bindRowRect.modelData.bind.modmask)
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        width: modPillText.implicitWidth + 8
                                                        height: 20; radius: 3
                                                        color: Theme.accent
                                                        Text {
                                                            id: modPillText
                                                            anchors.centerIn: parent
                                                            text: modelData
                                                            color: Theme.bg
                                                            font.family: Theme.systemFamily
                                                            font.pixelSize: Theme.fontSizeSmall - 2
                                                            font.bold: true
                                                        }
                                                    }
                                                }
                                            }

                                            // Key pill
                                            Rectangle {
                                                width: keyPillText.implicitWidth + 10
                                                height: 20; radius: 3
                                                color: Theme.bg2
                                                border.width: 1; border.color: Theme.bg3
                                                Text {
                                                    id: keyPillText
                                                    anchors.centerIn: parent
                                                    text: bindRowRect.modelData.bind.key
                                                    color: Theme.fg
                                                    font.family: Theme.systemFamily
                                                    font.pixelSize: Theme.fontSizeSmall - 1
                                                }
                                            }

                                            Text { text: "\u2192"; color: Theme.fg4; font.pixelSize: Theme.fontSizeSmall }

                                            // Description or dispatcher fallback
                                            Text {
                                                text: bindRowRect.modelData.bind.description
                                                    || (bindRowRect.modelData.bind.dispatcher
                                                        + (bindRowRect.modelData.bind.arg ? " " + bindRowRect.modelData.bind.arg : ""))
                                                color: Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            // Bind type tag
                                            Text {
                                                visible: bindRowRect.modelData.bind.mouse
                                                    || bindRowRect.modelData.bind.repeat
                                                    || bindRowRect.modelData.bind.locked
                                                text: bindRowRect.modelData.bind.mouse ? "mouse"
                                                    : (bindRowRect.modelData.bind.repeat ? "repeat" : "locked")
                                                color: Theme.fg4
                                                font.family: Theme.systemFamily
                                                font.pixelSize: Theme.fontSizeSmall - 2
                                                font.italic: true
                                            }

                                            // Edit button
                                            Rectangle {
                                                visible: !bindRowRect.modelData.bind.mouse
                                                width: editBtnText.implicitWidth + Theme.btnPaddingH * 2
                                                height: Theme.btnHeight; radius: Theme.btnRadius
                                                color: editBtnHover.containsMouse ? Theme.bg2 : Theme.bg1
                                                border.width: 1; border.color: Theme.bg3
                                                Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                                Text {
                                                    id: editBtnText
                                                    anchors.centerIn: parent
                                                    text: "Edit"
                                                    color: Theme.fg
                                                    font.family: Theme.systemFamily
                                                    font.pixelSize: Theme.fontSizeSmall
                                                }
                                                Components.HoverLayer {
                                                    id: editBtnHover
                                                    hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                                    onClicked: root.startEditBind(bindRowRect.modelData.index)
                                                }
                                            }
                                        }

                                        Components.HoverLayer {
                                            id: bindRowHover
                                            hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                            onClicked: {
                                                if (!bindRowRect.modelData.bind.mouse)
                                                    root.startEditBind(bindRowRect.modelData.index);
                                            }
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 4 }
                            }
                        }
                    }
                }

                // ── Key capture overlay ──
                Rectangle {
                    anchors.fill: parent
                    visible: root.editingBindIndex >= 0
                    color: Theme.bg

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        spacing: 12

                        Text {
                            text: "Edit Keybind"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.headerFontSize
                            font.bold: true
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: {
                                let b = root.editingBindIndex >= 0
                                    ? HyprlandConfigService.keybinds[root.editingBindIndex] : null;
                                if (!b) return "";
                                return (b.description || (b.dispatcher + " " + (b.arg || "")).trim());
                            }
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            Layout.alignment: Qt.AlignHCenter
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            text: {
                                let b = root.editingBindIndex >= 0
                                    ? HyprlandConfigService.keybinds[root.editingBindIndex] : null;
                                return b ? "Current: " + root.formatBindCombo(b) : "";
                            }
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Item { height: 4 }

                        // Capture area
                        Rectangle {
                            id: captureBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: 72
                            radius: Theme.btnRadius + 2
                            color: root.captureActive ? Theme.bg2 : Theme.bg1
                            border.width: 2
                            border.color: root.captureActive ? Theme.accent : Theme.bg3
                            Behavior on color { Components.CAnim { duration: Theme.animHover } }
                            Behavior on border.color { Components.CAnim { duration: Theme.animHover } }

                            focus: root.captureActive

                            Keys.onPressed: (event) => {
                                if (!root.captureActive) return;
                                event.accepted = true;
                                let key = event.key;
                                if (root.isModifierKey(key)) {
                                    let mods = root.qtModsToNames(event.modifiers);
                                    root._capturePreview = mods.length > 0
                                        ? mods.join(" + ") + " + \u2026" : "";
                                    return;
                                }
                                if (key === Qt.Key_Escape) {
                                    root.stopCapture();
                                    return;
                                }
                                let hyprKey = root.qtKeyToHyprland(event);
                                if (hyprKey === "") return;
                                root.capturedMods = root.qtModsToNames(event.modifiers);
                                root.capturedKey = hyprKey;
                                root._capturePreview = "";
                                root.stopCapture();
                            }

                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (root.captureActive)
                                        return root._capturePreview || "Press a key combination\u2026";
                                    if (root.capturedKey)
                                        return root.formatCapturedCombo();
                                    return "Click Record to capture";
                                }
                                color: root.captureActive ? Theme.accent
                                    : (root.capturedKey ? Theme.fg : Theme.fg4)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }
                        }

                        // Action buttons
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8

                            // Record / Cancel capture
                            Rectangle {
                                width: recLabel.implicitWidth + Theme.btnPaddingH * 2
                                height: Theme.btnHeight; radius: Theme.btnRadius
                                color: root.captureActive
                                    ? (recHover.containsMouse ? Qt.darker(Theme.redBright, 1.1) : Theme.redBright)
                                    : (recHover.containsMouse ? Theme.accent : Theme.bg2)
                                border.width: 1
                                border.color: root.captureActive ? Theme.redBright : Theme.accent
                                Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                Text {
                                    id: recLabel
                                    anchors.centerIn: parent
                                    text: root.captureActive ? "Cancel" : "Record"
                                    color: Theme.bg
                                    font.family: Theme.systemFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Components.HoverLayer {
                                    id: recHover
                                    hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                    onClicked: root.captureActive ? root.stopCapture() : root.startCapture()
                                }
                            }

                            // Apply
                            Rectangle {
                                visible: root.capturedKey !== ""
                                width: applyBtnLabel.implicitWidth + Theme.btnPaddingH * 2
                                height: Theme.btnHeight; radius: Theme.btnRadius
                                color: applyBtnHover.containsMouse ? Theme.accent : Theme.bg2
                                border.width: 1; border.color: Theme.accent
                                Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                Text {
                                    id: applyBtnLabel
                                    anchors.centerIn: parent
                                    text: "Apply"
                                    color: Theme.bg
                                    font.family: Theme.systemFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Components.HoverLayer {
                                    id: applyBtnHover
                                    hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                    onClicked: root.applyBindEdit()
                                }
                            }

                            // Close
                            Rectangle {
                                width: closeBtnLabel.implicitWidth + Theme.btnPaddingH * 2
                                height: Theme.btnHeight; radius: Theme.btnRadius
                                color: closeBtnHover.containsMouse ? Theme.bg2 : Theme.bg1
                                border.width: 1; border.color: Theme.bg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                Text {
                                    id: closeBtnLabel
                                    anchors.centerIn: parent
                                    text: "Close"
                                    color: Theme.fg
                                    font.family: Theme.systemFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                                Components.HoverLayer {
                                    id: closeBtnHover
                                    hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                    onClicked: root.cancelBindEdit()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
