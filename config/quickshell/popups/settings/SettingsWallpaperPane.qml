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

    component DirectoryRow: Rectangle {
        id: dirRow

        required property string label
        property bool rowEnabled: true

        signal activated()

        width: directoryListContent.width
        height: 32
        radius: Theme.hoverRadius
        color: dirRowArea.containsMouse && dirRow.rowEnabled ? Theme.bg2 : "transparent"
        border.width: 1
        border.color: dirRowArea.containsMouse && dirRow.rowEnabled ? Theme.bg3 : "transparent"
        Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
        Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

        Text {
            anchors {
                left: parent.left
                leftMargin: 10
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            text: dirRow.label
            color: dirRow.rowEnabled ? Theme.fg : Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideMiddle
        }

        Components.HoverLayer {
            id: dirRowArea
            disabled: !dirRow.rowEnabled
            flat: true
            onClicked: dirRow.activated()
        }
    }

    ColumnLayout {
        id: wpCol
        width: parent.width
        spacing: 8

        Components.SettingsPaneHeader {
            title: "Wallpaper"
            iconSource: "../icons/photo.svg"
        }

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

        Components.Divider {}

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
                    property bool isCurrent: root.themeState.wallpaper === root.wallpaperDir + "/" + modelData

                    width: (wpGrid.width - Math.max(0, wpGrid.columns - 1) * wpGrid.spacing) / Math.max(1, wpGrid.columns)
                    height: width * 0.65 + 24
                    opacity: root.isPending("wallpaper") && wpCard.isCurrent ? Theme.pendingOpacity : 1
                    Behavior on opacity { Components.StdAnim { duration: Theme.animHover } }
                    scale: wpArea.pressed ? 0.97 : 1.0
                    Behavior on scale { Components.StdAnim { duration: Theme.animMicro } }
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
                            Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

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
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
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
                        disabled: root.writePending
                        flat: true
                        onClicked: root.setRequested("wallpaper", root.wallpaperDir + "/" + wpCard.modelData)
                    }
                }
            }
        }

        Components.Divider { Layout.topMargin: 8 }

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

            Components.ActionButton {
                text: "Change Directory..."
                paddingH: 8
                onClicked: root.openDirectoryBrowserRequested()
            }
        }

        Rectangle {
            id: directoryBrowserPanel
            visible: root.directoryBrowserOpen
            Layout.fillWidth: true
            Layout.topMargin: 8
            implicitHeight: directoryBrowserContent.implicitHeight + 24
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

                Components.Divider {}

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

                            DirectoryRow {
                                label: ".."
                                rowEnabled: root.directoryBrowserPath !== "/"
                                onActivated: root.browseDirectoryRequested("..")
                            }

                            Repeater {
                                model: root.directoryBrowserEntries

                                delegate: DirectoryRow {
                                    required property string modelData

                                    label: modelData
                                    onActivated: root.browseDirectoryRequested(modelData)
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

                    Components.ActionButton {
                        text: "Cancel"
                        baseColor: Theme.bg
                        paddingH: 10
                        onClicked: root.closeDirectoryBrowserRequested()
                    }

                    Components.ActionButton {
                        text: "Select"
                        baseColor: Theme.accent
                        hoverColor: Theme.greenBright
                        borderColor: Theme.accent
                        textColor: Theme.bg
                        paddingH: 10
                        onClicked: root.confirmDirectoryBrowserRequested()
                    }
                }
            }
        }
    }
}
