#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail_prerequisite() {
	echo "POST_IMPORT_PREREQUISITE_MISSING $1" >&2
	echo "Run ./scripts/verify_fresh_source_lifecycle.sh for a self-contained fresh-source check; post-import gates never import on demand." >&2
	exit 2
}

if [[ ! -s "$project_root/.godot/editor/project_metadata.cfg" || ! -s "$project_root/.godot/global_script_class_cache.cfg" ]]; then
	fail_prerequisite "complete Godot editor import metadata is absent"
fi

imported_count=0
while IFS= read -r import_file; do
	imported_path="$(awk -F'"' '/^path="res:\/\/\.godot\/imported\/.*\.ctex"/ { print $2; exit }' "$import_file")"
	if [[ -z "$imported_path" ]]; then
		fail_prerequisite "tracked import metadata has no ctex path: ${import_file#"$project_root/"}"
	fi
	resource_path="$project_root/${imported_path#res://}"
	if [[ ! -f "$resource_path" || -L "$resource_path" || ! -s "$resource_path" ]]; then
		fail_prerequisite "required imported texture is absent or invalid: ${imported_path#res://}"
	fi
	imported_count=$((imported_count + 1))
done < <(find "$project_root/assets/art_v1" -maxdepth 1 -type f -name '*.png.import' | sort)

if [[ "$imported_count" -ne 12 ]]; then
	fail_prerequisite "expected 12 imported art textures, found $imported_count"
fi

echo "POST_IMPORT_PREREQUISITE_OK textures=12 metadata=editor,global-classes cache=complete"
