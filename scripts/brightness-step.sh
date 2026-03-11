#!/bin/sh
# Adjust brightness by 5% in perceptual space (gamma 2.2).
# Usage: brightness-step.sh up|down

DEVICE="intel_backlight"
STEP=0.05

current=$(brightnessctl -d "$DEVICE" g)
max=$(brightnessctl -d "$DEVICE" m)

case "$1" in
    up)   dir=1 ;;
    down) dir=-1 ;;
    *)    echo "Usage: $0 up|down" >&2; exit 1 ;;
esac

raw=$(awk "BEGIN {
    perceived = ($current / $max) ^ (1 / 2.2)
    perceived += $dir * $STEP
    if (perceived < 0) perceived = 0
    if (perceived > 1) perceived = 1
    v = int($max * perceived ^ 2.2)
    if (v < 0) v = 0
    if (v > $max) v = $max
    print v
}")

brightnessctl -d "$DEVICE" s "$raw"
brightnessctl -d "$DEVICE" -m > /tmp/quickshell-brightness
