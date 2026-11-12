#!/bin/sh
# Photo Frame, sleep-screen mode helper: whenever powerd is about to suspend (readyToSuspend),
# ask it to wake the Kindle at the next photo change. powerd only accepts rtcWakeup in this window.
# Uses one continuous lipc monitor (-m) so no readyToSuspend broadcast is missed between restarts
# (same approach as the onlinescreensaver scheduler).
DIR="$(cd "$(dirname "$0")" && pwd)"
PF_LOG_TO_RAM=1
. "${DIR}/common.sh"
trap '' HUP
cd /
kill_armer_monitor
log "armer start (pid $$), RTC_WAKE=${RTC_WAKE} $( [ -e "${RTC_WAKE}" ] && echo exists || echo missing )"
flush_log

# Flush /mnt/us once per wake cycle (I/O during later readyToSuspend retries can delay suspend).
PF_FLUSHED_FOR=0

arm() {
	load_settings
	awake="$(awake_secs)"
	if battery_low; then
		log "readyToSuspend: battery $(battery_pct)%, no wake-up alarm (Kindle just sleeps), awake ${awake}s"
		flush_log
		return
	fi
	now="$(date +%s)"
	due="$(cat "${PF_DUEFILE}" 2>/dev/null)"
	case "${due}" in ''|*[!0-9]*) due=0 ;; esac
	secs=$((due - now))
	if [ "${secs}" -lt 20 ]; then
		secs=$(( $(next_tick) - now ))
	fi
	# Low-battery hold sets due ~1 year ahead; do not arm an RTC wake for that.
	# 200000 s (~2.3 days) is above a 24 h interval and above a quiet-hours
	# sleep-through (at most ~24 h). Do not lower this; a <= 24 h wake must pass.
	if [ "${secs}" -gt 200000 ]; then
		log "readyToSuspend: due is ${secs}s away (hold), no wake-up alarm, awake ${awake}s"
		flush_log
		return
	fi
	if lipc-set-prop -i com.lab126.powerd rtcWakeup "${secs}" >/dev/null 2>&1; then
		log "readyToSuspend: rtcWakeup in ${secs}s, awake ${awake}s"
		# Shrink the readyToSuspend retry window (this firmware sends ~6 events, 5 s apart).
		# MobileRead t=221497: deferSuspend N is only accepted during readyToSuspend and
		# sets remaining time in that state to ~N seconds. 1 = suspend almost immediately
		# after this arm. (KindleCron claimed this returns to active; those measured logs
		# stayed in readyToSuspend.)
		if lipc-set-prop -i com.lab126.powerd deferSuspend 1 >/dev/null 2>&1; then
			log "readyToSuspend: deferSuspend=1 accepted, state $(powerd_state)"
		else
			log "readyToSuspend: deferSuspend=1 rejected, state $(powerd_state)"
		fi
	else
		log "readyToSuspend: rtcWakeup rejected, writing ${RTC_WAKE} instead (${secs}s), awake ${awake}s"
		[ -w "${RTC_WAKE}" ] && echo -n "${secs}" >"${RTC_WAKE}" 2>/dev/null
	fi
	cyc="$(awake_started)"
	if [ "${PF_FLUSHED_FOR}" != "${cyc}" ]; then
		flush_log
		PF_FLUSHED_FOR="${cyc}"
	fi
}

alive() {
	[ -f "${PF_PIDFILE}" ] && kill -0 "$(cat "${PF_PIDFILE}")" 2>/dev/null
}

while alive; do
	t0="$(date +%s)"
	lipc-wait-event -m com.lab126.powerd readyToSuspend 2>/dev/null | while read -r ev rest; do
		alive || exit 0
		case "${ev}" in
			readyToSuspend*) arm ;;
		esac
	done
	alive || break
	log "armer: lipc monitor ended after $(( $(date +%s) - t0 ))s, restarting"
	flush_log
	sleep 5
done
kill_armer_monitor
exit 0
