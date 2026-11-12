#!/bin/sh
# KUAL: Preview one photo now (the normal UI keeps running; any tap or page turn redraws it).
DIR="$(cd "$(dirname "$0")" && pwd)"
. "${DIR}/common.sh"
setup_fbink || log "preview: FBInk not found, using eips"
sleep 2
img="$(next_image)"
if [ -z "${img}" ]; then
	say "$(no_photo_message)"
	log "preview: no ${ORIENTATION} photos"
	exit 0
fi
show_image "${img}" && log "preview: showed $(basename "${img}") (fbink: $([ -x "${PF_FBINK}" ] && echo yes || echo no))"
exit 0
