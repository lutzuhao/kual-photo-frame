#!/bin/sh
# KUAL: Quiet hours  (quiet.sh off|22-07|23-07|00-06)
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
preset="$1"
case "${preset}" in
	off)
		set_setting QUIET_HOURS 0
		;;
	22-07)
		set_setting QUIET_HOURS 1
		set_setting QUIET_START 22
		set_setting QUIET_END 7
		;;
	23-07)
		set_setting QUIET_HOURS 1
		set_setting QUIET_START 23
		set_setting QUIET_END 7
		;;
	00-06)
		set_setting QUIET_HOURS 1
		set_setting QUIET_START 0
		set_setting QUIET_END 6
		;;
	*)
		log "set: bad quiet-hours preset '${preset}'"
		exit 1
		;;
esac
load_settings
log "setting quiet hours $(quiet_window_label) (preset ${preset})"
if [ "${QUIET_HOURS}" = "1" ]; then
	msg="Quiet hours $(quiet_window_label) local time (TZ_OFFSET=${TZ_OFFSET})."
else
	msg="Quiet hours off: photos change around the clock."
fi
loop_running && msg="${msg} Used from the next photo change."
/bin/sh "${DIR}/gen_menu.sh" >/dev/null 2>&1
setup_fbink
say_at -3 "${msg}"
exit 0
