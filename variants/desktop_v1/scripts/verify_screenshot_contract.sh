#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$project_root/scripts/verify_screenshots.sh"

if [[ ! -x "$wrapper" ]]; then
	echo "Screenshot verification must have one executable hard-timeout wrapper." >&2
	exit 1
fi
if ! rg -qF './scripts/verify_screenshots.sh' "$project_root/README.md"; then
	echo "README must route screenshot verification through the shared wrapper." >&2
	exit 1
fi
if ! rg -qF './scripts/verify_screenshots.sh' "$project_root/scripts/verify.sh"; then
	echo "verify.sh must route screenshot verification through the shared wrapper." >&2
	exit 1
fi
if ! rg -qF 'verify_screenshots.sh' "$project_root/scripts/release_health.sh"; then
	echo "release-health must route screenshot verification through the shared wrapper." >&2
	exit 1
fi
if rg -q 'OS\.execute\(' "$project_root/tests/screenshot_runner.gd"; then
	echo "Godot screenshot runner must not own blocking Xvfb process orchestration." >&2
	exit 1
fi

echo "SCREENSHOT_CONTRACT_OK entrypoints=README,verify,release-health orchestration=shared-hard-timeout"
