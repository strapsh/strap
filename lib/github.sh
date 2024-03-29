#!/usr/bin/env bash

set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
if ! command -v strap::lib::import >/dev/null; then
  echo "This file is not intended to be run or sourced outside of a strap execution context." >&2
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 1 || exit 1 # if sourced, return 1, else running as a command, so exit
fi

strap::lib::import logging || . logging.sh
strap::lib::import lang || . lang.sh
strap::lib::import io || . io.sh
strap::lib::import os || . os.sh
strap::lib::import git || . git.sh

STRAP_PROFILES="${STRAP_PROFILES:-}"

__STRAP_GITHUB_USER_JSON="${__STRAP_GITHUB_USER_JSON:-}"
__STRAP_GITHUB_USER_EMAILS_JSON="${__STRAP_GITHUB_USER_EMAILS_JSON:-}"
__STRAP_GITHUB_USER_KEYS_JSON="${__STRAP_GITHUB_USER_KEYS_JSON:-}"

__STRAP_GITHUB_USER="${STRAP_GITHUB_USER:-}" # for CI purposes to prevent prompting for user input
__STRAP_GITHUB_TOKEN="${STRAP_GITHUB_TOKEN:-}" # for CI purposes to prevent prompting for user input

set -a

strap::github::user::ensure() {

  strap::running "Checking GitHub username"

  local github_username="$(git config --global github.user || true)"
  local store=false && [[ -z "$github_username" ]] && store=true # ensure we store any discovered value before returning

  [[ -z "$github_username" ]] && github_username="$__STRAP_GITHUB_USER"; # fall back to env var

  if [[ -z "$github_username" ]]; then # fall back to user prompt
    echo
    strap::readval github_username "Enter your GitHub username" false true
  fi

  if [[ -n "$github_username" ]] && [[ "$store" == true ]]; then
    git config --global github.user "$github_username" || strap::abort "Unable to save GitHub username to git config"
  fi

  strap::ok
}

strap::github::user::get() {
  git config --global github.user || strap::abort "GitHub username is not available in git config"
}

strap::github::token::delete() {
  strap::git::credential::delete 'github.com'
}

strap::github::token::save() {
  local -r username="${1:-}" && [[ -z "$username" ]] && strap::error 'strap::github::token::find: $1 must be a github username' && return 1
  local -r token="${2:-}" && [[ -z "$token" ]] && strap::error 'strap::github::token::find: $2 must be a github api token' && return 1
  strap::git::credential::save 'github.com' "$username" "$token"
}

strap::github::token::find() {

  local -r username="${1:-}" && strap::assert::has_length "$username" '$1 must be a github username'
  local token="$(strap::git::credential::find 'github.com' "$username")"
  local store=false && [[ -z "$token" ]] && store=true # ensure we store any discovered value before returning

  # This is for legacy strap environments where strap stored the token manually in the osxkeychain instead of using
  # the git credential helper.  If found, it will be moved to the git credential helper (as this is the de-facto standard)
  # and then removed from the manual osx keychain entry:
  if [[ -z "$token" ]] && [[ "$STRAP_OS" == "mac" ]]; then

    local -r label="Strap GitHub API personal access token"

    if security find-internet-password -a "$username" -s api.github.com -l "$label" >/dev/null 2>&1; then

      token="$(security find-internet-password -a "$username" -s api.github.com -l "$label" -w)"

      if [[ -n "$token" ]]; then # found in the legacy location - remove it:
         security delete-internet-password -a "$username" -s api.github.com -l "$label" 2>&1 >/dev/null
      fi

    fi

  fi

  [[ -z "$token" ]] && token="$__STRAP_GITHUB_TOKEN" # fall back to env var - useful in CI to prevent prompting for user input

  if [[ -n "$token" ]] && [[ "$store" == true ]]; then
    # save to the de-facto location:
    strap::github::token::save "$username" "$token"
  fi

  echo "$token"
}

strap::github::api::request() {

  local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
  local -r url="${2:-}" && strap::assert::has_length "$url" '$2 must be a github api URL'

  local -r response="$(curl --silent --show-error -H "Authorization: token $token" --write-out "HTTPSTATUS:%{http_code}" "$url")"
  local -r body="$(echo "$response" | sed -e 's/HTTPSTATUS\:.*//g')"
  local -r status_code="$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')"

  if [[ "$status_code" == "200" || "$status_code" == "201" ]]; then
    echo "$body"
  elif [[ "$status_code" == 4* ]]; then
    return 1
  else
    strap::error "Unexpected GitHub API response:"
    strap::error "    Reqeuest URL: $url"
    strap::error "    Response Status Code: $status_code"
    strap::error "    Response Body: $body"
    return 1
  fi
}

strap::github::api::token::create() {

  local -r username="${1:-}" && strap::assert::has_length "$username" '$1 must be a github username'
  local -r max_password_attempts=3
  local -r max_otp_attempts=3
  local password_attempts=0
  local otp_attempts=0

  local utc_date=
  local token_description=
  local request_body=
  local token=
  local creds=
  local password=
  local two_factor_code=
  local response=
  local status_code=
  local headers=
  local body=
  local retry_ask=

  local -r machine_desc="$(strap::os::model)"
  local uname=''
  uname="$(uname -s)"

  while [[ -z "$token" ]]; do
    if [ "$uname" == "Darwin" ]; then
      open https://github.com/settings/tokens/new
    elif [ "$uname" == "Linux" ]; then
      gio open https://github.com/settings/tokens/new
    fi
    echo "Please login to Github, and visit https://github.com/settings/tokens/new to create a personal access token. Make sure the following scopes are selected: repo, read:org under admin:org, and read:public_key under admin:public_key. Once created, copy and paste the token into Strap."

    echo
    strap::readval token "Enter (or cmd-v paste) your Token once you have generated it" true

    if ! strap::github::api::token::is_valid "$token"; then
        strap::action "The token you created is invalid. Please try again."
        token='' # clear to ensure a new one is created next
    fi

  done

  # we have a token now - save it to secure storage:
  strap::github::token::save "$username" "$token"

  #Test if we need to do an SSO enable
  response="$(curl --silent --show-error -i -H "Authorization: token $token" -H 'Content-Type: application/json' https://api.github.com/user/issues)"
  headers="$(echo "$response" | sed "/^\s*$(printf '\r')*$/q" | sed '/^[[:space:]]*$/d' | tail -n +2)"
  if echo "$headers" | grep -q 'X-GitHub-SSO:'; then
    if [ "$uname" == "Darwin" ]; then
      open https://github.com/settings/tokens
    elif [ "$uname" == "Linux" ]; then
      gio open https://github.com/settings/tokens
    fi
    echo "One or more of the Github Orgs you belong to requires that you to enable an SSO personal access token before proceeding. Visit https://github.com/settings/tokens in your web browser and authorize the token"
    echo
    echo "For more information: https://help.github.com/en/articles/authorizing-a-personal-access-token-for-use-with-a-saml-single-sign-on-organization."
    echo
    read -r -p "Press [Enter] key once you have enabled the token..." ignore </dev/tty
  fi
}

strap::github::api::user() {

   local json="$__STRAP_GITHUB_USER_JSON"

   if [[ -z "$json" ]]; then
      local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
      json="$(strap::github::api::request "$token" 'https://api.github.com/user' || true)"
      [[  -z "$json" ]] && return 1
      export __STRAP_GITHUB_USER_JSON="$json"
   fi

   echo "$json"
}

strap::github::api::user::name() {
  local -r token="${1:-}"
  local -r user_json="$(strap::github::api::user ${token})"
  echo "$user_json"| jq -r '.name // empty'
}

strap::github::api::token::is_valid() {
  local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
  local -r json="$(strap::github::api::request "$token" 'https://api.github.com/user' || true)"
  [[ -z "$json" ]] && return 1
  export __STRAP_GITHUB_USER_JSON="$json"
}

strap::github::api::user::emails() {

  local json="$__STRAP_GITHUB_USER_EMAILS_JSON"

  if [[ -z "$json" ]]; then
    local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
    json="$(strap::github::api::request "$token" 'https://api.github.com/user/emails' || true)"
    [[  -z "$json" ]] && return 1
    export __STRAP_GITHUB_USER_EMAILS_JSON="$json"
  fi

  echo "$json"
}

strap::github::api::user::email() {
  local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
  local -r json="$(strap::github::api::user::emails "$token")"
  local email="$(echo "$json" | jq -r '[.[] | select(.email | contains("users.noreply.github.com"))][0] | .email // empty')"
  if [[ -z "$email" ]]; then
    email="$(echo "$json" | jq -r '[.[] | select(.verified == true and .primary == true)][0] | .email // empty')"
  fi
  [[ -z "$email" ]] && return 1
  echo "$email"
}

strap::github::api::user::keys() {

  local json="$__STRAP_GITHUB_USER_KEYS_JSON"

  if [[ -z "$json" ]]; then
    local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
    json="$(strap::github::api::request "$token" 'https://api.github.com/user/keys' || true)"
    [[  -z "$json" ]] && return 1
    export __STRAP_GITHUB_USER_KEYS_JSON="$json"
  fi

  echo "$json"
}

strap::github::api::user::keys::add() {
  local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
  local -r key="${2:-}" && strap::assert::has_length "$key" '$2 must the contents of an ssh public key file'

  now="$(date -u +%FT%TZ)"
  title="Strap-generated RSA public key on $now."
  [[ "$STRAP_PROFILES" == *"ci"* ]] && title="${title} This is for CI testing and may be safely deleted."
  request_body="{ \"title\": \"$title\", \"key\": \"$key\" }"
  response="$(curl --silent --show-error -i -H "Authorization: token $token" -H 'Content-Type: application/json' -X POST -d "$request_body" https://api.github.com/user/keys)"
  status_code="$(echo "$response" | head -1 | awk '{print $2}')"
  #headers="$(echo "$response" | sed "/^\s*$(printf '\r')*$/q" | sed '/^[[:space:]]*$/d' | tail -n +2)"
  #body="$(echo "$response" | sed "1,/^\s*$(printf '\r')*$/d")"

  # remove any cached keys result since we just added one.  This ensures the next time keys are requested, the
  # complete set will be retrieved:
  unset __STRAP_GITHUB_USER_KEYS_JSON

  if [[ "$status_code" != "201" ]]; then
    strap::abort 'Unable to upload Strap-generated RSA public key to GitHub'
  fi
}

strap::github::api::user::keys::contains() {
  local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
  local -r key="${2:-}" && strap::assert::has_length "$key" '$2 must be an ssh public key'
  local -r json="$(strap::github::api::user::keys "$token")"
  local result="$(echo "$json" | jq -r ".[] | select(.key == \"$key\") | .key")"
  if [[ -z "$result" ]]; then
    return 1
  fi
}

strap::github::api::user::keys::ensure() {

  local -r token="${1:-}" && strap::assert::has_length "$token" '$1 must be a github api token'
  local -r key="${2:-}" && strap::assert::has_length "$key" '$2 must the contents of an ssh public key file'

  strap::running "Checking ssh public key registered with GitHub"

  if ! strap::github::api::user::keys::contains "$token" "$key"; then
    strap::action "Registering ssh public key with GitHub"
    strap::github::api::user::keys::add "$token" "$key"
  fi

  strap::ok
}

set +a
