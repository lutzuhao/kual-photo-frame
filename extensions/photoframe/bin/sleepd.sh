#!/bin/sh
# Photo Frame, sleep-screen mode (default). Started detached by start.sh from the tmpfs copy.
#
# The Kindle UI (framework) keeps running. powerd does the sleeping, exactly like normal use:
#   goingToScreenSaver  -> wait SS_DELAY s for the stock sleep screen, then draw a photo over it
#   readyToSuspend      -> armer.sh sets "rtcWakeup" so powerd wakes the Kindle at the next tick
#   wakeupFromSuspend/resuming while still on the sleep screen and the tick is due -> next photo
#   outOfScreenSaver    -> the user pressed the power button: the stock UI repaints itself
# Same events KOReader uses on Kindle (IntoSS/OutOfSS, ReadyToSuspend, WakeupFromSuspend).
# Power diagnostics for every event go to /mnt/us/photoframe/diag.txt (see common.sh).
DIR="$(cd "$(dirname "$0")" && pwd)"
PF_LOG_TO_RAM=1
. "${DIR}/common.sh"
trap '' HUP
cd /

echo $$ >"${PF_PIDFILE}"
echo sleep >"${PF_MODEFILE}"
log "==== photo frame start: sleep-screen mode (pid $$, $(interval_label), ${ORIENTATION} photos, battery display ${SHOW_BATTERY}, quiet $(quiet_window_label) TZ${TZ_OFFSET})"
setup_fbink || log "WARNING: FBInk not found, falling back to eips (no dithering)"
fl_lock_start
hall_off_start
diag_static
flush_log

shown=0      # 1 = a photo is on the current sleep screen
sessions=0   # sleep-screen sessions seen so far
due=0        # epoch time of the next scheduled photo change
resleep=0    # 1 = we sent the Kindle back to the sleep screen after it woke on its own
resleep_fail=0  # consecutive power-button presses that did NOT bring the sleep screen back
last_susp=0  # wall time of the last "suspending" event
wait_s=30    # lipc-wait-event timeout
echo 0 >"${PF_DUEFILE}"

/bin/sh "${DIR}/armer.sh" </dev/null >/dev/null 2>&1 &
echo $! >"${PF_ARMERPID}"

cleanup() {
	log "sleep-screen daemon exiting ($1)"
	diag_point "daemon exiting ($1)"
	diag_syslog
	kill_pidfile "${PF_ARMERPID}"
	kill_armer_monitor
	restore_wifi_if_saved
	fl_lock_restore
	hall_off_restore
	rm -f "${PF_PIDFILE}" "${PF_MODEFILE}" "${PF_DUEFILE}" "${PF_AWAKEFILE}" "${PF_USEREXIT}" "${PF_SUSP}" "${PF_WAKE}"
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
	return 0
}

# Back on the sleep screen after a wake the user did not ask for: paint the same photo again
# (or the next one if its tick came while the Kindle was on the home screen).
redraw_current() {
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
	# Also listen for suspending so the log records each suspend.
	ev="$(lipc-wait-event -s "${wait_s}" com.lab126.powerd goingToScreenSaver,outOfScreenSaver,wakeupFromSuspend,resuming,suspending 2>/dev/null)"
	t1="$(date +%s)"
	wait_s=30
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
			diag_point "goingToScreenSaver ${ev#goingToScreenSaver }"
			mark_awake
			save_wifi_and_off
			sessions=$((sessions + 1))
			sleep "${SS_DELAY}"
			_sst="$(powerd_state)"
			if ! is_sleep_state "${_sst}"; then
				log "goingToScreenSaver aborted (state '${_sst}')"
				diag_point "goingToScreenSaver aborted"
				flush_log
				continue
			fi
			if [ "${resleep}" = "1" ] && [ "${shown}" = "1" ]; then
				redraw_current
			else
				draw_photo "sleep screen"
			fi
			resleep=0
			resleep_fail=0
			fl_off_in_ss
			flush_log
			continue
			;;
		outOfScreenSaver*)
			sleep 1   # let armer.sh record the suspending/wake details first
			if failed_hibernate_wake; then
				# failed 'suspending disk': nobody pressed anything. Handled below
				# like any other wake on its own (light off, back to the sleep screen).
				fl_apply
				diag_point "outOfScreenSaver after failed hibernate (not a button)"
				log "outOfScreenSaver ${ev#outOfScreenSaver } right after a failed 'suspending disk': not a power button"
			else
				diag_point "outOfScreenSaver"
				shown=0
				resleep=0
				resleep_fail=0
				restore_wifi_if_saved
				log "power button: back to the Kindle UI (photo frame stays armed for the next sleep)"
				flush_log
				continue
			fi
			;;
		suspending*)
			# Only RAM work here: the Kindle suspends a few seconds after this event.
			diag_point "suspending ${ev#suspending }"
			last_susp="$(date +%s)"
			resleep=0
			wait_s=15
			continue
			;;
		wakeupFromSuspend*)
			diag_point "wakeupFromSuspend ${ev#wakeupFromSuspend }"
			diag_powerd_status
			diag_syslog
			diag_dmesg
			mark_awake
			save_wifi_and_off
			hall_off_apply
			;;
		resuming*)
			diag_point "resuming"
			diag_syslog
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
		fl_off_in_ss
		flush_log
	elif [ "${shown}" = "1" ]; then
		# A photo was on the sleep screen and the Kindle is now on its home screen, but the
		# power button was not pressed. On the Oasis (FW 5.9.7) powerd wakes from the RAM
		# suspend about an hour in, goes to "suspending disk" and lands in "active" ~immediately
		# (log 2026-11-20: 13 times). Earlier versions gave up after 3 such wakes and left the
		# Kindle on the home screen for 10 min each time; now it always goes back to sleep.
		# Give powerd at least 15 s after "suspending" (and the power-button event 3 s),
		# except after a failed hibernate: that one is recognised for sure, so light off
		# and straight back to sleep.
		sleep 1   # armer.sh writes its suspending/wake notes at about the same moment
		_fh=0
		failed_hibernate_wake && _fh=1
		if [ "${_fh}" = "1" ]; then
			fl_apply
			sleep 2
		else
			if [ "${last_susp}" -gt 0 ] && [ $((now - last_susp)) -ge 0 ] && [ $((now - last_susp)) -lt 15 ]; then
				sleep $((15 - (now - last_susp)))
			fi
			sleep 3
		fi
		st="$(powerd_state)"
		if [ "${_fh}" = "0" ] && user_exit_recent 20; then
			_uarg="$(cat "${PF_USEREXIT}.arg" 2>/dev/null)"
			shown=0
			resleep=0
			resleep_fail=0
			restore_wifi_if_saved
			diag_point "power button (seen by armer arg=${_uarg})"
			diag_powerd_status
			diag_syslog
			diag_dmesg
			log "power button (seen by armer, arg=${_uarg}): back to the Kindle UI (photo frame stays armed for the next sleep)"
			flush_log
		elif ! is_sleep_state "${st}"; then
			if [ "${resleep_fail}" -ge 5 ]; then
				log "could not get back to the sleep screen after ${resleep_fail} presses; leaving the Kindle UI until it sleeps by itself"
				shown=0
				resleep=0
				resleep_fail=0
				flush_log
				continue
			fi
			_since="before any suspend"
			[ "${last_susp}" -gt 0 ] && _since="$(( $(date +%s) - last_susp ))s after 'suspending'"
			diag_point "woke on its own (state ${st})"
			diag_powerd_status
			diag_syslog
			diag_dmesg
			log "woke up on its own (state '${st}', no power button, ${_since}$( [ "${_fh}" = "1" ] && echo ', failed hibernate')): pressing power to go back to the sleep screen"
			fl_apply
			resleep=1
			lipc-set-prop -i com.lab126.powerd powerButton 1 >/dev/null 2>&1
			sleep $((SS_DELAY + 2))
			st="$(powerd_state)"
			if is_sleep_state "${st}"; then
				resleep_fail=0
				mark_awake
				save_wifi_and_off
				# The goingToScreenSaver event of our own press is usually missed (no listener
				# is waiting while we sleep here), so paint the photo over the stock screen now.
				redraw_current
				fl_off_in_ss
				fl_apply
			else
				resleep_fail=$((resleep_fail + 1))
				log "still '${st}' after pressing power (${resleep_fail}/5)"
			fi
			flush_log
		fi
	else
		shown=0
		resleep=0
		resleep_fail=0
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
