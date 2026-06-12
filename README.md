# img-x

A small set of shell utilities for organizing photo/video libraries: rename
files by their embedded EXIF capture date, bucket them into date folders, and
merge folders together.

The centerpiece, `x-exif.sh`, is a thin shell wrapper around
**[ExifTool](https://exiftool.org/)** — it does no metadata parsing of its own.
ExifTool does all the real work of cracking open each file and reading the
capture date; `x-exif` only takes that date and turns it into a filename. See
[Built on ExifTool](#built-on-exiftool) below.

## Built on ExifTool

[ExifTool](https://exiftool.org/) is a free, open-source, platform-independent
Perl library and command-line application by **Phil Harvey** for reading,
writing, and editing metadata in a huge range of image, audio, and video
formats (JPEG, HEIC, TIFF, RAW from virtually every camera maker, PNG, MP4,
MOV, PDF, XMP sidecars, and many more). It is the de-facto standard tool for
metadata work and the engine that makes `x-exif` possible.

## Requirements

- `bash`
- **[ExifTool](https://exiftool.org/)** by Phil Harvey — **required** by
  `x-exif.sh`. The script checks for it on startup and aborts with a pointer to
  <https://exiftool.org/> if it is not found on `PATH`. Install it with your
  package manager (`brew install exiftool`, `apt install libimage-exiftool-perl`,
  `dnf install perl-Image-ExifTool`, …) or from the official site.

## Architecture Decision Records (ADR)s
- all scripts in this repo must be compliant to run on macOS and linux.

## Scripts

### `x-exif.sh` — rename by EXIF date

Renames image files to a sortable, timestamp-prefixed name derived from their
EXIF capture date:

```
IMG_4747.JPG  →  2018-05-22_14.59.38_IMG_4747.JPG
```

Every sidecar that shares the same base name is renamed along with it, so a
file and its companions stay together:

```
IMG_4747.JPG         →  2018-05-22_14.59.38_IMG_4747.JPG
IMG_4747.JPG.sha256  →  2018-05-22_14.59.38_IMG_4747.JPG.sha256
IMG_4747.XMP         →  2018-05-22_14.59.38_IMG_4747.XMP
IMG_4747.XMP.sha256  →  2018-05-22_14.59.38_IMG_4747.XMP.sha256
```

A file whose date cannot be extracted is reported and left untouched.

**Usage**

```
x-exif [-cn] [filespec] [-- exiftool-options]
```

| Option | Effect |
| ------ | ------ |
| `-c`   | Use `Create Date` instead of `DateTimeOriginal` (e.g. for MOV files). |
| `-n`   | Dry run — print the `source → destination` renames without moving anything. |
| `--`   | Pass any following arguments through to `exiftool`. |

**Examples**

```sh
# Preview what would happen, no changes made:
x-exif -n _MISC/*.JPG

# Rename a batch of stills:
x-exif IMG_*.JPG

# MOV files, using Create Date:
x-exif -c *.MOV

# Forward extra options to exiftool:
x-exif IMG_*.MOV -- -api QuickTimeUTC=1
```

> Tip: always do a `-n` dry run first — renames are applied with `mv`.

#### `x-exif` as a *thin wrapper*

`x-exif` is deliberately a *thin wrapper*: it contains no metadata logic of its
own. All it does is ask ExifTool for one timestamp per file, normalize that
into a sortable `YYYY-MM-DD_HH.MM.SS_` prefix, and rename the file group. The
two ways it calls ExifTool are:

```sh
# Default (-DateTimeOriginal), used for stills such as JPEG:
exiftool -DateTimeOriginal "$F"

# With -c, it reads the "Create Date" tag instead (e.g. for MOV video):
exiftool "$F" | grep "^Create Date"
```

Because ExifTool understands so many formats and tags, anything it can read a
date out of, `x-exif` can rename. The two tags above cover the common cases,
but you can reach the rest of ExifTool's enormous feature set directly:
everything after `--` on the `x-exif` command line is forwarded verbatim to
ExifTool. For example, to make ExifTool interpret QuickTime timestamps as local
time:

```sh
x-exif IMG_*.MOV -- -api QuickTimeUTC=1
```

To explore what metadata your own files carry, run ExifTool directly — this is
exactly the kind of output `x-exif` is parsing:

```sh
exiftool -time:all -G1 -a -s IMG_4747.JPG   # show every date/time tag
exiftool IMG_4747.JPG                        # show all metadata
```

**Resources**

- Homepage & downloads: <https://exiftool.org/>
- Full tag documentation: <https://exiftool.org/TagNames/>
- Common date/time recipes: <https://exiftool.org/faq.html>
- Source (GitHub): <https://github.com/exiftool/exiftool>

ExifTool is distributed by Phil Harvey under the same terms as Perl itself
(the GNU GPL or the Artistic License). It is **not** included in this
repository and is **not** covered by this project's license — please refer to
ExifTool's own licensing. All credit for the metadata heavy lifting belongs to
ExifTool and its author.

### `img-dirs` — bucket files into date folders

Run inside a directory of files. Each file whose name begins with a
`YYYY-MM-DD` date (the prefix `x-exif.sh` produces) is moved into a folder of
that date; everything else goes into `_MISC/`.

```sh
cd ~/photos/incoming
img-dirs
```

### `img-merge2` — merge matching folders into one

Moves the contents of every directory matching an `egrep` regex into a single
destination directory, removing the now-empty sources.

```
img-merge2 <SPEC> <DEST>

# e.g. merge a span of dated folders into one:
img-merge2 "./2015-09-(16|17|18|19|2[0-9]) Viggo" "2015-09-16 to 29 Viggo"
```

> Note: `img-merge2` currently uses GNU `find -regextype`, which is not
> available on the stock macOS (BSD) `find`.

## Typical workflow

```sh
x-exif -n *.JPG      # preview the EXIF-based renames
x-exif *.JPG         # apply them
img-dirs             # sort the dated files into YYYY-MM-DD/ folders
```

## Install

`make install` copies `x-exif.sh` to `~/bin/x-exif` and makes it executable:

```sh
make install
```

## License

Dedicated to the public domain under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).
See [LICENSE](LICENSE). To the extent possible under law, all copyright and
related rights are waived.

This dedication covers **only** the scripts in this repository. It does not
cover [ExifTool](https://exiftool.org/), which `x-exif` depends on at runtime;
ExifTool is a separate work by Phil Harvey under its own license (see
[Built on ExifTool](#built-on-exiftool)).
