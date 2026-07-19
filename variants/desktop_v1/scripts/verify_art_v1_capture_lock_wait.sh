#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$project_root/scripts/verify_art_v1_capture_atomic.sh" --lock-wait-only
