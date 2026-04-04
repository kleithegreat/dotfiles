import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../wifi" as Wifi

FocusScope {
    id: root
    anchors.fill: parent

    property string paneState: "list"   // list | detail | password | enterprise | connecting | diagnostics | channels | vpnCountries | vpnCities
    property bool listLoading: paneState === "list"
        && ((!NetworkService.wifiRadioReady && NetworkService.wifiRadioBusy)
            || (NetworkService.wifiEnabled && NetworkService.scanning && NetworkService.networksModel.count === 0))
    property bool channelLoading: paneState === "channels" && NetworkService.channelScanning
    property string mullvadBrowseCountryCode: ""
    property string mullvadBrowseCountryName: ""
    property var mullvadBrowseCities: []
    readonly property bool wifiPoweredOff: NetworkService.wifiRadioReady && !NetworkService.wifiEnabled
    readonly property bool mullvadLocationView: paneState === "vpnCountries" || paneState === "vpnCities"
    readonly property bool mullvadLocationLoading: VpnService.mullvadRelayListLoading && VpnService.mullvadRelayCountries.length === 0
    readonly property bool mullvadLocationEmpty: paneState === "vpnCountries"
        ? VpnService.mullvadRelayCountries.length === 0
        : mullvadBrowseCities.length === 0

    readonly property bool mullvadOn: VpnService.mullvadState === "connected" || VpnService.mullvadState === "connecting"
    readonly property bool tailscaleOn: VpnService.tailscaleState === "running" || VpnService.tailscaleState === "starting"
    readonly property string mullvadSelectedLocation: {
        let label = VpnService.mullvadSelectedLocationLabel;
        if (label)
            return label;
        if (VpnService.mullvadRelaySelectionLoading)
            return "Loading…";
        return "Any country";
    }

    readonly property string mullvadStatus: {
        let s = VpnService.mullvadState;
        if (s === "connected") {
            let loc = VpnService.mullvadCity || VpnService.mullvadCountry;
            return loc ? "Connected — " + loc : "Connected";
        }
        if (s === "connecting") return "Connecting…";
        if (s === "disconnecting") return "Disconnecting…";
        if (s === "error") return "Error";
        return "Disconnected";
    }

    readonly property string tailscaleStatus: {
        let s = VpnService.tailscaleState;
        if (s === "running") return "Running";
        if (s === "starting") return "Starting…";
        if (s === "needs-login") return "Needs Login";
        return "Stopped";
    }

    Component.onCompleted: {
        NetworkService.scan();
        NetworkService.loadKnown();
        VpnService.refresh();
        VpnService.ensureMullvadRelayLocations();
    }

    Connections {
        target: NetworkService
        function onConnectSucceeded() { root.paneState = "list"; }
        function onConnectFailed() { root.paneState = "list"; }
        function onDisconnected() { root.paneState = "list"; }
        function onNetworkForgotten() { root.paneState = "list"; }
        function onWifiEnabledChanged() {
            if (!NetworkService.wifiEnabled && root.isWifiSubpane(root.paneState))
                root.resetState();
        }
    }

    Connections {
        target: VpnService
        function onMullvadRelayCountriesChanged() {
            if (root.paneState === "vpnCities" && root.mullvadBrowseCountryCode)
                root.openMullvadCities(root.mullvadBrowseCountryCode);
        }
    }

    function clearMullvadBrowse() {
        mullvadBrowseCountryCode = "";
        mullvadBrowseCountryName = "";
        mullvadBrowseCities = [];
    }

    function resetState() {
        paneState = "list";
        clearMullvadBrowse();
        NetworkService.resetTarget();
    }

    function isWifiSubpane(state) {
        return state === "detail"
            || state === "password"
            || state === "enterprise"
            || state === "connecting"
            || state === "diagnostics"
            || state === "channels";
    }

    function goBack() {
        if (paneState === "channels")
            paneState = "diagnostics";
        else if (paneState === "vpnCities")
            paneState = "vpnCountries";
        else
            resetState();
    }

    function connectTo(ssid, security) {
        paneState = NetworkService.connectTo(ssid, security);
    }

    function submitPassword(password) {
        if (!password) return;
        paneState = "connecting";
        NetworkService.submitPassword(password);
    }

    function submitEnterprise(identity, password) {
        if (!identity || !password) return;
        paneState = "connecting";
        NetworkService.submitEnterprise(identity, password);
    }

    function openDetail(ssid, security, signal, isActive) {
        NetworkService.openDetail(ssid, security, signal, isActive);
        paneState = "detail";
    }

    function startDiagnostics() {
        NetworkService.startDiagnostics();
        paneState = "diagnostics";
    }

    function startChannelScan() {
        NetworkService.startChannelScan();
        paneState = "channels";
    }

    function openMullvadLocations() {
        VpnService.refreshMullvadRelayLocations();
        paneState = "vpnCountries";
    }

    function openMullvadCities(countryCode) {
        let country = VpnService.mullvadCountryEntry(countryCode);
        if (!country) {
            paneState = "vpnCountries";
            return;
        }

        mullvadBrowseCountryCode = country.code;
        mullvadBrowseCountryName = country.name;
        mullvadBrowseCities = Array.isArray(country.cities) ? country.cities : [];
        paneState = "vpnCities";
    }

    function selectMullvadLocation(countryCode, cityCode) {
        VpnService.mullvadSetLocation(countryCode, cityCode || "");
    }

    function selectionTint(color, alpha) {
        if (alpha === undefined)
            alpha = 0.12;
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function mullvadCountryDetailText(country) {
        let parts = [];
        if (VpnService.mullvadSelectedCountryCode === country.code && VpnService.mullvadSelectedCity)
            parts.push("Selected: " + VpnService.mullvadSelectedCity);
        else
            parts.push(country.cityCount === 1 ? "1 city" : country.cityCount + " cities");

        if (country.relayCount > 0)
            parts.push(country.relayCount === 1 ? "1 relay" : country.relayCount + " relays");

        return parts.join(" · ");
    }

    function mullvadCityDetailText(city) {
        return city.relayCount === 1 ? "1 relay" : city.relayCount + " relays";
    }

    Keys.onEscapePressed: {
        if (root.paneState !== "list") root.goBack();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── Header ───────────────────────────────────────────

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: {
                    if (root.paneState === "detail")      return "󰖩  " + NetworkService.targetSsid;
                    if (root.paneState === "password")    return "󰌾  Password";
                    if (root.paneState === "enterprise")  return "󱄤  Sign In";
                    if (root.paneState === "connecting")  return "󰖩  Connecting…";
                    if (root.paneState === "diagnostics") return "󰖩  Diagnostics";
                    if (root.paneState === "channels")    return "󰐻  Channels";
                    if (root.paneState === "vpnCountries") return "󰒃  Mullvad Locations";
                    if (root.paneState === "vpnCities")    return "󰒃  " + root.mullvadBrowseCountryName;
                    return "󰖩  Wi-Fi";
                }
                color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true
                Layout.fillWidth: true; elide: Text.ElideRight
            }

            Rectangle {
                visible: root.paneState !== "list" && root.paneState !== "connecting"
                width: backLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                color: "transparent"
                Components.HoverLayer {
                    id: backA; color: Theme.bg2; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                    onClicked: root.goBack()
                    Text { id: backLabel; anchors.centerIn: parent; text: "← Back"
                        color: backA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }

            Rectangle {
                visible: root.mullvadLocationView
                width: refreshLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                color: "transparent"
                Components.HoverLayer {
                    id: refreshA; color: Theme.bg2; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                    disabled: VpnService.mullvadRelayListLoading
                    onClicked: VpnService.refreshMullvadRelayLocations(true)
                    Text { id: refreshLabel; anchors.centerIn: parent
                        text: VpnService.mullvadRelayListLoading ? "Refreshing…" : "Refresh"
                        color: refreshA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }

            Rectangle {
                visible: root.paneState === "list" && NetworkService.wifiEnabled
                width: rescanLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                color: "transparent"
                Components.HoverLayer {
                    id: rescanA; color: Theme.bg2; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                    onClicked: NetworkService.scan()
                    Text { id: rescanLabel; anchors.centerIn: parent; text: "Rescan"
                        color: rescanA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }
        }

        RowLayout {
            visible: HostCapabilities.hasWifi
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Power"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Components.ToggleSwitch {
                checked: NetworkService.wifiEnabled
                onToggled: NetworkService.toggleWifiRadio()
            }
        }

        // ── Error message ────────────────────────────────────

        Item {
            Layout.fillWidth: true; visible: NetworkService.connectError !== ""
            implicitHeight: netErrorText.implicitHeight
            Text { id: netErrorText; width: parent.width
                text: NetworkService.connectError; color: Theme.redBright
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        // ── LIST state: WiFi list + VPN ──────────────────────

        Item {
            visible: root.paneState === "list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Wifi.WifiList {
                        anchors.fill: parent
                        visible: NetworkService.wifiEnabled || root.listLoading
                        opacity: root.listLoading ? 0 : 1
                        enabled: opacity > 0.01
                        Behavior on opacity {
                            Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                        }
                        netModel: NetworkService.networksModel
                        connectedSsid: NetworkService.connectedSsid
                        isCaptivePortal: NetworkService.isCaptivePortal
                        onConnectRequested: (ssid, security) => root.connectTo(ssid, security)
                        onDetailRequested: (ssid, security, signal, isActive) => root.openDetail(ssid, security, signal, isActive)
                        onCaptiveLoginRequested: NetworkService.openCaptivePortal()
                    }

                    Item {
                        anchors.fill: parent
                        visible: root.wifiPoweredOff && !root.listLoading

                        Text {
                            anchors.centerIn: parent
                            text: "Wi-Fi is off"
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    Column {
                        anchors.fill: parent; anchors.topMargin: 4
                        spacing: 0
                        opacity: root.listLoading ? 1 : 0
                        visible: opacity > 0; z: 1
                        Behavior on opacity {
                            Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                        }

                        Repeater {
                            model: ListModel {
                                ListElement { skelWidth: 120 }
                                ListElement { skelWidth: 90 }
                                ListElement { skelWidth: 150 }
                                ListElement { skelWidth: 105 }
                            }
                            delegate: Item {
                                required property int skelWidth
                                required property int index
                                width: parent.width; height: 36

                                RowLayout {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: 8
                                    Rectangle { width: 18; height: 18; radius: 9; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                    Item { Layout.fillWidth: true }
                                    Rectangle { width: 10; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { width: 28; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                    Rectangle { width: 24; height: 24; radius: 12; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                }

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 120 }
                                    Components.Anim { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                    Components.Anim { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                                }
                            }
                        }
                    }
                }

                // ── VPN section ──────────────────────────────

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 8 }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 6

                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "󰒃  Mullvad"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true }
                        Text {
                            text: root.mullvadStatus
                            color: VpnService.mullvadState === "connected" ? Theme.fg3
                                 : VpnService.mullvadState === "error" ? Theme.redBright
                                 : Theme.fg4
                            Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        }
                        Components.ToggleSwitch {
                            checked: root.mullvadOn
                            onToggled: root.mullvadOn ? VpnService.mullvadDisconnect() : VpnService.mullvadConnect()
                        }
                    }
                    Text {
                        visible: VpnService.mullvadState === "connected" && VpnService.mullvadIp
                        text: VpnService.mullvadIp
                        color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Location"
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Text {
                            text: root.mullvadSelectedLocation
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            width: browseLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: "transparent"
                            Components.HoverLayer {
                                id: browseA; color: Theme.bg2; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                                onClicked: root.openMullvadLocations()
                                Text { id: browseLabel; anchors.centerIn: parent; text: "Browse"
                                    color: browseA.containsMouse ? Theme.blueBright : Theme.fg4
                                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                            }
                        }
                    }
                    Text {
                        visible: VpnService.mullvadRelaySetting
                        text: "Applying location…"
                        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: VpnService.mullvadRelayError !== ""
                        text: VpnService.mullvadRelayError
                        color: Theme.redBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: "󰛳  Tailscale"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true }
                        Text {
                            text: root.tailscaleStatus
                            color: VpnService.tailscaleState === "running" ? Theme.fg3
                                 : VpnService.tailscaleState === "needs-login" ? Theme.yellowBright
                                 : Theme.fg4
                            Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        }
                        Components.ToggleSwitch {
                            checked: root.tailscaleOn
                            onToggled: root.tailscaleOn ? VpnService.tailscaleDown() : VpnService.tailscaleUp()
                        }
                    }
                    Text {
                        visible: VpnService.tailscaleState === "running" && (VpnService.tailscaleTailnet || VpnService.tailscaleIp)
                        text: {
                            let parts = [];
                            if (VpnService.tailscaleTailnet) parts.push(VpnService.tailscaleTailnet);
                            if (VpnService.tailscaleIp) parts.push(VpnService.tailscaleIp);
                            if (VpnService.tailscaleExitNode) parts.push("Exit Node");
                            return parts.join(" · ");
                        }
                        color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
            }
        }

        Item {
            visible: root.mullvadLocationView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.hoverRadius
                    color: Theme.bg2
                    border.width: 1
                    border.color: Theme.bg3
                    implicitHeight: locationSummaryCol.implicitHeight + 16

                    ColumnLayout {
                        id: locationSummaryCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        Text {
                            text: "Selected location"
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall - 1
                        }
                        Text {
                            text: root.mullvadSelectedLocation
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: root.paneState === "vpnCountries"
                                ? "Choose a country, then optionally narrow it to a city."
                                : "Choose a city or keep an automatic city in " + root.mullvadBrowseCountryName + "."
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall - 1
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }

                Text {
                    visible: VpnService.mullvadRelaySetting
                    text: "Applying location…"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                    Layout.fillWidth: true
                }

                Text {
                    visible: VpnService.mullvadRelayError !== ""
                    text: VpnService.mullvadRelayError
                    color: Theme.redBright
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Column {
                        anchors.fill: parent; anchors.topMargin: 4
                        spacing: 6
                        opacity: root.mullvadLocationLoading ? 1 : 0
                        visible: opacity > 0
                        z: 1
                        Behavior on opacity {
                            Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                        }

                        Repeater {
                            model: ListModel {
                                ListElement { skelWidth: 160 }
                                ListElement { skelWidth: 190 }
                                ListElement { skelWidth: 140 }
                                ListElement { skelWidth: 170 }
                            }
                            delegate: Item {
                                required property int skelWidth
                                required property int index
                                width: parent.width; height: 52

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.hoverRadius
                                    color: Theme.bg2
                                    opacity: 0.5
                                }

                                ColumnLayout {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: Theme.listItemPadding
                                    spacing: 6
                                    Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3 }
                                    Rectangle { width: Math.max(80, skelWidth - 40); height: 8; radius: 4; color: Theme.bg3 }
                                }

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 120 }
                                    Components.Anim { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                    Components.Anim { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                                }
                            }
                        }
                    }

                    Components.WheelFlickable {
                        anchors.fill: parent
                        visible: !root.mullvadLocationLoading && !root.mullvadLocationEmpty
                        contentHeight: locationCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: locationCol
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                visible: root.paneState === "vpnCountries"
                                width: parent.width
                                height: anyCountryCol.implicitHeight + 16
                                radius: Theme.hoverRadius
                                color: VpnService.mullvadSelectedCountryCode === "any" && !VpnService.mullvadSelectedCityCode && !VpnService.mullvadSelectedHostname
                                    ? root.selectionTint(Theme.blueBright)
                                    : "transparent"
                                border.width: VpnService.mullvadSelectedCountryCode === "any" && !VpnService.mullvadSelectedCityCode && !VpnService.mullvadSelectedHostname ? 1 : 0
                                border.color: Theme.blueBright

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: Theme.bg2
                                    opacity: anyCountryArea.pressed ? 0.9 : (anyCountryArea.containsMouse ? 0.6 : 0)
                                    Behavior on opacity {
                                        Components.Anim {
                                            duration: Theme.animHover
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.animCurveStandard
                                        }
                                    }
                                }
                                scale: anyCountryArea.pressed ? 0.98 : 1.0
                                Behavior on scale {
                                    Components.Anim {
                                        duration: Theme.animMicro
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                                transformOrigin: Item.Center

                                ColumnLayout {
                                    id: anyCountryCol
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.listItemPadding
                                    anchors.rightMargin: Theme.listItemPadding
                                    anchors.topMargin: 8
                                    anchors.bottomMargin: 8
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Any country"
                                            color: VpnService.mullvadSelectedCountryCode === "any" && !VpnService.mullvadSelectedCityCode && !VpnService.mullvadSelectedHostname ? Theme.blueBright : Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: VpnService.mullvadSelectedCountryCode === "any" && !VpnService.mullvadSelectedCityCode && !VpnService.mullvadSelectedHostname ? "󰄬" : ""
                                            color: Theme.blueBright
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }

                                    Text {
                                        text: "Let Mullvad pick any country."
                                        color: Theme.fg4
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        Layout.fillWidth: true
                                    }
                                }

                                Components.HoverLayer {
                                    id: anyCountryArea
                                    hoverOpacity: 0
                                    pressedOpacity: 0
                                    pressedScale: 1.0
                                    disabled: VpnService.mullvadRelaySetting
                                    onClicked: root.selectMullvadLocation("any", "")
                                }
                            }

                            Rectangle {
                                visible: root.paneState === "vpnCities"
                                width: parent.width
                                height: anyCityCol.implicitHeight + 16
                                radius: Theme.hoverRadius
                                color: VpnService.mullvadSelectedCountryCode === root.mullvadBrowseCountryCode && !VpnService.mullvadSelectedCityCode && !VpnService.mullvadSelectedHostname
                                    ? root.selectionTint(Theme.blueBright)
                                    : "transparent"
                                border.width: VpnService.mullvadSelectedCountryCode === root.mullvadBrowseCountryCode && !VpnService.mullvadSelectedCityCode && !VpnService.mullvadSelectedHostname ? 1 : 0
                                border.color: Theme.blueBright

                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: Theme.bg2
                                    opacity: anyCityArea.pressed ? 0.9 : (anyCityArea.containsMouse ? 0.6 : 0)
                                    Behavior on opacity {
                                        Components.Anim {
                                            duration: Theme.animHover
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.animCurveStandard
                                        }
                                    }
                                }
                                scale: anyCityArea.pressed ? 0.98 : 1.0
                                Behavior on scale {
                                    Components.Anim {
                                        duration: Theme.animMicro
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                                transformOrigin: Item.Center

                                ColumnLayout {
                                    id: anyCityCol
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.listItemPadding
                                    anchors.rightMargin: Theme.listItemPadding
                                    anchors.topMargin: 8
                                    anchors.bottomMargin: 8
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            text: "Any city in " + root.mullvadBrowseCountryName
                                            color: VpnService.mullvadSelectedCountryCode === root.mullvadBrowseCountryCode && !VpnService.mullvadSelectedCityCode && !VpnService.mullvadSelectedHostname ? Theme.blueBright : Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: VpnService.mullvadSelectedCountryCode === root.mullvadBrowseCountryCode && !VpnService.mullvadSelectedCityCode && !VpnService.mullvadSelectedHostname ? "󰄬" : ""
                                            color: Theme.blueBright
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }

                                    Text {
                                        text: "Let Mullvad pick any city in this country."
                                        color: Theme.fg4
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        Layout.fillWidth: true
                                    }
                                }

                                Components.HoverLayer {
                                    id: anyCityArea
                                    hoverOpacity: 0
                                    pressedOpacity: 0
                                    pressedScale: 1.0
                                    disabled: VpnService.mullvadRelaySetting
                                    onClicked: root.selectMullvadLocation(root.mullvadBrowseCountryCode, "")
                                }
                            }

                            Repeater {
                                model: root.paneState === "vpnCountries" ? VpnService.mullvadRelayCountries : root.mullvadBrowseCities

                                Rectangle {
                                    required property var modelData

                                    readonly property bool countryMode: root.paneState === "vpnCountries"
                                    readonly property bool selected: countryMode
                                        ? VpnService.mullvadSelectedCountryCode === modelData.code
                                        : VpnService.mullvadSelectedCountryCode === root.mullvadBrowseCountryCode
                                            && VpnService.mullvadSelectedCityCode === modelData.code
                                            && !VpnService.mullvadSelectedHostname

                                    width: parent.width
                                    height: locationRowCol.implicitHeight + 16
                                    radius: Theme.hoverRadius
                                    color: selected ? root.selectionTint(Theme.blueBright) : "transparent"
                                    border.width: selected ? 1 : 0
                                    border.color: Theme.blueBright

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: Theme.bg2
                                        opacity: locationArea.pressed ? 0.9 : (locationArea.containsMouse ? 0.6 : 0)
                                        Behavior on opacity {
                                            Components.Anim {
                                                duration: Theme.animHover
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Theme.animCurveStandard
                                            }
                                        }
                                    }
                                    scale: locationArea.pressed ? 0.98 : 1.0
                                    Behavior on scale {
                                        Components.Anim {
                                            duration: Theme.animMicro
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.animCurveStandard
                                        }
                                    }
                                    transformOrigin: Item.Center

                                    ColumnLayout {
                                        id: locationRowCol
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.listItemPadding
                                        anchors.rightMargin: Theme.listItemPadding
                                        anchors.topMargin: 8
                                        anchors.bottomMargin: 8
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                text: modelData.name
                                                color: selected ? Theme.blueBright : Theme.fg
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.bold: true
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: countryMode ? "→" : (selected ? "󰄬" : "")
                                                color: selected ? Theme.blueBright : Theme.fg4
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSmall
                                            }
                                        }

                                        Text {
                                            text: countryMode ? root.mullvadCountryDetailText(modelData) : root.mullvadCityDetailText(modelData)
                                            color: Theme.fg4
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Components.HoverLayer {
                                        id: locationArea
                                        hoverOpacity: 0
                                        pressedOpacity: 0
                                        pressedScale: 1.0
                                        disabled: VpnService.mullvadRelaySetting
                                        onClicked: {
                                            if (countryMode)
                                                root.openMullvadCities(modelData.code);
                                            else
                                                root.selectMullvadLocation(root.mullvadBrowseCountryCode, modelData.code);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.mullvadLocationLoading && root.mullvadLocationEmpty
                        text: root.paneState === "vpnCountries"
                            ? "No Mullvad locations available."
                            : "No cities available for " + root.mullvadBrowseCountryName + "."
                        color: Theme.fg4
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        width: Math.min(parent.width, 260)
                    }
                }
            }
        }

        // ── DETAIL state ─────────────────────────────────────

        Wifi.WifiDetail {
            visible: root.paneState === "detail"
            opacity: root.paneState === "detail" ? 1 : 0
            Behavior on opacity {
                Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
            }
            Layout.fillWidth: true
            targetSsid: NetworkService.targetSsid
            targetSecurity: NetworkService.targetSecurity
            targetSignal: NetworkService.targetSignal
            targetIsConnected: NetworkService.targetIsConnected
            targetIsKnown: NetworkService.targetIsKnown
            detailIp: NetworkService.detailIp
            detailGateway: NetworkService.detailGateway
            detailDns: NetworkService.detailDns
            detailFreq: NetworkService.detailFreq
            connectError: NetworkService.connectError
            onConnectRequested: (ssid, security) => root.connectTo(ssid, security)
            onDisconnectRequested: NetworkService.disconnect()
            onForgetRequested: NetworkService.forgetNetwork()
            onDiagnosticsRequested: root.startDiagnostics()
        }

        // ── PASSWORD state ───────────────────────────────────

        Wifi.WifiPassword {
            visible: root.paneState === "password"
            opacity: root.paneState === "password" ? 1 : 0
            Behavior on opacity {
                Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
            }
            Layout.fillWidth: true
            targetSsid: NetworkService.targetSsid
            connectError: NetworkService.connectError
            onPasswordSubmitted: (pw) => root.submitPassword(pw)
            onBackRequested: root.resetState()
        }

        // ── ENTERPRISE state ─────────────────────────────────

        Wifi.WifiEnterprise {
            visible: root.paneState === "enterprise"
            opacity: root.paneState === "enterprise" ? 1 : 0
            Behavior on opacity {
                Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
            }
            Layout.fillWidth: true
            targetSsid: NetworkService.targetSsid
            connectError: NetworkService.connectError
            onEnterpriseSubmitted: (identity, password) => root.submitEnterprise(identity, password)
            onBackRequested: root.resetState()
        }

        // ── CONNECTING state ─────────────────────────────────

        Wifi.WifiConnecting {
            visible: root.paneState === "connecting"
            opacity: root.paneState === "connecting" ? 1 : 0
            Behavior on opacity {
                Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
            }
            Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
            targetSsid: NetworkService.targetSsid
        }

        // ── DIAGNOSTICS state ────────────────────────────────

        Wifi.WifiDiagnostics {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: root.paneState === "diagnostics"
            opacity: root.paneState === "diagnostics" ? 1 : 0
            Behavior on opacity {
                Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
            }
            diagLoading: NetworkService.diagLoading
            speedTestRunning: NetworkService.speedTestRunning
            connectedSsid: NetworkService.connectedSsid
            exportCopied: NetworkService.exportCopied
            diagBand: NetworkService.diagBand
            diagSignal: NetworkService.diagSignal
            diagNoise: NetworkService.diagNoise
            diagLinkRate: NetworkService.diagLinkRate
            diagGateway: NetworkService.diagGateway
            diagGwPing: NetworkService.diagGwPing
            diagGwJitter: NetworkService.diagGwJitter
            diagGwLoss: NetworkService.diagGwLoss
            diagNetPing: NetworkService.diagNetPing
            diagNetJitter: NetworkService.diagNetJitter
            diagNetLoss: NetworkService.diagNetLoss
            diagDnsServer: NetworkService.diagDnsServer
            diagDnsTime: NetworkService.diagDnsTime
            diagDownload: NetworkService.diagDownload
            diagUpload: NetworkService.diagUpload
            diagBufferbloat: NetworkService.diagBufferbloat
            diagBufferbloatOk: NetworkService.diagBufferbloatOk
            diagWifiStandard: NetworkService.diagWifiStandard
            histSignal: NetworkService.histSignal
            histNoise: NetworkService.histNoise
            histGwPing: NetworkService.histGwPing
            histGwJitter: NetworkService.histGwJitter
            histGwLoss: NetworkService.histGwLoss
            histNetPing: NetworkService.histNetPing
            histNetJitter: NetworkService.histNetJitter
            histNetLoss: NetworkService.histNetLoss
            histDnsTime: NetworkService.histDnsTime
            onSpeedTestRequested: NetworkService.startSpeedTest()
            onChannelScanRequested: root.startChannelScan()
            onDnsChanged: (server) => NetworkService.switchDns(server)
            onExportRequested: NetworkService.exportReport()
            onRerunRequested: root.startDiagnostics()
        }

        // ── CHANNELS state ───────────────────────────────────

        Item {
            id: channelSection
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.paneState === "channels"
            clip: true

            Wifi.WifiChannels {
                id: channelView
                anchors.fill: parent
                opacity: root.channelLoading ? 0 : 1
                enabled: opacity > 0.01
                Behavior on opacity {
                    Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                }
                channelModel: NetworkService.channelEntriesModel
                currentChannel: NetworkService.currentChannel
                currentBand: NetworkService.currentBand
                scanning: NetworkService.channelScanning
            }

            ColumnLayout {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                spacing: 8
                opacity: root.channelLoading ? 1 : 0
                visible: opacity > 0; z: 1
                Behavior on opacity {
                    Components.Anim { duration: Theme.animContentSwap; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                }

                Column {
                    Layout.fillWidth: true; spacing: 0

                    Repeater {
                        model: ListModel {
                            ListElement { skelWidth: 120 }
                            ListElement { skelWidth: 150 }
                            ListElement { skelWidth: 100 }
                            ListElement { skelWidth: 140 }
                        }
                        delegate: Item {
                            required property int skelWidth
                            required property int index
                            width: parent.width; height: 52

                            ColumnLayout {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                                RowLayout { spacing: 6
                                    Rectangle { width: 36; height: 10; radius: 5; color: Theme.bg3 }
                                    Rectangle { width: 40; height: 10; radius: 5; color: Theme.bg3 }
                                    Item { Layout.fillWidth: true }
                                    Rectangle { width: 65; height: 10; radius: 5; color: Theme.bg3 }
                                }
                                Rectangle { width: skelWidth; height: 8; radius: 4; color: Theme.bg3 }
                            }

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 120 }
                                Components.Anim { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                Components.Anim { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }
        }
    }
}
