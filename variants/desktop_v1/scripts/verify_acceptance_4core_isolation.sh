#!/usr/bin/env bash
set -euo pipefail

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="${ACCEPTANCE_4CORE_PROJECT_ROOT:-$(cd "$script_root/.." && pwd)}"
project_root="$(realpath -e "$project_root")"
source "$project_root/scripts/timeout_gate.sh"
"$project_root/scripts/verify_post_import_ready.sh"

scratch_parent="${ACCEPTANCE_4CORE_SCRATCH_PARENT:-${TMPDIR:-/tmp}}"
test_root="$(mktemp -d "$scratch_parent/xenogenesis-acceptance-4core.XXXXXX")"
cleanup_4core() {
	cleanup_hard_timeout_processes || true
	rm -rf "$test_root"
}
trap cleanup_4core EXIT
trap 'exit 143' TERM INT

select_four_cpus() {
	local allowed
	allowed="$(awk '/^Cpus_allowed_list:/ {print $2}' /proc/self/status)"
	local -a cpus=()
	local -a ranges=()
	IFS=',' read -r -a ranges <<< "$allowed"
	local range start end cpu
	for range in "${ranges[@]}"; do
		if [[ "$range" == *-* ]]; then
			start="${range%-*}"
			end="${range#*-}"
		else
			start="$range"
			end="$range"
		fi
		for ((cpu = start; cpu <= end && ${#cpus[@]} < 4; cpu++)); do
			cpus+=("$cpu")
		done
		if [[ "${#cpus[@]}" -eq 4 ]]; then
			break
		fi
	done
	if [[ "${#cpus[@]}" -ne 4 ]]; then
		echo "ACCEPTANCE_4CORE_RED reason=unsupported-cpu-count allowed=${allowed:-missing}" >&2
		return 1
	fi
	local joined
	joined="$(IFS=,; printf '%s' "${cpus[*]}")"
	printf '%s\n' "$joined"
}

assert_round_contract() {
	local round="$1"
	local log="$2"
	local cpu_list="$3"
	if ! rg -q '^ACCEPTANCE_REGRESSIONS_OK cases=5 resolutions=3 assertions=487 segments=recovery,core core_assertions=390 recovery_assertions=97 .*isolation=canonical-distinct project_cache=unchanged pids_pgids=reaped process_tree=gone$' "$log"; then
		echo "ACCEPTANCE_4CORE_RED round=$round reason=summary-contract" >&2
		return 1
	fi
	if ! rg -q '^ACCEPTANCE_CPU_CONSTRAINT allowed=[0-9,-]+ count=4$' "$log"; then
		echo "ACCEPTANCE_4CORE_RED round=$round reason=cpu-constraint" >&2
		return 1
	fi
	if ! rg -q '^ACCEPTANCE_SEGMENT_ISOLATION_OK filesystems=10-distinct displays=:[0-9]+,:[0-9]+ renderers=recovery-rendered,core-dummy$' "$log"; then
		echo "ACCEPTANCE_4CORE_RED round=$round reason=identity-isolation" >&2
		return 1
	fi
	local before after
	before="$(sed -n -E 's/^ACCEPTANCE_PROJECT_CACHE phase=before fingerprint=([0-9a-f]{64}) files=[0-9]+$/\1/p' "$log")"
	after="$(sed -n -E 's/^ACCEPTANCE_PROJECT_CACHE phase=after fingerprint=([0-9a-f]{64}) files=[0-9]+$/\1/p' "$log")"
	if [[ -z "$before" || "$before" != "$after" ]]; then
		echo "ACCEPTANCE_4CORE_RED round=$round reason=project-cache" >&2
		return 1
	fi
	local segment
	for segment in recovery core; do
		if ! rg -q "^ACCEPTANCE_SEGMENT_ORCHESTRATION segment=$segment phase=reaped .* status=0 .* pid_alive=0 pgid_alive=0 " "$log"; then
			echo "ACCEPTANCE_4CORE_RED round=$round reason=${segment}-not-reaped" >&2
			return 1
		fi
	done
	echo "ACCEPTANCE_4CORE_ROUND_OK round=$round cpus=$cpu_list assertions=487 identities=canonical-distinct cache=unchanged pids_pgids=reaped"
}

assert_fault_propagates() {
	local segment="$1"
	local cpu_list="$2"
	local fault_root="$test_root/fault-$segment"
	mkdir -p "$fault_root"
	local log="$fault_root.log"
	local status=0
	run_with_hard_timeout "acceptance-4core-fault-$segment" 80 5 \
		taskset -c "$cpu_list" env \
			ACCEPTANCE_ORCHESTRATION_FAULT_TOKEN=acceptance-4core-oracle \
			ACCEPTANCE_TEST_FAIL_SEGMENT="$segment" \
			"$project_root/scripts/run_acceptance_segments.sh" "$project_root" "$fault_root" \
			> "$log" 2>&1 || status=$?
	cat "$log"
	if [[ "$status" -eq 0 || -s "$fault_root/exit-ready" ]]; then
		echo "ACCEPTANCE_4CORE_RED reason=$segment-fault-was-green status=$status" >&2
		return 1
	fi
	if ! rg -q "^ACCEPTANCE_SEGMENT_ORCHESTRATION segment=$segment phase=reaped .* status=19 .* pid_alive=0 pgid_alive=0 " "$log"; then
		echo "ACCEPTANCE_4CORE_RED reason=$segment-fault-not-reaped status=$status" >&2
		return 1
	fi
	echo "ACCEPTANCE_4CORE_FAULT_OK segment=$segment status=$status overall=red pids_pgids=reaped"
}

cpu_list="$(select_four_cpus)"
for round in 1 2; do
	log="$test_root/round-$round.log"
	status=0
	taskset -c "$cpu_list" env --chdir="$project_root" \
		"$project_root/scripts/verify_acceptance_regressions.sh" > "$log" 2>&1 || status=$?
	cat "$log"
	if [[ "$status" -ne 0 ]]; then
		echo "ACCEPTANCE_4CORE_RED round=$round reason=runner-status status=$status" >&2
		exit "$status"
	fi
	assert_round_contract "$round" "$log" "$cpu_list"
done

assert_fault_propagates recovery "$cpu_list"
assert_fault_propagates core "$cpu_list"
echo "VERIFY_ACCEPTANCE_4CORE_ISOLATION_OK rounds=2 cpus=$cpu_list assertions=487 segments=recovery-exclusive,core-dummy faults=recovery,core-overall-red identities=canonical-distinct project_cache=unchanged pids_pgids=reaped scratch=clean-on-exit"
