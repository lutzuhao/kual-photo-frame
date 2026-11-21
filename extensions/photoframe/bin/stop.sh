#!/bin/sh
# KUAL: Stop photo frame.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
mode="$(cat "${PF_MODEFILE}" 2>/dev/null)"
if loop_running; then
	log "stop requested from KUAL, killing ${mode} loop $(cat "${PF_PIDFILE}")"
	diag_point "stop requested from KUAL"
	diag_powerd_status
	diag_syslog
fi
kill_pidfile "${PF_PIDFILE}"
kill_pidfile "${PF_ARMERPID}"
kill_armer_monitor
kill_touch
rm -f "${PF_STOPFILE}" "${PF_MODEFILE}" "${PF_DUEFILE}" "${PF_AWAKEFILE}"
PF_LOG_TO_RAM=0
flush_log
restore_wifi_if_saved
lipc-set-prop -i com.lab126.powerd preventScreenSaver 0 >/dev/null 2>&1
if [ -f "${PF_STATE}/restore.sh" ]; then
	# takeover mode changed the light and Wi-Fi: put them back
	. "${PF_STATE}/restore.sh"
	[ -n "${FL_WAS}" ] && lipc-set-prop -i com.lab126.powerd flIntensity "${FL_WAS}" >/dev/null 2>&1
	[ "${WIFI_WAS}" = "1" ] && lipc-set-prop -i com.lab126.cmd wirelessEnable 1 >/dev/null 2>&1
	rm -f "${PF_STATE}/restore.sh"
fi
# If the GUI is not running (e.g. stopped from SSH), bring it back.
if ! pidof cvm >/dev/null 2>&1; then
	cd /
	if [ -f /etc/upstart/lab126_gui.conf ]; then start lab126_gui >/dev/null 2>&1; else start framework >/dev/null 2>&1; fi
fi
log "stopped"
exit 0
