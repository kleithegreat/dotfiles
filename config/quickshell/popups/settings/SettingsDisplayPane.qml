import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    anchors.fill: parent
    contentHeight: displayCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Component.onCompleted: {
        BrightnessService.refresh();
        DisplayService.refresh();
    }

    ColumnLayout {
        id: displayCol
        width: parent.width
        spacing: 16

        // ── Night Light ──────────────────────────────────────

        Text { text: "NIGHT LIGHT"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "󰖔"
                color: DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
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
                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter
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
                    Behavior on x { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                }

                Components.HoverLayer {
                    id: nlSlider; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                    onClicked: (mouse) => { DisplayService.setNightLightTemperatureFromFraction(mouse.x / parent.width); }
                    onPositionChanged: (mouse) => { if (pressed) DisplayService.setNightLightTemperatureFromFraction(mouse.x / parent.width); }
                }
            }

            Text {
                text: DisplayService.nightLightTemperatureLabel
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight
            }
        }

        // ── Brightness ───────────────────────────────────────

        Rectangle { visible: BrightnessService.hasBacklight; Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { visible: BrightnessService.hasBacklight; text: "BRIGHTNESS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        RowLayout {
            visible: BrightnessService.hasBacklight
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "󰃠"
                color: Theme.yellowBright
                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
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

            Text {
                text: BrightnessService.brightnessPercent < 25 ? "󰃞" : (BrightnessService.brightnessPercent < 70 ? "󰃟" : "󰃠")
                color: Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter
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
                    Behavior on x { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
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
                Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight
            }
        }
    }
}
