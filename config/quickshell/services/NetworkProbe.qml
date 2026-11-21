pragma Singleton

import QtQuick
import Quickshell.Io

// Runs only while something is looking at it.
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

    readonly property string _pingStats: 'stats() { out=$(ping -c 5 -i 0.2 -W 1 "$1" 2>/dev/null); ' + 'loss=$(printf "%s" "$out" | sed --quiet "s/.*[^0-9]\\([0-9.]*\\)% packet loss.*/\\1/p"); ' + 'rtt=$(printf "%s" "$out" | grep --extended-regexp "rtt|round-trip" | tr "/" " "); ' + 'avg=$(printf "%s" "$rtt" | awk "{print \\$8}"); ' + 'jit=$(printf "%s" "$rtt" | awk "{print \\$10}"); ' + 'echo "$2_PING=${avg:--1}"; echo "$2_JITTER=${jit:--1}"; echo "$2_LOSS=${loss:--1}"; }; '

    readonly property Process _probe: Process {
        id: probe
        command: ["bash", "-c", root._pingStats + 'gw=$(ip route show default | awk \'{for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }\'); ' + 'iface=$(ip route show default | awk \'{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }\'); ' + '[ -n "$gw" ] && stats "$gw" GW; ' + 'stats 1.1.1.1 NET; ' + 'dns=$(nmcli --terse --fields IP4.DNS dev show "$iface" 2>/dev/null | head --lines=1 | cut --delimiter=: --fields=2); ' + 'echo "DNS_SERVER=${dns:---}"; ' + 'qt=$(dig +tries=1 +time=2 @"${dns:-1.1.1.1}" example.com 2>/dev/null | awk "/Query time:/{print \\$4}"); ' + 'echo "DNS_TIME=${qt:--1}"; ' + '[ -n "$iface" ] || exit 0; ' + 'link=$(nmcli --terse --fields ACTIVE,SIGNAL,FREQ,RATE,CHAN dev wifi list ifname "$iface" 2>/dev/null | awk --field-separator=: "/^yes/{print; exit}"); ' + '[ -n "$link" ] || exit 0; ' + 'echo "SIGNAL=$(printf "%s" "$link" | cut --delimiter=: --fields=2)"; ' + 'echo "FREQ=$(printf "%s" "$link" | cut --delimiter=: --fields=3 | tr --delete --complement "0-9")"; ' + 'echo "RATE=$(printf "%s" "$link" | cut --delimiter=: --fields=4)"; ' + 'echo "CHAN=$(printf "%s" "$link" | cut --delimiter=: --fields=5)"']
        stdout: StdioCollector {
            onStreamFinished: root._ingest(this.text)
        }
    }

    // Bufferbloat: the ping runs during the transfer, not around it.
    readonly property Process _speed: Process {
        id: speed
        command: ["bash", "-c", 'gw=$(ip route show default | awk \'{for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }\'); ' + 'idle=$([ -n "$gw" ] && ping -c 5 -i 0.2 -W 1 "$gw" 2>/dev/null | grep --extended-regexp "rtt|round-trip" | tr "/" " " | awk "{print \\$8}"); ' + 'echo "IDLE=${idle:--1}"; ' + 'log=$(mktemp); load=""; ' + 'cleanup() { [ -n "$load" ] && kill -INT "$load" 2>/dev/null; rm --force "$log" "$payload" 2>/dev/null; }; trap cleanup EXIT; ' + '[ -n "$gw" ] && { ping -c 60 -i 0.5 -W 1 "$gw" > "$log" 2>/dev/null & load=$!; }; ' + 'down=$(curl --fail --output /dev/null --write-out "%{speed_download}" --silent --max-time 15 "https://speed.cloudflare.com/__down?bytes=25000000" 2>/dev/null || true); ' + 'if [ -n "$down" ]; then echo "DOWN=$(echo "scale=1; $down * 8 / 1000000" | bc 2>/dev/null)"; else echo "DOWN=-1"; fi; ' + 'payload=$(mktemp); dd if=/dev/zero of="$payload" bs=1M count=10 2>/dev/null; ' + 'up=$(curl --fail --request POST --write-out "%{speed_upload}" --silent --max-time 15 --data-binary @"$payload" --header "Content-Type: application/octet-stream" "https://speed.cloudflare.com/__up" 2>/dev/null || true); ' + 'if [ -n "$up" ]; then echo "UP=$(echo "scale=1; $up * 8 / 1000000" | bc 2>/dev/null)"; else echo "UP=-1"; fi; ' + '[ -n "$load" ] && { kill -INT "$load" 2>/dev/null; wait "$load" 2>/dev/null; load=""; }; ' + 'busy=$([ -s "$log" ] && grep --extended-regexp "rtt|round-trip" "$log" | tr "/" " " | awk "{print \\$8}"); ' + 'echo "LOADED=${busy:--1}"']
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
        command: ["nmcli", "--terse", "--fields", "CHAN,SIGNAL", "dev", "wifi", "list", "--rescan", "no"]
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
