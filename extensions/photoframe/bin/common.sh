#!/bin/sh
# Photo Frame for jailbroken Kindle (PW1 / Oasis / FW 5.x). busybox 1.17 ash compatible.
# Paths can be overridden from the environment (used only for testing on a computer).
PF_HOME="${PF_HOME:-/mnt/us/photoframe}"
PF_EXT="${PF_EXT:-/mnt/us/extensions/photoframe}"
PF_TMP="${PF_TMP:-/var/tmp}"
PF_IMAGES="${PF_HOME}/images"
PF_STATE="${PF_HOME}/state"
PF_LOG="${PF_HOME}/log.txt"
PF_LANDSCAPE_LIST="${PF_HOME}/landscape.txt"
PF_SETTINGS="${PF_HOME}/settings.sh"
PF_STOPFILE="${PF_HOME}/STOP"
# runtime files live on tmpfs (never keep files open on /mnt/us: it is exported over USB)
PF_RUN="${PF_TMP}/photoframe-run"
PF_PIDFILE="${PF_TMP}/photoframe.pid"
PF_MODEFILE="${PF_TMP}/photoframe.mode"
PF_ARMERPID="${PF_TMP}/photoframe.armer.pid"
PF_TOUCHPID="${PF_TMP}/photoframe.touch.pid"
PF_DUEFILE="${PF_TMP}/photoframe.due"
PF_RAMLOG="${PF_TMP}/photoframe.log"
PF_FBINK="${PF_TMP}/pf_fbink"
PF_AWAKEFILE="${PF_TMP}/photoframe.awake"
PF_WIFIFILE="${PF_TMP}/photoframe.wifi"
RTC_WAKE="/sys/devices/platform/mxc_rtc.0/wakeup_enable"
if [ ! -e "$RTC_WAKE" ]; then for _r in /sys/devices/platform/*rtc*/wakeup_enable /sys/devices/platform/*/*rtc*/wakeup_enable; do [ -e "$_r" ] && { RTC_WAKE="$_r"; break; }; done; fi
PATH="/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"
export PATH

# Strip a leading + and any leading zeros so $(( )) is decimal, not octal (08).
# $1 = value, $2 = default if empty or not a number (optional sign allowed on input).
norm_int() {
	_v="$1"
	_d="$2"
	_s=1
	case "${_v}" in
		-*) _s=-1; _v="${_v#-}" ;;
		+*) _v="${_v#+}" ;;
	esac
	case "${_v}" in
		''|*[!0-9]*) echo "${_d}"; return ;;
	esac
	while [ "${#_v}" -gt 1 ] && [ "${_v#0}" != "${_v}" ]; do
		_v="${_v#0}"
	done
	[ -z "${_v}" ] && _v=0
	echo $((_s * _v))
}

# Pad 0-23 as two digits (for labels only; do not feed this to $(( ))).
pad2() {
	if [ "$1" -lt 10 ]; then echo "0$1"; else echo "$1"; fi
}

load_settings() {
	INTERVAL_MIN=15
	ORIENTATION=all
	FRAME_MODE=sleep
	TAP_LIGHT=0
	TAP_LIGHT_LEVEL=0
	TOUCH_DEV=
	LOW_BATTERY=8
	FRONTLIGHT_OFF=1
	SS_DELAY=3
	SHOW_BATTERY=1
	QUIET_HOURS=1
	QUIET_START=23
	QUIET_END=7
	TZ_OFFSET=+8
	[ -f "${PF_SETTINGS}" ] && . "${PF_SETTINGS}"
	case "${INTERVAL_MIN}" in ''|*[!0-9]*) INTERVAL_MIN=15 ;; esac
	[ "${INTERVAL_MIN}" -lt 1 ] && INTERVAL_MIN=1
	# Allowed KUAL choices: 15/30 min, 1/6/12/24 hr. Retired values (5, 10, 120, ...) act as 15.
	case "${INTERVAL_MIN}" in 15|30|60|360|720|1440) ;; *) INTERVAL_MIN=15 ;; esac
	INTERVAL=$((INTERVAL_MIN * 60))
	case "${ORIENTATION}" in all|portrait|landscape) ;; *) ORIENTATION=all ;; esac
	case "${FRAME_MODE}" in sleep|takeover) ;; *) FRAME_MODE=sleep ;; esac
	case "${TAP_LIGHT}" in 1) ;; *) TAP_LIGHT=0 ;; esac
	TAP_LIGHT_LEVEL="$(norm_int "${TAP_LIGHT_LEVEL}" 0)"
	LOW_BATTERY="$(norm_int "${LOW_BATTERY}" 8)"
	SS_DELAY="$(norm_int "${SS_DELAY}" 3)"
	case "${SHOW_BATTERY}" in 1) ;; *) SHOW_BATTERY=0 ;; esac
	case "${QUIET_HOURS}" in 1) ;; *) QUIET_HOURS=0 ;; esac
	QUIET_START="$(norm_int "${QUIET_START}" 23)"
	QUIET_END="$(norm_int "${QUIET_END}" 7)"
	[ "${QUIET_START}" -lt 0 ] || [ "${QUIET_START}" -gt 23 ] && QUIET_START=23
	[ "${QUIET_END}" -lt 0 ] || [ "${QUIET_END}" -gt 23 ] && QUIET_END=7
	TZ_OFFSET="$(tz_offset_hours)"
}

# Hours to add to the Kindle clock (typically UTC) to get local time. Default +8 (Asia/Taipei).
# Accepts 8, +8, +08, -5. Values outside -12..14 fall back to 8.
tz_offset_hours() {
	_h="$(norm_int "${TZ_OFFSET:-8}" 8)"
	if [ "${_h}" -lt -12 ] || [ "${_h}" -gt 14 ]; then
		echo 8
		return
	fi
	echo "${_h}"
}

# Seconds since local midnight (0..86399). Optional $1 = unix epoch (default: now).
local_tod() {
	_now="$1"
	[ -n "${_now}" ] || _now="$(date +%s)"
	_le=$((_now + $(tz_offset_hours) * 3600))
	_tod=$((_le % 86400))
	[ "${_tod}" -lt 0 ] && _tod=$((_tod + 86400))
	echo "${_tod}"
}

local_hour() {
	echo $(( $(local_tod "$1") / 3600 ))
}

# HH:MM in local time. Optional $1 = unix epoch.
local_hm() {
	_tod="$(local_tod "$1")"
	echo "$(pad2 $((_tod / 3600))):$(pad2 $(( (_tod % 3600) / 60 )))"
}

# 0 if local time is inside the quiet window [START, END).
# The window wraps midnight when START > END (e.g. 23-07). START == END is treated as off.
in_quiet_hours() {
	[ "${QUIET_HOURS}" = "1" ] || return 1
	[ "${QUIET_START}" = "${QUIET_END}" ] && return 1
	_h="$(local_hour "$1")"
	if [ "${QUIET_START}" -lt "${QUIET_END}" ]; then
		[ "${_h}" -ge "${QUIET_START}" ] && [ "${_h}" -lt "${QUIET_END}" ]
	else
		[ "${_h}" -ge "${QUIET_START}" ] || [ "${_h}" -lt "${QUIET_END}" ]
	fi
}

# Unix epoch of the next local QUIET_END (always in the future, at most ~24h).
# Optional $1 = unix epoch to compute from (default: now). Used by tests and by the daemons.
quiet_end_ts() {
	_now="$1"
	[ -n "${_now}" ] || _now="$(date +%s)"
	_end_tod=$((QUIET_END * 3600))
	_tod="$(local_tod "${_now}")"
	if [ "${_tod}" -lt "${_end_tod}" ]; then
		_delta=$((_end_tod - _tod))
	else
		_delta=$((86400 - _tod + _end_tod))
	fi
	# Never return a near-zero wake (would trip the armer's < 20 s fallback to next_tick).
	[ "${_delta}" -lt 30 ] && _delta=$((_delta + 86400))
	echo $((_now + _delta))
}

quiet_window_label() {
	if [ "${QUIET_HOURS}" != "1" ]; then
		echo "off"
		return
	fi
	echo "$(pad2 "${QUIET_START}"):00-$(pad2 "${QUIET_END}"):00"
}

# Menu mark id: off | 22-07 | 23-07 | 00-06 | custom
quiet_preset_id() {
	if [ "${QUIET_HOURS}" != "1" ]; then
		echo off
		return
	fi
	case "${QUIET_START}-${QUIET_END}" in
		22-7) echo 22-07 ;;
		23-7) echo 23-07 ;;
		0-6) echo 00-06 ;;
		*) echo custom ;;
	esac
}

# Path of the last photo shown, if the file is still there (does not advance the shuffle bag).
current_image() {
	_n="$(cat "${PF_STATE}/last.txt" 2>/dev/null)"
	if [ -n "${_n}" ] && [ -f "${PF_IMAGES}/${_n}" ]; then
		echo "${PF_IMAGES}/${_n}"
		return 0
	fi
	return 1
}

load_settings

mkdir -p "${PF_STATE}" 2>/dev/null

# PF_LOG_TO_RAM=1 (long-running sleep-screen daemons): log to tmpfs, copy to /mnt/us only when it is safe.
log() {
	if [ "${PF_LOG_TO_RAM}" = "1" ]; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"${PF_RAMLOG}"
		return 0
	fi
	if [ -f "${PF_LOG}" ] && [ "$(wc -c <"${PF_LOG}")" -gt 300000 ]; then
		tail -n 1000 "${PF_LOG}" >"${PF_LOG}.tmp" && mv "${PF_LOG}.tmp" "${PF_LOG}"
	fi
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"${PF_LOG}"
}

# Is /mnt/us usable (not exported to a computer over USB)?
userstore_ok() {
	v="$(lipc-get-prop com.lab126.volumd userstoreIsAvailable 2>/dev/null)"
	[ "${v}" = "0" ] && return 1
	[ -d "${PF_IMAGES}" ]
}

flush_log() {
	[ -s "${PF_RAMLOG}" ] || return 0
	userstore_ok || return 0
	if [ -f "${PF_LOG}" ] && [ "$(wc -c <"${PF_LOG}")" -gt 300000 ]; then
		tail -n 1000 "${PF_LOG}" >"${PF_LOG}.tmp" && mv "${PF_LOG}.tmp" "${PF_LOG}"
	fi
	cat "${PF_RAMLOG}" >>"${PF_LOG}" 2>/dev/null && rm -f "${PF_RAMLOG}"
}

# set_setting KEY VALUE: change (or add) KEY=VALUE in settings.sh
set_setting() {
	k="$1"
	v="$2"
	f="${PF_SETTINGS}"
	if [ -f "${f}" ] && grep -q "^${k}=" "${f}"; then
		sed "s|^${k}=.*|${k}=${v}|" "${f}" >"${f}.tmp" && mv "${f}.tmp" "${f}"
	else
		echo "${k}=${v}" >>"${f}"
	fi
	sync
}

# FBInk: the full build (with image support) installed by the KindleModding hotfix.
# KOReader also ships FBInk. /mnt/us is a vfat/fuse mount, so copy the binary to tmpfs
# before running it (same trick KOReader uses).
setup_fbink() {
	[ -x "${PF_FBINK}" ] && return 0
	for c in /mnt/us/libkh/bin/fbink /usr/bin/fbink /mnt/us/usbnet/bin/fbink /mnt/us/koreader/fbink /mnt/us/koreader/bin/fbink; do
		if [ -f "${c}" ]; then
			cp -f "${c}" "${PF_FBINK}" 2>/dev/null && chmod 755 "${PF_FBINK}" 2>/dev/null
			if "${PF_FBINK}" -h >/dev/null 2>&1 || [ $? -lt 126 ]; then
				return 0
			fi
			rm -f "${PF_FBINK}"
		fi
	done
	return 1
}

say() {
	# Clear the screen and print a short (ASCII) message centered on it.
	if [ -x "${PF_FBINK}" ]; then
		"${PF_FBINK}" -q -c -f -m -M -S 3 "$*" >/dev/null 2>&1 && return 0
	fi
	eips -c >/dev/null 2>&1
	eips 3 30 "$*" >/dev/null 2>&1
}

# say_at ROW TEXT: print one line without clearing (row counted from the top; negative = from the bottom)
say_at() {
	r="$1"
	shift
	if [ -x "${PF_FBINK}" ]; then
		"${PF_FBINK}" -q -m -y "${r}" "$*" >/dev/null 2>&1 && return 0
	fi
	[ "${r}" -lt 0 ] && r=$((40 + r))
	eips 1 "${r}" "$*" >/dev/null 2>&1
}

# Small, unobtrusive battery percentage in the bottom-right corner (e.g. "87%" or "87%+" if charging).
# Partial refresh only: never flashes or clears the photo. Failures are ignored so the photo stays.
overlay_battery() {
	[ "${SHOW_BATTERY}" = "1" ] || return 0
	_pct="$(battery_pct)"
	_txt="${_pct}%"
	is_charging && _txt="${_pct}%+"
	if [ -x "${PF_FBINK}" ]; then
		# -x/-y negative = from the right/bottom. -i inverts for contrast on mixed photos.
		# Do not use -c or -f (that would clear or flash the whole panel).
		_col=$((${#_txt} + 1))
		if "${PF_FBINK}" -q -w -i -x "-${_col}" -y -1 "${_txt}" >/dev/null 2>&1; then
			return 0
		fi
	fi
	_w=""; _h=""
	if [ -r /sys/class/graphics/fb0/virtual_size ]; then
		_vs="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)"
		_w="${_vs%%,*}"
		_h="${_vs##*,}"
	fi
	_w="$(norm_int "${_w}" 758)"
	_h="$(norm_int "${_h}" 1024)"
	_cols=$((_w / 8))
	_rows=$((_h / 16))
	[ "${_cols}" -lt 8 ] && _cols=50
	[ "${_rows}" -lt 4 ] && _rows=40
	_x=$((_cols - ${#_txt} - 1))
	_y=$((_rows - 2))
	[ "${_x}" -lt 0 ] && _x=0
	[ "${_y}" -lt 0 ] && _y=0
	eips "${_x}" "${_y}" "${_txt}" >/dev/null 2>&1
}

show_image() {
	img="$1"
	if [ -x "${PF_FBINK}" ]; then
		# Deghost: flash the whole panel black, then white, then draw the photo with a full refresh.
		"${PF_FBINK}" -q -k -f -w -B BLACK >/dev/null 2>&1
		"${PF_FBINK}" -q -k -f -w -B WHITE >/dev/null 2>&1
		# -c clear, -f flashing full refresh, -w wait for the refresh, dither = ordered dithering to the 16-level e-ink palette
		if "${PF_FBINK}" -q -c -f -w -g "file=${img},halign=CENTER,valign=CENTER,dither" >/dev/null 2>&1; then
			overlay_battery
			return 0
		fi
		log "fbink failed on ${img}, trying eips"
	fi
	eips -c >/dev/null 2>&1
	eips -c >/dev/null 2>&1
	eips -f -g "${img}" >/dev/null 2>&1
	overlay_battery
}

battery_pct() {
	b=""
	[ -r /sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity ] && \
		b="$(cat /sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity 2>/dev/null)"
	[ -z "${b}" ] && b="$(gasgauge-info -c 2>/dev/null)"
	b="$(echo "${b}" | tr -cd '0-9')"
	[ -z "${b}" ] && b=100
	echo "${b}"
}

is_charging() {
	c="$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)"
	[ "${c}" = "1" ]
}

battery_low() {
	[ "$(battery_pct)" -le "${LOW_BATTERY}" ] && ! is_charging
}

powerd_state() {
	lipc-get-prop com.lab126.powerd state 2>/dev/null
}

# Next clock tick (epoch seconds) at least 30 s away. Ticks are multiples of INTERVAL.
# Whole-hour TZ offsets (e.g. UTC+8) share the same :00 :15 :30 :45 boundaries as UTC.
next_tick() {
	now="$(date +%s)"
	t=$(( (now / INTERVAL + 1) * INTERVAL ))
	[ $((t - now)) -lt 30 ] && t=$((t + INTERVAL))
	echo "${t}"
}

interval_allowed() {
	case "$1" in 15|30|60|360|720|1440) return 0 ;; *) return 1 ;; esac
}

# "every 15 min" / "every 1 hour" / ...
interval_label() {
	case "${INTERVAL_MIN}" in
		60) echo "every 1 hour" ;;
		360) echo "every 6 hours" ;;
		720) echo "every 12 hours" ;;
		1440) echo "every 24 hours" ;;
		*) echo "every ${INTERVAL_MIN} min" ;;
	esac
}

# If settings.sh still has a retired interval (e.g. 5 min), persist 15 min.
migrate_interval_setting() {
	cur=""
	[ -f "${PF_SETTINGS}" ] && cur="$(awk -F= '/^INTERVAL_MIN=/{print $2; exit}' "${PF_SETTINGS}")"
	cur="$(echo "${cur}" | tr -cd '0-9')"
	[ -z "${cur}" ] && return 0
	interval_allowed "${cur}" && return 0
	set_setting INTERVAL_MIN 15
	INTERVAL_MIN=15
	INTERVAL=$((INTERVAL_MIN * 60))
	log "migrated INTERVAL_MIN=${cur} -> 15"
}

awake_started() {
	a="$(cat "${PF_AWAKEFILE}" 2>/dev/null)"
	case "${a}" in ''|*[!0-9]*) a=0 ;; esac
	echo "${a}"
}

awake_secs() {
	s="$(awake_started)"
	[ "${s}" -gt 0 ] || { echo 0; return; }
	echo $(( $(date +%s) - s ))
}

mark_awake() {
	date +%s >"${PF_AWAKEFILE}"
}

# Best-effort write of a powerd int property; log whether lipc accepted it.
try_powerd_int() {
	_prop="$1"
	_val="$2"
	_err="${PF_TMP}/photoframe.lipc-err"
	if lipc-set-prop -i com.lab126.powerd "${_prop}" "${_val}" >"${_err}" 2>&1; then
		log "powerd ${_prop}=${_val}: accepted"
		rm -f "${_err}"
		return 0
	fi
	_msg="$(tr '\n' ' ' <"${_err}" 2>/dev/null)"
	log "powerd ${_prop}=${_val}: rejected${_msg:+ (${_msg})}"
	rm -f "${_err}"
	return 1
}

powerd_remaining() {
	# "56.331120" or "Unknown" from: Remaining time in this state: ...
	lipc-get-prop com.lab126.powerd status 2>/dev/null | awk -F': ' '/Remaining time in this state/{print $2; exit}'
}

# After a photo is on the sleep screen, try to shrink powerd's ~60 s screenSaver (t2) dwell
# so readyToSuspend starts sooner. t2_timeout itself is a kdb/rootfs setting we do not change.
# suspendGrace is the documented T2-related lipc property; behaviour is unconfirmed, so log
# whether the set was accepted and whether remaining time changed.
nudge_ss_timeout() {
	_st="$(powerd_state)"
	_rem="$(powerd_remaining)"
	log "nudge_ss_timeout: state=${_st} remaining=${_rem} awake=$(awake_secs)s"
	try_powerd_int suspendGrace 1 || true
	_rem2="$(powerd_remaining)"
	if [ -n "${_rem2}" ] && [ "${_rem2}" != "${_rem}" ]; then
		log "nudge_ss_timeout: remaining '${_rem}' -> '${_rem2}'"
	fi
}

# Sleep-screen mode: turn Wi-Fi off while showing photos (saves power during the t2 wait).
# The previous wirelessEnable value is restored when the user leaves the sleep screen, or on Stop.
save_wifi_and_off() {
	if [ ! -f "${PF_WIFIFILE}" ]; then
		lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null | tr -cd '0-9' >"${PF_WIFIFILE}"
		log "wifi: was $(cat "${PF_WIFIFILE}" 2>/dev/null), switching off for sleep screen"
	fi
	lipc-set-prop -i com.lab126.cmd wirelessEnable 0 >/dev/null 2>&1
}

restore_wifi_if_saved() {
	if [ -f "${PF_WIFIFILE}" ]; then
		w="$(cat "${PF_WIFIFILE}" 2>/dev/null)"
		rm -f "${PF_WIFIFILE}"
		if [ "${w}" = "1" ]; then
			lipc-set-prop -i com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1
			log "wifi: restored on"
		fi
	fi
}

orientation_label() {
	case "${ORIENTATION}" in
		portrait) echo "vertical photos" ;;
		landscape) echo "horizontal (rotated) photos" ;;
		*) echo "photos" ;;
	esac
}

# Print the photo file names that match ORIENTATION, one per line.
# Returns 2 when a filter is set but photoframe/landscape.txt is missing.
list_photos() {
	if [ "${ORIENTATION}" != "all" ] && [ ! -f "${PF_LANDSCAPE_LIST}" ]; then
		return 2
	fi
	ls "${PF_IMAGES}" 2>/dev/null | grep -i -e '\.jpg$' -e '\.jpeg$' -e '\.png$' | \
		awk -v mode="${ORIENTATION}" -v lf="${PF_LANDSCAPE_LIST}" '
		BEGIN {
			if (mode != "all") {
				while ((getline l < lf) > 0) { sub(/\r$/, "", l); if (l != "") land[l] = 1 }
				close(lf)
			}
		}
		mode == "all" { print; next }
		mode == "landscape" { if ($0 in land) print; next }
		mode == "portrait" { if (!($0 in land)) print; next }'
	return 0
}

photo_count() {
	list_photos | wc -l | tr -cd '0-9'
}

# Shuffle bag: every matching photo is shown once before any repeats.
# The bag is rebuilt when ORIENTATION changes.
next_image() {
	bag="${PF_STATE}/bag.txt"
	last="$(cat "${PF_STATE}/last.txt" 2>/dev/null)"
	if [ "$(cat "${PF_STATE}/bag_filter.txt" 2>/dev/null)" != "${ORIENTATION}" ]; then
		rm -f "${bag}"
	fi
	if [ ! -s "${bag}" ]; then
		list_photos | \
			awk -v seed="$(( $(date +%s) % 100000 + $$ ))" 'BEGIN{srand(seed)} {printf "%.8f\t%s\n", rand(), $0}' | sort | cut -f2- >"${bag}.new"
		# avoid showing the same photo twice in a row across bag boundaries
		if [ -n "${last}" ] && [ "$(wc -l <"${bag}.new")" -gt 1 ] && [ "$(head -n 1 "${bag}.new")" = "${last}" ]; then
			{ tail -n +2 "${bag}.new"; echo "${last}"; } >"${bag}.tmp" && mv "${bag}.tmp" "${bag}.new"
		fi
		mv "${bag}.new" "${bag}"
		echo "${ORIENTATION}" >"${PF_STATE}/bag_filter.txt"
		log "new shuffle bag: $(wc -l <"${bag}") ${ORIENTATION} photos"
	fi
	while [ -s "${bag}" ]; do
		n="$(head -n 1 "${bag}")"
		tail -n +2 "${bag}" >"${bag}.tmp" && mv "${bag}.tmp" "${bag}"
		if [ -f "${PF_IMAGES}/${n}" ]; then
			echo "${n}" >"${PF_STATE}/last.txt"
			echo "${PF_IMAGES}/${n}"
			return 0
		fi
	done
	return 1
}

# Message for "no photos match"; used by start/preview/daemons.
no_photo_message() {
	if [ "${ORIENTATION}" != "all" ] && [ ! -f "${PF_LANDSCAPE_LIST}" ]; then
		echo "Photo Frame: photoframe/landscape.txt is missing, so photos cannot be filtered. Choose Photo orientation > All photos."
	elif [ "${ORIENTATION}" = "all" ]; then
		echo "Photo Frame: no photos found in /mnt/us/photoframe/images"
	else
		echo "Photo Frame: no $(orientation_label) found. Open KUAL > Photo Frame > Photo orientation and choose another option."
	fi
}

loop_running() {
	[ -f "${PF_PIDFILE}" ] && kill -0 "$(cat "${PF_PIDFILE}")" 2>/dev/null
}

# Kill the armer's continuous lipc monitor (left behind when the armer shell is killed).
kill_armer_monitor() {
	for p in /proc/[0-9]*; do
		c="$(tr '\000' ' ' <"${p}/cmdline" 2>/dev/null)"
		case "${c}" in
			"lipc-wait-event -m com.lab126.powerd readyToSuspend"*) kill -9 "${p##*/}" 2>/dev/null ;;
		esac
	done
}

kill_pidfile() {
	if [ -f "$1" ]; then
		p="$(cat "$1" 2>/dev/null)"
		[ -n "${p}" ] && kill -9 "${p}" 2>/dev/null
		rm -f "$1"
	fi
}

# busybox 1.17 ash has no "command -v": look the tool up on PATH by hand.
have() {
	_old_ifs="${IFS}"; IFS=:
	for _d in ${PATH} /usr/bin /usr/sbin /bin /sbin /mnt/us/libkh/bin; do
		if [ -x "${_d}/$1" ]; then IFS="${_old_ifs}"; return 0; fi
	done
	IFS="${_old_ifs}"
	return 1
}

# End the tap-light listener and the dd it may have left blocked on the input device.
kill_touch() {
	kill_pidfile "${PF_TOUCHPID}"
	for p in /proc/[0-9]*; do
		c="$(tr '\000' ' ' <"${p}/cmdline" 2>/dev/null)"
		case "${c}" in
			"dd if=/dev/input/"*|*"touch.sh"*) [ "${p##*/}" != "$$" ] && kill -9 "${p##*/}" 2>/dev/null ;;
		esac
	done
}

# Run a script detached from KUAL (own session if setsid exists), from the tmpfs copy.
launch_detached() {
	if have setsid; then
		setsid /bin/sh "$@" </dev/null >/dev/null 2>&1 &
	else
		( trap '' HUP TERM; exec /bin/sh "$@" </dev/null >/dev/null 2>&1 ) &
	fi
}

# Copy the scripts to tmpfs so long-running loops never hold files open on /mnt/us.
copy_to_run() {
	rm -rf "${PF_RUN}"
	mkdir -p "${PF_RUN}" && cp -f "$1"/*.sh "${PF_RUN}/"
}
