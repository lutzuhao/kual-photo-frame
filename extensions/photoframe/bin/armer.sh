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
PF_ARMED_FOR=0

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
	cyc="$(awake_started)"
	# rtcWakeup is set on EVERY readyToSuspend of the cycle on purpose: powerd only accepts it
	# in this window and a later value wins (KindleCron, 64mb.org notes); the latest set is
	# also the most accurate. diag.txt counts how many were sent per cycle ("rts"/"rtc").
	if lipc-set-prop -i com.lab126.powerd rtcWakeup "${secs}" >/dev/null 2>&1; then
		counter_inc rtcset
		# Log once per wake cycle. powerd sends several readyToSuspend events per cycle;
		# re-setting rtcWakeup is harmless, logging every one is not (I/O delays suspend).
		# deferSuspend is NOT used any more: measured on Oasis FW 5.9.7, "deferSuspend 1"
		# made powerd re-send readyToSuspend about every second, so the Kindle stayed
		# awake for minutes to hours (log 2026-11-15, 1,331 deferrals).
		if [ "${PF_ARMED_FOR}" != "${cyc}" ]; then
			log "readyToSuspend: rtcWakeup in ${secs}s, awake ${awake}s"
			PF_ARMED_FOR="${cyc}"
		fi
	else
		counter_inc rtcfail
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
	# outOfScreenSaver and wakeupFromSuspend are recorded here too, because this continuous
	# monitor never misses events while sleepd.sh is restarting lipc-wait-event or logging.
	lipc-wait-event -m com.lab126.powerd readyToSuspend,outOfScreenSaver,wakeupFromSuspend 2>/dev/null | while read -r ev rest; do
		alive || exit 0
		case "${ev}" in
			readyToSuspend*) counter_inc rts; echo "${rest}" >"${PF_CNT}.rtsarg"; arm ;;
			outOfScreenSaver*)
				date +%s >"${PF_USEREXIT}"
				echo "${rest}" >"${PF_USEREXIT}.arg"
				log "armer: outOfScreenSaver ${rest} (state $(powerd_state))"
				;;
			wakeupFromSuspend*)
				mark_awake
				log "armer: wakeupFromSuspend ${rest} (state $(powerd_state))"
				;;
		esac
	done
	alive || break
	log "armer: lipc monitor ended after $(( $(date +%s) - t0 ))s, restarting"
	flush_log
	sleep 5
done
kill_armer_monitor
exit 0
