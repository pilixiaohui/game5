#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture_root="$project_root/artifacts/art_m1/captures"
annotation_root="$project_root/artifacts/art_m1/annotations"
font="${M1_ANNOTATION_FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf}"

[[ -f "$font" ]] || {
	echo "M1 annotation font is unavailable: $font" >&2
	exit 2
}
mkdir -p "$annotation_root"

for phase in engagement retreat; do
	for size in 1280x720 1600x900 1920x1080; do
		width="${size%x*}"
		height="${size#*x}"
		hud_end=$((height * 14 / 100))
		rail_start=$((height * 78 / 100))
		font_size=$((height / 36))
		input="$capture_root/${phase}_${size}.png"
		output="$annotation_root/${phase}_${size}_rail78-safe.png"
		[[ -f "$input" ]] || {
			echo "M1 raw capture is unavailable: $input" >&2
			exit 2
		}
		filter="drawbox=x=0:y=0:w=iw:h=${hud_end}:color=0x06171c@0.72:t=fill,drawbox=x=0:y=${rail_start}:w=iw:h=ih-${rail_start}:color=0x171b12@0.62:t=fill,drawbox=x=0:y=${hud_end}:w=iw:h=3:color=0x75e6d1@1:t=fill,drawbox=x=0:y=${rail_start}:w=iw:h=3:color=0xf4d35e@1:t=fill,drawtext=fontfile=${font}:text='HUD SAFE 0 TO 14 PCT':x=18:y=${font_size}:fontsize=${font_size}:fontcolor=white,drawtext=fontfile=${font}:text='ACTION FIELD 14 TO 78 PCT':x=(w-text_w)/2:y=${hud_end}+10:fontsize=${font_size}:fontcolor=white,drawtext=fontfile=${font}:text='RAIL RESERVED 78 TO 100 PCT':x=18:y=h-text_h-14:fontsize=${font_size}:fontcolor=0xf4d35e,drawtext=fontfile=${font}:text='ICON TOP 78.5 PCT / RAIL LINE 80.1 PCT':x=w-text_w-18:y=h-text_h-14:fontsize=${font_size}/2:fontcolor=white"
		ffmpeg -hide_banner -loglevel error -y -i "$input" -vf "$filter" -frames:v 1 "$output"
	done
done

count="$(find "$annotation_root" -maxdepth 1 -type f -name '*_rail78-safe.png' | wc -l)"
[[ "$count" -eq 6 ]] || {
	echo "M1 annotation generation produced $count files instead of 6." >&2
	exit 1
}
echo "M1_ANNOTATION_OK count=6 source=raw-captures zones=0-14,14-78,78-100"
