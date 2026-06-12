#!/bin/bash

if ! command -v exiftool >/dev/null 2>&1; then
	echo "ERROR: exiftool not found. Install it from: https://exiftool.org/" >&2
	exit 1
fi

if [ $# -eq 0 ]; then
	echo "Usage: $0 [-cn] [filespec]" #$'\n'
	echo "Options:"
	echo	$'\t'-c$'\t'"Use Create Date instead of DateTimeOriginal (e.g., for MOV files)."
	echo	$'\t'-n$'\t'"Dry run."
	echo
	echo	$'\t'"EX: x-exif -n [^0-9]*"
	echo
	exit 0
fi

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
cmd="mv"
tag="DateTimeOriginal"

while getopts "cnx:" opt; do
    case "$opt" in
    c)  tag="Create Date"
	;;
    n)  cmd="echo"
        ;;
    x)  argx="$OPTARG"
	;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

echo "cmd=$cmd, argx=$argx Leftovers: $@" #$'\n'

# generalize: 
# if IMG_4747.JPG is being processed, then all files IMG_4747.* will be renamed with the new base. 
# Then for each of the files IMG_4747.* found (e.g., IMG_4747.JPG and IMG_4747.XMP) all files starting with 
# IMG_4747.JPG.* should also have their base renamed as well as IMG_4747.XMP.*

farray=( "$@" )
for F in "${farray[@]}"; do
	echo "* $F" #$'\n\n'

	#EXIF=`identify -verbose $F | grep DateTimeOriginal | cut -f3-7 -d:`
	if [ "$tag" == "DateTimeOriginal" ]; then
		EXIF=`exiftool -DateTimeOriginal "$F" | cut -f2-7 -d:` #JPG
	else
		EXIF=`exiftool "$F" | grep "^Create Date" | cut -f2-6 -d:` #MOV
	fi

	DATE=`echo $EXIF | cut -f1 -d" " | sed s/:/-/g `
	TIME=`echo $EXIF | cut -f2 -d" " | sed s/:/./g `
	STEM=${F%.*}                            # _MISC/IMG_4563  (or IMG_4563)
	if [ "$STEM" != "${STEM%/*}" ]; then    # has a directory component?
		DIR="${STEM%/*}/"               # _MISC/
		NAME="${STEM##*/}"              # IMG_4563
	else
		DIR=""
		NAME="$STEM"
	fi
	FN=${DIR}${DATE}_${TIME}_${NAME}        # _MISC/2018-05-03_11.31.17_IMG_4563

	OK=`echo $FN | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}.[0-9]\{2\}.[0-9]\{2\}'`
	if [ -z "$OK" ]; then
		echo "  NO DateTime extracted"
		continue;
	fi

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
