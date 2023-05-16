#!/usr/bin/env bash

#
# screen functions
#
# (c) 2023, Hetzner Online GmbH
#

get_screen_output() {
  local session="$1"
  local tmp_file="$FOLD/tmp_screen_hardcopy"
  echo > "$tmp_file"
  screen -S "$session" -X hardcopy "$tmp_file"
  cat "$tmp_file"
}

last_nonempty_line_of_screen_output_matches() {
  local session="$1"
  local pattern="$2"
  get_screen_output "$session" | grep -v '^$' | tail -n 1 | grep -q "$pattern"
}

# vim: ai:ts=2:sw=2:et
