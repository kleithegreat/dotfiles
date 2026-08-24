import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    // Edits accumulate here and are applied as one chunk. Writing per control —
    // or worse, per pointer move — can strand the session on a mode the display
    // cannot show, with no way back.
    property var edits: ({})
    readonly property bool dirty: Object.keys(edits).length > 0

    property var snapshot: []
    property int confirmLeft: 0

    Component.onCompleted: Sys.Displays.refresh()

    function edit(name, key, value) {
        const staged = Object.assign({}, edits);
        const one = Object.assign({}, staged[name] || {});
        one[key] = value;
        staged[name] = one;
        edits = staged;
    }

    function pendingFor(monitor, key) {
        const staged = edits[monitor.name];
        if (staged && staged[key] !== undefined)
            return staged[key];
        return monitor[key];
    }

    function stateFor(monitor) {
        return {
            name: monitor.name,
            width: pendingFor(monitor, "width"),
            height: pendingFor(monitor, "height"),
            refreshRate: pendingFor(monitor, "refreshRate"),
            x: root.pendingFor(monitor, "x"),
            y: root.pendingFor(monitor, "y"),
            scale: pendingFor(monitor, "scale"),
            transform: pendingFor(monitor, "transform"),
            vrr: pendingFor(monitor, "vrr"),
            disabled: pendingFor(monitor, "disabled")
        };
    }

    // Every monitor goes in the chunk, not just the edited ones: a monitor left
    // on `position = "auto"` re-resolves against the new geometry and slides
    // somewhere nobody asked for the moment a neighbour moves.
    function apply() {
        if (!dirty)
            return;

        const states = [];
        for (let i = 0; i < Sys.Displays.monitors.length; i++)
            states.push(stateFor(Sys.Displays.monitors[i]));

        snapshot = [];
        for (let i = 0; i < Sys.Displays.monitors.length; i++) {
            const monitor = Sys.Displays.monitors[i];
            snapshot.push({
                name: monitor.name,
                width: monitor.width,
                height: monitor.height,
                refreshRate: monitor.refreshRate,
                x: monitor.x,
                y: monitor.y,
                scale: monitor.scale,
                transform: monitor.transform,
                vrr: monitor.vrr,
                disabled: monitor.disabled
            });
        }

        edits = ({});
        Sys.Displays.apply(states);
        confirmLeft = 15;
        countdown.restart();
        // The confirm card is the top of a pane you are almost certainly
        // scrolled past -- a countdown nobody can see reverts every time.
        root.scrollTo(0);
    }

    // Only a layout the user kept is worth surviving a reload. Disabled outputs
    // go in too: staying off is a setting like any other.
    function keep() {
        confirmLeft = 0;
        countdown.stop();
        Sys.Displays.saveLayout(Sys.Displays.monitors.map(monitor => stateFor(monitor)));
        snapshot = [];
    }

    function revert() {
        countdown.stop();
        confirmLeft = 0;
        if (snapshot.length > 0)
            Sys.Displays.apply(snapshot);
        snapshot = [];
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmLeft--;
            if (root.confirmLeft <= 0)
                root.revert();
        }
    }

    function modesFor(monitor) {
        const seen = {};
        const modes = [];
        const listed = monitor.availableModes || [];
        for (let i = 0; i < listed.length; i++) {
            const parsed = String(listed[i]).match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
            if (!parsed)
                continue;
            const key = parsed[1] + "x" + parsed[2];
            const rate = Math.round(parseFloat(parsed[3]));
            const id = key + "@" + rate;
            if (seen[id])
                continue;
            seen[id] = true;
            modes.push({ label: key + " · " + rate + " Hz", value: id, width: parseInt(parsed[1], 10), height: parseInt(parsed[2], 10), rate: parseFloat(parsed[3]) });
        }
        return modes;
    }

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Card {
            Layout.fillWidth: true
            implicitHeight: confirmRow.implicitHeight + Metrics.s3 * 2
            visible: root.confirmLeft > 0
            color: Theme.accentSurface

            RowLayout {
                id: confirmRow
                anchors.fill: parent
                anchors.margins: Metrics.s3
                spacing: Metrics.s3

                Ui.Label {
                    Layout.fillWidth: true
                    text: "Keep these display settings?"
                    role: "body"
                }

                Ui.Label {
                    text: root.confirmLeft + "s"
                    role: "callout"
                    numeric: true
                }

                Ui.Button {
                    text: "Revert"
                    onClicked: root.revert()
                }

                Ui.Button {
                    text: "Keep"
                    variant: "filled"
                    onClicked: root.keep()
                }
            }
        }

        Ui.Group {
            title: "Arrangement"
            footnote: "Drag a display to where it sits on your desk. Edges snap together."

            Ui.DisplayArrangement {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                layout: Sys.Displays.monitors.filter(monitor => !monitor.disabled).map(monitor => ({
                    name: monitor.name,
                    x: root.pendingFor(monitor, "x"),
                    y: root.pendingFor(monitor, "y"),
                    width: root.pendingFor(monitor, "width"),
                    height: root.pendingFor(monitor, "height"),
                    primary: Sys.Displays.isPrimary(monitor)
                }))
                onMoved: (name, x, y) => {
                    root.edit(name, "x", x);
                    root.edit(name, "y", y);
                }
            }
        }

        Repeater {
            model: Sys.Displays.monitors.length

            Ui.Group {
                id: screen

                required property int index
                readonly property var monitor: Sys.Displays.monitors[screen.index]

                title: monitor.name + " · " + (monitor.description || "Display")

                Ui.ListRow {
                    Layout.fillWidth: true
                    icon: "monitor"
                    title: "Enabled"
                    interactive: false

                    Ui.Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: !root.pendingFor(screen.monitor, "disabled")
                        onToggled: on => root.edit(screen.monitor.name, "disabled", !on)
                    }
                }

                Ui.Divider {
                    inset: Metrics.rowInset
                }

                // Applied immediately rather than staged: nothing about which
                // display carries the bar can leave you unable to see a screen,
                // so there is nothing for a countdown to rescue.
                Ui.ListRow {
                    Layout.fillWidth: true
                    icon: "layout"
                    title: "Main display"
                    subtitle: Sys.Displays.primary === "" ? "Chosen automatically" : "Carries the bar and workspaces 1-10"
                    interactive: false

                    Ui.Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Sys.Displays.isPrimary(screen.monitor)
                        onToggled: on => Sys.Displays.setPrimary(on ? screen.monitor : null)
                    }
                }

                Ui.Divider {
                    inset: Metrics.rowInset
                }

                Ui.ListRow {
                    Layout.fillWidth: true
                    title: "Resolution"
                    subtitle: root.pendingFor(screen.monitor, "width") + " × " + root.pendingFor(screen.monitor, "height") + " at " + Math.round(root.pendingFor(screen.monitor, "refreshRate")) + " Hz"
                    interactive: false
                }

                Ui.Choice {
                    id: modes
                    Layout.fillWidth: true
                    Layout.leftMargin: Metrics.rowInset
                    Layout.rightMargin: Metrics.rowInset
                    Layout.bottomMargin: Metrics.s2
                    options: root.modesFor(screen.monitor)
                    current: root.pendingFor(screen.monitor, "width") + "x" + root.pendingFor(screen.monitor, "height") + "@" + Math.round(root.pendingFor(screen.monitor, "refreshRate"))
                    onPicked: value => {
                        const chosen = root.modesFor(screen.monitor).find(mode => mode.value === value);
                        if (!chosen)
                            return;
                        root.edit(screen.monitor.name, "width", chosen.width);
                        root.edit(screen.monitor.name, "height", chosen.height);
                        root.edit(screen.monitor.name, "refreshRate", chosen.rate);
                    }
                }

                Ui.Divider {
                    inset: Metrics.rowInset
                }

                Ui.ListRow {
                    Layout.fillWidth: true
                    title: "Scale"
                    interactive: false

                    Ui.Choice {
                        anchors.verticalCenter: parent.verticalCenter
                        options: [{ label: "100%", value: "1" }, { label: "125%", value: "1.25" }, { label: "150%", value: "1.5" }, { label: "200%", value: "2" }]
                        current: String(root.pendingFor(screen.monitor, "scale"))
                        onPicked: value => root.edit(screen.monitor.name, "scale", parseFloat(value))
                    }
                }

                Ui.Divider {
                    inset: Metrics.rowInset
                }

                Ui.ListRow {
                    Layout.fillWidth: true
                    title: "Variable refresh rate"
                    interactive: false

                    Ui.Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root.pendingFor(screen.monitor, "vrr") ? true : false
                        onToggled: on => root.edit(screen.monitor.name, "vrr", on ? 1 : 0)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.dirty
            spacing: Metrics.s2

            Item {
                Layout.fillWidth: true
            }

            Ui.Button {
                text: "Discard"
                onClicked: root.edits = ({})
            }

            Ui.Button {
                text: "Apply"
                variant: "filled"
                interactive: !Sys.Displays.applying
                onClicked: root.apply()
            }
        }

        Ui.Group {
            title: "Night Light"
            footnote: Sys.NightLight.mode === "auto" ? "Following the sunrise and sunset schedule." : ""

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "night-light"
                title: "Night Light"
                subtitle: Sys.NightLight.running ? Sys.NightLight.temperature + "K" : "Off"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.NightLight.running
                    pending: Sys.NightLight.busy
                    onToggled: on => Sys.NightLight.toggle(on)
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Schedule"
                interactive: false

                Ui.Choice {
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ label: "Auto", value: "auto" }, { label: "On", value: "on" }, { label: "Off", value: "off" }]
                    current: Sys.NightLight.mode
                    onPicked: value => Sys.NightLight.setMode(value, value === "on" ? Sys.NightLight.target : undefined)
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                spacing: Metrics.s3

                Ui.Label {
                    text: "Warmth"
                    role: "body"
                }

                Ui.Slider {
                    Layout.fillWidth: true
                    value: Sys.NightLight.fraction
                    onMoved: value => Sys.NightLight.setFraction(value)
                    onCommitted: Sys.NightLight.commitTemperature()
                }

                Ui.Label {
                    text: Sys.NightLight.target + "K"
                    role: "caption"
                    numeric: true
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: Metrics.s8 + Metrics.s2
                }
            }
        }
    }
}
