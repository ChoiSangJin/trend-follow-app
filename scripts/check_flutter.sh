#!/usr/bin/env bash
# Preserve the command status and expose diagnostics in GitHub's job annotations.
set -uo pipefail
log=$(mktemp)
trap 'rm -f "$log"' EXIT
if flutter "$@" >"$log" 2>&1; then
  cat "$log"
else
  result=$?
  cat "$log"
  python3 - "$log" <<'PY'
import os
import sys
from pathlib import Path
if os.environ.get('GITHUB_ACTIONS') == 'true':
    lines = Path(sys.argv[1]).read_text(errors='replace').splitlines()
    message = '\n'.join(lines[-180:])[-55000:]
    message = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::error title=Flutter validation::{message}')
PY
  exit "$result"
fi
