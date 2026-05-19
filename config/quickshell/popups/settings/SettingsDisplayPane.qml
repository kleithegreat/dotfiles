import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    anchors.fill: parent
    contentHeight: displayCol.implicitHeight
    clip: true
    interactive: !monitorLayout.hoveringMonitor

    property int selectedMonitorIdx: 0
    property string selectedResolution: ""
    property real selectedRate: -1
    readonly property int sliderValueWidth: Math.max(Theme.fontSize * 4, 40)

    // ── Transform labels (Hyprland transform 0-7) ──
    readonly property var transformLabels: [
        "Normal", "90°", "180°", "270°",
        "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"
    ]
    readonly property var vrrLabels: ["Off", "On", "Fullscreen only"]
    readonly property var vrrValues: [0, 1, 2]

    // ── Confirmation state ──
    property bool confirmVisible: false
    property int confirmSecondsLeft: 15
    property var _preChangeSnapshot: null  // { monitors: [...] } before risky change

    property var layoutMonitors: []
    property bool monitorDragActive: false
    readonly property var brightnessDevices: BrightnessService.devicesForMonitors(DisplayService.monitors, BrightnessService.brightnessDevices)

    readonly property var enabledMonitors: {
        let m = DisplayService.monitors;
        if (!m) return [];
        let result = [];
        for (let i = 0; i < m.length; i++) {
            if (!m[i].disabled)
                result.push(m[i]);
        }
        return result;
    }

    readonly property var currentMonitor: {
        let m = root.enabledMonitors;
        if (root.selectedMonitorIdx >= m.length) return null;
        return m[root.selectedMonitorIdx];
    }

    readonly property var parsedModes: {
        let mon = root.currentMonitor;
        if (!mon || !mon.availableModes) return { resolutions: [], ratesByRes: {} };
        let ratesByRes = {};
        for (let i = 0; i < mon.availableModes.length; i++) {
            let match = mon.availableModes[i].match(/(\d+)x(\d+)@([\d.]+)Hz/);
            if (!match) continue;
            let res = match[1] + "x" + match[2];
            let rate = parseFloat(match[3]);
            if (!ratesByRes[res]) ratesByRes[res] = [];
            let isDupe = false;
            for (let j = 0; j < ratesByRes[res].length; j++) {
                if (Math.abs(ratesByRes[res][j] - rate) < 0.01) { isDupe = true; break; }
            }
            if (!isDupe) ratesByRes[res].push(rate);
        }
        let resolutions = Object.keys(ratesByRes);
        for (let i = 0; i < resolutions.length; i++)
            ratesByRes[resolutions[i]].sort(function(a, b) { return b - a; });
        resolutions.sort(function(a, b) {
            let ap = a.split("x"); let bp = b.split("x");
            return (parseInt(bp[0]) * parseInt(bp[1])) - (parseInt(ap[0]) * parseInt(ap[1]));
        });
        return { resolutions: resolutions, ratesByRes: ratesByRes };
    }

    readonly property var resolutions: root.parsedModes.resolutions
    readonly property var currentRates: root.parsedModes.ratesByRes[root.selectedResolution] || []

    // ── Mirror choices for current monitor ──
    readonly property var mirrorChoices: {
        let mon = root.currentMonitor;
        if (!mon) return [];
        let choices = [{ value: "none", label: "Off" }];
        let all = DisplayService.monitors;
        if (!all) return choices;
        for (let i = 0; i < all.length; i++) {
            if (all[i].name !== mon.name && !all[i].disabled)
                choices.push({ value: all[i].name, label: all[i].name + " — " + (all[i].model || all[i].name) });
        }
        return choices;
    }

    Connections {
        target: DisplayService
        function onMonitorsChanged() {
            if (!root.monitorDragActive)
                root.layoutMonitors = root._cloneMonitors(DisplayService.monitors || []);
            if (!DisplayService.monitorApplyBusy && root.currentMonitor)
                root.syncSelectionFromMonitor();
        }
    }

    Connections {
        target: HyprlandConfigService
        function onMonitorUndoRequested(monitorName, state) {
            root._applyMonitorState(monitorName, state);
        }
    }

    onCurrentMonitorChanged: {
        if (resolutionSelect)
            resolutionSelect.expanded = false;
        if (rateSelect)
            rateSelect.expanded = false;
        if (root.currentMonitor)
            root.syncSelectionFromMonitor();
    }

    function syncSelectionFromMonitor() {
        let mon = root.currentMonitor;
        if (!mon) return;
        root.selectedResolution = mon.width + "x" + mon.height;
        let rates = root.parsedModes.ratesByRes[root.selectedResolution] || [];
        root.selectedRate = root.findClosestRate(rates, mon.refreshRate);
    }

    function findClosestRate(rates, target) {
        if (rates.length === 0) return -1;
        let best = rates[0];
        let bestDiff = Math.abs(rates[0] - target);
        for (let i = 1; i < rates.length; i++) {
            let diff = Math.abs(rates[i] - target);
            if (diff < bestDiff) { bestDiff = diff; best = rates[i]; }
        }
        return best;
    }

    function selectResolution(res) {
        if (res === root.selectedResolution) return;
        root.selectedResolution = res;
        let rates = root.parsedModes.ratesByRes[res] || [];
        root.selectedRate = rates.length > 0 ? rates[0] : -1;
        root.applyCurrentSelection();
    }

    function selectRate(rate) {
        if (Math.abs(rate - root.selectedRate) < 0.01) return;
        root.selectedRate = rate;
        root.applyCurrentSelection();
    }

    function applyCurrentSelection() {
        let mon = root.currentMonitor;
        if (!mon || root.selectedRate < 0) return;
        let parts = root.selectedResolution.split("x");
        let oldState = root._monitorStateFor(mon);
        let newState = JSON.parse(JSON.stringify(oldState));
        newState.width = parseInt(parts[0]);
        newState.height = parseInt(parts[1]);
        newState.refreshRate = root.selectedRate;
        root._applyRiskyMonitorState(mon.name, oldState, newState);
    }

    // ── Full config apply (position, transform, extras) ──
    function _snapshotMonitors() {
        let snap = [];
        let all = DisplayService.monitors;
        if (!all) return snap;
        for (let i = 0; i < all.length; i++)
            snap.push({ name: all[i].name, x: all[i].x, y: all[i].y,
                         width: all[i].width, height: all[i].height,
                         refreshRate: all[i].refreshRate, scale: all[i].scale,
                         transform: all[i].transform, vrr: all[i].vrr,
                         mirrorOf: all[i].mirrorOf });
        return snap;
    }

    function _cloneMonitors(monitors) {
        return JSON.parse(JSON.stringify(monitors || []));
    }

    function _stateByName(states, name) {
        for (let i = 0; i < states.length; i++) {
            if (states[i].name === name)
                return states[i];
        }
        return null;
    }

    function _normalizeMonitorStates(states) {
        let minX = null;
        let minY = null;
        for (let i = 0; i < states.length; i++) {
            let state = states[i];
            if (state.mirrorOf && state.mirrorOf !== "none")
                continue;
            minX = minX === null ? state.x : Math.min(minX, state.x);
            minY = minY === null ? state.y : Math.min(minY, state.y);
        }

        if ((minX === null || minX === 0) && (minY === null || minY === 0))
            return states;

        let normalized = [];
        for (let i = 0; i < states.length; i++) {
            let copy = JSON.parse(JSON.stringify(states[i]));
            copy.x -= minX || 0;
            copy.y -= minY || 0;
            normalized.push(copy);
        }
        return normalized;
    }

    function _stagedMonitorStates() {
        let next = root._snapshotMonitors();
        let staged = monitorLayout.monitors || [];
        for (let i = 0; i < next.length; i++) {
            let stagedState = root._stateByName(staged, next[i].name);
            if (stagedState) {
                next[i].x = stagedState.x;
                next[i].y = stagedState.y;
            }
        }
        return root._normalizeMonitorStates(next);
    }

    function _monitorPositionChanged(oldState, newState) {
        return oldState && newState && (oldState.x !== newState.x || oldState.y !== newState.y);
    }

    function _monitorStateFor(mon) {
        return { x: mon.x, y: mon.y, width: mon.width, height: mon.height,
                 refreshRate: mon.refreshRate, scale: mon.scale,
                 transform: mon.transform, vrr: mon.vrr, mirrorOf: mon.mirrorOf };
    }

    function _applyMonitorState(monitorName, state) {
        let extras = {};
        if (state.vrr !== undefined && state.vrr !== false && state.vrr !== 0)
            extras.vrr = typeof state.vrr === "boolean" ? (state.vrr ? 1 : 0) : state.vrr;
        if (state.mirrorOf && state.mirrorOf !== "none")
            extras.mirror = state.mirrorOf;
        return DisplayService.applyMonitorConfig(
            monitorName, state.width, state.height, state.refreshRate,
            state.x, state.y, state.scale, state.transform, extras
        );
    }

    function _applyRiskyMonitorState(monitorName, oldState, newState) {
        let hadSnapshot = root._preChangeSnapshot !== null;
        root._captureSnapshot();
        if (!root._applyMonitorState(monitorName, newState)) {
            if (!hadSnapshot)
                root._preChangeSnapshot = null;
            return;
        }

        root._showConfirmBanner();
        HyprlandConfigService.pushMonitorUndo(monitorName, oldState, newState);
    }

    function applyMonitorField(field, value) {
        let mon = root.currentMonitor;
        if (!mon) return;
        let oldState = root._monitorStateFor(mon);
        let newState = JSON.parse(JSON.stringify(oldState));
        newState[field] = value;

        root._applyRiskyMonitorState(mon.name, oldState, newState);
    }

    // ── Confirmation countdown ──
    // Capture the "safe" state before any risky change (only once per sequence)
    function _captureSnapshot() {
        if (!root._preChangeSnapshot)
            root._preChangeSnapshot = root._snapshotMonitors();
    }

    // Show or reset the countdown banner
    function _showConfirmBanner() {
        root.confirmSecondsLeft = 15;
        root.confirmVisible = true;
        confirmTimer.restart();
    }

    function _confirmChanges() {
        confirmTimer.stop();
        root.confirmVisible = false;
        root._preChangeSnapshot = null;
    }

    function _revertChanges() {
        if (!root._preChangeSnapshot) {
            confirmTimer.stop();
            root.confirmVisible = false;
            return;
        }

        let snap = root._preChangeSnapshot;
        if (!DisplayService.applyMonitorBatch(snap)) {
            root.confirmSecondsLeft = 1;
            root.confirmVisible = true;
            confirmTimer.restart();
            return;
        }

        confirmTimer.stop();
        root.confirmVisible = false;
        root._preChangeSnapshot = null;
    }

    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmSecondsLeft--;
            if (root.confirmSecondsLeft <= 0)
                root._revertChanges();
        }
    }

    function formatRate(rate, allRates) {
        let rounded = Math.round(rate);
        for (let i = 0; i < allRates.length; i++) {
            if (Math.abs(allRates[i] - rate) > 0.01 && Math.round(allRates[i]) === rounded)
                return rate.toFixed(2) + "Hz";
        }
        return rounded + "Hz";
    }

    function formatResolution(res) {
        return res.replace("x", " \u00d7 ");
    }

    Component.onCompleted: {
        root.layoutMonitors = root._cloneMonitors(DisplayService.monitors || []);
        BrightnessService.refresh();
        DisplayService.refresh();
    }

    ColumnLayout {
        id: displayCol
        width: parent.width
        spacing: 16

        // ── Header ───────────────────────────────────────────

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/monitor.svg"; color: Theme.fg }
            Text { text: "Display"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }

            // Undo / Redo (monitor entries)
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

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        // ── Confirmation Banner ──────────────────────────────

        Rectangle {
            visible: root.confirmVisible
            Layout.fillWidth: true
            height: visible ? confirmRow.implicitHeight + 16 : 0
            radius: Theme.btnRadius + 2
            color: root.confirmSecondsLeft <= 5 ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.15)
                 : root.confirmSecondsLeft <= 10 ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.12)
                 : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)
            border.width: 1
            border.color: root.confirmSecondsLeft <= 5 ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.4)
                        : root.confirmSecondsLeft <= 10 ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.3)
                        : Theme.bg3
            Behavior on color { Components.CAnim { duration: Theme.animHover } }
            Behavior on border.color { Components.CAnim { duration: Theme.animHover } }

            RowLayout {
                id: confirmRow
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                spacing: 8

                Text {
                    text: "Reverting in " + root.confirmSecondsLeft + "s..."
                    color: root.confirmSecondsLeft <= 5 ? Theme.redBright : Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: keepLabel.implicitWidth + Theme.btnPaddingH * 2
                    height: Theme.btnHeight; radius: Theme.btnRadius
                    color: keepArea.containsMouse ? Theme.greenBright : Theme.green
                    Behavior on color { Components.CAnim { duration: Theme.animHover } }

                    Text { id: keepLabel; anchors.centerIn: parent; text: "Confirm"; color: Theme.bg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    Components.HoverLayer { id: keepArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root._confirmChanges() }
                }

                Rectangle {
                    width: revertLabel.implicitWidth + Theme.btnPaddingH * 2
                    height: Theme.btnHeight; radius: Theme.btnRadius
                    color: revertArea.containsMouse ? Theme.bg2 : Theme.bg1
                    border.width: 1; border.color: Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover } }

                    Text { id: revertLabel; anchors.centerIn: parent; text: "Revert"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall }
                    Components.HoverLayer { id: revertArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0; onClicked: root._revertChanges() }
                }
            }
        }

        // ── Monitors ─────────────────────────────────────────

        Text {
            visible: root.enabledMonitors.length > 0
            text: "MONITORS"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Flow {
            visible: root.enabledMonitors.length > 1
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.enabledMonitors

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    property bool isCurrent: index === root.selectedMonitorIdx

                    width: monLabel.implicitWidth + 16
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: isCurrent ? Theme.accent : (monArea.containsMouse ? Theme.bg2 : Theme.bg1)
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    border.width: 1
                    border.color: isCurrent ? Theme.accent : Theme.bg3
                    Behavior on border.color { Components.CAnim { duration: Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    scale: monArea.pressed ? 0.95 : 1.0
                    Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    transformOrigin: Item.Center

                    Text {
                        id: monLabel
                        anchors.centerIn: parent
                        text: modelData.name
                        color: isCurrent ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    }

                    Components.HoverLayer {
                        id: monArea
                        anchors.fill: parent
                        disabled: DisplayService.monitorApplyBusy
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        hoverOpacity: 0
                        pressedOpacity: 0
                        pressedScale: 1.0
                        onClicked: root.selectedMonitorIdx = index
                    }
                }
            }
        }

        // ── Monitor Layout Canvas ────────────────────────────

        Rectangle {
            visible: root.enabledMonitors.length > 0
            Layout.fillWidth: true
            height: 180
            radius: Theme.btnRadius + 2
            color: Theme.bg
            border.width: 1
            border.color: Theme.bg3

            Components.MonitorLayout {
                id: monitorLayout
                anchors.fill: parent
                monitors: root.layoutMonitors
                draggable: root.enabledMonitors.length > 1 && !DisplayService.monitorApplyBusy
                selectedIndex: {
                    // Map enabledMonitors index → full monitors array index
                    let mon = root.currentMonitor;
                    if (!mon) return -1;
                    let all = DisplayService.monitors;
                    if (!all) return -1;
                    for (let i = 0; i < all.length; i++) {
                        if (all[i].name === mon.name) return i;
                    }
                    return -1;
                }

                property var _dragUndoState: null

                onMonitorClicked: (index) => {
                    // Map to enabled-monitors index
                    let mon = monitors[index];
                    if (!mon) return;
                    for (let i = 0; i < root.enabledMonitors.length; i++) {
                        if (root.enabledMonitors[i].name === mon.name) {
                            root.selectedMonitorIdx = i;
                            break;
                        }
                    }
                }

                onDragStarted: {
                    root.monitorDragActive = true;
                    _dragUndoState = root._snapshotMonitors();
                    root._captureSnapshot();
                }

                onDragEnded: {
                    root.monitorDragActive = false;
                    if (_dragUndoState) {
                        let newStates = root._stagedMonitorStates();
                        if (!DisplayService.applyMonitorBatch(newStates)) {
                            root.layoutMonitors = root._cloneMonitors(DisplayService.monitors || []);
                            if (!root.confirmVisible)
                                root._preChangeSnapshot = null;
                            _dragUndoState = null;
                            return;
                        }

                        for (let i = 0; i < _dragUndoState.length; i++) {
                            let old = _dragUndoState[i];
                            let next = root._stateByName(newStates, old.name);
                            if (root._monitorPositionChanged(old, next))
                                HyprlandConfigService.pushMonitorUndo(old.name, old, next);
                        }
                        _dragUndoState = null;
                    }
                    root._showConfirmBanner();
                }
            }
        }

        Text {
            visible: root.enabledMonitors.length > 1
            text: "Drag monitors to reposition"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        // ── Monitor Info ─────────────────────────────────────

        RowLayout {
            visible: root.currentMonitor !== null
            Layout.fillWidth: true
            spacing: 8

            Components.Icon {
                source: "../icons/monitor.svg"
                color: Theme.blueBright
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: root.currentMonitor ? root.currentMonitor.name : ""
                    color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                }

                Text {
                    text: root.currentMonitor ? (root.currentMonitor.model || root.currentMonitor.name) : ""
                    color: Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                }
            }

            Text {
                text: root.currentMonitor ? (root.currentMonitor.width + " \u00d7 " + root.currentMonitor.height + " @ " + Math.round(root.currentMonitor.refreshRate) + "Hz") : ""
                color: Theme.fg3
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
        }

        // ── Resolution ───────────────────────────────────────

        Text {
            visible: root.resolutions.length > 0
            text: "RESOLUTION"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Components.InlineDropdown {
            visible: root.resolutions.length > 0
            Layout.fillWidth: true
            id: resolutionSelect
            disabled: DisplayService.monitorApplyBusy
            pending: DisplayService.monitorApplyBusy
            model: root.resolutions
            currentValue: root.selectedResolution
            textForValue: function(resolution) { return root.formatResolution(resolution); }
            maxVisibleItems: 7
            onExpandedChanged: {
                if (expanded) {
                    rateSelect.expanded = false;
                    transformSelect.expanded = false;
                    vrrSelect.expanded = false;
                    mirrorSelect.expanded = false;
                }
            }
            onActivated: (resolution) => { root.selectResolution(resolution); }
        }

        // ── Refresh Rate ─────────────────────────────────────

        Text {
            visible: root.currentRates.length > 0
            text: "REFRESH RATE"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Components.InlineDropdown {
            visible: root.currentRates.length > 0
            Layout.fillWidth: true
            id: rateSelect
            disabled: DisplayService.monitorApplyBusy
            pending: DisplayService.monitorApplyBusy
            model: root.currentRates
            currentValue: root.selectedRate
            textForValue: function(rate) { return root.formatRate(rate, root.currentRates); }
            maxVisibleItems: 6
            onExpandedChanged: {
                if (expanded) {
                    resolutionSelect.expanded = false;
                    transformSelect.expanded = false;
                    vrrSelect.expanded = false;
                    mirrorSelect.expanded = false;
                }
            }
            onActivated: (rate) => { root.selectRate(rate); }
        }

        Text {
            visible: DisplayService.monitorApplyStatus !== ""
            text: DisplayService.monitorApplyStatus === "applying" ? "Applying\u2026"
                : DisplayService.monitorApplyStatus === "applied" ? "Applied"
                : "Failed to apply"
            color: DisplayService.monitorApplyStatus === "error" ? Theme.redBright
                 : DisplayService.monitorApplyStatus === "applied" ? Theme.greenBright
                 : Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Rectangle {
            visible: root.enabledMonitors.length > 0
            Layout.fillWidth: true
            height: 1
            color: Theme.bg3
        }

        // ── Transform ────────────────────────────────────────

        Text {
            visible: root.currentMonitor !== null
            text: "TRANSFORM"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Components.InlineDropdown {
            visible: root.currentMonitor !== null
            Layout.fillWidth: true
            id: transformSelect
            disabled: DisplayService.monitorApplyBusy
            pending: DisplayService.monitorApplyBusy
            model: root.transformLabels
            currentValue: root.currentMonitor ? root.transformLabels[root.currentMonitor.transform || 0] : root.transformLabels[0]
            maxVisibleItems: 8
            onExpandedChanged: {
                if (expanded) {
                    resolutionSelect.expanded = false;
                    rateSelect.expanded = false;
                    vrrSelect.expanded = false;
                    mirrorSelect.expanded = false;
                }
            }
            onActivated: (label) => {
                let idx = root.transformLabels.indexOf(label);
                if (idx >= 0)
                    root.applyMonitorField("transform", idx);
            }
        }

        // ── VRR ──────────────────────────────────────────────

        Text {
            visible: root.currentMonitor !== null
            text: "VARIABLE REFRESH RATE"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Components.InlineDropdown {
            visible: root.currentMonitor !== null
            Layout.fillWidth: true
            id: vrrSelect
            disabled: DisplayService.monitorApplyBusy
            pending: DisplayService.monitorApplyBusy
            model: root.vrrLabels
            currentValue: {
                if (!root.currentMonitor) return root.vrrLabels[0];
                let v = root.currentMonitor.vrr;
                // vrr in JSON is boolean false or int
                if (v === false || v === 0) return root.vrrLabels[0];
                if (v === true || v === 1) return root.vrrLabels[1];
                if (v === 2) return root.vrrLabels[2];
                return root.vrrLabels[0];
            }
            maxVisibleItems: 3
            onExpandedChanged: {
                if (expanded) {
                    resolutionSelect.expanded = false;
                    rateSelect.expanded = false;
                    transformSelect.expanded = false;
                    mirrorSelect.expanded = false;
                }
            }
            onActivated: (label) => {
                let idx = root.vrrLabels.indexOf(label);
                if (idx >= 0)
                    root.applyMonitorField("vrr", root.vrrValues[idx]);
            }
        }

        // ── Mirror ───────────────────────────────────────────

        Text {
            visible: root.enabledMonitors.length > 1
            text: "MIRROR"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Components.InlineDropdown {
            visible: root.enabledMonitors.length > 1
            Layout.fillWidth: true
            id: mirrorSelect
            disabled: DisplayService.monitorApplyBusy
            pending: DisplayService.monitorApplyBusy
            model: {
                let labels = [];
                for (let i = 0; i < root.mirrorChoices.length; i++)
                    labels.push(root.mirrorChoices[i].label);
                return labels;
            }
            currentValue: {
                let mon = root.currentMonitor;
                if (!mon || !mon.mirrorOf || mon.mirrorOf === "none") return "Off";
                for (let i = 0; i < root.mirrorChoices.length; i++) {
                    if (root.mirrorChoices[i].value === mon.mirrorOf)
                        return root.mirrorChoices[i].label;
                }
                return "Off";
            }
            maxVisibleItems: 5
            onExpandedChanged: {
                if (expanded) {
                    resolutionSelect.expanded = false;
                    rateSelect.expanded = false;
                    transformSelect.expanded = false;
                    vrrSelect.expanded = false;
                }
            }
            onActivated: (label) => {
                for (let i = 0; i < root.mirrorChoices.length; i++) {
                    if (root.mirrorChoices[i].label === label) {
                        root.applyMonitorField("mirrorOf", root.mirrorChoices[i].value);
                        return;
                    }
                }
            }
        }

        Rectangle {
            visible: root.currentMonitor !== null
            Layout.fillWidth: true
            height: 1
            color: Theme.bg3
        }

        // ── Brightness ───────────────────────────────────────

        Text { visible: root.brightnessDevices.length > 0; text: "BRIGHTNESS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Repeater {
            model: root.brightnessDevices

            delegate: ColumnLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Components.Icon {
                        source: modelData.kind === "backlight" ? "../icons/laptop.svg" : "../icons/monitor.svg"
                        color: modelData.kind === "backlight" ? Theme.blueBright : Theme.yellowBright
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: modelData.kind === "backlight" ? "Built-in Display" : "External Display"
                            color: Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                        }

                        Text {
                            text: modelData.label || modelData.device
                            color: Theme.fg3
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

                Components.BrightnessSlider {
                    brightnessDevice: modelData
                    valueWidth: root.sliderValueWidth
                }
            }
        }

        Rectangle { visible: root.brightnessDevices.length > 0; Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        // ── Night Light ──────────────────────────────────────

        Text { text: "NIGHT LIGHT"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Components.Icon {
                source: "../icons/night-light.svg"
                color: DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg4
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Night Light"
                    color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                }

                Text {
                    text: DisplayService.nightLightSubtitle
                    color: DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            Components.ToggleSwitch {
                checked: DisplayService.nightLightEnabled
                disabled: DisplayService.nightLightBusy
                pending: DisplayService.nightLightBusy
                onToggled: DisplayService.toggleNightLight(!DisplayService.nightLightEnabled)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            opacity: DisplayService.nightLightBusy ? 0.72 : 1
            Behavior on opacity { Components.Anim { duration: Theme.animHover } }

            Components.Icon {
                source: "../icons/temperature.svg"
                color: Theme.fg4
                Layout.preferredWidth: 16
            }

            Rectangle {
                Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * DisplayService.nightLightTemperatureFraction
                    radius: parent.radius; color: Theme.orangeBright
                    Behavior on width {
                        Components.Anim {
                            duration: Theme.animMicro
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                }

                Rectangle {
                    width: 12; height: 12; radius: 6; color: Theme.fg
                    y: (parent.height - height) / 2
                    x: Math.max(0, Math.min(parent.width - width, parent.width * DisplayService.nightLightTemperatureFraction - width / 2))
                    scale: nlSlider.pressed ? 1.2 : (nlSlider.containsMouse ? 1.1 : 1.0)
                    Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    Behavior on x { SpringAnimation { spring: 4; damping: 0.4 } }
                }

                Components.HoverLayer {
                    id: nlSlider; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                    disabled: DisplayService.nightLightBusy
                    onPressed: (mouse) => { DisplayService.setNightLightTemperatureFromFraction(mouse.x / parent.width); }
                    onPositionChanged: (mouse) => { if (pressed) DisplayService.setNightLightTemperatureFromFraction(mouse.x / parent.width); }
                    onReleased: { DisplayService.commitNightLightTemperature(); }
                }
            }

            Text {
                text: DisplayService.nightLightTemperatureLabel
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: root.sliderValueWidth; horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }
    }
}
