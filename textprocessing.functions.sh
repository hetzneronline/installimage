#!/usr/bin/env bash

#
# textprocessing functions
#
# (c) 2016, Hetzner Online GmbH
#

# safe_replace() <pattern> <replacement> <file>
# replace pattern with replacement if file exists and contains pattern
# $1 <pattern>
# $2 <replacement>
# $3 <file>
safe_replace() {
  local pattern="${1}"
  local replacement="${2}"
  local file="${3}"

  debug "# replacing ´${pattern}´ in file ${file}"

  # check if file exists
  if ! [[ -f "${file}" ]]; then
    # report and fail if it does not
    debug "file does not exist"
    return 1
  fi

  # check if file contains pattern
  if ! grep --extended-regexp --quiet "${pattern}" "${file}"; then
    # report and fail if it does not
    debug "pattern not found in file"
    return 1
  fi

  # escape /
  # bash builtins can not handle this!
  replacement="$(echo "${replacement}" | sed 's/[\/&]/\\&/g')"

  sed --regexp-extended --in-place "s/${pattern}/${replacement}/g" "${file}"
}

# vim: ai:ts=2:sw=2:et
