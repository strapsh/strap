#!/usr/bin/env bash

set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
if ! command -v strap::lib::import >/dev/null; then
  echo "This file is not intended to be run or sourced outside of a strap execution context." >&2
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1 # if sourced, return 1, else running as a command, so exit
fi

strap::lib::import logging || . logging.sh
strap::lib::import lang || . lang.sh

strap::path::contains() {
  local -r element="${1:-}" && strap::assert::has_length "$element" 'requires a $1 argument'
  echo "$PATH" | tr ':' '\n' | grep -q "$element"
}
