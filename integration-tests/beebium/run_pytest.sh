#!/usr/bin/env bash
# Run nio-apps Beebium integration tests for BBC config-nio.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
nio_apps="$(cd "$here/../.." && pwd)"
workspace="$(cd "$nio_apps/../.." && pwd)"

export BEEBIUM_HOME="${BEEBIUM_HOME:-$HOME/dev/bbc/beebium}"
export FUJINET_NIO_HOME="${FUJINET_NIO_HOME:-$workspace/repos/fujinet-nio}"
export FN_ROM_HOME="${FN_ROM_HOME:-$workspace/repos/fn-rom}"
export FUJINET_NIO_LIB="${FUJINET_NIO_LIB:-$workspace/repos/fujinet-nio-lib}"
export FUJINET_BIN="${FUJINET_BIN:-$FUJINET_NIO_HOME/build/fujibus-pty-debug/fujinet-nio}"
export FN_ROM="${FN_ROM:-$FN_ROM_HOME/build/fujinet.rom}"
export CONFNIO_BBC_SSD="${CONFNIO_BBC_SSD:-$workspace/build/images/confnio-bbc.ssd}"

client="${BEEBIUM_HOME}/clients/beebium-python-client"
if [[ ! -f "$client/pyproject.toml" ]]; then
  echo "ERROR: Beebium Python client not found at $client" >&2
  exit 1
fi

(
  cd "$workspace"
  ./scripts/build.sh confnio-bbc-disk bbc-boot-disk fujinet-pty
)

cd "$here"
exec uv run --python "${BEEBIUM_PYTHON:-3.12}" --with pytest --with-editable "$client" python -m pytest -p no:beebium "$@"
