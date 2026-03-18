#!/usr/bin/env bash
# Gather Wi-Fi diagnostics: signal, noise, link rate, gateway ping,
# internet ping, and DNS lookup time.  Outputs KEY=VALUE lines.
set -uo pipefail

iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1)
[ -z "$iface" ] && exit 1

# ── Wi-Fi link info (nmcli, no root needed) ──────────────────
# Fields: SSID:FREQ:RATE:SIGNAL:ACTIVE
active_line=$(nmcli -t -f SSID,FREQ,RATE,SIGNAL,ACTIVE dev wifi list ifname "$iface" 2>/dev/null \
    | grep ':yes$' | head -1)

freq_val="" signal_val="" link_rate="" band=""

if [ -n "$active_line" ]; then
    # Parse from the right — SSID can contain colons
    signal_val=$(echo "$active_line" | rev | cut -d: -f2 | rev)
    rate_raw=$(echo "$active_line" | rev | cut -d: -f3 | rev)
    freq_val=$(echo "$active_line" | rev | cut -d: -f4 | rev)

    # Rate comes as "130 Mb/s" — extract number
    link_rate=$(echo "$rate_raw" | grep -oP '[\d.]+' | head -1)

    if [ -n "$freq_val" ]; then
        if [ "$freq_val" -lt 3000 ] 2>/dev/null; then
            band="2.4 GHz"
        elif [ "$freq_val" -lt 6000 ] 2>/dev/null; then
            band="5 GHz"
        else
            band="6 GHz"
        fi
    fi
fi

# Try iw dev link (usually works without root, unlike station dump)
# for dBm signal and more precise tx bitrate
signal_dbm=""
iw_link=$(iw dev "$iface" link 2>/dev/null || true)
if [ -n "$iw_link" ]; then
    signal_dbm=$(echo "$iw_link" | awk '/signal:/{print $2}')
    iw_rate=$(echo "$iw_link" | awk '/tx bitrate:/{print $3}')
    [ -n "$iw_rate" ] && link_rate="$iw_rate"
fi

# If iw didn't give dBm, rough-convert percentage: dBm ≈ (pct/2) - 100
if [ -z "$signal_dbm" ] && [ -n "$signal_val" ]; then
    signal_dbm=$(( (signal_val / 2) - 100 ))
fi

# Noise floor (best-effort, may need root)
noise=$(iw dev "$iface" survey dump 2>/dev/null \
    | awk '/\[in use\]/{found=1} found && /noise/{print $2; exit}' || true)

echo "BAND=${band:-unknown}"
echo "SIGNAL=${signal_dbm:---}"
echo "NOISE=${noise:---}"
echo "LINKRATE=${link_rate:---}"

# ── Gateway ping ─────────────────────────────────────────────
gw=$(ip route | awk '/default/{print $3; exit}')
echo "GW=${gw:---}"

gw_ping="" gw_jitter="" gw_loss=""
if [ -n "$gw" ]; then
    ping_out=$(ping -c 10 -i 0.2 -W 1 "$gw" 2>/dev/null || true)
    gw_loss=$(echo "$ping_out" | grep -oP '\d+(?=% packet loss)' || true)
    rtt_line=$(echo "$ping_out" | grep -E 'rtt|round-trip' || true)
    if [ -n "$rtt_line" ]; then
        gw_ping=$(echo "$rtt_line" | grep -oP '[\d.]+' | sed -n '2p')
        gw_jitter=$(echo "$rtt_line" | grep -oP '[\d.]+' | sed -n '4p')
    fi
fi
echo "GW_PING=${gw_ping:---}"
echo "GW_JITTER=${gw_jitter:---}"
echo "GW_LOSS=${gw_loss:---}"

# ── Internet ping (1.1.1.1) ─────────────────────────────────
net_ping="" net_jitter="" net_loss=""
net_out=$(ping -c 10 -i 0.2 -W 1 1.1.1.1 2>/dev/null || true)
net_loss=$(echo "$net_out" | grep -oP '\d+(?=% packet loss)' || true)
net_rtt=$(echo "$net_out" | grep -E 'rtt|round-trip' || true)
if [ -n "$net_rtt" ]; then
    net_ping=$(echo "$net_rtt" | grep -oP '[\d.]+' | sed -n '2p')
    net_jitter=$(echo "$net_rtt" | grep -oP '[\d.]+' | sed -n '4p')
fi
echo "NET_PING=${net_ping:---}"
echo "NET_JITTER=${net_jitter:---}"
echo "NET_LOSS=${net_loss:---}"

# ── DNS ──────────────────────────────────────────────────────
dns=$(nmcli -t -f IP4.DNS dev show "$iface" 2>/dev/null | head -1 | cut -d: -f2)
echo "DNS_SERVER=${dns:---}"

dns_time=""
if [ -n "$dns" ]; then
    if command -v dig &>/dev/null; then
        dns_time=$(dig +stats +short example.com @"$dns" 2>/dev/null \
            | awk '/Query time:/{print $4}')
    fi
    # Fallback: time a DNS resolution via bash
    if [ -z "${dns_time:-}" ]; then
        start_ms=$(date +%s%3N)
        getent hosts example.com >/dev/null 2>&1 || true
        end_ms=$(date +%s%3N)
        dns_time=$(( end_ms - start_ms ))
    fi
fi
echo "DNS_TIME=${dns_time:---}"
