#!/bin/sh
# KUAL: Exit style  (mode.sh sleep|takeover)
exec /bin/sh "$(cd "$(dirname "$0")" && pwd)/set.sh" FRAME_MODE "$1"
