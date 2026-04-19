import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState
    required property bool writePending
    required property string pendingKey
    required property var wallpapers
    required property var wallpaperPreviewPaths
    required property string wallpaperDir
    required property bool directoryBrowserOpen
    required property string directoryBrowserPath
    required property var directoryBrowserEntries

    signal setRequested(string key, string value)
    signal openDirectoryBrowserRequested()
    signal closeDirectoryBrowserRequested()
    signal browseDirectoryRequested(string name)
    signal confirmDirectoryBrowserRequested()

    function isPending(key) {
        return root.writePending && root.pendingKey === key;
    }

    function previewSource(name) {
        let previewPath = root.wallpaperPreviewPaths[name];
        let path = previewPath ? String(previewPath) : root.wallpaperDir + "/" + name;
        return "file://" + path;
    }

    readonly property real wallpaperCardMinWidth: Math.max(Theme.fontSize * 11, 140)
    readonly property int wallpaperColumnCount: {
        if (wpGrid.width <= 0)
            return 1;

        return Math.max(1, Math.floor((wpGrid.width + wpGrid.spacing) / (root.wallpaperCardMinWidth + wpGrid.spacing)));
    }

    anchors.fill: parent
    contentHeight: wpCol.implicitHeight
    clip: true

    ColumnLayout {
        id: wpCol
        width: parent.width
        spacing: 8

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/photo.svg"; color: Theme.fg }
            Text { text: "Wallpaper"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "Filter to theme"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            Components.ToggleSwitch {
                checked: root.themeState.filter_wallpaper === true
                disabled: root.writePending
                pending: root.isPending("filter_wallpaper")
                onToggled: root.setRequested(
                    "filter_wallpaper",
                    root.themeState.filter_wallpaper === true ? "off" : "on"
                )
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text {
            visible: !root.directoryBrowserOpen && root.wallpapers.length === 0
            text: "No wallpapers found in the selected directory."
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.topMargin: 24
        }

        Grid {
            id: wpGrid
            visible: !root.directoryBrowserOpen
            Layout.fillWidth: true
            columns: root.wallpaperColumnCount
            spacing: 8

            Repeater {
                model: root.wallpapers

                delegate: Item {
                    id: wpCard
                    required property string modelData
                    required property int index
                    property bool isCurrent: root.themeState.wallpaper === root.wallpaperDir + "/" + modelData

                    width: (wpGrid.width - Math.max(0, wpGrid.columns - 1) * wpGrid.spacing) / Math.max(1, wpGrid.columns)
                    height: width * 0.65 + 24
                    opacity: root.isPending("wallpaper") && wpCard.isCurrent ? 0.72 : 1
                    Behavior on opacity { Components.Anim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    scale: wpArea.pressed ? 0.97 : 1.0
                    Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    transformOrigin: Item.Center

                    Column {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            width: parent.width
                            height: parent.height - 24
                            radius: 8
                            clip: true
                            color: Theme.bg1
                            border.width: wpCard.isCurrent ? 2 : 1
                            border.color: wpCard.isCurrent ? Theme.accent : (wpArea.containsMouse ? Theme.fg4 : Theme.bg3)
                            Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                source: root.previewSource(wpCard.modelData)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        Text {
                            width: parent.width
                            height: Math.max(Theme.fontSizeSmall + 10, 20)
                            text: wpCard.modelData.replace(/\.\w+$/, "")
                            color: wpCard.isCurrent ? Theme.accent : Theme.fg3
                            Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideMiddle
                            leftPadding: 4
                            rightPadding: 4
                        }
                    }

                    Components.HoverLayer {
                        id: wpArea
                        anchors.fill: parent
                        disabled: root.writePending
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.setRequested("wallpaper", root.wallpaperDir + "/" + wpCard.modelData)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 8 }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.wallpaperDir
                color: Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideMiddle
            }

            Rectangle {
                width: changeDirLabel.implicitWidth + 16
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: changeDirArea.containsMouse ? Theme.bg2 : Theme.bg1
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                border.width: 1
                border.color: Theme.bg3
                scale: changeDirArea.pressed ? 0.95 : 1.0
                Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                transformOrigin: Item.Center

                Text { id: changeDirLabel; anchors.centerIn: parent; text: "Change Directory..."; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }

                Components.HoverLayer {
                    id: changeDirArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: root.openDirectoryBrowserRequested()
                }
            }
        }

        Rectangle {
            id: directoryBrowserPanel
            visible: root.directoryBrowserOpen
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: directoryBrowserContent.implicitHeight + 24
            Layout.preferredHeight: implicitHeight
            radius: Theme.btnRadius + 2
            color: Theme.bg1
            border.width: 1
            border.color: Theme.bg3
            clip: true

            ColumnLayout {
                id: directoryBrowserContent
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text {
                    text: "Browse Directories"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Text {
                    text: "Current Path"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Text {
                    text: root.directoryBrowserPath
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.bg3 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Math.max(directoryListContent.implicitHeight + 8, 76), 184)
                    radius: Theme.btnRadius
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.bg3

                    Components.WheelFlickable {
                        id: directoryListFlick
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        contentWidth: width
                        contentHeight: directoryListContent.implicitHeight

                        Column {
                            id: directoryListContent
                            width: directoryListFlick.width
                            spacing: 4

                            Rectangle {
                                id: parentDirectoryEntry
                                width: directoryListContent.width
                                height: 32
                                radius: Theme.hoverRadius
                                color: parentDirectoryArea.containsMouse && root.directoryBrowserPath !== "/" ? Theme.bg2 : "transparent"
                                border.width: 1
                                border.color: parentDirectoryArea.containsMouse && root.directoryBrowserPath !== "/" ? Theme.bg3 : "transparent"
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                                Text {
                                    anchors {
                                        left: parent.left
                                        leftMargin: 10
                                        right: parent.right
                                        rightMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: ".."
                                    color: root.directoryBrowserPath === "/" ? Theme.fg4 : Theme.fg
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideMiddle
                                }

                                Components.HoverLayer {
                                    id: parentDirectoryArea
                                    anchors.fill: parent
                                    enabled: root.directoryBrowserPath !== "/"
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    hoverEnabled: true

                                    hoverOpacity: 0

                                    pressedOpacity: 0

                                    pressedScale: 1.0
                                    onClicked: root.browseDirectoryRequested("..")
                                }
                            }

                            Repeater {
                                model: root.directoryBrowserEntries

                                delegate: Rectangle {
                                    id: subdirEntry
                                    required property string modelData

                                    width: directoryListContent.width
                                    height: 32
                                    radius: Theme.hoverRadius
                                    color: subdirEntryArea.containsMouse ? Theme.bg2 : "transparent"
                                    border.width: 1
                                    border.color: subdirEntryArea.containsMouse ? Theme.bg3 : "transparent"
                                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                    Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                                    Text {
                                        anchors {
                                            left: parent.left
                                            leftMargin: 10
                                            right: parent.right
                                            rightMargin: 10
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: subdirEntry.modelData
                                        color: Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideMiddle
                                    }

                                    Components.HoverLayer {
                                        id: subdirEntryArea
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true

                                        hoverOpacity: 0

                                        pressedOpacity: 0

                                        pressedScale: 1.0
                                        onClicked: root.browseDirectoryRequested(subdirEntry.modelData)
                                    }
                                }
                            }

                            Text {
                                visible: root.directoryBrowserEntries.length === 0
                                width: directoryListContent.width
                                text: "No subdirectories in this location."
                                color: Theme.fg4
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap
                                leftPadding: 10
                                rightPadding: 10
                                topPadding: 6
                                bottomPadding: 6
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Layout.topMargin: 2

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: cancelDirLabel.implicitWidth + 20
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: cancelDirArea.containsMouse ? Theme.bg2 : Theme.bg
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        scale: cancelDirArea.pressed ? 0.95 : 1.0
                        Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        transformOrigin: Item.Center

                        Text {
                            id: cancelDirLabel
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Components.HoverLayer {
                            id: cancelDirArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.closeDirectoryBrowserRequested()
                        }
                    }

                    Rectangle {
                        width: selectDirLabel.implicitWidth + 20
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: selectDirArea.containsMouse ? Theme.greenBright : Theme.accent
                        border.width: 1
                        border.color: Theme.accent
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        scale: selectDirArea.pressed ? 0.95 : 1.0
                        Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        transformOrigin: Item.Center

                        Text {
                            id: selectDirLabel
                            anchors.centerIn: parent
                            text: "Select"
                            color: Theme.bg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Components.HoverLayer {
                            id: selectDirArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.confirmDirectoryBrowserRequested()
                        }
                    }
                }
            }
        }
    }
}
