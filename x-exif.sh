#!/bin/bash

if ! command -v exiftool >/dev/null 2>&1; then
	echo "ERROR: exiftool not found. Install it from: https://exiftool.org/" >&2
	exit 1
fi

if [ $# -eq 0 ]; then
	echo "Usage: $0 [-cn] [filespec] [-- exiftool-options]" #$'\n'
	echo "Options:"
	echo	$'\t'-c$'\t'"Use Create Date instead of DateTimeOriginal (e.g., for MOV files)."
	echo	$'\t'-n$'\t'"Dry run."
	echo	$'\t'--$'\t'"Pass any following arguments through to exiftool."
	echo
	echo	$'\t'"EX: x-exif -n [^0-9]*"
	echo	$'\t'"EX: x-exif IMG_*.MOV -- -api QuickTimeUTC=1"
	echo
	exit 0
fi

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
cmd="mv"
tag="DateTimeOriginal"

while getopts "cn" opt; do
    case "$opt" in
    c)  tag="CreateDate"
	;;
    n)  cmd="echo"
        ;;
    esac
done

shift $((OPTIND-1))

# Split positionals at "--": files before, extra exiftool options after.
files=()
exifopts=()
seen_dd=0
for a in "$@"; do
	if [ $seen_dd -eq 0 ] && [ "$a" = "--" ]; then
		seen_dd=1
		continue
	fi
	if [ $seen_dd -eq 0 ]; then
		files+=("$a")
	else
		exifopts+=("$a")
	fi
done

echo "cmd=$cmd, exifopts=${exifopts[*]} Files: ${files[*]}" #$'\n'

# generalize: 
# if IMG_4747.JPG is being processed, then all files IMG_4747.* will be renamed with the new base. 
# Then for each of the files IMG_4747.* found (e.g., IMG_4747.JPG and IMG_4747.XMP) all files starting with 
# IMG_4747.JPG.* should also have their base renamed as well as IMG_4747.XMP.*

farray=( "${files[@]}" )
for F in "${farray[@]}"; do
	echo "* $F" #$'\n\n'

	# Let ExifTool read the tag and format the timestamp; -s3 prints the
	# value only, empty if the tag is absent.
	DT=`exiftool "${exifopts[@]}" -d '%Y-%m-%d_%H.%M.%S' -s3 -"$tag" "$F"`
	if [ -z "$DT" ]; then
		echo "  NO DateTime extracted"
		continue;
	fi

	STEM=${F%.*}                            # _MISC/IMG_4563  (or IMG_4563)
	if [ "$STEM" != "${STEM%/*}" ]; then    # has a directory component?
		DIR="${STEM%/*}/"               # _MISC/
		NAME="${STEM##*/}"              # IMG_4563
	else
		DIR=""
		NAME="$STEM"
	fi
	FN=${DIR}${DT}_${NAME}                  # _MISC/2018-05-03_11.31.17_IMG_4563

	echo "  [$FN]"
	if [ "$cmd" = "echo" ]; then           # dry run: aligned "src → dst" listing
		w=0
		for G in "$STEM".*; do
			[ ${#G} -gt $w ] && w=${#G}
		done
		for G in "$STEM".*; do
			printf "  %-*s → %s\n" "$w" "$G" "$FN${G#$STEM}"
		done
	else
		for G in "$STEM".*; do
			$cmd "$G" "$FN${G#$STEM}"
		done
	fi
done
