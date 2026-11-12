#!/bin/sh
# Photo Frame, takeover mode while charging (TAP_LIGHT=1): a tap on the screen toggles the front light.
# Usage: touch.sh <event device> <light level for "on">
# Reads raw input events with dd (one 16-byte struct input_event per read on the 32-bit PW1 kernel).
# A "tap" is the first event after at least 0.8 s without any touch events, so one finger
# down/move/up sequence toggles the light only once.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
trap '' HUP
cd /
dev="$1"
on="$2"
case "${on}" in ''|*[!0-9]*|0) on=12 ;; esac

uptime_cs() {
	read up rest </proc/uptime
	s="${up%%.*}"
	c="${up##*.}"
	c="${c#0}"
	[ -z "${c}" ] && c=0
	echo $((s * 100 + c))
}

log "tap light: listening on ${dev}, on-level ${on}"
evf="${PF_TMP}/photoframe.ev"
bad=0
last=0
while :; do
	rm -f "${evf}"
	dd if="${dev}" of="${evf}" bs=16 count=1 2>/dev/null
	if [ ! -s "${evf}" ]; then
		# read error or end of file: not a touch
		bad=$((bad + 1))
		[ "${bad}" -eq 3 ] && log "tap light: cannot read ${dev}"
		loop_running || exit 0
		sleep 5
		continue
	fi
	bad=0
	# Stop listening as soon as the photo frame is no longer running (e.g. after exit).
	if ! loop_running; then
		log "tap light: frame not running, listener exits"
		exit 0
	fi
	now="$(uptime_cs)"
	if [ $((now - last)) -ge 80 ]; then
		cur="$(lipc-get-prop com.lab126.powerd flIntensity 2>/dev/null | tr -cd '0-9')"
		[ -z "${cur}" ] && cur=0
		if [ "${cur}" -gt 0 ]; then
			lipc-set-prop -i com.lab126.powerd flIntensity 0 >/dev/null 2>&1
			log "tap: light off (was ${cur})"
		else
			lipc-set-prop -i com.lab126.powerd flIntensity "${on}" >/dev/null 2>&1
			log "tap: light on (${on})"
		fi
	fi
	last="${now}"
done
