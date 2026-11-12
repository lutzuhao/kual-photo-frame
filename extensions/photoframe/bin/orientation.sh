#!/bin/sh
# KUAL: Photo orientation  (orientation.sh all|portrait|landscape)
exec /bin/sh "$(cd "$(dirname "$0")" && pwd)/set.sh" ORIENTATION "$1"
