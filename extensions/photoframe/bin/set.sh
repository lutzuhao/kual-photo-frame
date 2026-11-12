#!/bin/sh
# Change one setting from the KUAL menu: set.sh KEY VALUE
# Saves it in /mnt/us/photoframe/settings.sh, rebuilds the menu (marks the current choice with *)
# and prints a confirmation at the bottom of the screen.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
k="$1"
v="$2"
case "${k}" in
	INTERVAL_MIN) interval_allowed "${v}" || { log "set: bad ${k} '${v}'"; exit 1; } ;;
	ORIENTATION) case "${v}" in all|portrait|landscape) ;; *) log "set: bad ${k} '${v}'"; exit 1 ;; esac ;;
	FRAME_MODE) case "${v}" in sleep|takeover) ;; *) log "set: bad ${k} '${v}'"; exit 1 ;; esac ;;
	TAP_LIGHT) case "${v}" in 0|1) ;; *) log "set: bad ${k} '${v}'"; exit 1 ;; esac ;;
	SHOW_BATTERY) case "${v}" in 0|1) ;; *) log "set: bad ${k} '${v}'"; exit 1 ;; esac ;;
	*) log "set: unknown setting '${k}'"; exit 1 ;;
esac
set_setting "${k}" "${v}"
load_settings
log "setting ${k}=${v}"
msg=""
case "${k}" in
	INTERVAL_MIN)
		msg="New photo $(interval_label)."
		loop_running && msg="${msg} Used from the next photo change."
		;;
	ORIENTATION)
		# a new filter needs a new shuffle bag
		rm -f "${PF_STATE}/bag.txt" "${PF_STATE}/bag_filter.txt"
		cnt="$(photo_count)"
		[ -z "${cnt}" ] && cnt=0
		if [ "${cnt}" -eq 0 ]; then
			msg="$(no_photo_message)"
		else
			case "${ORIENTATION}" in
				all) msg="Showing all photos (${cnt})." ;;
				portrait) msg="Showing only vertical photos (${cnt})." ;;
				landscape) msg="Showing only horizontal photos (${cnt}). Turn the Kindle on its side." ;;
			esac
		fi
		;;
	FRAME_MODE)
		if [ "${FRAME_MODE}" = "sleep" ]; then
			msg="Quick exit: sleep-screen mode."
		else
			msg="Full takeover mode: exiting restarts the Kindle UI."
		fi
		loop_running && msg="${msg} Stop and start the photo frame to use it."
		;;
	TAP_LIGHT)
		if [ "${TAP_LIGHT}" = "1" ]; then
			msg="Tap light ON: only while charging (stays awake, full takeover)."
		else
			msg="Tap light OFF: sleeps between photos."
		fi
		loop_running && msg="${msg} Stop and start the photo frame to use it."
		;;
	SHOW_BATTERY)
		if [ "${SHOW_BATTERY}" = "1" ]; then
			msg="Battery display on: a small percentage in the bottom-right corner."
		else
			msg="Battery display off."
		fi
		loop_running && msg="${msg} Used from the next photo change."
		;;
esac
/bin/sh "${DIR}/gen_menu.sh" >/dev/null 2>&1
setup_fbink
say_at -3 "${msg}"
exit 0
