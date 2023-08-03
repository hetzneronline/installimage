#!/usr/bin/env bash

#
# blsconfig functions
#
# (c) 2023, Hetzner Online GmbH
#

blsconfig_fix_paths() {
  # paths must be relative to the "boot partition"!

  # try to find boot mount
  local boot_mp='/boot'
  while read _ mp _; do
    [[ "$mp" == "$FOLD/hdd/boot" ]] && boot_mp=''
  done < /proc/mounts

  # adjust linux and initrd options for all entries
  for f in "$FOLD/hdd/boot/loader/entries/"*'.conf'; do
    [[ -e "$f" ]] ||  continue

    {
      while read option first_arg remaining_args; do
        case "$option" in
          linux|initrd)
            first_arg="$boot_mp/${first_arg##*/}"
          ;;
        esac
        echo "$option $first_arg $remaining_args" | awk '{$1=$1};1'
      done < "$f"
    } > "$f.new"

    if cmp -s "$f.new" "$f"; then
      rm "$f.new"
      continue
    fi

    debug '# adjusting BLS config paths:'
    diff -Naur "$f" "$f.new" | debugoutput
    mv "$f.new" "$f"
  done
}

# vim: ai:ts=2:sw=2:et
