import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    anchors.fill: parent
    contentHeight: displayCol.implicitHeight
    clip: true

    property int selectedMonitorIdx: 0
    property string selectedResolution: ""
    property real selectedRate: -1
    readonly property int sliderValueWidth: Math.max(Theme.fontSize * 4, 40)

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

    Connections {
        target: DisplayService
        function onMonitorsChanged() {
            if (!DisplayService.monitorApplyBusy && root.currentMonitor)
                root.syncSelectionFromMonitor();
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
        DisplayService.applyMonitorMode(mon.name, parseInt(parts[0]), parseInt(parts[1]), root.selectedRate, mon.scale);
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
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

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
                if (expanded)
                    rateSelect.expanded = false;
            }
            onActivated: (resolution) => { root.selectResolution(resolution); }
        }

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
                if (expanded)
                    resolutionSelect.expanded = false;
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

        // ── Brightness ───────────────────────────────────────

        Text { visible: BrightnessService.hasBacklight; text: "BRIGHTNESS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        RowLayout {
            visible: BrightnessService.hasBacklight
            Layout.fillWidth: true
            spacing: 8

            Components.Icon {
                source: "../icons/brightness-high.svg"
                color: Theme.yellowBright
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Brightness"
                    color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                }

                Text {
                    text: BrightnessService.backlightLabel
                    color: Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                }
            }

            Text {
                text: BrightnessService.brightnessAvailable ? BrightnessService.brightnessPercent + "%" : ""
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
        }

        RowLayout {
            visible: BrightnessService.hasBacklight
            Layout.fillWidth: true
            spacing: 8

            Components.Icon {
                source: BrightnessService.brightnessPercent < 25 ? "../icons/brightness-low.svg" : (BrightnessService.brightnessPercent < 70 ? "../icons/brightness-medium.svg" : "../icons/brightness-high.svg")
                color: Theme.fg4
                Layout.preferredWidth: 16
            }

            Rectangle {
                Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * BrightnessService.brightnessFraction
                    radius: parent.radius; color: Theme.yellowBright
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
                    x: Math.max(0, Math.min(parent.width - width, parent.width * BrightnessService.brightnessFraction - width / 2))
                    scale: brSlider.pressed ? 1.2 : (brSlider.containsMouse ? 1.1 : 1.0)
                    Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    Behavior on x { SpringAnimation { spring: 4; damping: 0.4 } }
                }

                Components.HoverLayer {
                    id: brSlider; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                    onClicked: (mouse) => { BrightnessService.setBrightnessFraction(mouse.x / parent.width); }
                    onPositionChanged: (mouse) => { if (pressed) BrightnessService.setBrightnessFraction(mouse.x / parent.width); }
                }
            }

            Text {
                text: BrightnessService.brightnessAvailable ? BrightnessService.brightnessPercent + "%" : ""
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: root.sliderValueWidth; horizontalAlignment: Text.AlignRight
            }
        }

        Rectangle { visible: BrightnessService.hasBacklight; Layout.fillWidth: true; height: 1; color: Theme.bg3 }

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
                    onClicked: (mouse) => { DisplayService.setNightLightTemperatureFromFraction(mouse.x / parent.width); }
                    onPositionChanged: (mouse) => { if (pressed) DisplayService.setNightLightTemperatureFromFraction(mouse.x / parent.width); }
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
