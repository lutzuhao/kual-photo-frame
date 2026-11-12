#!/bin/sh
# KUAL: Tap to toggle light  (taplight.sh 0|1)
exec /bin/sh "$(cd "$(dirname "$0")" && pwd)/set.sh" TAP_LIGHT "$1"
