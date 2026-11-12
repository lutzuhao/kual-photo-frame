#!/bin/sh
# KUAL: Show status (settings, photo counts, running mode) at the bottom of the screen.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
setup_fbink
o="${ORIENTATION}"
all=0; por=0; lan=0
ORIENTATION=all; all="$(photo_count)"
if [ -f "${PF_LANDSCAPE_LIST}" ]; then
	ORIENTATION=portrait; por="$(photo_count)"
	ORIENTATION=landscape; lan="$(photo_count)"
	split="vertical ${por}, horizontal ${lan}"
else
	split="landscape.txt missing"
fi
ORIENTATION="${o}"
if loop_running; then
	run="running ($(cat "${PF_MODEFILE}" 2>/dev/null) mode)"
else
	run="not running"
fi
case "${ORIENTATION}" in all) ol="all" ;; portrait) ol="vertical only" ;; *) ol="horizontal only" ;; esac
if [ "${FRAME_MODE}" = "sleep" ]; then ml="quick exit (sleep screen)"; else ml="full takeover"; fi
if [ "${TAP_LIGHT}" = "1" ]; then tl="on while charging"; else tl="off"; fi
if [ "${SHOW_BATTERY}" = "1" ]; then bl="on"; else bl="off"; fi
qh="$(quiet_window_label)"
say_at -7 "Photo Frame: ${run}"
say_at -6 "Photos: ${all} (${split})"
say_at -5 "Showing: ${ol}, $(interval_label)"
say_at -4 "Exit style: ${ml}; tap light: ${tl}"
say_at -3 "Battery display: ${bl}; quiet hours: ${qh} (TZ${TZ_OFFSET})"
say_at -2 "Battery $(battery_pct)%, charging: $(is_charging && echo yes || echo no)"
log "status: ${run}; photos ${all} (${split}); ${ORIENTATION}; $(interval_label); ${FRAME_MODE}; tap ${TAP_LIGHT}; battery display ${SHOW_BATTERY}; quiet ${qh} TZ${TZ_OFFSET}"
exit 0
