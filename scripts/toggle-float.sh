#!/bin/sh
# Toggle floating and, when untiling, resize to 75% of the monitor and center.

floating=$(hyprctl activewindow -j | jq -r '.floating')

if [ "$floating" = "false" ]; then
    hyprctl --batch "dispatch togglefloating ; dispatch resizeactive exact 75% 75% ; dispatch centerwindow 1"
else
    hyprctl dispatch togglefloating
fi
