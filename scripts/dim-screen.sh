#!/bin/sh
# Gradually dim the screen for hypridle. Operates in perceptual brightness space (gamma 2.2).
# Resume with: brightnessctl -r

DEVICE="intel_backlight"
STEPS=20
DELAY=0.05

# Save current state for later restore
brightnessctl -d "$DEVICE" -s

current=$(brightnessctl -d "$DEVICE" g)
max=$(brightnessctl -d "$DEVICE" m)

# Nothing to dim
[ "$current" -eq 0 ] && exit 0

# Target = 30% of current brightness (in raw space)
target=$(awk "BEGIN { printf \"%d\", $current * 0.3 }")

# Convert current and target to perceptual space, lerp, convert back
i=0
while [ "$i" -lt "$STEPS" ]; do
    raw=$(awk "BEGIN {
        p_cur = ($current / $max) ^ (1 / 2.2)
        p_tgt = ($target / $max) ^ (1 / 2.2)
        t = ($i + 1) / $STEPS
        p = p_cur + (p_tgt - p_cur) * t
        printf \"%d\", $max * p ^ 2.2
    }")
    brightnessctl -d "$DEVICE" s "$raw"
    sleep "$DELAY"
    i=$((i + 1))
done
