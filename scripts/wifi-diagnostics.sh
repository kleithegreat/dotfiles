#!/usr/bin/env bash
# Gather Wi-Fi diagnostics: signal, noise, link rate, gateway ping,
# internet ping, and DNS lookup time.  Outputs KEY:VALUE lines.
set -uo pipefail

iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1)
[ -z "$iface" ] && exit 1

# ── Wi-Fi link info ──────────────────────────────────────────
link=$(iw dev "$iface" link 2>/dev/null)
station=$(iw dev "$iface" station dump 2>/dev/null)

freq=$(echo "$link" | awk '/freq:/{print $2}')
if [ -n "$freq" ]; then
    if [ "$freq" -lt 3000 ] 2>/dev/null; then
        echo "BAND:2.4 GHz"
    elif [ "$freq" -lt 6000 ] 2>/dev/null; then
        echo "BAND:5 GHz"
    else
        echo "BAND:6 GHz"
    fi
    echo "FREQ:$freq"
fi

signal=$(echo "$station" | awk '/signal:/{print $2; exit}')
[ -n "$signal" ] && echo "SIGNAL:$signal"

linkrate=$(echo "$link" | awk '/tx bitrate:/{print $3; exit}')
[ -n "$linkrate" ] && echo "LINKRATE:$linkrate"

# ── Noise floor ──────────────────────────────────────────────
noise=$(iw dev "$iface" survey dump 2>/dev/null \
    | awk '/\[in use\]/{found=1} found && /noise/{print $2; exit}')
[ -n "$noise" ] && echo "NOISE:$noise"

# ── Gateway ping ─────────────────────────────────────────────
gw=$(ip route | awk '/default/{print $3; exit}')
if [ -n "$gw" ]; then
    echo "GW:$gw"
    gw_ping=$(ping -c 10 -i 0.2 -W 1 "$gw" 2>/dev/null)
    if [ -n "$gw_ping" ]; then
        gw_loss=$(echo "$gw_ping" | awk -F'[, %]+' '/packet loss/{for(i=1;i<=NF;i++) if($i=="packet") print $(i-1)}')
        gw_stats=$(echo "$gw_ping" | awk -F'[/ ]+' '/rtt|round-trip/{print $5,$7}')
        gw_avg=$(echo "$gw_stats" | awk '{print $1}')
        gw_jitter=$(echo "$gw_stats" | awk '{print $2}')
        [ -n "$gw_avg" ] && echo "GW_PING:$gw_avg"
        [ -n "$gw_jitter" ] && echo "GW_JITTER:$gw_jitter"
        [ -n "$gw_loss" ] && echo "GW_LOSS:$gw_loss"
    fi
fi

# ── Internet ping (1.1.1.1) ─────────────────────────────────
net_ping=$(ping -c 10 -i 0.2 -W 1 1.1.1.1 2>/dev/null)
if [ -n "$net_ping" ]; then
    net_loss=$(echo "$net_ping" | awk -F'[, %]+' '/packet loss/{for(i=1;i<=NF;i++) if($i=="packet") print $(i-1)}')
    net_stats=$(echo "$net_ping" | awk -F'[/ ]+' '/rtt|round-trip/{print $5,$7}')
    net_avg=$(echo "$net_stats" | awk '{print $1}')
    net_jitter=$(echo "$net_stats" | awk '{print $2}')
    [ -n "$net_avg" ] && echo "NET_PING:$net_avg"
    [ -n "$net_jitter" ] && echo "NET_JITTER:$net_jitter"
    [ -n "$net_loss" ] && echo "NET_LOSS:$net_loss"
fi

# ── DNS lookup ───────────────────────────────────────────────
dns=$(nmcli -t -f IP4.DNS dev show "$iface" 2>/dev/null | head -1 | cut -d: -f2)
if [ -n "$dns" ]; then
    echo "DNS_SERVER:$dns"
    if command -v dig >/dev/null 2>&1; then
        dns_time=$(dig +stats +short example.com @"$dns" 2>/dev/null \
            | awk '/Query time:/{print $4}')
    fi
    # Fallback: time a ping to the DNS server
    if [ -z "${dns_time:-}" ]; then
        dns_time=$(ping -c 1 -W 2 "$dns" 2>/dev/null \
            | awk -F'[= ]+' '/time=/{for(i=1;i<=NF;i++) if($i=="time") printf "%.0f\n", $(i+1)}')
    fi
    [ -n "${dns_time:-}" ] && echo "DNS_TIME:$dns_time"
fi
