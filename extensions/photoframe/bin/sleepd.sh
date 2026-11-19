#!/bin/sh
# Photo Frame, sleep-screen mode (default). Started detached by start.sh from the tmpfs copy.
#
# The Kindle UI (framework) keeps running. powerd does the sleeping, exactly like normal use:
#   goingToScreenSaver  -> wait SS_DELAY s for the stock sleep screen, then draw a photo over it
#   readyToSuspend      -> armer.sh sets "rtcWakeup" so powerd wakes the Kindle at the next tick
#   wakeupFromSuspend/resuming while still on the sleep screen and the tick is due -> next photo
#   outOfScreenSaver    -> the user pressed the power button: the stock UI repaints itself
# Same events KOReader uses on Kindle (IntoSS/OutOfSS, ReadyToSuspend, WakeupFromSuspend).
DIR="$(cd "$(dirname "$0")" && pwd)"
PF_LOG_TO_RAM=1
. "${DIR}/common.sh"
trap '' HUP
cd /

echo $$ >"${PF_PIDFILE}"
echo sleep >"${PF_MODEFILE}"
log "==== photo frame start: sleep-screen mode (pid $$, $(interval_label), ${ORIENTATION} photos, battery display ${SHOW_BATTERY}, quiet $(quiet_window_label) TZ${TZ_OFFSET})"
setup_fbink || log "WARNING: FBInk not found, falling back to eips (no dithering)"

shown=0      # 1 = a photo is on the current sleep screen
sessions=0   # sleep-screen sessions seen so far
due=0        # epoch time of the next scheduled photo change
resleep=0    # 1 = we sent the Kindle back to the sleep screen after it woke on its own
resleep_tries=0
echo 0 >"${PF_DUEFILE}"

/bin/sh "${DIR}/armer.sh" </dev/null >/dev/null 2>&1 &
echo $! >"${PF_ARMERPID}"

cleanup() {
	log "sleep-screen daemon exiting ($1)"
	kill_pidfile "${PF_ARMERPID}"
	kill_armer_monitor
	restore_wifi_if_saved
	rm -f "${PF_PIDFILE}" "${PF_MODEFILE}" "${PF_DUEFILE}" "${PF_AWAKEFILE}" "${PF_USEREXIT}"
	flush_log
	exit 0
}

# Keep the current photo and schedule the RTC wake for the end of quiet hours (at most ~24h).
hold_for_quiet() {
	due="$(quiet_end_ts)"
	echo "${due}" >"${PF_DUEFILE}"
	log "quiet hours ($(quiet_window_label), local $(local_hm)): $1 until local $(local_hm "${due}") (${due})"
}

draw_photo() {
	load_settings
	if ! userstore_ok; then
		log "userstore not available (USB?), photo not changed"
		return 1
	fi
	# Low battery takes precedence over quiet hours: no further changes, no wake-up alarm.
	if [ "${shown}" = "1" ] && battery_low; then
		log "battery $(battery_pct)% <= ${LOW_BATTERY}%: keeping the current photo, awake $(awake_secs)s"
		due=$(( $(date +%s) + 86400 * 365 ))
		echo "${due}" >"${PF_DUEFILE}"
		flush_log
		return 1
	fi
	if in_quiet_hours && ! quiet_ending_soon; then
		if [ "${shown}" = "1" ]; then
			hold_for_quiet "keeping the current photo"
			flush_log
			nudge_ss_timeout
			return 0
		fi
		# Entering the sleep screen at night: paint a photo (prefer the last one) but do not advance the bag.
		img="$(current_image)"
		if [ -z "${img}" ]; then
			img="$(next_image)"
		fi
		if [ -z "${img}" ]; then
			log "no ${ORIENTATION} photos to show"
			say "$(no_photo_message)"
		else
			show_image "${img}"
			log "quiet hours ($(quiet_window_label), local $(local_hm)): showing $(basename "${img}")  battery=$(battery_pct)%  charging=$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)  awake=$(awake_secs)s"
		fi
		shown=1
		hold_for_quiet "held"
		flush_log
		nudge_ss_timeout
		return 0
	fi
	img="$(next_image)"
	if [ -z "${img}" ]; then
		log "no ${ORIENTATION} photos to show"
		say "$(no_photo_message)"
	else
		show_image "${img}"
		log "$1: showing $(basename "${img}")  battery=$(battery_pct)%  charging=$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)  awake=$(awake_secs)s"
	fi
	shown=1
	due="$(next_tick)"
	echo "${due}" >"${PF_DUEFILE}"
	flush_log
	nudge_ss_timeout
	return 0
}

# Back on the sleep screen after a wake the user did not ask for: paint the same photo again
# (or the next one if its tick came while the Kindle was on the home screen).
redraw_current() {
	resleep=0
	if [ "$(date +%s)" -ge $((due - 20)) ]; then
		draw_photo "tick (after waking on its own)"
		return
	fi
	if ! userstore_ok; then
		log "userstore not available (USB?), photo not redrawn"
		return 1
	fi
	img="$(current_image)"
	if [ -z "${img}" ]; then
		draw_photo "sleep screen"
		return
	fi
	show_image "${img}"
	log "back on the sleep screen: showing $(basename "${img}") again  battery=$(battery_pct)%  awake=$(awake_secs)s"
	flush_log
	nudge_ss_timeout
}

# Did the user press the power button in the last $1 seconds?
user_exit_recent() {
	_u="$(cat "${PF_USEREXIT}" 2>/dev/null)"
	case "${_u}" in ''|*[!0-9]*) return 1 ;; esac
	[ $(( $(date +%s) - _u )) -le "$1" ]
}

is_sleep_state() {
	case "$1" in
		*creen*|*eady*|*uspend*) return 0 ;;
	esac
	return 1
}

# Put the Kindle to sleep now (same as one press of the power button; KOReader does the same).
started="$(date +%s)"
if ! is_sleep_state "$(powerd_state)"; then
	( sleep 4; lipc-set-prop -i com.lab126.powerd powerButton 1 >/dev/null 2>&1 ) &
fi

fast=0
while :; do
	[ -f "${PF_STOPFILE}" ] && { rm -f "${PF_STOPFILE}"; cleanup "stop file"; }
	t0="$(date +%s)"
	# Also listen for suspending so the log records how long this cycle stayed awake.
	ev="$(lipc-wait-event -s 30 com.lab126.powerd goingToScreenSaver,outOfScreenSaver,wakeupFromSuspend,resuming,suspending 2>/dev/null)"
	t1="$(date +%s)"
	# a lipc-wait-event that keeps returning at once (unsupported option, powerd gone) must not spin the CPU
	if [ -z "${ev}" ] && [ $((t1 - t0)) -lt 2 ]; then
		fast=$((fast + 1))
		if [ "${fast}" -ge 5 ] && [ "${sessions}" = "0" ]; then
			log "lipc-wait-event is not working; switching to takeover mode"
			kill_pidfile "${PF_ARMERPID}"
			kill_armer_monitor
			flush_log
			exec /bin/sh "${DIR}/loop.sh"
		fi
		sleep 5
		continue
	fi
	fast=0
	[ -n "${ev}" ] && log "event: ${ev} (state $(powerd_state))"
	case "${ev}" in
		goingToScreenSaver*)
			mark_awake
			save_wifi_and_off
			sessions=$((sessions + 1))
			sleep "${SS_DELAY}"
			if [ "${resleep}" = "1" ] && [ "${shown}" = "1" ]; then
				redraw_current
			else
				resleep=0
				draw_photo "sleep screen"
			fi
			resleep_tries=0
			continue
			;;
		outOfScreenSaver*)
			shown=0
			resleep=0
			resleep_tries=0
			restore_wifi_if_saved
			log "power button: back to the Kindle UI (photo frame stays armed for the next sleep)"
			flush_log
			continue
			;;
		suspending*)
			log "suspending: awake $(awake_secs)s this cycle"
			continue
			;;
		wakeupFromSuspend*)
			mark_awake
			save_wifi_and_off
			;;
	esac
	st="$(powerd_state)"
	now="$(date +%s)"
	if is_sleep_state "${st}"; then
		[ "${sessions}" = "0" ] && sessions=1
		if [ "${shown}" = "0" ]; then
			# missed the goingToScreenSaver event
			sleep 1
			draw_photo "sleep screen (late)"
		elif [ "${now}" -ge $((due - 20)) ]; then
			sleep 1
			draw_photo "tick"
		fi
	elif [ "${shown}" = "1" ] && [ "${resleep_tries}" -lt 3 ]; then
		# A photo was on the sleep screen and the Kindle is now on its home screen, but the
		# power button was not pressed: powerd sometimes wakes up on its own (about an hour
		# into a suspend, or when a charger is plugged in) and lands on the home screen.
		# Wait a moment in case the power-button event is still on its way, then go back.
		sleep 3
		st="$(powerd_state)"
		if user_exit_recent 20; then
			shown=0
			resleep=0
			resleep_tries=0
			restore_wifi_if_saved
			log "power button (seen by armer): back to the Kindle UI (photo frame stays armed for the next sleep)"
			flush_log
		elif ! is_sleep_state "${st}"; then
			resleep=1
			resleep_tries=$((resleep_tries + 1))
			log "woke up on its own (state '${st}', no power button): back to the sleep screen (try ${resleep_tries})"
			flush_log
			lipc-set-prop -i com.lab126.powerd powerButton 1 >/dev/null 2>&1
		fi
	else
		if [ "${shown}" = "1" ]; then
			log "still on the home screen after ${resleep_tries} tries; leaving it until the next sleep"
			flush_log
		fi
		shown=0
		resleep=0
		resleep_tries=0
		if [ "${sessions}" = "0" ] && [ $((now - started)) -ge 60 ]; then
			# the Kindle never went to sleep after our power-button request: use the old takeover mode
			log "sleep screen did not start (state '${st}'); switching to takeover mode"
			kill_pidfile "${PF_ARMERPID}"
			kill_armer_monitor
			flush_log
			exec /bin/sh "${DIR}/loop.sh"
		fi
	fi
done
