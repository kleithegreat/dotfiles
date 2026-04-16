pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // ── Mullvad state ──
    readonly property string mullvadPendingAction: _mullvadPendingAction
    readonly property bool mullvadBusy: mullvadConnectProc.running || mullvadDisconnectProc.running || _mullvadPendingAction !== ""
    readonly property string mullvadState: {
        if (_mullvadPendingAction === "connect")
            return "connecting";
        if (_mullvadPendingAction === "disconnect")
            return "disconnecting";
        return _mullvadState;
    }
    readonly property string mullvadCountry: _mullvadCountry
    readonly property string mullvadCity: _mullvadCity
    readonly property string mullvadIp: _mullvadIp
    readonly property var mullvadRelayCountries: _mullvadRelayCountries
    readonly property bool mullvadRelayListLoading: mullvadRelayListProc.running
    readonly property bool mullvadRelaySelectionLoading: mullvadRelayGetProc.running
    readonly property bool mullvadRelaySetting: mullvadSetLocationProc.running
    readonly property string mullvadRelayError: _mullvadRelayError
    readonly property string mullvadSelectedCountryCode: _mullvadSelectedCountryCode
    readonly property string mullvadSelectedCityCode: _mullvadSelectedCityCode
    readonly property string mullvadSelectedHostname: _mullvadSelectedHostname
    readonly property string mullvadSelectedCountry: resolveMullvadCountryName(_mullvadSelectedCountryCode)
    readonly property string mullvadSelectedCity: resolveMullvadCityName(_mullvadSelectedCountryCode, _mullvadSelectedCityCode)
    readonly property string mullvadSelectedLocationLabel: {
        if (_mullvadSelectedHostname)
            return _mullvadSelectedHostname;

        let country = root.mullvadSelectedCountry;
        if (!country)
            return "";

        if (_mullvadSelectedCityCode) {
            let city = root.mullvadSelectedCity;
            return city ? country + " · " + city : country + " · " + _mullvadSelectedCityCode.toUpperCase();
        }

        return country;
    }

    // ── Tailscale state ──
    readonly property string tailscalePendingAction: _tailscalePendingAction
    readonly property bool tailscaleBusy: tailscaleUpProc.running || tailscaleDownProc.running || _tailscalePendingAction !== ""
    readonly property string tailscaleState: {
        if (_tailscalePendingAction === "up")
            return "starting";
        return _tailscaleState;
    }
    readonly property string tailscaleError: _tailscaleError
    readonly property string tailscaleTailnet: _tailscaleTailnet
    readonly property string tailscaleIp: _tailscaleIp
    readonly property bool tailscaleExitNode: _tailscaleExitNode

    // ── Internal staging ──
    property string _mullvadState: "disconnected"
    property string _mullvadCountry: ""
    property string _mullvadCity: ""
    property string _mullvadIp: ""
    property string _mullvadBuf: ""
    property var _mullvadRelayCountries: []
    property var _mullvadRelayCountryIndex: ({})
    property bool _mullvadRelayListLoaded: false
    property string _mullvadRelayListBuf: ""
    property string _mullvadRelayListErrBuf: ""
    property string _mullvadRelayGetBuf: ""
    property string _mullvadRelayGetErrBuf: ""
    property string _mullvadRelayError: ""
    property string _mullvadSelectedCountryCode: ""
    property string _mullvadSelectedCityCode: ""
    property string _mullvadSelectedHostname: ""

    property string _tailscaleState: "stopped"
    property string _tailscaleError: ""
    property string _tailscaleTailnet: ""
    property string _tailscaleIp: ""
    property bool _tailscaleExitNode: false
    property string _tailscaleBuf: ""
    property string _mullvadPendingAction: ""
    property string _tailscalePendingAction: ""
    property bool _mullvadRefreshPending: false
    property bool _mullvadSelectionRefreshPending: false
    property bool _tailscaleRefreshPending: false
    property bool _mullvadActionRefreshPending: false
    property bool _tailscaleActionRefreshPending: false

    Component.onCompleted: refresh()

    // ── Public API ──

    function refresh() {
        refreshMullvadStatus();
        refreshMullvadSelection();
        refreshTailscaleStatus();
    }

    function refreshMullvadStatus() {
        if (mullvadProc.running) {
            _mullvadRefreshPending = true;
            return;
        }
        _mullvadBuf = "";
        mullvadProc.running = true;
    }

    function refreshMullvadSelection() {
        if (mullvadRelayGetProc.running) {
            _mullvadSelectionRefreshPending = true;
            return;
        }
        _mullvadRelayGetBuf = "";
        _mullvadRelayGetErrBuf = "";
        mullvadRelayGetProc.running = true;
    }

    function refreshTailscaleStatus() {
        if (tailscaleProc.running) {
            _tailscaleRefreshPending = true;
            return;
        }
        _tailscaleBuf = "";
        tailscaleProc.running = true;
    }

    function ensureMullvadRelayLocations() {
        refreshMullvadRelayLocations(false);
    }

    function refreshMullvadRelayLocations(force) {
        if (force === undefined)
            force = false;
        if (!force && (_mullvadRelayListLoaded || mullvadRelayListProc.running))
            return;
        _mullvadRelayError = "";
        _mullvadRelayListBuf = "";
        _mullvadRelayListErrBuf = "";
        mullvadRelayListProc.running = true;
    }

    function mullvadConnect() {
        if (mullvadConnectProc.running || mullvadDisconnectProc.running)
            return;
        _mullvadPendingAction = "connect";
        mullvadConnectProc.running = true;
    }

    function mullvadDisconnect() {
        if (mullvadDisconnectProc.running || mullvadConnectProc.running)
            return;
        _mullvadPendingAction = "disconnect";
        mullvadDisconnectProc.running = true;
    }

    function tailscaleUp() {
        if (tailscaleUpProc.running || tailscaleDownProc.running)
            return;
        _tailscaleError = "";
        _tailscalePendingAction = "up";
        tailscaleUpProc.running = true;
    }

    function tailscaleDown() {
        if (tailscaleDownProc.running || tailscaleUpProc.running)
            return;
        _tailscaleError = "";
        _tailscalePendingAction = "down";
        tailscaleDownProc.running = true;
    }

    function mullvadSetLocation(countryCode, cityCode) {
        if (!countryCode || mullvadSetLocationProc.running)
            return;

        let command = ["mullvad", "relay", "set", "location", countryCode];
        if (cityCode)
            command.push(cityCode);

        _mullvadRelayError = "";
        mullvadSetLocationProc.errBuf = "";
        mullvadSetLocationProc.command = command;
        mullvadSetLocationProc.running = true;
    }

    function mullvadCountryEntry(countryCode) {
        if (!countryCode)
            return null;
        return _mullvadRelayCountryIndex[countryCode] || null;
    }

    function mullvadCitiesForCountry(countryCode) {
        let country = mullvadCountryEntry(countryCode);
        return country && Array.isArray(country.cities) ? country.cities : [];
    }

    function mullvadCountryName(countryCode) {
        return resolveMullvadCountryName(countryCode);
    }

    function resolveMullvadCountryName(countryCode) {
        if (!countryCode)
            return "";
        if (countryCode === "any")
            return "Any country";

        let country = _mullvadRelayCountryIndex[countryCode];
        return country ? country.name : countryCode.toUpperCase();
    }

    function resolveMullvadCityName(countryCode, cityCode) {
        if (!cityCode)
            return "";

        let cities = mullvadCitiesForCountry(countryCode);
        for (let i = 0; i < cities.length; i++) {
            if (cities[i].code === cityCode)
                return cities[i].name;
        }

        return cityCode.toUpperCase();
    }

    function normalizeCommandError(errBuf, fallbackMessage) {
        let text = (errBuf || "").trim();
        if (!text)
            return fallbackMessage;

        let lines = text.split(/\r?\n/);
        let compact = [];
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (line !== "")
                compact.push(line);
        }

        return compact.length > 0 ? compact[compact.length - 1] : fallbackMessage;
    }

    function applyMullvadRelayList(text) {
        let countries = [];
        let index = {};
        let currentCountry = null;
        let currentCity = null;
        let lines = (text || "").split(/\r?\n/);

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];
            if (!line)
                continue;

            let countryMatch = line.match(/^([^\t].*?) \(([a-z]{2})\)$/i);
            if (countryMatch) {
                currentCountry = {
                    name: countryMatch[1],
                    code: countryMatch[2],
                    cityCount: 0,
                    relayCount: 0,
                    cities: []
                };
                countries.push(currentCountry);
                index[currentCountry.code] = currentCountry;
                currentCity = null;
                continue;
            }

            let cityMatch = line.match(/^\t(.+?) \(([a-z]{3})\)\s+@/i);
            if (cityMatch && currentCountry) {
                currentCity = {
                    name: cityMatch[1],
                    code: cityMatch[2],
                    relayCount: 0
                };
                currentCountry.cities.push(currentCity);
                currentCountry.cityCount = currentCountry.cities.length;
                continue;
            }

            if (/^\t\t\S+/.test(line) && currentCountry && currentCity) {
                currentCity.relayCount += 1;
                currentCountry.relayCount += 1;
            }
        }

        _mullvadRelayCountries = countries;
        _mullvadRelayCountryIndex = index;
    }

    function applyMullvadRelaySelection(text) {
        let locationLine = (text || "").match(/^\s*Location:\s*(.+)$/m);
        if (!locationLine) {
            _mullvadSelectedCountryCode = "";
            _mullvadSelectedCityCode = "";
            _mullvadSelectedHostname = "";
            return;
        }

        let countryCode = "";
        let cityCode = "";
        let hostname = "";
        let match;
        let tokenMatcher = /\b(country|city|hostname)\s+(\S+)/g;
        while ((match = tokenMatcher.exec(locationLine[1])) !== null) {
            if (match[1] === "country")
                countryCode = match[2];
            else if (match[1] === "city")
                cityCode = match[2];
            else if (match[1] === "hostname")
                hostname = match[2];
        }

        _mullvadSelectedCountryCode = countryCode;
        _mullvadSelectedCityCode = cityCode;
        _mullvadSelectedHostname = hostname;
    }

    // ── Mullvad status ──

    property Process mullvadProc: Process {
        command: ["mullvad", "status", "-j"]
        running: false
        stdout: SplitParser {
            onRead: (line) => { root._mullvadBuf += line; }
        }
        onExited: (code, status) => {
            if (code === 0 && root._mullvadBuf) {
                try {
                    let d = JSON.parse(root._mullvadBuf);
                    root._mullvadState = d.state || "disconnected";
                    let loc = d.details?.location;
                    root._mullvadCountry = loc?.country ?? "";
                    root._mullvadCity = loc?.city ?? "";
                    root._mullvadIp = loc?.ipv4 ?? "";
                } catch (e) {
                    console.log("[VpnService] mullvad parse error:", e);
                }
            }
            root._mullvadBuf = "";
            if (root._mullvadActionRefreshPending) {
                root._mullvadActionRefreshPending = false;
                root._mullvadPendingAction = "";
            }
            if (root._mullvadRefreshPending) {
                root._mullvadRefreshPending = false;
                mullvadProc.running = true;
            }
        }
    }

    property Process mullvadRelayGetProc: Process {
        command: ["mullvad", "relay", "get"]
        running: false
        stdout: SplitParser {
            onRead: (line) => { root._mullvadRelayGetBuf += line + "\n"; }
        }
        stderr: SplitParser {
            onRead: (line) => { root._mullvadRelayGetErrBuf += line + "\n"; }
        }
        onExited: (code, status) => {
            if (code === 0 && root._mullvadRelayGetBuf) {
                root.applyMullvadRelaySelection(root._mullvadRelayGetBuf);
            } else if (code !== 0) {
                console.log("[VpnService] mullvad relay get failed:", root.normalizeCommandError(root._mullvadRelayGetErrBuf, "relay get failed"));
            }
            root._mullvadRelayGetBuf = "";
            root._mullvadRelayGetErrBuf = "";
            if (root._mullvadSelectionRefreshPending) {
                root._mullvadSelectionRefreshPending = false;
                mullvadRelayGetProc.running = true;
            }
        }
    }

    property Process mullvadRelayListProc: Process {
        command: ["mullvad", "relay", "list"]
        running: false
        stdout: SplitParser {
            onRead: (line) => { root._mullvadRelayListBuf += line + "\n"; }
        }
        stderr: SplitParser {
            onRead: (line) => { root._mullvadRelayListErrBuf += line + "\n"; }
        }
        onExited: (code, status) => {
            if (code === 0 && root._mullvadRelayListBuf) {
                root._mullvadRelayError = "";
                root._mullvadRelayListLoaded = true;
                root.applyMullvadRelayList(root._mullvadRelayListBuf);
            } else if (code !== 0) {
                root._mullvadRelayError = root.normalizeCommandError(root._mullvadRelayListErrBuf, "Failed to load Mullvad locations");
                console.log("[VpnService] mullvad relay list failed:", root._mullvadRelayError);
            }
            root._mullvadRelayListBuf = "";
            root._mullvadRelayListErrBuf = "";
        }
    }

    // ── Tailscale status ──

    property Process tailscaleProc: Process {
        command: ["tailscale", "status", "--json"]
        running: false
        stdout: SplitParser {
            onRead: (line) => { root._tailscaleBuf += line; }
        }
        onExited: (code, status) => {
            if (code === 0 && root._tailscaleBuf) {
                try {
                    let d = JSON.parse(root._tailscaleBuf);
                    let bs = d.BackendState || "";
                    if (bs === "Running") root._tailscaleState = "running";
                    else if (bs === "NeedsLogin" || bs === "NeedsMachineAuth") root._tailscaleState = "needs-login";
                    else if (bs === "Starting") root._tailscaleState = "starting";
                    else root._tailscaleState = "stopped";

                    root._tailscaleError = "";
                    root._tailscaleTailnet = d.CurrentTailnet?.Name ?? "";

                    let ips = d.Self?.TailscaleIPs;
                    root._tailscaleIp = (Array.isArray(ips) && ips.length > 0) ? ips[0] : "";

                    let hasExit = false;
                    if (d.Peer) {
                        let keys = Object.keys(d.Peer);
                        for (let i = 0; i < keys.length; i++) {
                            if (d.Peer[keys[i]].ExitNode) {
                                hasExit = true;
                                break;
                            }
                        }
                    }
                    root._tailscaleExitNode = hasExit;
                } catch (e) {
                    root._tailscaleState = "stopped";
                    root._tailscaleError = "Failed to parse Tailscale status";
                    root._tailscaleTailnet = "";
                    root._tailscaleIp = "";
                    root._tailscaleExitNode = false;
                }
            } else if (code !== 0) {
                root._tailscaleError = "Failed to read Tailscale status";
            }
            root._tailscaleBuf = "";
            if (root._tailscaleActionRefreshPending) {
                root._tailscaleActionRefreshPending = false;
                root._tailscalePendingAction = "";
            }
            if (root._tailscaleRefreshPending) {
                root._tailscaleRefreshPending = false;
                tailscaleProc.running = true;
            }
        }
    }

    // ── Action processes ──

    property Process mullvadConnectProc: Process {
        command: ["mullvad", "connect"]
        running: false
        onExited: (code) => {
            if (code === 0) {
                root._mullvadActionRefreshPending = true;
            } else {
                root._mullvadPendingAction = "";
            }
            root.refreshMullvadStatus();
            root.refreshMullvadSelection();
        }
    }

    property Process mullvadDisconnectProc: Process {
        command: ["mullvad", "disconnect"]
        running: false
        onExited: (code) => {
            if (code === 0) {
                root._mullvadActionRefreshPending = true;
            } else {
                root._mullvadPendingAction = "";
            }
            root.refreshMullvadStatus();
            root.refreshMullvadSelection();
        }
    }

    property Process mullvadSetLocationProc: Process {
        property string errBuf: ""
        running: false
        stderr: SplitParser {
            onRead: (line) => { mullvadSetLocationProc.errBuf += line + "\n"; }
        }
        onExited: (code, status) => {
            if (code !== 0)
                root._mullvadRelayError = root.normalizeCommandError(mullvadSetLocationProc.errBuf, "Failed to set Mullvad location");
            else
                root._mullvadRelayError = "";

            mullvadSetLocationProc.errBuf = "";
            root.refreshMullvadStatus();
            root.refreshMullvadSelection();
        }
    }

    property Process tailscaleUpProc: Process {
        command: ["tailscale", "up"]
        running: false
        property string errBuf: ""
        stderr: SplitParser {
            onRead: (line) => { tailscaleUpProc.errBuf += line + "\n"; }
        }
        onExited: (code) => {
            if (code === 0) {
                root._tailscaleError = "";
                root._tailscaleActionRefreshPending = true;
            } else {
                root._tailscaleError = root.normalizeCommandError(tailscaleUpProc.errBuf, "Failed to start Tailscale");
                root._tailscalePendingAction = "";
            }
            tailscaleUpProc.errBuf = "";
            root.refreshTailscaleStatus();
        }
    }

    property Process tailscaleDownProc: Process {
        command: ["tailscale", "down"]
        running: false
        property string errBuf: ""
        stderr: SplitParser {
            onRead: (line) => { tailscaleDownProc.errBuf += line + "\n"; }
        }
        onExited: (code) => {
            if (code === 0) {
                root._tailscaleError = "";
                root._tailscaleActionRefreshPending = true;
            } else {
                root._tailscaleError = root.normalizeCommandError(tailscaleDownProc.errBuf, "Failed to stop Tailscale");
                root._tailscalePendingAction = "";
            }
            tailscaleDownProc.errBuf = "";
            root.refreshTailscaleStatus();
        }
    }

    // ── Poll timer ──

    property Timer pollTimer: Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
