#!/bin/sh
# Photo Frame, takeover mode: stops the Kindle UI and shows photos itself.
# Used when FRAME_MODE=takeover, when TAP_LIGHT=1 and the Kindle is charging, or as the fallback
# if sleep-screen mode cannot start. Started detached from the tmpfs copy. busybox ash compatible.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"

# Survive the framework teardown (the framework job sends SIGTERM/SIGHUP to what KUAL started).
trap '' HUP TERM

echo $$ >"${PF_PIDFILE}"
echo takeover >"${PF_MODEFILE}"
rm -f "${PF_STOPFILE}"
log "==== slideshow start: takeover mode (pid $$, $(interval_label), ${ORIENTATION} photos, tap light ${TAP_LIGHT}, battery display ${SHOW_BATTERY}, quiet $(quiet_window_label) TZ${TZ_OFFSET})"

setup_fbink || log "WARNING: FBInk not found, falling back to eips (no dithering)"

# ---- remember state we change, so stop can restore it ----
WIFI_WAS="$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null)"
FL_WAS="$(lipc-get-prop com.lab126.powerd flIntensity 2>/dev/null | tr -cd '0-9')"
echo "WIFI_WAS='${WIFI_WAS}'" >"${PF_STATE}/restore.sh"
echo "FL_WAS='${FL_WAS}'" >>"${PF_STATE}/restore.sh"

tap_on_level() {
	l="${TAP_LIGHT_LEVEL}"
	[ "${l}" -gt 0 ] 2>/dev/null || l="${FL_WAS}"
	case "${l}" in ''|*[!0-9]*|0) l=12 ;; esac
	[ "${l}" -gt 24 ] && l=24
	echo "${l}"
}

find_touch_dev() {
	if [ -n "${TOUCH_DEV}" ] && [ -c "${TOUCH_DEV}" ]; then
		echo "${TOUCH_DEV}"
		return 0
	fi
	for s in /sys/class/input/event*; do
		[ -e "${s}" ] || continue
		nm="$(cat "${s}/device/name" 2>/dev/null)"
		case "${nm}" in
			*zforce*|*Zforce*|*ZFORCE*|*touch*|*Touch*|*cyttsp*|*pt_mt*)
				echo "/dev/input/${s##*/}"
				return 0
				;;
		esac
	done
	[ -c /dev/input/event0 ] && { echo /dev/input/event0; return 0; }
	return 1
}

start_touch() {
	[ -f "${PF_TOUCHPID}" ] && kill -0 "$(cat "${PF_TOUCHPID}")" 2>/dev/null && return 0
	td="$(find_touch_dev)"
	if [ -z "${td}" ]; then
		log "tap light: no touch input device found"
		return 1
	fi
	for s in /sys/class/input/event*; do
		[ -e "${s}" ] && log "input ${s##*/}: $(cat "${s}/device/name" 2>/dev/null)"
	done
	/bin/sh "${DIR}/touch.sh" "${td}" "$(tap_on_level)" </dev/null >/dev/null 2>&1 &
	echo $! >"${PF_TOUCHPID}"
}

stop_touch() {
	if [ -f "${PF_TOUCHPID}" ]; then
		kill_touch
		log "tap light: stopped listening"
	fi
}

restore_ui() {
	log "restoring normal Kindle UI ($1)"
	stop_touch
	rm -f "${PF_PIDFILE}" "${PF_MODEFILE}"
	say "Photo Frame stopped ($1). Restoring Kindle UI..."
	lipc-set-prop -i com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
	if [ -n "${FL_WAS}" ]; then
		lipc-set-prop -i com.lab126.powerd flIntensity "${FL_WAS}" >/dev/null 2>&1
	fi
	if [ "${WIFI_WAS}" = "1" ]; then
		lipc-set-prop -i com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1
	fi
	rm -f "${PF_STATE}/restore.sh"
	cd /
	if [ -f /etc/upstart/lab126_gui.conf ]; then
		start lab126_gui >/dev/null 2>&1 || initctl start lab126_gui >/dev/null 2>&1
	else
		start framework >/dev/null 2>&1 || /etc/init.d/framework start >/dev/null 2>&1
	fi
	# Safety net: if the UI did not come back within ~3 minutes, reboot (always restores the stock UI).
	i=0
	while [ $i -lt 36 ]; do
		sleep 5
		if pidof cvm >/dev/null 2>&1; then
			log "UI is back"
			exit 0
		fi
		i=$((i + 1))
	done
	log "UI did not come back, rebooting"
	sync
	reboot
	exit 0
}

awake_wanted() {
	[ "${TAP_LIGHT}" = "1" ] && is_charging
}

# ---- take over the screen ----
lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1
if [ "${FRONTLIGHT_OFF}" = "1" ]; then
	lipc-set-prop -i com.lab126.powerd flIntensity 0 >/dev/null 2>&1
fi
# Wi-Fi must be off, otherwise the wireless driver refuses to suspend (EBUSY).
lipc-set-prop -i com.lab126.cmd wirelessEnable 0 >/dev/null 2>&1

# Stop the Amazon GUI (pillow, awesome, cvm) so nothing draws over the photo
# (status bar clock, screensaver, sleep cover). Same method KOReader's "no framework" mode uses on FW 5.x.
log "stopping framework"
cd /
if [ -f /etc/upstart/lab126_gui.conf ]; then
	stop lab126_gui >/dev/null 2>&1 || initctl stop lab126_gui >/dev/null 2>&1
else
	stop framework >/dev/null 2>&1 || /etc/init.d/framework stop >/dev/null 2>&1
fi
sleep 3

change_photo() {
	img="$(next_image)"
	if [ -z "${img}" ]; then
		log "no ${ORIENTATION} photos found in ${PF_IMAGES}"
		say "$(no_photo_message)"
		sleep 10
		restore_ui "no photos"
	fi
	show_image "${img}"
	log "showing $(basename "${img}")  battery=$(battery_pct)%"
}

# Stay awake until the tick (charging + TAP_LIGHT). Returns 0 = tick, 2 = unplugged, 3 = stop file.
# A power-button press makes powerd leave its current state; that exits to the Kindle UI.
wait_awake() {
	target="$1"
	state0="$(powerd_state)"
	n=0
	while [ "$(date +%s)" -lt "${target}" ]; do
		sleep 2
		[ -f "${PF_STOPFILE}" ] && return 3
		st="$(powerd_state)"
		if [ -n "${state0}" ] && [ "${st}" != "${state0}" ]; then
			restore_ui "power button"
		fi
		n=$((n + 1))
		if [ $((n % 5)) -eq 0 ] && ! is_charging; then
			return 2
		fi
	done
	return 0
}

change_photo

while :; do
	[ -f "${PF_STOPFILE}" ] && { rm -f "${PF_STOPFILE}"; restore_ui "stop file"; }
	load_settings

	if battery_low; then
		restore_ui "battery $(battery_pct)%"
	fi

	if in_quiet_hours && ! quiet_ending_soon; then
		# Hold the photo already on screen; wake at the end of the window (<= 24 h).
		target="$(quiet_end_ts)"
		log "quiet hours ($(quiet_window_label), local $(local_hm)): holding photo until local $(local_hm "${target}")"
	else
		target="$(next_tick)"
	fi

	if awake_wanted; then
		# ---- awake mode: charging, keep running, a tap toggles the light ----
		start_touch
		log "awake (charging) until $(date -d "@${target}" '+%H:%M:%S' 2>/dev/null || echo "${target}")"
		wait_awake "${target}"
		r=$?
		if [ "${r}" = "2" ]; then
			log "charger unplugged: back to sleeping between photos"
			stop_touch
			[ "${FRONTLIGHT_OFF}" = "1" ] && lipc-set-prop -i com.lab126.powerd flIntensity 0 >/dev/null 2>&1
			continue
		fi
		[ "${r}" = "3" ] && continue
		change_photo
		continue
	fi

	stop_touch
	now="$(date +%s)"
	secs=$((target - now))
	chg_before="$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)"

	# let the e-ink controller finish and flush the log before suspending
	sync
	sleep 2

	slept_ok=0
	if [ -w "${RTC_WAKE}" ]; then
		# PW1 (i.MX508): mxc_rtc wakeup_enable takes a relative number of seconds; rtcwake/wakealarm do not work on PW1.
		echo -n "${secs}" >"${RTC_WAKE}" 2>/dev/null
		if echo mem >/sys/power/state 2>/dev/null; then
			slept_ok=1
		fi
	fi
	woke="$(date +%s)"

	if [ "${slept_ok}" != "1" ]; then
		# Suspend refused (e.g. Wi-Fi still up): stay awake but idle until the tick, checking for a power-button press.
		log "suspend failed, waiting awake for ${secs}s"
		state0="$(powerd_state)"
		while [ "$(date +%s)" -lt "${target}" ]; do
			sleep 5
			[ -f "${PF_STOPFILE}" ] && break
			st="$(powerd_state)"
			if [ -n "${state0}" ] && [ "${st}" != "${state0}" ]; then
				restore_ui "power button"
			fi
		done
		woke="$(date +%s)"
	fi

	if [ "${woke}" -lt $((target - 20)) ]; then
		# Woke up early: either the charger was (un)plugged, or the user pressed the power button.
		chg_after="$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)"
		if [ "${chg_after}" != "${chg_before}" ]; then
			log "early wake: charger state ${chg_before} -> ${chg_after}, continuing"
			continue
		fi
		[ -f "${PF_STOPFILE}" ] && continue
		restore_ui "power button"
	fi

	change_photo
done
