import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PanelWindow {
    id: wifiPop
    property bool active: false; signal close()
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:wifi"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property string connectedSsid: ""
    ListModel { id: netModel }
    ListModel { id: knownModel }

    // ── Connection-flow state ─────────────────────────────────
    // "list" → browsing | "password" → WPA-PSK prompt
    // "enterprise" → 802.1X prompt | "connecting" → in progress
    property string popupState: "list"
    property string targetSsid: ""
    property string targetSecurity: ""
    property string connectError: ""

    onActiveChanged: {
        if (active) { resetState(); scan(); loadKnown(); }
    }

    function resetState() {
        popupState = "list";
        targetSsid = "";
        targetSecurity = "";
        connectError = "";
    }

    function scan() { netModel.clear(); connectedSsid = ""; scanProc.running = true; }
    function loadKnown() { knownModel.clear(); knownProc.running = true; }

    function isKnown(ssid) {
        for (let i = 0; i < knownModel.count; i++) if (knownModel.get(i).name === ssid) return true;
        return false;
    }

    // ── nmcli -t field parser (handles \: and \\ escapes) ─────
    function parseNmcli(line) {
        let fields = [], cur = "";
        for (let i = 0; i < line.length; i++) {
            if (line[i] === '\\' && i + 1 < line.length) { cur += line[i + 1]; i++; }
            else if (line[i] === ':') { fields.push(cur); cur = ""; }
            else cur += line[i];
        }
        fields.push(cur);
        return fields;
    }

    function isEnterprise(sec) { return sec.indexOf("802.1X") >= 0; }

    // ── Connection routing ────────────────────────────────────
    function connectTo(ssid, security) {
        connectError = "";
        if (isKnown(ssid)) {
            // Known network — reconnect directly
            popupState = "connecting";
            targetSsid = ssid;
            connectProc.command = ["nmcli", "dev", "wifi", "connect", ssid];
            connectProc.running = true;
        } else if (isEnterprise(security)) {
            // Unknown 802.1X — show identity + password form
            targetSsid = ssid;
            targetSecurity = security;
            popupState = "enterprise";
        } else if (security !== "") {
            // Unknown WPA/WPA2-PSK — show password form
            targetSsid = ssid;
            targetSecurity = security;
            popupState = "password";
        } else {
            // Open network — connect directly
            popupState = "connecting";
            targetSsid = ssid;
            connectProc.command = ["nmcli", "dev", "wifi", "connect", ssid];
            connectProc.running = true;
        }
    }

    function submitPassword(password) {
        if (!password) return;
        popupState = "connecting";
        connectProc.command = ["nmcli", "dev", "wifi", "connect", targetSsid, "password", password];
        connectProc.running = true;
    }

    function submitEnterprise(identity, password) {
        if (!identity || !password) return;
        popupState = "connecting";
        connectProc.command = [
            "nmcli", "dev", "wifi", "connect", targetSsid,
            "802-1x.eap", "peap",
            "802-1x.phase2-auth", "mschapv2",
            "802-1x.identity", identity,
            "802-1x.password", password
        ];
        connectProc.running = true;
    }

    // ── Processes ─────────────────────────────────────────────
    Process {
        id: scanProc
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE", "dev", "wifi", "list", "--rescan", "yes"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let p = wifiPop.parseNmcli(line);
            if (p.length < 4 || !p[0]) return;
            if (p[3] === "*") wifiPop.connectedSsid = p[0];
            for (let i = 0; i < netModel.count; i++) if (netModel.get(i).ssid === p[0]) return;
            netModel.append({ ssid: p[0], signal: parseInt(p[1]) || 0, security: p[2] || "", active: p[3] === "*" });
        } }
    }

    Process {
        id: knownProc; command: ["nmcli", "-t", "-f", "NAME", "con", "show"]; running: false
        stdout: SplitParser { onRead: (line) => { if (line.trim()) knownModel.append({ name: line.trim() }); } }
    }

    Process {
        id: connectProc; running: false
        onExited: (code, status) => {
            if (code === 0) {
                wifiPop.resetState();
                wifiPop.scan();
            } else {
                wifiPop.connectError = "Connection failed (exit " + code + ")";
                wifiPop.popupState = "list";
            }
        }
    }

    Process { id: nmtuiProc; command: ["alacritty", "-e", "nmtui"]; running: false }

    // ── Backdrop ──────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: {
            if (wifiPop.popupState !== "list") wifiPop.resetState();
            else wifiPop.close();
        }
        MouseArea { anchors.fill: parent; onClicked: wifiPop.close() }
    }

    // ── Popup card ────────────────────────────────────────────
    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth; height: wifiCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: wifiPop.active ? 1 : 0
        scale: wifiPop.active ? 1.0 : 0.92
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: wifiCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 8

            // ── Header ────────────────────────────────────────
            RowLayout { Layout.fillWidth: true
                Text {
                    text: {
                        if (wifiPop.popupState === "password") return "󰌾  Password";
                        if (wifiPop.popupState === "enterprise") return "󱄤  Sign In";
                        if (wifiPop.popupState === "connecting") return "󰖩  Connecting…";
                        return "󰖩  Wi-Fi";
                    }
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true
                }

                // Back button (in form states)
                Text {
                    visible: wifiPop.popupState === "password" || wifiPop.popupState === "enterprise"
                    text: "← Back"; color: backA.containsMouse ? Theme.blueBright : Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    MouseArea { id: backA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.resetState() }
                }

                // Rescan button (in list state)
                Text {
                    visible: wifiPop.popupState === "list"
                    text: "Rescan"; color: rescanA.containsMouse ? Theme.blueBright : Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    MouseArea { id: rescanA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.scan() }
                }
            }

            // ── Connected badge ───────────────────────────────
            Text { visible: wifiPop.popupState === "list" && wifiPop.connectedSsid !== ""
                text: "Connected: " + wifiPop.connectedSsid; color: Theme.greenBright
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }

            // ── Error banner ──────────────────────────────────
            Text { visible: wifiPop.connectError !== ""
                text: wifiPop.connectError; color: Theme.redBright
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap; Layout.fillWidth: true }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ══════════════════════════════════════════════════
            // ── LIST STATE ────────────────────────────────────
            // ══════════════════════════════════════════════════
            Flickable {
                visible: wifiPop.popupState === "list"
                Layout.fillWidth: true; Layout.maximumHeight: 280; Layout.minimumHeight: 30
                contentHeight: netCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: netCol; width: parent.width; spacing: 4
                    Repeater {
                        model: netModel
                        Rectangle {
                            id: netItem; required property string ssid; required property int signal
                            required property string security; required property bool active
                            width: netCol.width; height: 30; radius: 6
                            color: niArea.containsMouse ? Theme.bg2 : "transparent"

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                                Text {
                                    text: {
                                        if (signal > 75) return "󰖩";
                                        if (signal > 50) return "󰖩";
                                        if (signal > 25) return "󰖩";
                                        return "󰖩";
                                    }
                                    color: {
                                        if (netItem.active) return Theme.greenBright;
                                        if (signal > 60) return Theme.fg;
                                        if (signal > 30) return Theme.fg3;
                                        return Theme.fg4;
                                    }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                                }
                                Text { text: netItem.ssid; color: netItem.active ? Theme.greenBright : Theme.fg
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { visible: wifiPop.isEnterprise(netItem.security); text: "󱄤"; color: Theme.yellowBright
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                Text { visible: netItem.security !== "" && !wifiPop.isEnterprise(netItem.security); text: "󰌾"; color: Theme.fg4
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                Text { text: netItem.signal + "%"; color: Theme.fg4
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                            }

                            MouseArea { id: niArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: { if (!netItem.active) wifiPop.connectTo(netItem.ssid, netItem.security); } }
                        }
                    }
                }
            }

            Text { visible: wifiPop.popupState === "list" && netModel.count === 0
                text: "Scanning…"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }

            // ── Open nmtui fallback ───────────────────────────
            Rectangle {
                visible: wifiPop.popupState === "list"
                Layout.fillWidth: true; height: 28; radius: 6; color: nmtuiArea.containsMouse ? Theme.bg2 : "transparent"
                Text { anchors.centerIn: parent; text: "Open nmtui (advanced)…"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                MouseArea { id: nmtuiArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: { nmtuiProc.running = true; wifiPop.close(); } }
            }

            // ══════════════════════════════════════════════════
            // ── PASSWORD STATE (WPA-PSK) ──────────────────────
            // ══════════════════════════════════════════════════
            ColumnLayout {
                visible: wifiPop.popupState === "password"
                Layout.fillWidth: true; spacing: 8

                Text { text: "Network: " + wifiPop.targetSsid; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight
                    Layout.fillWidth: true }

                // Password field
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 6; color: Theme.bg2; border.width: 1; border.color: Theme.bg3
                    TextInput {
                        id: pskInput; anchors.fill: parent; anchors.margins: 8
                        color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        echoMode: TextInput.Password; clip: true
                        Keys.onReturnPressed: wifiPop.submitPassword(text)
                        Keys.onEscapePressed: wifiPop.resetState()
                    }
                    Text { visible: !pskInput.text; text: "Password"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: 6; color: connPskA.containsMouse ? Theme.blueBright : Theme.bg3
                    Text { anchors.centerIn: parent; text: "Connect"; color: connPskA.containsMouse ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    MouseArea { id: connPskA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.submitPassword(pskInput.text) }
                }
            }

            // Focus password field when entering this state
            Connections {
                target: wifiPop
                function onPopupStateChanged() {
                    if (wifiPop.popupState === "password") { pskInput.text = ""; pskInput.forceActiveFocus(); }
                    if (wifiPop.popupState === "enterprise") { eapIdentity.text = ""; eapPassword.text = ""; eapIdentity.forceActiveFocus(); }
                }
            }

            // ══════════════════════════════════════════════════
            // ── ENTERPRISE STATE (802.1X PEAP/MSCHAPv2) ──────
            // ══════════════════════════════════════════════════
            ColumnLayout {
                visible: wifiPop.popupState === "enterprise"
                Layout.fillWidth: true; spacing: 8

                Text { text: "Network: " + wifiPop.targetSsid; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight
                    Layout.fillWidth: true }
                Text { text: "802.1X · PEAP / MSCHAPv2"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }

                // Identity field
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 6; color: Theme.bg2; border.width: 1; border.color: Theme.bg3
                    TextInput {
                        id: eapIdentity; anchors.fill: parent; anchors.margins: 8
                        color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; clip: true
                        Keys.onReturnPressed: eapPassword.forceActiveFocus()
                        Keys.onEscapePressed: wifiPop.resetState()
                    }
                    Text { visible: !eapIdentity.text; text: "Username / Identity"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }

                // Password field
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 6; color: Theme.bg2; border.width: 1; border.color: Theme.bg3
                    TextInput {
                        id: eapPassword; anchors.fill: parent; anchors.margins: 8
                        color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        echoMode: TextInput.Password; clip: true
                        Keys.onReturnPressed: wifiPop.submitEnterprise(eapIdentity.text, text)
                        Keys.onEscapePressed: wifiPop.resetState()
                    }
                    Text { visible: !eapPassword.text; text: "Password"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: 6; color: connEapA.containsMouse ? Theme.blueBright : Theme.bg3
                    Text { anchors.centerIn: parent; text: "Sign In"; color: connEapA.containsMouse ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    MouseArea { id: connEapA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.submitEnterprise(eapIdentity.text, eapPassword.text) }
                }

                // nmtui fallback for other EAP methods
                Text { text: "Need EAP-TLS or other method? Use nmtui below."; color: Theme.fg4; wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 2; Layout.fillWidth: true }
            }

            // ══════════════════════════════════════════════════
            // ── CONNECTING STATE ──────────────────────────────
            // ══════════════════════════════════════════════════
            ColumnLayout {
                visible: wifiPop.popupState === "connecting"
                Layout.fillWidth: true; spacing: 8; Layout.alignment: Qt.AlignHCenter

                Text { text: "Connecting to " + wifiPop.targetSsid + "…"; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.alignment: Qt.AlignHCenter }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter; width: 120; height: 4; radius: 2; color: Theme.bg3
                    Rectangle {
                        id: progBar; height: parent.height; radius: parent.radius; color: Theme.blueBright
                        SequentialAnimation on width {
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 120; duration: 1200; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 120; to: 0; duration: 1200; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }
        }
    }
}