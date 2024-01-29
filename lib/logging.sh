#!/usr/bin/env bash

set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
if ! command -v strap::lib::import >/dev/null; then
  echo "This file is not intended to be run or sourced outside of a strap execution context." >&2
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1 # if sourced, return 1, else running as a command, so exit
fi

# strap::lib::import fonts || . fonts.sh

set -a

strap::ok() {
    echo -e "${FONT_GREEN}OK${FONT_CLEAR} ${1:-}"
}

strap::bot() {
    echo -e "\n${FONT_BOLD}${FONT_BLUE}##${FONT_CLEAR} ${FONT_ULINE}${FONT_BOLD}${1:-}${FONT_CLEAR}\n"
}

strap::running() {
    echo -en "$FONT_SLATE_BLUE_3 ⇒ $FONT_CLEAR ${1:-}: "
}

strap::action() {
    echo -en "\n    $FONT_BOLD$FONT_DODGER_BLUE_3 ⇒  $FONT_CLEAR$FONT_BOLD${1:-} ... "
}

strap::info() {
    echo -e "${FONT_CORNFLOWER_BLUE}    [info]$FONT_CLEAR ${1:-}"
}

strap::warn() {
    echo -e "$FONT_YELLOW[warning]$FONT_CLEAR ${1:-}"
}

strap::error() {
    echo -e "$FONT_RED[error]$FONT_CLEAR ${1:-}" >&2
}

strap::abort() {
  local msg="${1:-}"
  printf "\n\n"
  [[ -n "$msg" ]] && strap::error "$msg"
  local -r stack_depth="${#FUNCNAME[@]}"
  local i=0
  while [[ $i < $stack_depth ]]; do
    stack_line="$(caller $i)"
    func_name="$(echo $stack_line | awk '{print $2}')"
    source_file="$(echo $stack_line | awk '{print $3}')"
    line_number="$(echo $stack_line | awk '{print $1}')"
    strap::error "    at ${FONT_LIGHT_SKYBLUE_1}${func_name}${FONT_CLEAR} (${FONT_LIGHT_STEEL_BLUE_1}${source_file}${FONT_CLEAR}:${FONT_SKYBLUE_2}${line_number}${FONT_CLEAR})"
    ((i++))
  done
  exit 1
}

function strap::err::print() {
  local msg plain=false
  if [[ "${1:-}" == "--plain" ]]; then
    plain=true
    shift
  fi
  if [[ ! -t 2 || "${plain}" == true || $# -eq 0 ]]; then # not a terminal or explicitly requested no color output:
    msg="$@"
  else # otherwise use color output:
    msg="${FONT_RED}${@}${FONT_CLEAR}"
  fi
  printf '%s' "${msg}" >&2
}

function strap::err::println() {
  [[ $# -eq 0 ]] || strap::err::print "$@"
  printf '\n' >&2
}

function strap::err::exit() {
  [[ $# -eq 0 ]] || strap::err::println "$@"
  exit 1
}

function strap::sys::strace() {
  local -r stack_size="${#FUNCNAME[@]}"
  local i=1 # don't print out this function itself - it's always last and doesn't help
  while [[ $i < $stack_size ]]; do
    local lineno="${BASH_LINENO[$(( i - 1 ))]}"
    local func="${FUNCNAME[$i]}";
    local src="${BASH_SOURCE[$i]}";

    if [[ ! -f "${src}" ]]; then

      # try to find if $func is defined in our standard sys.sh source file:
      local testsrc="${STRAP_LIB_DIR}/sys.sh"
      local foundno="$(grep -En "${func}[[:space:]]*[(]?[)]?[[:space:]]*{\$" ${testsrc} | awk -F':' '{print $1}' || true)"

      if [[ -z "${foundno}" ]]; then
        # Not in sys.sh - try $STRAP_SCRIPT
        testsrc="${STRAP_SCRIPT}"
        foundno="$(grep -En "${func}[[:space:]]*[(]?[)]?[[:space:]]*{\$" ${testsrc} | awk -F':' '{print $1}' || true)"
      fi

      if [[ -n "${foundno}" ]]; then
        src="${testsrc}"
        local lineadjust=1; [[ ${i} -eq 0 ]] && lineadjust=0
        lineno=$((lineno + foundno + lineadjust))
      fi
    fi

    # if we're in a terminal (e.g. not being piped), print color output to stderr, otherwise don't:
    if [[ -t 2 ]]; then
      printf '    at %s (%s:%s)\n' \
             "${FONT_LIGHT_SKYBLUE_1}${func}${FONT_CLEAR}" \
             "${FONT_LIGHT_STEEL_BLUE_1}${src}${FONT_CLEAR}" \
             "${FONT_SKYBLUE_2}${lineno}${FONT_CLEAR}" \
             >&2
    else
      printf '    at %s (%s:%s)\n' "${func}" "${src}" "${lineno}" >&2
    fi

    i=$((i + 1))
  done
}

function strap::err::abort() {
  local msg="${1:-}"
  strap::err::println
  strap::err::println
  [[ -z "${msg}" ]] || strap::err::println '[abort] ' "${msg}"
  strap::sys::strace
  exit 1
}

function strap::err::cmd_exit() {
  [[ $# -eq 0 ]] || strap::err::println "${STRAP_USER_COMMAND}: $@"
  exit 1
}

function strap::err::cmd_invalid() {

  local -r cmd="${1:-}" subcmd="${2:-}"
  strap::assert::has_length "${cmd}" '$1 must be a strap command'
  strap::assert::has_length "${subcmd}" '$2 must be the subcommand'

  strap::err::println "${cmd}: unknown command '${subcmd}'"
  strap::err::println --plain "See '${cmd} --help' for available commands."
}

set +a
