#!/bin/sh
# Connect to WPA-Enterprise (PEAP/MSCHAPv2) WiFi network.
# Usage: wifi-connect.sh <ssid> <identity> <password>

SSID="$1"
IDENTITY="$2"
PASSWORD="$3"

iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1)

nmcli connection delete id "$SSID" 2>/dev/null

nmcli connection add type wifi ifname "$iface" con-name "$SSID" \
    ssid "$SSID" \
    wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 \
    802-1x.identity "$IDENTITY" \
    802-1x.password "$PASSWORD" \
    && nmcli connection up id "$SSID"
