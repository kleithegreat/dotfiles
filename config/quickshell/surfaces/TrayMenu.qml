import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.ui as Ui

Popover {
    id: root

    required property ShellState state

    // Rows arrive a DBus round trip after the handle; opening on the flag alone shows a sliver.
    readonly property bool requested: state.isOpen("menu")
    readonly property int rows: opener.children ? opener.children.values.length : 0

    shown: requested && (rows > 0 || trail.length > 0)
    anchor: state.anchor
    panelWidth: 300
    padded: false
    contentHeight: column.implicitHeight + Metrics.s1 * 2

    // Submenus replace the list rather than cascading.
    property var trail: []
    readonly property var handle: trail.length > 0 ? trail[trail.length - 1] : root.state.menu

    onRequestedChanged: if (!requested) trail = []

    QsMenuOpener {
        id: opener
        menu: root.handle
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Metrics.s1
        spacing: 0

        Ui.ListRow {
            Layout.fillWidth: true
            visible: root.trail.length > 0
            icon: "chevron-left"
            title: "Back"
            onClicked: root.trail = root.trail.slice(0, root.trail.length - 1)
        }

        Repeater {
            model: opener.children

            Loader {
                required property var modelData

                Layout.fillWidth: true
                sourceComponent: modelData.isSeparator ? divider : option

                Component {
                    id: divider

                    Item {
                        implicitHeight: Metrics.s2

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Metrics.rowInset
                            anchors.rightMargin: Metrics.rowInset
                            height: Metrics.hairline
                            color: Theme.separator
                        }
                    }
                }

                Component {
                    id: option

                    Ui.ListRow {
                        readonly property var entry: modelData

                        title: entry.text
                        interactive: entry.enabled
                        opacity: entry.enabled ? 1 : 0.4
                        chevron: entry.hasChildren
                        icon: entry.buttonType === QsMenuButtonType.CheckBox && entry.checkState !== Qt.Unchecked ? "circle-check-filled" : entry.buttonType === QsMenuButtonType.RadioButton && entry.checkState !== Qt.Unchecked ? "circle-check" : ""

                        onClicked: {
                            if (entry.hasChildren) {
                                root.trail = root.trail.concat([entry]);
                                return;
                            }
                            entry.triggered();
                            root.state.close();
                        }
                    }
                }
            }
        }
    }
}
