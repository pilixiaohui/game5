#!/usr/bin/env bash
set -euo pipefail

capture_root=""
is_validation=0
for argument in "$@"; do
	case "$argument" in
		--capture-root=*) capture_root="${argument#--capture-root=}" ;;
		--validate-art-v1-child) is_validation=1 ;;
	esac
done
if [[ -z "$capture_root" || -z "${ART_V1_FIXTURE_SOURCE_DIR:-}" || -z "${ART_V1_FIXTURE_STATE_FILE:-}" ]]; then
	echo "Capture fixture is missing its owned roots." >&2
	exit 2
fi

invocation=0
if [[ -s "$ART_V1_FIXTURE_STATE_FILE" ]]; then
	invocation="$(<"$ART_V1_FIXTURE_STATE_FILE")"
fi
invocation=$((invocation + 1))
printf '%s\n' "$invocation" > "$ART_V1_FIXTURE_STATE_FILE"
mkdir -p "$capture_root"
if [[ "$is_validation" -eq 1 ]]; then
	exit 0
fi
cp -a "$ART_V1_FIXTURE_SOURCE_DIR/." "$capture_root/"
if [[ -n "${ART_V1_FIXTURE_GENERATION_MTIME:-}" ]]; then
	find "$capture_root" -maxdepth 1 -type f -name '*.png' -exec touch -m -d "@$ART_V1_FIXTURE_GENERATION_MTIME" {} +
fi

mode="${ART_V1_FIXTURE_MODE:-success}"
if [[ "$mode" == "validation_failure" && "$invocation" -eq 1 ]]; then
	printf '%s\n' 'not-a-png' > "$capture_root/battle_1280x720.png"
	exit 0
fi
if [[ "$mode" == "extra_directory" && "$invocation" -eq 1 ]]; then
	mkdir "$capture_root/unexpected"
elif [[ "$mode" == "extra_symlink" && "$invocation" -eq 1 ]]; then
	ln -s battle_1280x720.png "$capture_root/unexpected-link"
elif [[ "$mode" == "extra_fifo" && "$invocation" -eq 1 ]]; then
	mkfifo "$capture_root/unexpected-fifo"
elif [[ "$mode" == "capture_root_symlink" && "$invocation" -eq 1 ]]; then
	linked_root="$capture_root.real"
	mv "$capture_root" "$linked_root"
	ln -s "$linked_root" "$capture_root"
fi

should_hang=0
if [[ "$mode" == "first_interrupt" && "$invocation" -eq 1 ]]; then
	should_hang=1
elif [[ "$mode" == "second_interrupt" && "$invocation" -eq 2 ]]; then
	should_hang=1
fi
if [[ "$should_hang" -eq 1 ]]; then
	sleep 300 &
	child_pid=$!
	if [[ -n "${ART_V1_FIXTURE_PID_FILE:-}" ]]; then
		printf '%s\n' "$child_pid" > "$ART_V1_FIXTURE_PID_FILE"
		ps -o pgid= -p "$child_pid" | tr -d ' ' > "$ART_V1_FIXTURE_PID_FILE.pgid"
	fi
	wait "$child_pid"
fi

exit 0
