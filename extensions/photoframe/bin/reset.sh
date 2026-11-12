#!/bin/sh
# KUAL: Reset shuffle order.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
rm -f "${PF_STATE}/bag.txt" "${PF_STATE}/last.txt" "${PF_STATE}/bag_filter.txt"
log "shuffle order reset"
exit 0
