import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PanelWindow {
    id: wifiPop
    property bool active: false; signal close()
    property bool closing: false
    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:wifi"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property string connectedSsid: ""
    ListModel { id: netModel }
    ListModel { id: knownModel }

    property string popupState: "list"
    property string targetSsid: ""
    property string targetSecurity: ""
    property string connectError: ""

    onActiveChanged: {
        if (active) {
            wifiPanel.opacity = 0; wifiPanel.scale = 0.92;
            wifiOpenAnim.start();
            resetState(); scan(); loadKnown();
        } else if (!closing) {
            closing = true; wifiCloseAnim.start();
        }
    }

    SequentialAnimation {
        id: wifiOpenAnim
        ParallelAnimation {
            NumberAnimation { target: wifiPanel; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: wifiPanel; property: "scale"; to: 1.0; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: wifiCloseAnim
        ParallelAnimation {
            NumberAnimation { target: wifiPanel; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
            NumberAnimation { target: wifiPanel; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { wifiPop.closing = false; } }
    }

    function resetState() {
        popupState = "list"; targetSsid = ""; targetSecurity = ""; connectError = "";
    }

    function scan() { netModel.clear(); connectedSsid = ""; scanProc.running = true; }
    function loadKnown() { knownModel.clear(); knownProc.running = true; }

    function isKnown(ssid) {
        for (let i = 0; i < knownModel.count; i++) if (knownModel.get(i).name === ssid) return true;
        return false;
    }

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

    function connectTo(ssid, security) {
        connectError = "";
        if (isEnterprise(security)) {
            targetSsid = ssid; targetSecurity = security; popupState = "enterprise";
        } else if (isKnown(ssid)) {
            popupState = "connecting"; targetSsid = ssid;
            connectProc.command = ["nmcli", "dev", "wifi", "connect", ssid];
            connectProc.running = true;
        } else if (security !== "") {
            targetSsid = ssid; targetSecurity = security; popupState = "password";
        } else {
            popupState = "connecting"; targetSsid = ssid;
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
        enterpriseProc.command = [
            "bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1); " +
            "nmcli connection delete id " + JSON.stringify(targetSsid) + " 2>/dev/null; " +
            "nmcli connection add type wifi ifname \"$iface\" con-name " + JSON.stringify(targetSsid) +
            " ssid " + JSON.stringify(targetSsid) +
            " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" +
            " 802-1x.identity " + JSON.stringify(identity) +
            " 802-1x.password " + JSON.stringify(password) +
            " && nmcli connection up id " + JSON.stringify(targetSsid)
        ];
        enterpriseProc.running = true;
    }

    function disconnect() { disconnectProc.running = true; }

    // ── Processes ─────────────────────────────────────────────
    Process {
        id: scanProc
        command: [
            "bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1); " +
            "nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE dev wifi list ifname \"$iface\" --rescan yes"
        ]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let p = wifiPop.parseNmcli(line);
            if (p.length < 4 || !p[0]) return;
            if (p[3] === "*") wifiPop.connectedSsid = p[0];
            for (let i = 0; i < netModel.count; i++) {
                if (netModel.get(i).ssid === p[0]) {
                    if ((parseInt(p[1]) || 0) > netModel.get(i).signal)
                        netModel.set(i, { ssid: p[0], signal: parseInt(p[1]) || 0, security: p[2] || "", active: p[3] === "*" });
                    return;
                }
            }
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
            if (code === 0) { wifiPop.resetState(); wifiPop.scan(); }
            else { wifiPop.connectError = "Connection failed (exit " + code + ")"; wifiPop.popupState = "list"; }
        }
    }

    Process {
        id: enterpriseProc; running: false
        onExited: (code, status) => {
            if (code === 0) { wifiPop.resetState(); wifiPop.scan(); }
            else { wifiPop.connectError = "Enterprise auth failed (exit " + code + ")"; wifiPop.popupState = "list"; }
        }
    }

    Process {
        id: disconnectProc; running: false
        command: [
            "bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1); " +
            "nmcli dev disconnect \"$iface\""
        ]
        onExited: { wifiPop.scan(); }
    }



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
        id: wifiPanel
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth; height: wifiCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: 0.92
        transformOrigin: Item.TopRight
        Behavior on height { NumberAnimation { duration: Theme.animHeightResize; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: wifiCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 8

            RowLayout { Layout.fillWidth: true
                Text {
                    text: {
                        if (wifiPop.popupState === "password") return "󰌾  Password";
                        if (wifiPop.popupState === "enterprise") return "󱄤  Sign In";
                        if (wifiPop.popupState === "connecting") return "󰖩  Connecting…";
                        return "󰖩  Wi-Fi";
                    }
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true
                }
                // Back button
                Rectangle {
                    visible: wifiPop.popupState === "password" || wifiPop.popupState === "enterprise"
                    width: backLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: backA.pressed ? 0.9 : (backA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: backA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: backLabel; anchors.centerIn: parent; text: "← Back"; color: backA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: backA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.resetState() }
                }
                // Rescan button
                Rectangle {
                    visible: wifiPop.popupState === "list"
                    width: rescanLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: rescanA.pressed ? 0.9 : (rescanA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: rescanA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: rescanLabel; anchors.centerIn: parent; text: "Rescan"; color: rescanA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: rescanA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.scan() }
                }
            }

            // ── Connected + disconnect ────────────────────────
            RowLayout {
                visible: wifiPop.popupState === "list" && wifiPop.connectedSsid !== ""
                Layout.fillWidth: true; spacing: 8
                // Animated left accent bar
                Rectangle { width: 3; height: parent.height; radius: 1.5; color: Theme.greenBright
                    opacity: wifiPop.connectedSsid !== "" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.animSpring; easing.type: Easing.OutCubic } }
                }
                Text { text: "Connected: " + wifiPop.connectedSsid; color: Theme.greenBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                Rectangle {
                    width: dcLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: dcA.pressed ? 0.9 : (dcA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: dcA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: dcLabel; anchors.centerIn: parent; text: "Disconnect"; color: dcA.containsMouse ? Theme.redBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: dcA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.disconnect() }
                }
            }

            // Error message with slide/fade in
            Item {
                Layout.fillWidth: true; visible: wifiPop.connectError !== ""
                implicitHeight: errorText.implicitHeight
                Text { id: errorText; width: parent.width
                    text: wifiPop.connectError; color: Theme.redBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    opacity: wifiPop.connectError !== "" ? 1 : 0
                    y: wifiPop.connectError !== "" ? 0 : 6
                    Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── LIST ──────────────────────────────────────────
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 170; Layout.maximumHeight: 170
                visible: wifiPop.popupState === "list"
                opacity: wifiPop.popupState === "list" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }

                Flickable {
                    anchors.fill: parent
                    contentHeight: netCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: netCol; width: parent.width; spacing: 4
                        Repeater {
                            model: netModel
                            Rectangle {
                                id: netItem; required property string ssid; required property int signal
                                required property string security; required property bool active
                                width: netCol.width; height: 30; radius: Theme.hoverRadius
                                color: "transparent"

                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                    opacity: niArea.pressed ? 0.9 : (niArea.containsMouse ? 0.6 : 0)
                                    Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                                }
                                scale: niArea.pressed ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                transformOrigin: Item.Center

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: Theme.listItemPadding; spacing: 6
                                    Text {
                                        text: "󰖩"
                                        color: {
                                            if (netItem.active) return Theme.greenBright;
                                            if (signal > 60) return Theme.fg;
                                            if (signal > 30) return Theme.fg3;
                                            return Theme.fg4;
                                        }
                                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
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
            }

            // Scanning indicator with pulsing animation
            Item {
                visible: wifiPop.popupState === "list" && netModel.count === 0
                Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
                implicitHeight: scanningRow.implicitHeight
                RowLayout {
                    id: scanningRow; anchors.centerIn: parent; spacing: 6
                    Text { id: scanIcon; text: "󰖩"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutQuad }
                        }
                    }
                    Text { text: "Scanning…"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }

            // ── PASSWORD ──────────────────────────────────────
            ColumnLayout {
                visible: wifiPop.popupState === "password"
                opacity: wifiPop.popupState === "password" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                Layout.fillWidth: true; spacing: 8

                Text { text: "Network: " + wifiPop.targetSsid; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
                    border.width: 1; border.color: pskInput.activeFocus ? Theme.blueBright : Theme.bg3
                    Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
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
                    Layout.fillWidth: true; height: 30; radius: Theme.btnRadius
                    color: connPskA.containsMouse ? Theme.blueBright : Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    scale: connPskA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { anchors.centerIn: parent; text: "Connect"; color: connPskA.containsMouse ? Theme.bg : Theme.fg
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    MouseArea { id: connPskA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.submitPassword(pskInput.text) }
                }
            }

            Connections {
                target: wifiPop
                function onPopupStateChanged() {
                    if (wifiPop.popupState === "password") { pskInput.text = ""; pskInput.forceActiveFocus(); }
                    if (wifiPop.popupState === "enterprise") { eapIdentity.text = ""; eapPassword.text = ""; eapIdentity.forceActiveFocus(); }
                }
            }

            // ── ENTERPRISE ────────────────────────────────────
            ColumnLayout {
                visible: wifiPop.popupState === "enterprise"
                opacity: wifiPop.popupState === "enterprise" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                Layout.fillWidth: true; spacing: 8

                Text { text: "Network: " + wifiPop.targetSsid; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: "802.1X · PEAP / MSCHAPv2"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }

                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
                    border.width: 1; border.color: eapIdentity.activeFocus ? Theme.blueBright : Theme.bg3
                    Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
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

                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
                    border.width: 1; border.color: eapPassword.activeFocus ? Theme.blueBright : Theme.bg3
                    Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
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
                    Layout.fillWidth: true; height: 30; radius: Theme.btnRadius
                    color: connEapA.containsMouse ? Theme.blueBright : Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    scale: connEapA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { anchors.centerIn: parent; text: "Sign In"; color: connEapA.containsMouse ? Theme.bg : Theme.fg
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    MouseArea { id: connEapA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.submitEnterprise(eapIdentity.text, eapPassword.text) }
                }

                Text { text: "Only PEAP/MSCHAPv2 is supported."; color: Theme.fg4; wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 2; Layout.fillWidth: true }
            }

            // ── CONNECTING ────────────────────────────────────
            ColumnLayout {
                visible: wifiPop.popupState === "connecting"
                opacity: wifiPop.popupState === "connecting" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                Layout.fillWidth: true; spacing: 8; Layout.alignment: Qt.AlignHCenter

                Text { text: "Connecting to " + wifiPop.targetSsid + "…"; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter; width: 120; height: 4; radius: 2; color: Theme.bg3
                    Rectangle {
                        height: parent.height; radius: parent.radius; color: Theme.blueBright
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
