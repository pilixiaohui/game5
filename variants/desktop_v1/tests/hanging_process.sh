#!/usr/bin/env bash
set -euo pipefail

if [[ "${HANG_MODE:-wait}" == "normal" ]]; then
	exit 0
fi

if [[ "${HANG_MODE:-wait}" == "leader_exit" ]]; then
	nohup sleep 300 >/dev/null 2>&1 &
else
	sleep 300 &
fi
child_pid=$!
if [[ -n "${HANG_PID_FILE:-}" ]]; then
	printf '%s\n' "$child_pid" > "$HANG_PID_FILE"
	ps -o pgid= -p "$child_pid" | tr -d ' ' > "$HANG_PID_FILE.pgid"
fi
if [[ "${HANG_MODE:-wait}" == "leader_exit" ]]; then
	exit 0
fi
wait "$child_pid"
