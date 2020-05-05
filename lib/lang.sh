#!/usr/bin/env bash

set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
if ! command -v strap::lib::import >/dev/null; then
  echo "This file is not intended to be run or sourced outside of a strap execution context." >&2
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1 # if sourced, return 1, else running as a command, so exit
fi

strap::lib::import logging || . logging.sh

set -a

strap::assert::has_length() {
  local -r arg="${1:-}"
  local -r msg="${2:-}"
  if [[ -z "$arg" ]]; then
    calling_func="${FUNCNAME[1]:-}: "
    strap::abort "${FONT_RED}${calling_func}${msg}${FONT_CLEAR}"
  fi
}

strap::assert() {
  local -r command="${1:-}" && strap::assert::has_length "$command" '$1 must be the command to evaluate'
  local -r msg="${2:-}" && strap::assert::has_length "$msg" '$2 must be the message to print if the command fails'
  if ! eval "$command"; then
    calling_func="${FUNCNAME[1]:-}: "
    strap::abort "${FONT_RED}${calling_func}${msg}${FONT_CLEAR}"
  fi
}

set +a

