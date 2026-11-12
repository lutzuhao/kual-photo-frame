#!/bin/sh
# KUAL: Start photo frame.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
migrate_interval_setting
setup_fbink
if loop_running; then
	log "start requested but the photo frame is already running ($(cat "${PF_MODEFILE}" 2>/dev/null) mode)"
	say "Photo Frame is already running. Use Stop photo frame first."
	exit 0
fi
cnt="$(photo_count)"
[ -z "${cnt}" ] && cnt=0
if [ "${cnt}" -eq 0 ]; then
	log "start aborted: no ${ORIENTATION} photos"
	say "$(no_photo_message)"
	exit 1
fi

mode="${FRAME_MODE}"
why=""
if [ "${TAP_LIGHT}" = "1" ] && is_charging; then
	mode="takeover"
	why=" (tap light while charging)"
fi
if [ "${mode}" = "sleep" ] && ! have lipc-wait-event; then
	mode="takeover"
	why=" (lipc-wait-event not found)"
	log "lipc-wait-event not found, using takeover mode"
fi

if ! copy_to_run "${DIR}"; then
	log "could not copy scripts to ${PF_RUN}, running from ${DIR}"
	PF_RUN="${DIR}"
fi
rm -f "${PF_STOPFILE}"
log "start: ${cnt} ${ORIENTATION} photos, ${mode} mode${why}, $(interval_label), battery $(battery_pct)%"

if [ "${mode}" = "sleep" ]; then
	say "Photo Frame: ${cnt} $(orientation_label), new photo $(interval_label). The Kindle now goes to sleep and shows the photos. Press the power button once to return to the Kindle."
	launch_detached "${PF_RUN}/sleepd.sh"
else
	if [ "${TAP_LIGHT}" = "1" ] && is_charging; then
		say "Photo Frame: ${cnt} $(orientation_label), $(interval_label). Charging: tap the screen to switch the light on/off. To exit: press the power button once and wait about a minute."
	else
		say "Photo Frame: ${cnt} $(orientation_label), $(interval_label). To exit: press the power button once and wait about a minute."
	fi
	sleep 6
	launch_detached "${PF_RUN}/loop.sh"
fi
exit 0
