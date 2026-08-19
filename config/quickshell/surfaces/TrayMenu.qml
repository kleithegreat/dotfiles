import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.ui as Ui

// Tray menus are drawn from their DBus model with the shell's own primitives.
// Quickshell can hand them to the platform instead, but only in QApplication
// mode, and what comes back is a Qt widget menu — correct behaviour wearing a
// different design system's clothes.
Popover {
    id: root

    required property ShellState state

    shown: state.isOpen("menu")
    anchor: state.anchor
    panelWidth: 300
    padded: false
    contentHeight: column.implicitHeight + Metrics.s1 * 2

    // Submenus replace the list rather than cascading out sideways. A tray menu
    // is a handful of rows; a second floating panel to hold three of them is
    // more machinery than the content justifies.
    property var trail: []
    readonly property var handle: trail.length > 0 ? trail[trail.length - 1] : root.state.menu

    onShownChanged: if (!shown) trail = []

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
