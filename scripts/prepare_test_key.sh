#!/usr/bin/env bash
# Standard Android debug credentials; this is not a production signing identity.
set -euo pipefail
umask 077
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
key_file=${1:-"$project_root/android/.test-signing/debug.keystore"}
mkdir -p -- "$(dirname -- "$key_file")"
if [ ! -f "$key_file" ]; then
  keytool -genkeypair -keystore "$key_file" -storepass android -keypass android \
    -alias androiddebugkey -dname 'CN=Android Debug,O=Malmun Test,C=KR' \
    -keyalg RSA -keysize 2048 -validity 10000 -storetype JKS
fi
keytool -list -keystore "$key_file" -storepass android -alias androiddebugkey >/dev/null
chmod 600 "$key_file"
