import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../components" as Components

Components.WheelFlickable {
    id: root
    anchors.fill: parent
    contentHeight: mainCol.implicitHeight
    clip: true

    // Data
    property var stateData: ({})
    property string loadState: "loading"
    readonly property bool hasData: loadState === "ready"
    property bool firstLoadDone: false
    readonly property int totalSeconds: hasData ? (stateData.total || 0) : 0
    readonly property int yesterdaySeconds: hasData ? (stateData.yesterday || 0) : 0
    readonly property int averageSeconds: hasData ? (stateData.average || 0) : 0
    readonly property string currentApp: hasData ? (stateData.current || "") : ""
    readonly property var apps: hasData ? (stateData.apps || []) : []
    readonly property var weekData: hasData ? (stateData.week || []) : []
    readonly property var monthData: hasData ? (stateData.month || []) : []
    readonly property string weekRange: hasData ? (stateData.week_range || "") : ""
    property bool chartVisualsReady: false
    readonly property int staleAfterSeconds: 5
    readonly property real weekChartHeight: Math.max(Theme.fontSize * 8, 96)
    readonly property real weekValueFontSize: Math.max(Theme.fontSizeMicro, 8)
    readonly property real monthCellSize: Math.max(Theme.fontSize + 8, 20)
    readonly property real monthCellGap: Math.max(2, Math.round(Theme.fontSizeSmall / 3))
    readonly property real monthLabelFontSize: Math.max(Theme.fontSizeMicro, 8)
    property string emptyStateMessage: {
        if (loadState === "missing")
            return "The focus time daemon is not running.\nStart it with: desktopctl daemon";
        if (loadState === "stale")
            return "Focus daemon has not updated recently.\nRestart it if Hyprland was restarted.";
        return "Unable to read focus time data";
    }

    readonly property int weekMax: {
        let max = 1;
        for (let i = 0; i < weekData.length; i++)
            if (weekData[i] && weekData[i].total > max) max = weekData[i].total;
        return max;
    }

    readonly property int monthMax: {
        let max = 1;
        for (let i = 0; i < monthData.length; i++)
            if (monthData[i] && monthData[i].total > max) max = monthData[i].total;
        return max;
    }

    // Data loading
    Process {
        id: stateProc
        command: ["bash", "-c", "state_root=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"; state_path=\"$state_root/focustime_state.json\"; [ -f \"$state_path\" ] || exit 3; cat -- \"$state_path\""]
        running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { stateProc.buf += line; } }
        onExited: (code) => {
            let trimmed = buf.trim();

            if (code === 3) {
                root.loadState = "missing";
                root.stateData = ({});
            } else if (code !== 0 || trimmed === "") {
                root.loadState = "parse_error";
                root.stateData = ({});
            } else {
                try {
                    let parsed = JSON.parse(trimmed);
                    let lastUpdated = Number(parsed.last_updated);
                    let now = Math.floor(Date.now() / 1000);
                    if (isFinite(lastUpdated) && lastUpdated > 0 && Math.abs(now - lastUpdated) <= root.staleAfterSeconds) {
                        root.stateData = parsed;
                        root.loadState = "ready";
                    } else {
                        root.loadState = "stale";
                        root.stateData = ({});
                    }
                } catch (e) {
                    root.loadState = "parse_error";
                    root.stateData = ({});
                }
            }
            root.firstLoadDone = true;
            if (root.loadState === "ready" && !root.chartVisualsReady) {
                Qt.callLater(function() {
                    if (root.loadState === "ready")
                        root.chartVisualsReady = true;
                });
            }
            buf = "";
        }
    }

    Component.onCompleted: { stateProc.buf = ""; stateProc.running = true; }

    Timer {
        interval: 3000; repeat: true; running: true
        onTriggered: { if (!stateProc.running) { stateProc.buf = ""; stateProc.running = true; } }
    }

    // Helpers
    function formatDuration(seconds) {
        if (seconds < 60) return "< 1m";
        let h = Math.floor(seconds / 3600);
        let m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    function formatShort(seconds) {
        if (seconds < 60) return "";
        let h = Math.floor(seconds / 3600);
        let m = Math.floor((seconds % 3600) / 60);
        if (h > 0 && m > 0) return h + "h" + m;
        return h > 0 ? h + "h" : m + "m";
    }

    function deltaText() {
        if (yesterdaySeconds === 0 && totalSeconds === 0) return "";
        if (yesterdaySeconds === 0) return "no data yesterday";
        let diff = totalSeconds - yesterdaySeconds;
        if (diff === 0) return "= same as yesterday";
        return (diff > 0 ? "↑ " : "↓ ") + formatDuration(Math.abs(diff)) + " vs yesterday";
    }

    function deltaColor() {
        let diff = totalSeconds - yesterdaySeconds;
        return diff > 0 ? Theme.orangeBright : (diff < 0 ? Theme.greenBright : Theme.fg4);
    }

    // Content
    ColumnLayout {
        id: mainCol
        width: parent.width
        spacing: 16

        // Empty state
        ColumnLayout {
            visible: !root.hasData && root.firstLoadDone
            Layout.fillWidth: true
            Layout.topMargin: 80
            spacing: 12

            Components.Icon {
                source: "../icons/hourglass.svg"
                color: Theme.fg4
                iconSize: 48
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "No screen time data"
                color: Theme.fg3
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: root.emptyStateMessage
                color: Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // Header
        Components.SettingsPaneHeader { title: "Screen Time"; iconSource: "../icons/hourglass.svg" }

        // Screen Time
        Components.SectionLabel {
            visible: root.hasData
            text: "TODAY"
        }

        ColumnLayout {
            visible: root.hasData
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: root.formatDuration(root.totalSeconds)
                color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: 24; font.bold: true
            }

            Text {
                visible: text !== ""
                text: root.deltaText()
                color: root.deltaColor()
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                visible: root.currentApp !== ""
                text: "Currently: " + root.currentApp
                color: Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
        }

        RowLayout {
            visible: root.hasData
            Layout.fillWidth: true
            spacing: 24

            ColumnLayout {
                spacing: 2
                Text { text: "Weekly Average"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                Text { text: root.formatDuration(root.averageSeconds); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true }
            }

            ColumnLayout {
                spacing: 2
                Text { text: "Week"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                Text { text: root.weekRange; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
            }
        }

        // This week
        Components.Divider { visible: root.hasData }

        Components.SectionLabel {
            visible: root.hasData
            text: "THIS WEEK"
        }

        Row {
            id: weekRow
            visible: root.hasData
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.weekData.length

                Item {
                    id: barItem
                    required property int index
                    width: {
                        let n = root.weekData.length;
                        return n > 0 ? (mainCol.width - (n - 1) * weekRow.spacing) / n : 0;
                    }
                    height: root.weekChartHeight

                    property var dayData: root.weekData[index] || {}
                    property int dayTotal: dayData.total || 0
                    property bool isToday: dayData.is_target || false
                    property real barFraction: root.weekMax > 0 ? dayTotal / root.weekMax : 0

                    Text {
                        anchors.bottom: barRect.top
                        anchors.bottomMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.chartVisualsReady
                        text: barItem.dayTotal > 0 ? root.formatShort(barItem.dayTotal) : ""
                        color: barItem.isToday ? Theme.fg : Theme.fg4
                        font.family: Theme.fontFamily; font.pixelSize: root.weekValueFontSize
                    }

                    Rectangle {
                        id: barRect
                        anchors.bottom: dayLabel.top
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.chartVisualsReady
                        width: parent.width * 0.55
                        height: Math.max(2, (parent.height - (Theme.fontSizeSmall * 2 + 10)) * barItem.barFraction)
                        radius: Math.min(width / 4, 6)
                        color: barItem.isToday ? Theme.accent : Theme.blueBright
                        opacity: barItem.isToday ? 1.0 : 0.5

                        Behavior on height {
                            enabled: root.chartVisualsReady
                            Components.StdAnim { duration: Theme.animNormal }
                        }
                    }

                    Text {
                        id: dayLabel
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: barItem.dayData.day || ""
                        color: barItem.isToday ? Theme.fg : Theme.fg4
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
                        font.bold: barItem.isToday
                    }
                }
            }
        }

        // This month
        Components.Divider { visible: root.hasData }

        Components.SectionLabel {
            visible: root.hasData
            text: "THIS MONTH"
        }

        Row {
            visible: root.hasData
            Layout.alignment: Qt.AlignHCenter
            spacing: root.monthCellGap

            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                Text {
                    required property string modelData
                    width: root.monthCellSize
                    text: modelData
                    color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: root.monthLabelFontSize
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Grid {
            visible: root.hasData
            Layout.alignment: Qt.AlignHCenter
            columns: 7
            columnSpacing: root.monthCellGap
            rowSpacing: root.monthCellGap

            Repeater {
                model: root.monthData.length

                Rectangle {
                    id: heatCell
                    required property int index
                    property var cellData: root.monthData[index]
                    property bool isNull: cellData === null || cellData === undefined
                    property int cellTotal: isNull ? 0 : (cellData.total || 0)
                    property bool isToday: !isNull && (cellData.is_target || false)

                    width: root.monthCellSize; height: root.monthCellSize; radius: Math.max(3, Math.round(root.monthCellSize * 0.15))
                    color: heatCell.isNull ? "transparent" : Theme.bg2
                    border.width: heatCell.isToday ? 1 : 0
                    border.color: Theme.fg

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: heatCell.border.width
                        radius: parent.radius
                        color: Theme.greenBright
                        opacity: (!heatCell.isNull && heatCell.cellTotal > 0)
                            ? (0.15 + 0.85 * Math.min(1.0, heatCell.cellTotal / root.monthMax))
                            : 0
                    }
                }
            }
        }

        // Apps
        Components.Divider { visible: root.hasData && root.apps.length > 0 }

        Components.SectionLabel {
            visible: root.hasData && root.apps.length > 0
            text: "APPS"
        }

        Repeater {
            model: root.apps.length

            ColumnLayout {
                id: appItem
                required property int index
                property var appData: root.apps[index] || {}

                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: appItem.appData.name || appItem.appData["class"] || ""
                        color: Theme.fg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        text: root.formatDuration(appItem.appData.seconds || 0)
                        color: Theme.fg3
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 4; radius: 2; color: Theme.bg2

                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        visible: root.chartVisualsReady
                        width: parent.width * Math.min(1.0, (appItem.appData.percent || 0) / 100)
                        radius: parent.radius
                        color: Theme.blueBright
                        opacity: 0.8

                        Behavior on width {
                            enabled: root.chartVisualsReady
                            Components.StdAnim { duration: Theme.animNormal }
                        }
                    }
                }
            }
        }

        Item { visible: root.hasData; Layout.fillWidth: true; Layout.preferredHeight: 8 }
    }
}
