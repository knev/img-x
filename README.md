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
x-exif [-cn] [-f:m|-f:c|-f:f] [filespec] [-- exiftool-options]
x-exif -h | --help
x-exif -v | --version
```

| Option | Effect |
| ------ | ------ |
| `-c`   | Use `Create Date` instead of `DateTimeOriginal` (e.g. for MOV files). |
| `-n`   | Dry run — print the `source → destination` renames without moving anything. |
| `-f:m` / `-f:c` | Use a **filesystem** date instead of the EXIF date: `:m` = file modify date, `:c` = file create (birth) date. For files ExifTool can't read a date from. |
| `-f:f` | Use the date embedded in the **filename**: the first valid `YYYY-MM-DD` or `YYYYMMDD` (with an optional trailing `HHMMSS` time). E.g. `IMG_20261012_120000.jpg` → `2026-10-12_12.00.00_…`. |
| `--`   | Pass any following arguments through to `exiftool`. |
| `-h` / `--help` | Show usage help and exit. |
| `-v` / `--version` | Print the version (`vX.Y.Z`) and exit. |

**Examples**

```sh
# Preview what would happen, no changes made:
x-exif -n _MISC/*.JPG

# Rename a batch of stills:
x-exif IMG_*.JPG

# MOV files, using Create Date:
x-exif -c *.MOV

# Files with no readable EXIF date — use the filesystem modify date instead:
x-exif -f:m *.JPG

# …or take the date straight from the filename (IMG_20261012_… → 2026-10-12_…):
x-exif -f:f *.jpg

# Forward extra options to exiftool:
x-exif IMG_*.MOV -- -api QuickTimeUTC=1
```

> Tip: always do a `-n` dry run first — renames are applied with `mv`.

#### `x-exif` as a *thin wrapper*

`x-exif` is deliberately a *thin wrapper*: it contains no metadata logic of its
own — not even date parsing. It asks ExifTool for one already-formatted
timestamp per file and lets ExifTool do all the work of reading the tag and
rendering it; the script only prepends that string to the original name and
renames the file group. The single call it makes is:

```sh
# -d formats the timestamp, -s3 prints the value only (empty if absent).
# $tag is DateTimeOriginal by default, or CreateDate with -c (e.g. MOV video).
exiftool -d '%Y-%m-%d_%H.%M.%S' -s3 -"$tag" "$F"
```

That one command yields, e.g., `2018-05-22_14.59.38`, which becomes the
filename prefix. Letting ExifTool's `-d` formatter produce the timestamp means
time zones, sub-second values, and the quirks of every file format are handled
by ExifTool rather than by brittle text munging in the script.

The one exception is `-f`, for files ExifTool can't read a date from. It takes
the prefix from a **non-EXIF** source instead, so this date never goes through
ExifTool:

- `-f:m` / `-f:c` — a **filesystem** date, read directly with `stat` (BSD
  `stat -f` on macOS, GNU `stat -c` on Linux) and formatted with `date`. On
  Linux the file *create* (birth) date is often unavailable; when it is, the
  file is reported as `NO DateTime extracted` and left untouched rather than
  substituting another date.
- `-f:f` — the date already present in the **filename**, found by scanning
  left-to-right for the first valid `YYYY-MM-DD` or `YYYYMMDD` (a `19201080`
  with month `20` is skipped, not accepted), with an optional `HHMMSS` time
  immediately after it. Pure string parsing — no `stat`, no ExifTool.

> **Why not just use ExifTool to rename?** ExifTool can rename by date on its
> own (`exiftool '-FileName<DateTimeOriginal' -d '%Y-%m-%d_%H.%M.%S_%%f.%%e'`),
> and for a lone file you should. `x-exif` exists for the one thing that
> one-liner can't do: it also sweeps the **non-metadata sidecars** —
> `.sha256` hashes, XMP companions, etc. — so the whole `IMG_4747.*` group is
> renamed together instead of orphaning files ExifTool can't read a date from.

Because ExifTool understands so many formats and tags, anything it can read a
date out of, `x-exif` can rename. You can also reach the rest of ExifTool's
enormous feature set directly: everything after `--` on the `x-exif` command
line is forwarded verbatim to ExifTool. For example, to make ExifTool interpret
QuickTime timestamps as local time:

```sh
x-exif IMG_*.MOV -- -api QuickTimeUTC=1
```

To explore what metadata your own files carry, run ExifTool directly — these
show the tags `x-exif` selects from:

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
