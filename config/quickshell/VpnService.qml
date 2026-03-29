pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // ── Mullvad state ──
    readonly property string mullvadState: _mullvadState      // connected | connecting | disconnected | disconnecting | error
    readonly property string mullvadCountry: _mullvadCountry
    readonly property string mullvadCity: _mullvadCity
    readonly property string mullvadIp: _mullvadIp

    // ── Tailscale state ──
    readonly property string tailscaleState: _tailscaleState   // running | stopped | needs-login | starting
    readonly property string tailscaleTailnet: _tailscaleTailnet
    readonly property string tailscaleIp: _tailscaleIp
    readonly property bool tailscaleExitNode: _tailscaleExitNode

    // ── Internal staging ──
    property string _mullvadState: "disconnected"
    property string _mullvadCountry: ""
    property string _mullvadCity: ""
    property string _mullvadIp: ""
    property string _mullvadBuf: ""

    property string _tailscaleState: "stopped"
    property string _tailscaleTailnet: ""
    property string _tailscaleIp: ""
    property bool _tailscaleExitNode: false
    property string _tailscaleBuf: ""

    // ── Public API ──

    function refresh() {
        _mullvadBuf = "";
        mullvadProc.running = true;
        _tailscaleBuf = "";
        tailscaleProc.running = true;
    }

    function mullvadConnect() {
        mullvadConnectProc.running = true;
    }

    function mullvadDisconnect() {
        mullvadDisconnectProc.running = true;
    }

    function tailscaleUp() {
        tailscaleUpProc.running = true;
    }

    function tailscaleDown() {
        tailscaleDownProc.running = true;
    }

    // ── Mullvad status ──

    property Process mullvadProc: Process {
        command: ["mullvad", "status", "-j"]
        running: true
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
        }
    }

    // ── Tailscale status ──

    property Process tailscaleProc: Process {
        command: ["tailscale", "status", "--json"]
        running: true
        stdout: SplitParser {
            onRead: (line) => { root._tailscaleBuf += line; }
        }
        onExited: (code, status) => {
            if (root._tailscaleBuf) {
                try {
                    let d = JSON.parse(root._tailscaleBuf);
                    let bs = d.BackendState || "";
                    if (bs === "Running") root._tailscaleState = "running";
                    else if (bs === "NeedsLogin" || bs === "NeedsMachineAuth") root._tailscaleState = "needs-login";
                    else if (bs === "Starting") root._tailscaleState = "starting";
                    else root._tailscaleState = "stopped";

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
                    root._tailscaleTailnet = "";
                    root._tailscaleIp = "";
                    root._tailscaleExitNode = false;
                }
            }
            root._tailscaleBuf = "";
        }
    }

    // ── Action processes ──

    property Process mullvadConnectProc: Process {
        command: ["mullvad", "connect"]
        running: false
        onExited: () => { root._mullvadBuf = ""; mullvadProc.running = true; }
    }

    property Process mullvadDisconnectProc: Process {
        command: ["mullvad", "disconnect"]
        running: false
        onExited: () => { root._mullvadBuf = ""; mullvadProc.running = true; }
    }

    property Process tailscaleUpProc: Process {
        command: ["tailscale", "up"]
        running: false
        onExited: () => { root._tailscaleBuf = ""; tailscaleProc.running = true; }
    }

    property Process tailscaleDownProc: Process {
        command: ["tailscale", "down"]
        running: false
        onExited: () => { root._tailscaleBuf = ""; tailscaleProc.running = true; }
    }

    // ── Poll timer ──

    property Timer pollTimer: Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
