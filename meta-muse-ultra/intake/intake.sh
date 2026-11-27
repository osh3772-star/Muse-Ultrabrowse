#!/usr/bin/env bash
# Credential intake dispatcher — one setup, two paths.
#
#   intake.sh setup [--spec FILE]   Decide the intake path and record it.
#                                   Path A (private Google Sheet) is used
#                                   only when the Sheets connector reports
#                                   "connected"; otherwise path B (file
#                                   round-trip) is recorded. Sheet first,
#                                   file as fallback — always in that order.
#   intake.sh path                  Print the recorded path (A or B).
#   intake.sh form  ...             Create a file form (make-form.py).
#   intake.sh apply ...             Apply a filled file form (apply-intake.py).
#   intake.sh sheet-apply ...       Apply the sheet form (sheet-intake.py);
#                                   falls back to the file path when the
#                                   connector is not connected.
#
# Values are never printed by any of these commands. See the agent-vault
# skill for the full procedure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cmd="${1:-}"
case "$cmd" in
  setup)
    shift
    if python3 "$HERE/sheet-intake.py" status 2>/dev/null | grep -q '^sheets=connected$'; then
      python3 "$HERE/sheet-intake.py" setup "$@"
    else
      python3 - "$HERE" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import intake_common as ic
cfg = ic.load_intake_config()
cfg["path"] = "B"
ic.save_intake_config(cfg)
PYEOF
      echo "intake_path=B reason=sheets-not-connected"
    fi
    ;;
  path)
    python3 - "$HERE" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import intake_common as ic
print(ic.load_intake_config().get("path", "unset"))
PYEOF
    ;;
  form)
    shift
    exec python3 "$HERE/make-form.py" "$@"
    ;;
  apply)
    shift
    exec python3 "$HERE/apply-intake.py" "$@"
    ;;
  sheet-apply)
    shift
    exec python3 "$HERE/sheet-intake.py" apply "$@"
    ;;
  *)
    echo "usage: intake.sh setup [--spec FILE] | path | form ... | apply ... | sheet-apply ..." >&2
    exit 2
    ;;
esac
