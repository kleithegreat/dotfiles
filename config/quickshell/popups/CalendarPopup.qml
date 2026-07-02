import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components" as Components

FocusScope {
    id: cal
    property bool active: false
    signal close()
    property bool closing: false
    property bool contentLoaded: false
    property bool suppressHeightAnimation: false
    readonly property bool overlayVisible: active || closing
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    property real panelHeightHint: Theme.calCellSize * 8 + Theme.popupPadding * 2 + 48
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    function preparePanelForOpen() {
        let item = calContentLoader.item;
        if (!item)
            return false;

        item.opacity = 0;
        item.scale = Theme.popupStartScale;
        return true;
    }

    onActiveChanged: {
        if (active) {
            calCloseAnim.stop();
            closing = false;
            suppressHeightAnimation = true;
            let today = new Date();
            todayDate = today;
            viewYear = today.getFullYear();
            viewMonth = today.getMonth();
            contentLoaded = true;
            forceActiveFocus();
            calendarOpenWorkTimer.restart();
            if (preparePanelForOpen())
                calOpenAnim.restart();
        } else if (!closing) {
            calOpenAnim.stop();
            calendarOpenWorkTimer.stop();
            if (calContentLoader.item) {
                suppressHeightAnimation = true;
                closing = true;
                calCloseAnim.restart();
            } else {
                suppressHeightAnimation = false;
                closing = false;
            }
        }
    }

    Timer {
        id: calendarOpenWorkTimer
        interval: Theme.animPopupIn
        repeat: false
        onTriggered: {
            if (cal.active && cal.currentView === "weather")
                cal.refreshWeather(false);
        }
    }

    Timer {
        interval: 1200
        running: !cal.contentLoaded
        repeat: false
        onTriggered: cal.contentLoaded = true
    }

    Timer {
        // Keeps the 'today' highlight correct if the popup stays open across midnight.
        interval: 60 * 1000
        running: cal.active
        repeat: true
        onTriggered: {
            let n = new Date();
            if (n.getDate() !== cal.todayDate.getDate())
                cal.todayDate = n;
        }
    }

    SequentialAnimation {
        id: calOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: calContentLoader.item
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            SequentialAnimation {
                PauseAnimation { duration: Theme.animPopupScaleLead }
                Components.Anim {
                    target: calContentLoader.item
                    property: "scale"
                    to: 1.0
                    duration: Math.max(0, Theme.animPopupIn - Theme.animPopupScaleLead)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveEmphasizedEnter
                }
            }
        }
        onFinished: {
            if (cal.active && !cal.closing)
                cal.suppressHeightAnimation = false;
        }
    }
    SequentialAnimation {
        id: calCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: calContentLoader.item
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: calContentLoader.item
                property: "scale"
                to: Theme.popupStartScale
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction {
            script: {
                cal.closing = false;
                cal.suppressHeightAnimation = false;
            }
        }
    }

    // Refreshed on open and by the date-rollover timer so 'today' bindings stay reactive.
    property var todayDate: new Date()
    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property string currentView: "calendar"
    property bool gridVisible: true
    readonly property real calHighlightSize: Theme.calCellSize * 26 / 32
    readonly property real calendarPaneWidth: Theme.calCellSize * 7 + 12
    // 344 is the weather page's minimum width; Theme.calWidth (306) is narrower today.
    readonly property real panelWidth: Math.max(Theme.calWidth, 344)
    property bool weatherLoading: false
    property bool weatherReady: false
    property string weatherErrorText: ""
    property real weatherTemperatureC: 0
    property real weatherHighC: 0
    property real weatherLowC: 0
    property int weatherHumidity: 0
    property real weatherWindKph: 0
    property int weatherRainChance: 0
    property int weatherCode: -1
    property bool weatherIsDay: {
        let now = new Date();
        return now.getHours() >= 7 && now.getHours() < 19;
    }
    property real weatherLatitude: 0
    property real weatherLongitude: 0
    property bool weatherLocationReady: false
    property string weatherSunriseLabel: "--:--"
    property string weatherSunsetLabel: "--:--"
    property string weatherUpdatedLabel: ""
    property double weatherLastFetchMs: 0
    readonly property var rainCodes: [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82]
    readonly property var snowCodes: [71, 73, 75, 77, 85, 86]
    readonly property var stormCodes: [95, 96, 99]
    readonly property string weatherBadgeText: {
        if (weatherLoading)
            return "Refreshing";
        if (weatherErrorText !== "")
            return weatherReady ? "Cached" : "Offline";
        return weatherReady ? "Live" : "Loading";
    }

    onCurrentViewChanged: {
        if (active && currentView === "weather")
            refreshWeather(false);
    }

    function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); }
    function firstDow(y, m) { return new Date(y, m, 1).getDay(); }
    function shiftMonth(delta) {
        gridVisible = false;
        swapTimer.action = function() {
            let next = cal.viewMonth + delta;
            if (next < 0) {
                cal.viewMonth = 11;
                cal.viewYear--;
            } else if (next > 11) {
                cal.viewMonth = 0;
                cal.viewYear++;
            } else {
                cal.viewMonth = next;
            }
        };
        swapTimer.start();
    }
    function formatTemperature(value) {
        return Math.round((value * 9 / 5) + 32) + "F";
    }
    function formatPercent(value) {
        return Math.round(value) + "%";
    }
    function formatWind(value) {
        return Math.round(value * 0.621371) + " mph";
    }
    function formatClockLabel(date) {
        if (!date || isNaN(date.getTime()))
            return "--:--";

        let hour = date.getHours();
        let suffix = hour >= 12 ? "PM" : "AM";
        hour = hour % 12;
        if (hour === 0)
            hour = 12;
        return hour + ":" + date.getMinutes().toString().padStart(2, "0") + " " + suffix;
    }
    function parseClockFromIso(value) {
        if (!value)
            return "--:--";
        let parsed = new Date(value);
        return formatClockLabel(parsed);
    }
    function weatherConditionText(code) {
        switch (code) {
        case 0: return "Clear";
        case 1: return "Mostly clear";
        case 2: return "Partly cloudy";
        case 3: return "Overcast";
        case 45:
        case 48:
            return "Foggy";
        case 51:
        case 53:
        case 55:
            return "Drizzle";
        case 56:
        case 57:
            return "Icy drizzle";
        case 61:
        case 63:
        case 65:
            return "Rain";
        case 66:
        case 67:
            return "Freezing rain";
        case 71:
        case 73:
        case 75:
        case 77:
            return "Snow";
        case 80:
        case 81:
        case 82:
            return "Showers";
        case 85:
        case 86:
            return "Snow showers";
        case 95:
            return "Thunderstorm";
        case 96:
        case 99:
            return "Stormy";
        default:
            return "Forecast";
        }
    }
    function weatherVibeText(code, isDay, temperatureC) {
        if (code === 0)
            return isDay ? "Clear and bright right now." : "Clear and calm tonight.";
        if (code === 1 || code === 2)
            return isDay ? "A few clouds with comfortable light." : "A few clouds passing through.";
        if (code === 3)
            return "Cloudy conditions outside.";
        if (code === 45 || code === 48)
            return "Fog is reducing visibility.";
        if (rainCodes.indexOf(code) >= 0)
            return "Rain is likely. Take an umbrella.";
        if (snowCodes.indexOf(code) >= 0)
            return "Snowy conditions outside.";
        if (stormCodes.indexOf(code) >= 0)
            return "Storms are nearby. Keep an eye on conditions.";
        if (temperatureC >= 27)
            return "Warm conditions outside.";
        if (temperatureC <= 5)
            return "Cold conditions outside.";
        return "Current local conditions.";
    }
    function weatherAccentColor(code, isDay) {
        if (stormCodes.indexOf(code) >= 0)
            return Theme.purpleBright;
        if (snowCodes.indexOf(code) >= 0)
            return Theme.aquaBright;
        if (rainCodes.indexOf(code) >= 0)
            return Theme.blueBright;
        if (code === 45 || code === 48)
            return Theme.fg3;
        if (code === 2 || code === 3)
            return Theme.aqua;
        return isDay ? Theme.yellowBright : Theme.blueBright;
    }
    readonly property color weatherStatusColor: {
        if (weatherErrorText !== "" && !weatherReady)
            return Theme.redBright;
        if (weatherLoading)
            return Theme.blueBright;
        if (weatherErrorText !== "")
            return Theme.yellowBright;
        return weatherAccentColor(weatherCode, weatherIsDay);
    }
    function applySunStatus(text) {
        let foundLocation = false;
        let lines = text.split(/\r?\n/);
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            let locationMatch = /^Location:\s*(-?[0-9]+(?:\.[0-9]+)?)\s*,\s*(-?[0-9]+(?:\.[0-9]+)?)$/.exec(line);
            if (locationMatch) {
                weatherLatitude = parseFloat(locationMatch[1]);
                weatherLongitude = parseFloat(locationMatch[2]);
                weatherLocationReady = true;
                foundLocation = true;
                continue;
            }

            let solarMatch = /^Sunrise:\s+([0-9]{2}:[0-9]{2})\s+Sunset:\s+([0-9]{2}:[0-9]{2})$/.exec(line);
            if (solarMatch) {
                weatherSunriseLabel = solarMatch[1];
                weatherSunsetLabel = solarMatch[2];
            }
        }
        return foundLocation || weatherLocationReady;
    }
    function startWeatherFetch() {
        if (!weatherLocationReady) {
            weatherLoading = false;
            weatherErrorText = "Location unavailable.";
            return;
        }

        let url = "https://api.open-meteo.com/v1/forecast?latitude="
            + weatherLatitude.toFixed(4)
            + "&longitude=" + weatherLongitude.toFixed(4)
            + "&current=temperature_2m,relative_humidity_2m,is_day,weather_code,wind_speed_10m"
            + "&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"
            + "&forecast_days=1&timezone=auto";
        weatherFetchProc.command = ["curl", "-fsS", "--connect-timeout", "3", "--max-time", "6", url];
        weatherFetchProc.running = true;
    }
    function applyWeatherPayload(text) {
        let payload;
        try {
            payload = JSON.parse(text);
        } catch (error) {
            return false;
        }

        if (!payload || !payload.current || !payload.daily)
            return false;

        let current = payload.current;
        let daily = payload.daily;
        let nextTemp = current.temperature_2m;
        let nextHumidity = current.relative_humidity_2m;
        let nextWind = current.wind_speed_10m;
        let nextCode = current.weather_code;
        let nextHigh = daily.temperature_2m_max && daily.temperature_2m_max.length > 0 ? daily.temperature_2m_max[0] : nextTemp;
        let nextLow = daily.temperature_2m_min && daily.temperature_2m_min.length > 0 ? daily.temperature_2m_min[0] : nextTemp;
        let nextRainChance = daily.precipitation_probability_max && daily.precipitation_probability_max.length > 0 ? daily.precipitation_probability_max[0] : 0;

        if (nextTemp === undefined || nextHumidity === undefined || nextWind === undefined || nextCode === undefined)
            return false;

        weatherTemperatureC = nextTemp;
        weatherHighC = nextHigh;
        weatherLowC = nextLow;
        weatherHumidity = nextHumidity;
        weatherWindKph = nextWind;
        weatherRainChance = nextRainChance;
        weatherCode = nextCode;
        weatherIsDay = current.is_day === 1 || current.is_day === true;
        if (daily.sunrise && daily.sunrise.length > 0)
            weatherSunriseLabel = parseClockFromIso(daily.sunrise[0]);
        if (daily.sunset && daily.sunset.length > 0)
            weatherSunsetLabel = parseClockFromIso(daily.sunset[0]);
        weatherUpdatedLabel = formatClockLabel(new Date());
        weatherLastFetchMs = Date.now();
        weatherReady = true;
        weatherErrorText = "";
        return true;
    }
    function refreshWeather(force) {
        if (sunStatusProc.running || weatherFetchProc.running)
            return;

        let freshEnough = weatherReady && (Date.now() - weatherLastFetchMs) < 15 * 60 * 1000;
        if (!force && freshEnough)
            return;

        weatherLoading = true;
        if (!weatherReady)
            weatherErrorText = "";
        sunStatusProc.running = true;
    }

    Timer {
        id: swapTimer; interval: Theme.animContentSwap; property var action
        onTriggered: { if (action) action(); cal.gridVisible = true; }
    }

    Keys.onEscapePressed: cal.close()
    readonly property int viewFirstDow: firstDow(viewYear, viewMonth)
    readonly property int viewDaysInMonth: daysInMonth(viewYear, viewMonth)
    readonly property int gridCellCount: Math.ceil((viewFirstDow + viewDaysInMonth) / 7) * 7

    component IconButton: Rectangle {
        id: iconButton
        required property string icon
        property int size: 24
        signal clicked()

        width: size
        height: size
        radius: Theme.hoverRadius
        color: "transparent"

        Components.HoverLayer {
            id: iconButtonHover
            onClicked: iconButton.clicked()

            Components.Icon {
                anchors.centerIn: parent
                source: iconButton.icon
                color: iconButtonHover.containsMouse ? Theme.fg : Theme.fg4
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
            }
        }
    }

    component WeatherMetricChip: Rectangle {
        id: chip
        required property string label
        required property string value

        radius: 12
        color: Theme.bg2
        border.width: 1
        border.color: Theme.bg3
        implicitHeight: chipCol.implicitHeight + 14

        Column {
            id: chipCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 2

            Text {
                text: chip.label
                color: Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
            Text {
                text: chip.value
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }
    }

    component ViewToggleButton: Rectangle {
        id: toggle
        required property string label
        required property string viewValue
        required property color accentColor

        readonly property bool selected: cal.currentView === viewValue

        radius: 999
        color: selected ? Theme.bg2 : "transparent"
        border.width: 1
        border.color: selected ? accentColor : Theme.bg3
        implicitWidth: toggleLabel.implicitWidth + 18
        implicitHeight: toggleLabel.implicitHeight + 8

        Components.HoverLayer {
            anchors.fill: parent
            color: toggle.selected ? Theme.bg3 : Theme.bg2
            hoverOpacity: 1.0
            pressedOpacity: 1.0
            pressedScale: 0.98
            onClicked: {
                if (!toggle.selected)
                    cal.currentView = toggle.viewValue;
            }
        }

        Text {
            id: toggleLabel
            anchors.centerIn: parent
            text: toggle.label
            color: toggle.selected ? toggle.accentColor : Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: toggle.selected
        }
    }

    component WeatherSkyArt: Item {
        id: art
        required property int code
        required property bool isDay
        required property color accentColor
        clip: true

        readonly property bool showCloud: [2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99].indexOf(code) >= 0
        readonly property bool showRain: cal.rainCodes.indexOf(code) >= 0
        readonly property bool showSnow: cal.snowCodes.indexOf(code) >= 0
        readonly property bool showStorm: cal.stormCodes.indexOf(code) >= 0
        readonly property bool showFog: code === 45 || code === 48

        Rectangle {
            width: parent.width * 0.78
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 2
            color: Theme.bg1
        }

        Rectangle {
            id: orb
            width: parent.width * 0.38
            height: width
            radius: width / 2
            x: parent.width * 0.12
            y: parent.height * 0.10
            color: art.accentColor
        }

        Rectangle {
            visible: !art.isDay
            width: orb.width
            height: orb.height
            radius: width / 2
            x: orb.x + orb.width * 0.24
            y: orb.y + orb.height * 0.02
            color: Theme.bg2
        }

        Rectangle {
            visible: !art.showCloud
            width: art.isDay ? 4 : 5
            height: art.isDay ? 4 : 5
            radius: width / 2
            x: parent.width * 0.66
            y: parent.height * 0.18
            color: Theme.fg2
        }

        Rectangle {
            visible: !art.showCloud && !art.isDay
            width: 3
            height: 3
            radius: 2
            x: parent.width * 0.74
            y: parent.height * 0.28
            color: Theme.fg3
        }

        Item {
            visible: art.showCloud
            x: parent.width * 0.28
            y: parent.height * 0.32
            width: parent.width * 0.58
            height: parent.height * 0.34

            Rectangle {
                x: 0
                y: height * 0.42
                width: parent.width * 0.60
                height: parent.height * 0.42
                radius: height / 2
                color: art.isDay ? Theme.fg2 : Theme.fg3
            }
            Rectangle {
                x: parent.width * 0.18
                y: height * 0.18
                width: parent.height * 0.55
                height: parent.height * 0.55
                radius: width / 2
                color: Theme.fg2
            }
            Rectangle {
                x: parent.width * 0.38
                y: 0
                width: parent.height * 0.72
                height: parent.height * 0.72
                radius: width / 2
                color: art.isDay ? Theme.fg3 : Theme.fg4
            }
        }

        Repeater {
            model: art.showRain ? 3 : 0
            Rectangle {
                required property int index
                width: 3
                height: 14
                radius: 2
                x: parent.width * (0.38 + index * 0.10)
                y: parent.height * 0.70 + (index % 2 === 0 ? 0 : 4)
                color: Theme.blueBright
            }
        }

        Repeater {
            model: art.showSnow ? 3 : 0
            Rectangle {
                required property int index
                width: 5
                height: 5
                radius: 3
                x: parent.width * (0.40 + index * 0.11)
                y: parent.height * 0.70 + (index % 2 === 0 ? 0 : 6)
                color: Theme.fg2
            }
        }

        Repeater {
            model: art.showFog ? 3 : 0
            Rectangle {
                required property int index
                width: parent.width * 0.34
                height: 4
                radius: 2
                x: parent.width * 0.30
                y: parent.height * (0.68 + index * 0.09)
                color: Theme.fg4
            }
        }

        Components.Icon {
            visible: art.showStorm
            anchors.right: parent.right
            anchors.rightMargin: parent.width * 0.14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.12
            source: "../icons/bolt-filled.svg"
            iconSize: parent.width * 0.18
            color: Theme.yellowBright
        }
    }

    Timer {
        id: weatherRefreshTimer
        interval: 15 * 60 * 1000
        running: cal.active && cal.currentView === "weather"
        repeat: true
        onTriggered: cal.refreshWeather(true)
    }

    Process {
        id: sunStatusProc
        command: ["desktopctl", "sun", "status"]
        running: false
        property string buf: ""
        onRunningChanged: {
            if (running)
                buf = "";
        }
        stdout: SplitParser {
            onRead: (line) => {
                sunStatusProc.buf += line + "\n";
            }
        }
        onExited: (code) => {
            if (code === 0 && sunStatusProc.buf.trim() !== "" && cal.applySunStatus(sunStatusProc.buf)) {
                cal.startWeatherFetch();
            } else {
                cal.weatherLoading = false;
                cal.weatherErrorText = cal.weatherReady ? "Showing the last good forecast." : "Location unavailable.";
            }
        }
    }

    Process {
        id: weatherFetchProc
        running: false
        property string buf: ""
        onRunningChanged: {
            if (running)
                buf = "";
        }
        stdout: SplitParser {
            onRead: (line) => {
                weatherFetchProc.buf += line + "\n";
            }
        }
        onExited: (code) => {
            let success = code === 0 && weatherFetchProc.buf.trim() !== "" && cal.applyWeatherPayload(weatherFetchProc.buf);
            if (!success) {
                if (cal.weatherReady)
                    cal.weatherErrorText = "Showing the last good forecast.";
                else
                    cal.weatherErrorText = "Could not reach the weather feed right now.";
            }
            cal.weatherLoading = false;
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin
        width: calContentLoader.width
        height: calContentLoader.height
        visible: cal.overlayVisible && !cal.closing && height > 0 && !calContentLoader.item
        radius: Theme.popupRadius
        color: Theme.bg1
        border.width: 1
        border.color: Theme.bg3

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Loader {
        id: calContentLoader
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin
        width: cal.panelWidth
        height: cal.overlayVisible ? cal.panelHeightHint : 0
        active: cal.contentLoaded || cal.active || cal.closing
        asynchronous: true
        sourceComponent: calPanelComponent
        Behavior on height {
            enabled: !cal.suppressHeightAnimation
            Components.StdAnim { duration: Theme.animHeightResize }
        }

        onLoaded: {
            cal.panelHeightHint = item.implicitHeight;
            cal.preparePanelForOpen();
            if (cal.active)
                calOpenAnim.start();
        }
    }

    Connections {
        target: calContentLoader.item

        function onImplicitHeightChanged() {
            cal.panelHeightHint = calContentLoader.item.implicitHeight;
        }
    }

    Component {
        id: calPanelComponent

        Rectangle {
            id: calPanel
            anchors.fill: parent
            implicitHeight: calShell.implicitHeight + Theme.popupPadding * 2
            radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
            opacity: 0; scale: Theme.popupStartScale
            transformOrigin: Item.Top
            layer.enabled: calOpenAnim.running || calCloseAnim.running
            layer.smooth: true
            MouseArea { anchors.fill: parent }

            SequentialAnimation {
                id: pageSwapAnim
                ParallelAnimation {
                    Components.StdAnim {
                        target: pageLoader.item
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.animContentSwap
                    }
                    Components.StdAnim {
                        target: pageLoader.item
                        property: "scale"
                        from: 0.985
                        to: 1.0
                        duration: Theme.animContentSwap
                    }
                }
            }

            ColumnLayout {
                id: calShell
                anchors.fill: parent
                anchors.margins: Theme.popupPadding
                spacing: 10

                Loader {
                    id: pageLoader
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? item.implicitHeight : 0
                    sourceComponent: cal.currentView === "weather" ? weatherPageComponent : calendarPageComponent
                    Behavior on Layout.preferredHeight {
                        Components.StdAnim { duration: Theme.animHeightResize }
                    }
                    onLoaded: {
                        if (item) {
                            item.opacity = 0;
                            item.scale = 0.985;
                            pageSwapAnim.restart();
                        }
                    }
                }

                Components.Divider {}

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    ViewToggleButton {
                        label: "Calendar"
                        viewValue: "calendar"
                        accentColor: Theme.yellowBright
                    }

                    ViewToggleButton {
                        label: "Weather"
                        viewValue: "weather"
                        accentColor: Theme.blueBright
                    }
                }
            }

            Component {
                id: calendarPageComponent

                Item {
                    width: pageLoader.width
                    implicitHeight: calCol.implicitHeight

                    ColumnLayout {
                        id: calCol
                        width: cal.calendarPaneWidth
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            IconButton {
                                icon: "../icons/chevron-left.svg"
                                onClicked: cal.shiftMonth(-1)
                            }
                            Text {
                                text: ["January","February","March","April","May","June","July","August","September","October","November","December"][cal.viewMonth] + " " + cal.viewYear
                                color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true
                                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                            }
                            IconButton {
                                icon: "../icons/chevron-right.svg"
                                onClicked: cal.shiftMonth(1)
                            }
                        }

                        RowLayout { spacing: 0; Layout.fillWidth: true
                            Repeater { model: ["Su","Mo","Tu","We","Th","Fr","Sa"]
                                Text { required property string modelData; text: modelData; color: Theme.fg4
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    Layout.preferredWidth: Theme.calCellSize; horizontalAlignment: Text.AlignHCenter }
                            }
                        }

                        Grid {
                            columns: 7; Layout.fillWidth: true; spacing: 0
                            opacity: cal.gridVisible ? 1 : 0
                            Behavior on opacity {
                                Components.StdAnim { duration: Theme.animContentSwap }
                            }

                            Repeater {
                                model: cal.gridCellCount
                                Item {
                                    required property int index
                                    property int dayNum: index - cal.viewFirstDow + 1
                                    property bool isCur: dayNum >= 1 && dayNum <= cal.viewDaysInMonth
                                    property bool isToday: isCur && dayNum === cal.todayDate.getDate() && cal.viewMonth === cal.todayDate.getMonth() && cal.viewYear === cal.todayDate.getFullYear()
                                    width: Theme.calCellSize; height: Theme.calCellSize

                                    Rectangle {
                                        anchors.centerIn: parent; width: cal.calHighlightSize; height: cal.calHighlightSize; radius: width / 2
                                        color: Theme.bg2
                                        opacity: isCur && !isToday && dayCellMouse.containsMouse ? 0.5 : 0
                                        Behavior on opacity {
                                            Components.StdAnim { duration: Theme.animHover }
                                        }
                                    }

                                    Rectangle {
                                        id: todayCircle
                                        anchors.centerIn: parent; width: cal.calHighlightSize; height: cal.calHighlightSize; radius: width / 2
                                        color: isToday ? Theme.blueBright : "transparent"
                                        scale: isToday && cal.active ? 1.0 : 0.8
                                        Behavior on scale {
                                            Components.Anim {
                                                duration: Theme.animSpring
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Theme.animCurveEmphasizedEnter
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent; text: isCur ? dayNum : ""
                                        color: isToday ? Theme.bg : (((index % 7) === 0 || (index % 7) === 6) ? Theme.fg4 : Theme.fg)
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: isToday
                                    }
                                    MouseArea {
                                        id: dayCellMouse; anchors.fill: parent; hoverEnabled: isCur
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: weatherPageComponent

                Item {
                    width: pageLoader.width
                    implicitHeight: weatherCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: weatherCol
                        width: parent.width
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 2

                                Text {
                                    text: "Local forecast"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.headerFontSize
                                    font.bold: true
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: cal.weatherReady ? "Live local conditions." : "Fetching local conditions."
                                    color: Theme.fg4
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                radius: 999
                                color: Theme.bg2
                                border.width: 1
                                border.color: cal.weatherStatusColor
                                implicitWidth: badgeLabel.implicitWidth + 12
                                implicitHeight: badgeLabel.implicitHeight + 6

                                Text {
                                    id: badgeLabel
                                    anchors.centerIn: parent
                                    text: cal.weatherBadgeText
                                    color: cal.weatherStatusColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: true
                                }
                            }

                            IconButton {
                                size: 26
                                icon: "../icons/refresh.svg"
                                onClicked: cal.refreshWeather(true)
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            radius: 16
                            clip: true
                            color: Theme.bg2
                            border.width: 1
                            border.color: Theme.bg3
                            implicitHeight: 162

                            WeatherSkyArt {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: 10
                                anchors.rightMargin: 10
                                width: Math.min(parent.width * 0.40, 92)
                                height: 76
                                code: cal.weatherCode
                                isDay: cal.weatherIsDay
                                accentColor: cal.weatherAccentColor(cal.weatherCode, cal.weatherIsDay)
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 12
                                spacing: 4

                                Text {
                                    text: cal.weatherReady ? cal.formatTemperature(cal.weatherTemperatureC) : "--F"
                                    color: Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeLarge * 2 + 2
                                    font.bold: true
                                }
                                Text {
                                    text: cal.weatherReady ? cal.weatherConditionText(cal.weatherCode) : (cal.weatherLoading ? "Looking outside..." : "Forecast offline")
                                    color: cal.weatherAccentColor(cal.weatherCode, cal.weatherIsDay)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.bold: true
                                }
                                Text {
                                    width: parent.width - 8
                                    text: cal.weatherReady
                                        ? cal.weatherVibeText(cal.weatherCode, cal.weatherIsDay, cal.weatherTemperatureC)
                                        : (cal.weatherErrorText !== "" ? cal.weatherErrorText : "Resolving local weather now.")
                                    color: Theme.fg3
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.Wrap
                                }
                                Text {
                                    text: cal.weatherReady
                                        ? "High " + cal.formatTemperature(cal.weatherHighC) + "  Low " + cal.formatTemperature(cal.weatherLowC)
                                        : "Sunrise " + cal.weatherSunriseLabel + "  Sunset " + cal.weatherSunsetLabel
                                    color: Theme.fg2
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            WeatherMetricChip {
                                Layout.fillWidth: true
                                label: "Humidity"
                                value: cal.weatherReady ? cal.formatPercent(cal.weatherHumidity) : "--"
                            }

                            WeatherMetricChip {
                                Layout.fillWidth: true
                                label: "Wind"
                                value: cal.weatherReady ? cal.formatWind(cal.weatherWindKph) : "--"
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            WeatherMetricChip {
                                Layout.fillWidth: true
                                label: "Rain chance"
                                value: cal.weatherReady ? cal.formatPercent(cal.weatherRainChance) : "--"
                            }

                            WeatherMetricChip {
                                Layout.fillWidth: true
                                label: "Updated"
                                value: cal.weatherUpdatedLabel !== "" ? cal.weatherUpdatedLabel : "Waiting"
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            radius: 14
                            color: Theme.bg2
                            border.width: 1
                            border.color: Theme.bg3
                            implicitHeight: solarRow.implicitHeight + 18

                            RowLayout {
                                id: solarRow
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: "Sunrise"
                                        color: Theme.fg4
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                    Text {
                                        text: cal.weatherSunriseLabel
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        font.bold: true
                                    }
                                }

                                Rectangle {
                                    width: 1
                                    Layout.fillHeight: true
                                    color: Theme.bg3
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: "Sunset"
                                        color: Theme.fg4
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                    Text {
                                        text: cal.weatherSunsetLabel
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        font.bold: true
                                    }
                                }
                            }
                        }

                    }
                }
            }
        }
    }
}
