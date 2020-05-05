#!/usr/bin/env bash

set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
if ! command -v strap::lib::import >/dev/null; then
  echo "This file is not intended to be run or sourced outside of a strap execution context." >&2
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1 # if sourced, return 1, else running as a command, so exit
fi

strap::lib::import lang || . lang.sh
strap::lib::import logging || . logging.sh
strap::lib::import path || . path.sh
strap::lib::import os || . os.sh

##
# Ensures any initialization or setup for apt-get is required.  This can be a no-op if it is always already installed
# on the host OS before strap is run.
##
strap::aptget::init() {
  sudo apt-get update -qq #-o Acquire:Check-Valid-Until=false
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:deadsnakes/ppa # for Python
  sudo apt-get update -qq #-o Acquire:Check-Valid-Until=false
}

strap::aptget::pkg::is_installed() {
  local package_id="${1:-}" && strap::assert::has_length "$package_id" '$1 must be the package id'
  sudo dpkg-query -W -f='${Status}' "$package_id" 2>/dev/null | grep -q "ok installed"
}

strap::aptget::pkg::install() {
  local package_id="${1:-}" && strap::assert::has_length "$package_id" '$1 must be the package id'
  sudo apt-get install -y "$package_id"
}