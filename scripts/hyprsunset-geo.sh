#!/bin/sh
# Launch hyprsunset with geoclue2-based coordinates.
# Falls back to hardcoded lat/lon if where-am-i fails.

FALLBACK_LAT="40.76"
FALLBACK_LON="-74.98"

loc=$(timeout 10 where-am-i -t 10 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$loc" ]; then
    lat=$(echo "$loc" | awk '/Latitude:/ { printf "%.2f", $2 }')
    lon=$(echo "$loc" | awk '/Longitude:/ { printf "%.2f", $2 }')
fi

lat="${lat:-$FALLBACK_LAT}"
lon="${lon:-$FALLBACK_LON}"

pkill hyprsunset 2>/dev/null
exec hyprsunset -l "$lat" -L "$lon"
