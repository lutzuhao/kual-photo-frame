#!/bin/sh
# Writes the KUAL menu (menu.json) with "* " in front of the current choices.
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
out="${PF_EXT}/menu.json"

mark() {
	# mark CURRENT VALUE LABEL
	if [ "$1" = "$2" ]; then echo "* $3"; else echo "$3"; fi
}

# item NAME PRIORITY ACTION PARAMS EXITMENU STATUS_TEXT LAST(1 = no trailing comma)
item() {
	sep=","
	[ "$7" = "1" ] && sep=""
	pl=""
	[ -n "$4" ] && pl="
			\"params\": \"$4\","
	cat <<ITEM
		{
			"name": "$1",
			"priority": $2,
			"action": "$3",${pl}
			"exitmenu": $5,
			"status": false,
			"internal": "status $6"
		}${sep}
ITEM
}

# submenu NAME PRIORITY: open; endsub LAST
submenu() {
	cat <<SUB
		{
			"name": "$1",
			"priority": $2,
			"items": [
SUB
}
endsub() {
	sep=","
	[ "$1" = "1" ] && sep=""
	cat <<SUB
			]
		}${sep}
SUB
}

{
	echo '{'
	echo '	"items": ['
	echo '		{'
	echo '			"name": "Photo Frame",'
	echo '			"priority": 0,'
	echo '			"items": ['
	item "Start photo frame" 1 ./bin/start.sh "" true "Starting photo frame . . ." 0
	item "Stop photo frame" 2 ./bin/stop.sh "" false "Photo frame stopped" 0
	submenu "Change interval" 3
	migrate_interval_setting
	i=0
	for m in 15 30 60 360 720 1440; do
		i=$((i + 1))
		case "${m}" in
			60) l="Every 1 hour" ;;
			360) l="Every 6 hours" ;;
			720) l="Every 12 hours" ;;
			1440) l="Every 24 hours" ;;
			*) l="Every ${m} min" ;;
		esac
		last=0
		[ "${m}" = "1440" ] && last=1
		item "$(mark "${INTERVAL_MIN}" "${m}" "${l}")" "${i}" ./bin/interval.sh "${m}" false "Interval: ${l}" "${last}"
	done
	endsub 0
	submenu "Photo orientation" 4
	item "$(mark "${ORIENTATION}" all "All photos")" 1 ./bin/orientation.sh all false "Showing all photos" 0
	item "$(mark "${ORIENTATION}" portrait "Only vertical photos")" 2 ./bin/orientation.sh portrait false "Showing only vertical photos" 0
	item "$(mark "${ORIENTATION}" landscape "Only horizontal (rotated) photos")" 3 ./bin/orientation.sh landscape false "Showing only horizontal photos" 1
	endsub 0
	submenu "Exit style" 5
	item "$(mark "${FRAME_MODE}" sleep "Quick exit: sleep-screen mode")" 1 ./bin/mode.sh sleep false "Exit style: quick (sleep screen)" 0
	item "$(mark "${FRAME_MODE}" takeover "Full takeover: slow exit, restarts UI")" 2 ./bin/mode.sh takeover false "Exit style: full takeover" 1
	endsub 0
	submenu "Tap to toggle light" 6
	item "$(mark "${TAP_LIGHT}" 0 "Off: always sleep between photos")" 1 ./bin/taplight.sh 0 false "Tap light: off" 0
	item "$(mark "${TAP_LIGHT}" 1 "On while charging: stay awake, full takeover")" 2 ./bin/taplight.sh 1 false "Tap light: on while charging" 1
	endsub 0
	submenu "Battery display" 7
	item "$(mark "${SHOW_BATTERY}" 1 "On: show percentage in the corner")" 1 ./bin/battery.sh 1 false "Battery display: on" 0
	item "$(mark "${SHOW_BATTERY}" 0 "Off")" 2 ./bin/battery.sh 0 false "Battery display: off" 1
	endsub 0
	submenu "Quiet hours" 8
	qid="$(quiet_preset_id)"
	item "$(mark "${qid}" off "Off: change photos around the clock")" 1 ./bin/quiet.sh off false "Quiet hours: off" 0
	item "$(mark "${qid}" 22-07 "22:00-07:00")" 2 ./bin/quiet.sh 22-07 false "Quiet hours: 22:00-07:00" 0
	item "$(mark "${qid}" 23-07 "23:00-07:00")" 3 ./bin/quiet.sh 23-07 false "Quiet hours: 23:00-07:00" 0
	item "$(mark "${qid}" 00-06 "00:00-06:00")" 4 ./bin/quiet.sh 00-06 false "Quiet hours: 00:00-06:00" 1
	endsub 0
	item "Preview one photo now" 9 ./bin/once.sh "" true "Showing one photo . . ." 0
	item "Reset shuffle order" 10 ./bin/reset.sh "" false "Shuffle order reset" 0
	item "Show status" 11 ./bin/status.sh "" false "Photo Frame status" 1
	echo '			]'
	echo '		}'
	echo '	]'
	echo '}'
} >"${out}.tmp" && mv "${out}.tmp" "${out}"
