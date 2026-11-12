#!/bin/sh
# KUAL: Battery display  (battery.sh 0|1)
exec /bin/sh "$(cd "$(dirname "$0")" && pwd)/set.sh" SHOW_BATTERY "$1"
