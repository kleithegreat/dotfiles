pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string currentProfile: "unknown"
    property string pendingProfile: ""
    property string backend: "none"
    property string chargeMode: "unknown"
    property int chargeStart: -1
    property int chargeStop: -1
    property bool chargeCfgKnown: false
    property string chargeLimitError: ""
    property string pendingChargeLimit: ""
    property string uncappedChargeMode: "adaptive"
    readonly property int chargeLimitStartValue: 50
    readonly property int chargeLimitStopValue: 80
    readonly property bool chargeLimitBusy: chargeCfgProc.running || chargeSetProc.running
    readonly property bool chargeLimitEnabled: pendingChargeLimit !== "" ? pendingChargeLimit === "capped" : (chargeCfgKnown && chargeMode === "custom")
    readonly property string chargeLimitStateText: {
        if (chargeCfgProc.running) return "Checking…";
        if (chargeSetProc.running) return "Applying…";
        if (!chargeCfgKnown) return "Unknown";
        if (chargeMode === "custom" && chargeStop >= 0) return chargeStop + "%";
        return chargeMode === "custom" ? "Capped" : "Uncapped";
    }
    readonly property string chargeLimitDetailText: {
        if (chargeLimitError !== "") return chargeLimitError;
        if (chargeCfgProc.running) return "Reading current Dell charging configuration";
        if (chargeSetProc.running) {
            return pendingChargeLimit === "capped"
                ? "Setting custom interval to " + chargeLimitStartValue + "%-" + chargeLimitStopValue + "%"
                : "Restoring " + humanizeChargeMode(chargeSetProc.targetMode) + " charging";
        }
        if (!chargeCfgKnown) return "Battery charge limit unavailable";
        if (chargeMode === "custom") {
            if (chargeStart >= 0 && chargeStop >= 0) return "Currently custom " + chargeStart + "%-" + chargeStop + "%";
            return "A custom charging interval is active";
        }
        return "Toggle sets a " + chargeLimitStartValue + "%-" + chargeLimitStopValue + "% custom interval";
    }
    onCurrentProfileChanged: pendingProfile = ""

    function detect() { ppctlProc.running = true; }
    function detectChargeLimit() {
        if (chargeCfgProc.running || chargeSetProc.running) return;
        chargeLimitError = "";
        pendingChargeLimit = "";
        chargeCfgProc.running = true;
    }

    function humanizeChargeMode(mode) {
        if (mode === "primarily_ac") return "Primarily AC";
        if (mode === "adaptive") return "Adaptive";
        if (mode === "custom") return "Custom";
        if (mode === "standard") return "Standard";
        if (mode === "express") return "Express";
        return "Unknown";
    }

    function applyChargeConfigOutput(output) {
        let modeMatch = output.match(/Charging mode:\s*(\S+)/);
        if (!modeMatch) {
            chargeCfgKnown = false;
            chargeMode = "unknown";
            chargeStart = -1;
            chargeStop = -1;
            chargeLimitError = "Unexpected charging config output";
            return;
        }

        chargeMode = modeMatch[1].trim();
        chargeCfgKnown = true;
        chargeLimitError = "";

        let intervalMatch = output.match(/Charging interval:\s*\((\d+),\s*(\d+)\)/);
        if (chargeMode === "custom" && intervalMatch) {
            chargeStart = parseInt(intervalMatch[1], 10);
            chargeStop = parseInt(intervalMatch[2], 10);
        } else {
            chargeStart = -1;
            chargeStop = -1;
        }

        if (chargeMode !== "custom" && chargeMode !== "unknown") uncappedChargeMode = chargeMode;
    }

    function setProfile(profile) {
        pendingProfile = profile;
        if (backend === "ppctl") {
            setProc.command = ["powerprofilesctl", "set", profile];
        } else {
            let m = profile === "performance" ? "performance" : (profile === "power-saver" ? "powersave" : "reset");
            if (m === "reset") setProc.command = ["pkexec", "auto-cpufreq", "--force=reset"];
            else setProc.command = ["pkexec", "auto-cpufreq", "--force=" + m];
        }
        setProc.running = true;
        refreshTimer.restart();
        pendingTimeout.restart();
    }

    function setChargeLimit(enabled) {
        if (chargeLimitBusy) return;

        chargeLimitError = "";
        pendingChargeLimit = enabled ? "capped" : "uncapped";

        if (enabled) {
            if (chargeCfgKnown && chargeMode !== "custom" && chargeMode !== "unknown")
                uncappedChargeMode = chargeMode;
            chargeSetProc.targetEnabled = true;
            chargeSetProc.targetMode = "custom";
            chargeSetProc.command = [
                "pkexec",
                "smbios-battery-ctl",
                "--set-charging-mode=custom",
                "--set-custom-charge-interval",
                chargeLimitStartValue.toString(),
                chargeLimitStopValue.toString()
            ];
        } else {
            let targetMode = (uncappedChargeMode !== "" && uncappedChargeMode !== "custom" && uncappedChargeMode !== "unknown")
                ? uncappedChargeMode
                : "adaptive";
            chargeSetProc.targetEnabled = false;
            chargeSetProc.targetMode = targetMode;
            chargeSetProc.command = ["pkexec", "smbios-battery-ctl", "--set-charging-mode=" + targetMode];
        }

        chargeSetProc.running = true;
    }

    property Timer refreshTimer: Timer { interval: 1500; onTriggered: root.detect() }
    property Timer pendingTimeout: Timer { interval: 3000; onTriggered: root.pendingProfile = "" }

    property Process ppctlProc: Process {
        command: ["powerprofilesctl", "get"]; running: false
        stdout: SplitParser { onRead: (line) => { root.backend = "ppctl"; root.currentProfile = line.trim(); } }
        onExited: (code, status) => { if (code !== 0) { root.backend = "autocpufreq"; govProc.running = true; } }
    }
    property Process govProc: Process {
        command: ["cat", "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let g = line.trim();
            if (g === "performance") root.currentProfile = "performance";
            else if (g === "powersave") root.currentProfile = "power-saver";
            else root.currentProfile = "balanced";
        } }
    }
    property Process setProc: Process { running: false }
    property Process chargeCfgProc: Process {
        command: ["pkexec", "smbios-battery-ctl", "--get-charging-cfg"]
        running: false
        property string buf: ""
        property string errBuf: ""
        onRunningChanged: if (running) {
            buf = "";
            errBuf = "";
            root.chargeCfgKnown = false;
            root.chargeMode = "unknown";
            root.chargeStart = -1;
            root.chargeStop = -1;
        }
        stdout: SplitParser { onRead: (line) => { chargeCfgProc.buf += line + "\n"; } }
        stderr: SplitParser { onRead: (line) => { chargeCfgProc.errBuf += line + "\n"; } }
        onExited: (code) => {
            if (code === 0) root.applyChargeConfigOutput(chargeCfgProc.buf);
            else root.chargeLimitError = chargeCfgProc.errBuf.trim() !== "" ? chargeCfgProc.errBuf.trim() : "Unable to read battery charge limit";
            chargeCfgProc.buf = "";
            chargeCfgProc.errBuf = "";
        }
    }
    property Process chargeSetProc: Process {
        running: false
        property bool targetEnabled: false
        property string targetMode: "adaptive"
        property string errBuf: ""
        onRunningChanged: if (running) errBuf = ""
        stderr: SplitParser { onRead: (line) => { chargeSetProc.errBuf += line + "\n"; } }
        onExited: (code) => {
            if (code === 0) {
                root.chargeCfgKnown = true;
                root.chargeLimitError = "";
                root.chargeMode = chargeSetProc.targetEnabled ? "custom" : chargeSetProc.targetMode;
                if (chargeSetProc.targetEnabled) {
                    root.chargeStart = root.chargeLimitStartValue;
                    root.chargeStop = root.chargeLimitStopValue;
                } else {
                    root.chargeStart = -1;
                    root.chargeStop = -1;
                    root.uncappedChargeMode = chargeSetProc.targetMode;
                }
            } else {
                root.chargeLimitError = chargeSetProc.errBuf.trim() !== "" ? chargeSetProc.errBuf.trim() : "Unable to update battery charge limit";
            }

            root.pendingChargeLimit = "";
            chargeSetProc.errBuf = "";
        }
    }
}
