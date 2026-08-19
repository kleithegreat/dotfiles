pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// Battery, CPU power profile, and the Dell charge-limit control.
QtObject {
    id: root

    // ── Battery ────────────────────────────────────────────────────────────

    readonly property var _device: UPower.displayDevice
    readonly property bool present: _device.isPresent
    readonly property real charge: _device.percentage
    readonly property int percent: Math.round(charge * 100)
    readonly property bool charging: _device.state === UPowerDeviceState.Charging || _device.state === UPowerDeviceState.FullyCharged
    readonly property bool full: _device.state === UPowerDeviceState.FullyCharged
    readonly property real timeRemaining: charging ? _device.timeToFull : _device.timeToEmpty

    readonly property string icon: {
        if (charging)
            return "battery-charging";
        if (percent >= 80)
            return "battery-full";
        if (percent >= 55)
            return "battery-high";
        if (percent >= 25)
            return "battery-medium";
        return "battery-low";
    }

    readonly property bool low: present && !charging && percent <= 15

    // ── Profile ────────────────────────────────────────────────────────────

    // Backends are probed in parallel and resolved by specificity. Chaining them
    // — run the next one when the previous exits non-zero — looks tidier and is
    // wrong: a binary that is not installed fails to *start*, which never emits
    // an exit, so the chain stalls on the first absent backend and every later
    // one is silently never tried.
    property string _helperProfile: ""
    property string _ppctlProfile: ""
    property string _governorProfile: ""

    readonly property string backend: _helperProfile !== "" ? "laptop-helper" : _ppctlProfile !== "" ? "ppctl" : _governorProfile !== "" ? "autocpufreq" : "none"
    readonly property string profile: _helperProfile !== "" ? _helperProfile : _ppctlProfile !== "" ? _ppctlProfile : _governorProfile !== "" ? _governorProfile : "unknown"
    property string pendingProfile: ""

    readonly property var profiles: {
        const list = [{ id: "performance", label: "Performance", icon: "flame" }, { id: "balanced", label: "Balanced", icon: "speed" }, { id: "power-saver", label: "Power Saver", icon: "leaf" }];
        if (backend === "laptop-helper")
            list.push({ id: "e-core-only", label: "Efficiency Cores", icon: "leaf-filled" });
        return list;
    }

    onProfileChanged: pendingProfile = ""

    function detect() {
        helper.running = true;
        ppctl.running = true;
        governor.running = true;
    }

    function setProfile(id) {
        pendingProfile = id;

        if (backend === "laptop-helper")
            profileWriter.command = ["pkexec", "laptop-power-profile", "set", id];
        else if (backend === "ppctl")
            profileWriter.command = ["powerprofilesctl", "set", id];
        else
            profileWriter.command = ["pkexec", "auto-cpufreq", "--force=" + (id === "performance" ? "performance" : id === "power-saver" ? "powersave" : "reset")];

        profileWriter.running = true;
        settle.restart();
        abandon.restart();
    }

    // ── Charge limit (Dell smbios) ─────────────────────────────────────────

    readonly property int chargeFloor: 50
    readonly property int chargeCeiling: 80

    // custom · adaptive · standard · express · primarily_ac · unknown
    property string chargeMode: "unknown"
    property int chargeStart: -1
    property int chargeStop: -1
    property bool chargeKnown: false
    property string chargeError: ""
    property string chargePending: ""
    // Remembered so turning the cap off restores what was there before it.
    property string uncappedMode: "adaptive"

    readonly property bool chargeBusy: chargeRead.running || chargeWriter.running
    readonly property bool chargeCapped: chargePending !== "" ? chargePending === "capped" : chargeKnown && chargeMode === "custom"

    function readChargeLimit() {
        if (chargeBusy)
            return;
        chargeError = "";
        chargePending = "";
        chargeRead.running = true;
    }

    function setChargeLimit(capped) {
        if (chargeBusy)
            return;

        chargeError = "";
        chargePending = capped ? "capped" : "uncapped";

        if (capped) {
            if (chargeKnown && chargeMode !== "custom" && chargeMode !== "unknown")
                uncappedMode = chargeMode;
            chargeWriter.targetMode = "custom";
            chargeWriter.command = ["pkexec", "smbios-battery-ctl", "--set-charging-mode=custom", "--set-custom-charge-interval", String(chargeFloor), String(chargeCeiling)];
        } else {
            chargeWriter.targetMode = uncappedMode !== "" && uncappedMode !== "custom" && uncappedMode !== "unknown" ? uncappedMode : "adaptive";
            chargeWriter.command = ["pkexec", "smbios-battery-ctl", "--set-charging-mode=" + chargeWriter.targetMode];
        }

        chargeWriter.running = true;
    }

    Component.onCompleted: detect()

    // ── Processes ──────────────────────────────────────────────────────────

    readonly property Process _helper: Process {
        id: helper
        command: ["laptop-power-profile", "get"]
        stdout: StdioCollector {
            onStreamFinished: root._helperProfile = this.text.trim()
        }
    }

    readonly property Process _ppctl: Process {
        id: ppctl
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: root._ppctlProfile = this.text.trim()
        }
    }

    readonly property Process _governor: Process {
        id: governor
        command: ["cat", "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim();
                root._governorProfile = value === "" ? "" : value === "performance" ? "performance" : value === "powersave" ? "power-saver" : "balanced";
            }
        }
    }

    readonly property Process _profileWriter: Process {
        id: profileWriter
        stderr: StdioCollector {
            id: profileFailure
        }
        onExited: code => {
            if (code !== 0) {
                root.pendingProfile = "";
                Toast.error(profileFailure.text.trim().split("\n").filter(line => line !== "").pop() || "Could not change the power profile");
            }
        }
    }

    readonly property Timer _settle: Timer {
        id: settle
        interval: 1500
        onTriggered: root.detect()
    }

    // A backend that accepts the write but never reports the new value would
    // otherwise leave the control stuck in its pending state forever.
    readonly property Timer _abandon: Timer {
        id: abandon
        interval: 3000
        onTriggered: root.pendingProfile = ""
    }

    readonly property Process _chargeRead: Process {
        id: chargeRead
        command: ["pkexec", "smbios-battery-ctl", "--get-charging-cfg"]
        stderr: StdioCollector {
            id: chargeReadFailure
        }
        stdout: StdioCollector {
            id: chargeReadOutput
        }
        onExited: code => {
            if (code !== 0) {
                root.chargeKnown = false;
                root.chargeMode = "unknown";
                root.chargeError = chargeReadFailure.text.trim() || "Could not read the charge limit";
                return;
            }

            const mode = chargeReadOutput.text.match(/Charging mode:\s*(\S+)/);
            if (!mode) {
                root.chargeKnown = false;
                root.chargeMode = "unknown";
                root.chargeError = "Unexpected charging configuration";
                return;
            }

            root.chargeMode = mode[1].trim();
            root.chargeKnown = true;
            root.chargeError = "";

            const interval = chargeReadOutput.text.match(/Charging interval:\s*\((\d+),\s*(\d+)\)/);
            root.chargeStart = root.chargeMode === "custom" && interval ? parseInt(interval[1], 10) : -1;
            root.chargeStop = root.chargeMode === "custom" && interval ? parseInt(interval[2], 10) : -1;

            if (root.chargeMode !== "custom" && root.chargeMode !== "unknown")
                root.uncappedMode = root.chargeMode;
        }
    }

    readonly property Process _chargeWriter: Process {
        id: chargeWriter
        property string targetMode: "adaptive"
        stderr: StdioCollector {
            id: chargeWriteFailure
        }
        onExited: code => {
            if (code === 0) {
                root.chargeKnown = true;
                root.chargeError = "";
                root.chargeMode = root.chargePending === "capped" ? "custom" : chargeWriter.targetMode;
                root.chargeStart = root.chargePending === "capped" ? root.chargeFloor : -1;
                root.chargeStop = root.chargePending === "capped" ? root.chargeCeiling : -1;
                if (root.chargePending !== "capped")
                    root.uncappedMode = chargeWriter.targetMode;
            } else {
                root.chargeError = chargeWriteFailure.text.trim() || "Could not update the charge limit";
            }
            root.chargePending = "";
        }
    }
}
