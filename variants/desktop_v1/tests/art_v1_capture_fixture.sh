#!/usr/bin/env bash
set -euo pipefail

capture_root=""
for argument in "$@"; do
	case "$argument" in
		--capture-root=*) capture_root="${argument#--capture-root=}" ;;
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
cp -a "$ART_V1_FIXTURE_SOURCE_DIR/." "$capture_root/"

mode="${ART_V1_FIXTURE_MODE:-success}"
if [[ "$mode" == "validation_failure" && "$invocation" -eq 1 ]]; then
	printf '%s\n' 'not-a-png' > "$capture_root/battle_1280x720.png"
	exit 0
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
