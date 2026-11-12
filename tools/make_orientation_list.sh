#!/bin/sh
# Rebuild photoframe/landscape.txt (photos rotated 90 degrees) from manifest.csv.
# Run from the repository root after convert_photos.py, or pass the paths:
#   sh tools/make_orientation_list.sh
#   sh tools/make_orientation_list.sh path/to/manifest.csv path/to/landscape.txt
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="${1:-}"
out="${2:-}"
if [ -z "${manifest}" ]; then
	if [ -f "${root}/photoframe/manifest.csv" ]; then
		manifest="${root}/photoframe/manifest.csv"
	elif [ -f "${root}/manifest.csv" ]; then
		manifest="${root}/manifest.csv"
	else
		echo "manifest.csv not found. Run tools/convert_photos.py first, or pass the path." >&2
		exit 1
	fi
fi
if [ -z "${out}" ]; then
	out="${root}/photoframe/landscape.txt"
fi
# Column "rotated_landscape" may be 3rd (this repo) or 4th (older Drive exports).
awk -F, '
NR == 1 {
	for (i = 1; i <= NF; i++) {
		h = $i; sub(/\r$/, "", h)
		if (h == "kindle_file") c_file = i
		if (h == "rotated_landscape") c_rot = i
	}
	if (!c_file) c_file = 1
	if (!c_rot) c_rot = (NF >= 4 ? 4 : 3)
	next
}
{
	sub(/\r$/, "", $c_rot)
	if ($c_rot == "yes") print $c_file
}
' "${manifest}" >"${out}"
echo "landscape (rotated): $(wc -l <"${out}" | tr -d ' ')"
echo "wrote ${out}"
