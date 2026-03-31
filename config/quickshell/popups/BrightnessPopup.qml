import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../components" as Components

FocusScope {
    id: displayPop
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: displayContentLoader.item
    readonly property Item focusTarget: displayPop
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    readonly property bool showBrightnessSection: BrightnessService.hasBacklight
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    function preparePanelForOpen() {
        let item = displayContentLoader.item;
        if (!item)
            return false;

        item.opacity = 0;
        item.scale = 0.92;
        return true;
    }

    onActiveChanged: {
        if (active) {
            forceActiveFocus();
            contentLoaded = true;
            BrightnessService.refresh();
            DisplayService.refresh();
            if (preparePanelForOpen())
                displayOpenAnim.start();
        } else if (!closing) {
            if (displayContentLoader.item) {
                closing = true;
                displayCloseAnim.start();
            } else {
                closing = false;
            }
        }
    }

    SequentialAnimation {
        id: displayOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: displayContentLoader.item
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            Components.Anim {
                target: displayContentLoader.item
                property: "scale"
                to: 1.0
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
        }
    }

    SequentialAnimation {
        id: displayCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: displayContentLoader.item
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: displayContentLoader.item
                property: "scale"
                to: 0.92
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { displayPop.closing = false; } }
    }

    Keys.onEscapePressed: displayPop.close()

    Loader {
        id: displayContentLoader
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.audioPopupWidth
        height: item ? item.implicitHeight : 0
        active: displayPop.contentLoaded || displayPop.active || displayPop.closing
        asynchronous: true
        sourceComponent: displayPanelComponent

        onLoaded: {
            item.opacity = 0;
            item.scale = 0.92;
            if (displayPop.active)
                displayOpenAnim.start();
        }
    }

    Component {
        id: displayPanelComponent

        Rectangle {
            id: displayPanel
            anchors.fill: parent
            implicitHeight: displayCol.implicitHeight + Theme.popupPadding * 2
            radius: Theme.popupRadius
            color: Theme.bg1
            border.width: 1
            border.color: Theme.bg3
            opacity: 0
            scale: 0.92
            transformOrigin: Item.TopRight
            Behavior on height {
                Components.Anim {
                    duration: Theme.animHeightResize
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveStandard
                }
            }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: displayCol
                anchors.fill: parent
                anchors.margins: Theme.popupPadding
                spacing: Theme.sectionSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "󰍹  Display"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.headerFontSize
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Text {
                        text: BrightnessService.hasBacklight ? (BrightnessService.brightnessAvailable ? BrightnessService.brightnessPercent + "%" : "") : DisplayService.nightLightSubtitle
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.bg3
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "󰖔"
                        color: DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg4
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                        Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Night Light"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.headerFontSize
                            font.bold: true
                        }

                        Text {
                            text: DisplayService.nightLightSubtitle
                            color: DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    Components.ToggleSwitch {
                        checked: DisplayService.nightLightEnabled
                        onToggled: DisplayService.toggleNightLight(!DisplayService.nightLightEnabled)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "󰌵"
                        color: Theme.fg4
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                        Layout.preferredWidth: 16
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.sliderHeight
                        radius: Theme.sliderHeight / 2
                        color: Theme.bg3

                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * DisplayService.nightLightTemperatureFraction
                            radius: parent.radius
                            color: Theme.orangeBright
                            Behavior on width {
                                Components.Anim {
                                    duration: Theme.animMicro
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                        }

                        Rectangle {
                            width: 12
                            height: 12
                            radius: 6
                            color: Theme.fg
                            y: (parent.height - height) / 2
                            x: Math.max(0, Math.min(parent.width - width, parent.width * DisplayService.nightLightTemperatureFraction - width / 2))
                            scale: nightLightSliderMouse.pressed ? 1.2 : (nightLightSliderMouse.containsMouse ? 1.1 : 1.0)
                            Behavior on scale {
                                Components.Anim {
                                    duration: Theme.animMicro
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                            Behavior on x {
                                Components.Anim {
                                    duration: Theme.animMicro
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                        }

                        Components.HoverLayer {
                            id: nightLightSliderMouse
                            hoverOpacity: 0
                            pressedOpacity: 0
                            pressedScale: 1.0
                            onClicked: (mouse) => { DisplayService.setNightLightTemperatureFromFraction(mouse.x / parent.width); }
                            onPositionChanged: (mouse) => {
                                if (pressed)
                                    DisplayService.setNightLightTemperatureFromFraction(mouse.x / parent.width);
                            }
                        }
                    }

                    Text {
                        text: DisplayService.nightLightTemperatureLabel
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                    }
                }

                Rectangle {
                    visible: displayPop.showBrightnessSection
                    Layout.fillWidth: true
                    height: visible ? 1 : 0
                    color: Theme.bg3
                }

                ColumnLayout {
                    visible: displayPop.showBrightnessSection
                    Layout.fillWidth: true
                    spacing: Theme.listItemPadding

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "󰃠"
                            color: Theme.yellowBright
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize
                            Layout.alignment: Qt.AlignTop
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Brightness"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.headerFontSize
                                font.bold: true
                            }

                            Text {
                                text: BrightnessService.backlightLabel
                                color: Theme.fg3
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: BrightnessService.brightnessPercent < 25 ? "󰃞" : (BrightnessService.brightnessPercent < 70 ? "󰃟" : "󰃠")
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize
                            Layout.preferredWidth: 16
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: Theme.sliderHeight
                            radius: Theme.sliderHeight / 2
                            color: Theme.bg3

                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: parent.width * BrightnessService.brightnessFraction
                                radius: parent.radius
                                color: Theme.yellowBright
                                Behavior on width {
                                    Components.Anim {
                                        duration: Theme.animMicro
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                            }

                            Rectangle {
                                width: 12
                                height: 12
                                radius: 6
                                color: Theme.fg
                                y: (parent.height - height) / 2
                                x: Math.max(0, Math.min(parent.width - width, parent.width * BrightnessService.brightnessFraction - width / 2))
                                scale: brightnessSliderMouse.pressed ? 1.2 : (brightnessSliderMouse.containsMouse ? 1.1 : 1.0)
                                Behavior on scale {
                                    Components.Anim {
                                        duration: Theme.animMicro
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                                Behavior on x {
                                    Components.Anim {
                                        duration: Theme.animMicro
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                            }

                            Components.HoverLayer {
                                id: brightnessSliderMouse
                                hoverOpacity: 0
                                pressedOpacity: 0
                                pressedScale: 1.0
                                onClicked: (mouse) => { BrightnessService.setBrightnessFraction(mouse.x / parent.width); }
                                onPositionChanged: (mouse) => {
                                    if (pressed)
                                        BrightnessService.setBrightnessFraction(mouse.x / parent.width);
                                }
                            }
                        }

                        Text {
                            text: BrightnessService.brightnessAvailable ? BrightnessService.brightnessPercent + "%" : ""
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            Layout.preferredWidth: 32
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
}
