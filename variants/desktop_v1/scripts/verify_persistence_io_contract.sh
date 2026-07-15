#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
production_file="$project_root/scripts/core/game_session.gd"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/xenogenesis-io-contract.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

sed -n 's/^const \(IO_[A-Z0-9_]*\).*/\1/p' "$production_file" | sort -u > "$test_root/declared"
sed -n '/# BEGIN PERSISTENCE_IO_CALLSITES/,/# END PERSISTENCE_IO_CALLSITES/p' "$production_file" \
	| rg -o '\bIO_[A-Z0-9_]+\b' | sort -u > "$test_root/listed"
awk '
	/# BEGIN PERSISTENCE_IO_CALLSITES/ { in_list = 1; next }
	/# END PERSISTENCE_IO_CALLSITES/ { in_list = 0; next }
	in_list || /^const IO_/ { next }
	{ print }
' "$production_file" | rg -o '\bIO_[A-Z0-9_]+\b' | sort -u > "$test_root/used"

diff -u "$test_root/declared" "$test_root/listed"
diff -u "$test_root/declared" "$test_root/used"

find_direct_io_bypasses() {
	local source_file="$1"
	local output_file="$2"
	awk '
		/^func / {
			function_name = $2
			sub(/\(.*/, "", function_name)
		}
		/(FileAccess|DirAccess)\./ {
			if (function_name != "_fs_path_status" &&
				function_name != "_fs_open_snapshot_read" &&
				function_name != "_fs_read_snapshot_bytes" &&
				function_name != "_fs_open_snapshot_write" &&
				function_name != "_fs_write_snapshot_bytes" &&
				function_name != "_fs_make_dir" &&
				function_name != "_fs_remove" &&
				function_name != "_fs_copy" &&
				function_name != "_fs_rename") {
				print FNR ":" $0
			}
		}
	' "$source_file" > "$output_file"
}

find_direct_io_bypasses "$production_file" "$test_root/bypasses"
test ! -s "$test_root/bypasses"

cp "$production_file" "$test_root/negative-control.gd"
printf '\nfunc _negative_control_bypass(path: String) -> bool:\n\treturn FileAccess.file_exists(path)\n' >> "$test_root/negative-control.gd"
find_direct_io_bypasses "$test_root/negative-control.gd" "$test_root/negative-bypasses"
test -s "$test_root/negative-bypasses"

callsite_count="$(wc -l < "$test_root/declared")"
test "$callsite_count" -eq 51
echo "PERSISTENCE_IO_CONTRACT_OK callsites=$callsite_count declared=listed=used direct_bypasses=0 negative_control=rejected"
