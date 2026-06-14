#!/bin/bash

VERSION=

usage() {
	echo "Usage: $0 [-cn] [-f:m|-f:c|-f:f] [filespec] [-- exiftool-options]"
	echo "Options:"
	echo	$'\t'-c$'\t'"Use Create Date instead of DateTimeOriginal (e.g., for MOV files)."
	echo	$'\t'-n$'\t'"Dry run."
	echo	$'\t'-f$'\t'"Use a non-EXIF date source instead of the EXIF date:"
	echo	$'\t'$'\t'"  :m = file modify date, :c = file create (birth) date,"
	echo	$'\t'$'\t'"  :f = date parsed from the filename (YYYY-MM-DD or YYYYMMDD)."
	echo	$'\t'--$'\t'"Pass any following arguments through to exiftool."
	echo	$'\t'"-h, --help"$'\t'"Show this help and exit."
	echo	$'\t'"-v, --version"$'\t'"Print the version (vX.Y.Z) and exit."
	echo
	echo	$'\t'"EX: x-exif -n [^0-9]*"
	echo	$'\t'"EX: x-exif -f:m *.JPG"
	echo	$'\t'"EX: x-exif -f:f *.jpg"
	echo	$'\t'"EX: x-exif IMG_*.MOV -- -api QuickTimeUTC=1"
	echo
}

# -h/--help and -v/--version: handle before anything else (need no exiftool).
# Stop at "--" so a flag meant for exiftool isn't intercepted here.
for a in "$@"; do
	case "$a" in
	--)           break ;;
	-h|--help)    usage; exit 0 ;;
	-v|--version) echo "v$VERSION"; exit 0 ;;  # gv fills VERSION as x.y.z (no 'v')
	esac
done

if ! command -v exiftool >/dev/null 2>&1; then
	echo "ERROR: exiftool not found. Install it from: https://exiftool.org/" >&2
	exit 1
fi

if [ $# -eq 0 ]; then
	usage
	exit 0
fi

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
cmd="mv"
tag="DateTimeOriginal"
fallback=""                     # "" = EXIF; m|c = filesystem date; f = filename date
fallbackdesc=""

while getopts "cnf:" opt; do
    case "$opt" in
    c)  tag="CreateDate"
	;;
    n)  cmd="echo"
        ;;
    f)  case "${OPTARG#[:=]}" in     # strip the ':' / '=' of -f:m / -f=m
        m) fallback="m"; fallbackdesc="modify" ;;
        c) fallback="c"; fallbackdesc="create" ;;
        f) fallback="f"; fallbackdesc="filename" ;;
        *) echo "ERROR: -f takes ':m' (modify), ':c' (create) or ':f' (filename), got '$OPTARG'" >&2; exit 1 ;;
        esac
        ;;
    esac
done

shift $((OPTIND-1))

# Detect the stat/date flavor once (macOS=BSD, Linux=GNU) — only the -f:m/-f:c
# filesystem-date paths use it. ADR: scripts run on both macOS and linux.
if [ "$fallback" = "m" ] || [ "$fallback" = "c" ]; then
	if stat -f '%m' . >/dev/null 2>&1; then
		STAT_FLAVOR="bsd"
	else
		STAT_FLAVOR="gnu"
	fi
fi

# fs_epoch <m|c> <file> -> filesystem date as epoch seconds (empty/0 if absent).
fs_epoch() {
	if [ "$STAT_FLAVOR" = "bsd" ]; then
		case "$1" in
		m) stat -f '%m' "$2" ;;
		c) stat -f '%B' "$2" ;;     # %B = birth (create) time
		esac
	else
		case "$1" in
		m) stat -c '%Y' "$2" ;;
		c) stat -c '%W' "$2" ;;     # %W = birth time, 0 if filesystem lacks it
		esac
	fi
}

# fmt_epoch <epoch> -> "YYYY-MM-DD_HH.MM.SS" (matches the EXIF -d format above).
fmt_epoch() {
	if [ "$STAT_FLAVOR" = "bsd" ]; then
		date -r "$1" +'%Y-%m-%d_%H.%M.%S'
	else
		date -d "@$1" +'%Y-%m-%d_%H.%M.%S'
	fi
}

# fname_date <name> -> first valid date embedded in the name, as "YYYY-MM-DD"
# (or "YYYY-MM-DD_HH.MM.SS" when a 6-digit time directly follows); empty if none.
# Pure bash (portable to macOS bash 3.2): scans left-to-right, skips matches that
# aren't valid dates (e.g. 19201080). Integer checks use [ ] so leading zeros
# stay decimal — $(( )) would misread 08/09 as octal.
fname_date() {
	local rest="$1" m y mo d after
	local dre='([0-9]{4})-([0-9]{2})-([0-9]{2})|([0-9]{8})'
	while [[ "$rest" =~ $dre ]]; do
		m="${BASH_REMATCH[0]}"
		if [ -n "${BASH_REMATCH[4]}" ]; then        # YYYYMMDD form
			y="${BASH_REMATCH[4]:0:4}"; mo="${BASH_REMATCH[4]:4:2}"; d="${BASH_REMATCH[4]:6:2}"
		else                                        # YYYY-MM-DD form
			y="${BASH_REMATCH[1]}"; mo="${BASH_REMATCH[2]}"; d="${BASH_REMATCH[3]}"
		fi
		if [ "$y" -ge 1900 ] && [ "$y" -le 2099 ] \
		   && [ "$mo" -ge 1 ] && [ "$mo" -le 12 ] \
		   && [ "$d" -ge 1 ] && [ "$d" -le 31 ]; then
			after="${rest#*"$m"}"                # text right after the date
			if [[ "$after" =~ ^[_-]?([0-9][0-9])([0-9][0-9])([0-9][0-9])([^0-9]|$) ]] \
			   && [ "${BASH_REMATCH[1]}" -le 23 ] \
			   && [ "${BASH_REMATCH[2]}" -le 59 ] \
			   && [ "${BASH_REMATCH[3]}" -le 59 ]; then
				printf '%s-%s-%s_%s.%s.%s\n' "$y" "$mo" "$d" \
					"${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
			else
				printf '%s-%s-%s\n' "$y" "$mo" "$d"
			fi
			return 0
		fi
		rest="${rest#*"$m"}"                         # skip this match, keep scanning
	done
	return 1
}

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

echo "cmd=$cmd, fallback=${fallback:-none}, exifopts=${exifopts[*]} Files: ${files[*]}" #$'\n'

# generalize: 
# if IMG_4747.JPG is being processed, then all files IMG_4747.* will be renamed with the new base. 
# Then for each of the files IMG_4747.* found (e.g., IMG_4747.JPG and IMG_4747.XMP) all files starting with 
# IMG_4747.JPG.* should also have their base renamed as well as IMG_4747.XMP.*

farray=( "${files[@]}" )
for F in "${farray[@]}"; do
	echo "* $F" #$'\n\n'

	case "$fallback" in
	"")     # Let ExifTool read the tag and format the timestamp; -s3 prints the
	        # value only, empty if the tag is absent.
	        DT=`exiftool "${exifopts[@]}" -d '%Y-%m-%d_%H.%M.%S' -s3 -"$tag" "$F"`
	        ;;
	m|c)    # User chose the filesystem date; ExifTool is not consulted.
	        epoch=$(fs_epoch "$fallback" "$F")
	        case "$epoch" in
	        ''|*[!0-9]*|0)  DT="" ;;                # absent (e.g. Linux birthtime)
	        *)              DT=$(fmt_epoch "$epoch") ;;
	        esac
	        ;;
	f)      # User chose the date embedded in the filename.
	        DT=$(fname_date "${F##*/}")
	        ;;
	esac
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

	printf '  [%s]' "$FN"
	case "$fallback" in
	m|c) printf '  (filesystem %s date)' "$fallbackdesc" ;;
	f)   printf '  (filename date)' ;;
	esac
	echo
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
