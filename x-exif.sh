#!/bin/bash

if [ $# -eq 0 ]; then
	echo "USAGE: $0 [-cn] [filespec]" #$'\n'
	echo
	echo	$'\t'-c$'\t'"Use Create Date instead of DateTimeOriginal (e.g., for MOV files)."
	echo	$'\t'-n$'\t'"Dry run."
	echo
	echo	$'\t'"EX: x-exif -n [^0-9]*"
	echo
	exit 0
fi

# http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash

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

#exit 0

# http://owl.phy.queensu.ca/~phil/exiftool/
# https://www.cyberciti.biz/faq/bash-for-loop/
# http://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
# http://stackoverflow.com/questions/12711786/bash-convert-command-line-arguments-into-array
# https://www.cyberciti.biz/tips/handling-filenames-with-spaces-in-bash.html
# http://stackoverflow.com/questions/18271397/find-a-4-digit-number-and-get-the-text-after-them

farray=( "$@" )
for F in "${farray[@]}"; do
	echo "* $F" #$'\n\n'

	#EXIF=`identify -verbose $F | grep DateTimeOriginal | cut -f3-7 -d:`
	if [ "$tag" == "DateTimeOriginal" ]; then
		EXIF=`exiftool -DateTimeOriginal "$F" | cut -f2-7 -d:` #JPG
	else
		EXIF=`exiftool $F | grep "^Create Date" | cut -f2-6 -d:` #MOV
	fi

	DATE=`echo $EXIF | cut -f1 -d" " | sed s/:/-/g `
	TIME=`echo $EXIF | cut -f2 -d" " | sed s/:/./g `
	FN=$DATE\_$TIME\_${F%.*}

	OK=`echo $FN | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}.[0-9]\{2\}.[0-9]\{2\}'`
	if [ -z "$OK" ]; then
		echo "  NO DateTime extracted"
		continue;
	fi

	echo "  [$FN]"
	$cmd "${F%.*}.${F##*.}" "$FN.${F##*.}"
	if [ -f "${F%.*}.XMP" ]; then
		$cmd "${F%.*}.XMP" "$FN.XMP"
	fi
done
