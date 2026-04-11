import qs
import QtQuick
import QtQuick.Layouts
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
                    { key: "beziers", label: "Beziers" }
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
        }
    }
}
