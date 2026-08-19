pragma Singleton

import QtQuick
import Quickshell.Io

// Link quality measurement. It only runs while something is looking at it:
// pinging the gateway twice a minute forever to populate a pane nobody has
// open is a cost with no reader.
QtObject {
    id: root

    property bool active: false

    property real gatewayPing: -1
    property real gatewayJitter: -1
    property real gatewayLoss: -1
    property real internetPing: -1
    property real internetJitter: -1
    property real internetLoss: -1
    property string dnsServer: ""
    property real dnsTime: -1

    property int signal: -1
    property string linkRate: ""
    property int channel: -1
    property real frequency: 0

    property real download: -1
    property real upload: -1
    property real idleLatency: -1
    property real loadedLatency: -1

    // [{ channel, count, strongest }]
    property var survey: []

    readonly property bool measuring: probe.running
    readonly property bool testingSpeed: speed.running
    readonly property bool surveying: scan.running

    readonly property real bloat: idleLatency > 0 && loadedLatency > 0 ? loadedLatency / idleLatency : -1
    readonly property string band: frequency >= 5900 ? "6 GHz" : frequency >= 4900 ? "5 GHz" : frequency > 0 ? "2.4 GHz" : ""

    // Bounded sample history for the sparklines.
    readonly property int span: 40
    property var gatewayHistory: []
    property var internetHistory: []
    property var signalHistory: []
    property var dnsHistory: []

    function measure() {
        if (!probe.running)
            probe.running = true;
    }

    function runSpeedTest() {
        if (!speed.running)
            speed.running = true;
    }

    function surveyChannels() {
        if (!scan.running)
            scan.running = true;
    }

    function reset() {
        gatewayHistory = [];
        internetHistory = [];
        signalHistory = [];
        dnsHistory = [];
        download = -1;
        upload = -1;
        idleLatency = -1;
        loadedLatency = -1;
    }

    function _record(series, value) {
        if (value < 0)
            return series;
        const next = series.concat([value]);
        return next.length > span ? next.slice(next.length - span) : next;
    }

    function _number(text) {
        const value = parseFloat(text);
        return isNaN(value) ? -1 : value;
    }

    function _ingest(text) {
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const split = lines[i].indexOf("=");
            if (split < 0)
                continue;
            const key = lines[i].slice(0, split);
            const value = lines[i].slice(split + 1).trim();

            if (key === "GW_PING")
                gatewayPing = _number(value);
            else if (key === "GW_JITTER")
                gatewayJitter = _number(value);
            else if (key === "GW_LOSS")
                gatewayLoss = _number(value);
            else if (key === "NET_PING")
                internetPing = _number(value);
            else if (key === "NET_JITTER")
                internetJitter = _number(value);
            else if (key === "NET_LOSS")
                internetLoss = _number(value);
            else if (key === "DNS_SERVER")
                dnsServer = value === "--" ? "" : value;
            else if (key === "DNS_TIME")
                dnsTime = _number(value);
            else if (key === "SIGNAL")
                signal = Math.round(_number(value));
            else if (key === "RATE")
                linkRate = value === "--" ? "" : value;
            else if (key === "CHAN")
                channel = Math.round(_number(value));
            else if (key === "FREQ")
                frequency = _number(value);
        }

        gatewayHistory = _record(gatewayHistory, gatewayPing);
        internetHistory = _record(internetHistory, internetPing);
        signalHistory = _record(signalHistory, signal);
        dnsHistory = _record(dnsHistory, dnsTime);
    }

    readonly property string _pingStats: 'stats() { out=$(ping -c 5 -i 0.2 -W 1 "$1" 2>/dev/null); ' + 'loss=$(printf "%s" "$out" | sed -n "s/.*[^0-9]\\([0-9.]*\\)% packet loss.*/\\1/p"); ' + 'rtt=$(printf "%s" "$out" | grep -E "rtt|round-trip" | tr "/" " "); ' + 'avg=$(printf "%s" "$rtt" | awk "{print \\$8}"); ' + 'jit=$(printf "%s" "$rtt" | awk "{print \\$10}"); ' + 'echo "$2_PING=${avg:--1}"; echo "$2_JITTER=${jit:--1}"; echo "$2_LOSS=${loss:--1}"; }; '

    readonly property Process _probe: Process {
        id: probe
        command: ["bash", "-c", root._pingStats + 'gw=$(ip route | awk "/^default/{print \\$3; exit}"); ' + 'iface=$(ip route | awk "/^default/{for (i = 1; i <= NF; i++) if (\\$i == \\"dev\\") { print \\$(i + 1); exit } }"); ' + '[ -n "$gw" ] && stats "$gw" GW; ' + 'stats 1.1.1.1 NET; ' + 'dns=$(nmcli -t -f IP4.DNS dev show "$iface" 2>/dev/null | head -1 | cut -d: -f2); ' + 'echo "DNS_SERVER=${dns:---}"; ' + 'qt=$(dig +tries=1 +time=2 @"${dns:-1.1.1.1}" example.com 2>/dev/null | awk "/Query time:/{print \\$4}"); ' + 'echo "DNS_TIME=${qt:--1}"; ' + '[ -n "$iface" ] || exit 0; ' + 'link=$(nmcli -t -f ACTIVE,SIGNAL,FREQ,RATE,CHAN dev wifi list ifname "$iface" 2>/dev/null | awk -F: "/^yes/{print; exit}"); ' + '[ -n "$link" ] || exit 0; ' + 'echo "SIGNAL=$(printf "%s" "$link" | cut -d: -f2)"; ' + 'echo "FREQ=$(printf "%s" "$link" | cut -d: -f3 | tr -dc "0-9")"; ' + 'echo "RATE=$(printf "%s" "$link" | cut -d: -f4)"; ' + 'echo "CHAN=$(printf "%s" "$link" | cut -d: -f5)"']
        stdout: StdioCollector {
            onStreamFinished: root._ingest(this.text)
        }
    }

    // Bufferbloat is the gateway's latency under load against its latency at
    // rest, so the ping has to run *during* the transfer, not before and after.
    readonly property Process _speed: Process {
        id: speed
        command: ["bash", "-c", 'gw=$(ip route | awk "/^default/{print \\$3; exit}"); ' + 'idle=$(ping -c 5 -i 0.2 -W 1 "$gw" 2>/dev/null | grep -E "rtt|round-trip" | tr "/" " " | awk "{print \\$8}"); ' + 'echo "IDLE=${idle:--1}"; ' + 'log=$(mktemp); load=""; ' + 'cleanup() { [ -n "$load" ] && kill -INT "$load" 2>/dev/null; rm -f "$log" "$payload" 2>/dev/null; }; trap cleanup EXIT; ' + 'ping -c 60 -i 0.5 -W 1 "$gw" > "$log" 2>/dev/null & load=$!; ' + 'down=$(curl -o /dev/null -w "%{speed_download}" -s --max-time 15 "https://speed.cloudflare.com/__down?bytes=25000000"); ' + 'echo "DOWN=$(echo "scale=1; ${down:-0} * 8 / 1000000" | bc 2>/dev/null)"; ' + 'payload=$(mktemp); dd if=/dev/zero of="$payload" bs=1M count=10 2>/dev/null; ' + 'up=$(curl -X POST -w "%{speed_upload}" -s --max-time 15 --data-binary @"$payload" -H "Content-Type: application/octet-stream" "https://speed.cloudflare.com/__up"); ' + 'echo "UP=$(echo "scale=1; ${up:-0} * 8 / 1000000" | bc 2>/dev/null)"; ' + 'kill -INT "$load" 2>/dev/null; wait "$load" 2>/dev/null; load=""; ' + 'busy=$(grep -E "rtt|round-trip" "$log" | tr "/" " " | awk "{print \\$8}"); ' + 'echo "LOADED=${busy:--1}"']
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const split = lines[i].indexOf("=");
                    if (split < 0)
                        continue;
                    const key = lines[i].slice(0, split);
                    const value = root._number(lines[i].slice(split + 1).trim());
                    if (key === "DOWN")
                        root.download = value;
                    else if (key === "UP")
                        root.upload = value;
                    else if (key === "IDLE")
                        root.idleLatency = value;
                    else if (key === "LOADED")
                        root.loadedLatency = value;
                }
            }
        }
    }

    readonly property Process _scan: Process {
        id: scan
        command: ["nmcli", "-t", "-f", "CHAN,SIGNAL", "dev", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const counts = {};
                const lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const parts = lines[i].split(":");
                    if (parts.length < 2)
                        continue;
                    const chan = parseInt(parts[0], 10);
                    const strength = parseInt(parts[1], 10) || 0;
                    if (isNaN(chan))
                        continue;
                    if (!counts[chan])
                        counts[chan] = { channel: chan, count: 0, strongest: 0 };
                    counts[chan].count++;
                    counts[chan].strongest = Math.max(counts[chan].strongest, strength);
                }

                const listed = [];
                for (const key in counts)
                    listed.push(counts[key]);
                listed.sort((a, b) => a.channel - b.channel);
                root.survey = listed;
            }
        }
    }

    readonly property Timer _poll: Timer {
        interval: 6000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.measure()
    }
}
