#!/bin/sh
# KUAL: Change interval > Every N min  (interval.sh <minutes>)
exec /bin/sh "$(cd "$(dirname "$0")" && pwd)/set.sh" INTERVAL_MIN "$1"
