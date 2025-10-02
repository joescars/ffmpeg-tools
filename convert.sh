#!/usr/bin/env bash

set -euo pipefail

#############################################
# Simple video converter wrapper for ffmpeg #
#############################################

# Usage examples:
#   ./convert.sh input.mp4 1500k
#   ./convert.sh input.mp4 1500   # ("k" will be appended)
#   ./convert.sh -input.mp4 -1500 # (tolerates leading dashes per request)
#   ./convert.sh -n input.mp4 2M  # dry‑run only prints the ffmpeg command
#
# Output goes next to the source file: /path/to/input-NEW.mp4 (adds numeric suffix if needed)
# Command template: ffmpeg -i INPUT -b:v BITRATE OUTPUT
#
# Optional environment variables:
#   VC_SUFFIX (default: NEW)  -> used in output filename base-<SUFFIX>.ext
#   VC_VCODEC (default: libx264)
#   VC_ACODEC (default: libfdk_aac) -> change to e.g. aac if you want re-encode
#   VC_EXTRA  (default: empty) additional ffmpeg args appended verbatim
#
# Flags:
#   -h | --help : show help
#   -n | --dry-run : only print command, do not execute

show_help() {
	sed -n '1,100p' "$0" | sed -n '/^#############################################/,$p' | sed '1d;2d'
	cat <<'EOF'
Examples:
	convert.sh movie.mkv 2500k
	convert.sh movie.mkv 2500        # auto -> 2500k
	convert.sh -movie.mkv -2500      # tolerated legacy style
	VC_SUFFIX=SMALL convert.sh movie.mkv 1200k
	VC_VCODEC=libx265 VC_ACODEC=aac VC_EXTRA='-crf 28' convert.sh movie.mkv 800k
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "$1 not found (please install)"; }

dry_run=false
input_file=""
bitrate=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help) show_help; exit 0 ;;
		-n|--dry-run) dry_run=true; shift; ;;
		--) shift; break ;;
		-*) # Unrecognized leading-dash argument treated as positional (per user request)
				val="${1#-}"
				if [[ -z $input_file ]]; then input_file="$val"; else bitrate="$val"; fi
				shift ;;
		*)  if [[ -z $input_file ]]; then input_file="$1"; elif [[ -z $bitrate ]]; then bitrate="$1"; else die "Unexpected extra argument: $1"; fi; shift ;;
	esac
done

# Allow remaining args after --
if [[ -z $bitrate && $# -gt 0 ]]; then
	bitrate="$1"; shift || true
fi

[[ -n $input_file ]] || die "No input file provided"
[[ -n $bitrate ]] || die "No bitrate provided"

[[ -f $input_file ]] || die "Input file '$input_file' not found"

# Normalize bitrate: if it's all digits, append 'k'
if [[ $bitrate =~ ^[0-9]+$ ]]; then
	bitrate="${bitrate}k"
fi

# Basic validation: must end with k, K, m, M, or be digits+unit
if ! [[ $bitrate =~ ^[0-9]+(k|K|m|M)$ ]]; then
	echo "Warning: bitrate '$bitrate' unusual; expected forms like 1500k or 2M" >&2
fi

suffix="${VC_SUFFIX:-x265}"
# hevc_nvenc for NVIDIA hardware
# hevc_videotoolbox for macOS hardware
# libx265 for software
vcodec="${VC_VCODEC:-hevc_nvenc}"
# aac for built-in ffmpeg encoder
# libfdk_aac for better quality (if ffmpeg built with --enable-libf
# aac_at for Apple devices (if ffmpeg built with --enable-libfdk-aac)
acodec="${VC_ACODEC:-libfdk_aac}"
extra="${VC_EXTRA:-}"

base_name="${input_file##*/}"              # strip path
dir_name="${input_file%/*}"; [[ $dir_name == "$input_file" ]] && dir_name="." # if no path
ext=""; filename_noext="$base_name"
if [[ $base_name == *.* ]]; then
	ext=".${base_name##*.}"
	filename_noext="${base_name%.*}"
fi

output_base="${filename_noext}-${suffix}${ext}"
if [[ $dir_name == "." ]]; then
	output_file="$output_base"
else
	output_file="$dir_name/$output_base"
fi

if [[ -e $output_file ]]; then
	i=1
	while :; do
		if [[ $dir_name == "." ]]; then
			candidate="${filename_noext}-${suffix}-$i${ext}"
		else
			candidate="$dir_name/${filename_noext}-${suffix}-$i${ext}"
		fi
		[[ -e $candidate ]] && ((i++)) && continue
		output_file="$candidate"
		break
	done
fi

cmd=(ffmpeg -hide_banner -loglevel info -y -i "$input_file" -c:v "$vcodec" -profile:v main10 -b:v "$bitrate" -c:a "$acodec" -b:a 384k -sn)
if [[ -n $extra ]]; then
	# shellcheck disable=SC2206 # we intentionally split extra
	extra_arr=( $extra )
	cmd+=( "${extra_arr[@]}" )
fi
cmd+=("$output_file")

echo "Input : $input_file"
echo "Bitrate: $bitrate"
echo "Output: $output_file"
echo "Video codec: $vcodec | Audio codec: $acodec"
[[ -n $extra ]] && echo "Extra args: $extra"
echo "Running: ${cmd[*]}"

if [ "$dry_run" = true ]; then
	echo "(dry-run) Not executing."
	exit 0
fi

require ffmpeg

# Cleanup partial output on interruption
partial_cleanup() { echo "Interrupted; removing partial output '$output_file'" >&2; rm -f -- "$output_file"; exit 130; }
trap partial_cleanup INT TERM

"${cmd[@]}"

echo "Done. Generated $output_file"

