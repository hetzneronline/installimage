#!/usr/bin/env bash

#
# kernel module config functions
#
# (c) 2023, Hetzner Online GmbH
#

unwanted_kernel_modules() {
  echo pcspkr
  debian_based_image && echo snd_pcsp
}

board_requires_drm_blacklisting() {
  has_fujitsu_board &&
    {
      [[ "$(board_name)" == D3417-B1 ]] ||
      [[ "$(board_name)" == D3417-B2 ]] ||
      [[ "$(board_name)" == D3401-H1 ]] ||
      [[ "$(board_name)" == D3401-H2 ]]
    } &&
    return
  [[ "$IAM" == ubuntu ]] &&
    ((IMG_VERSION >= 2204)) &&
    ! hwe_image &&
    [[ "$(board_vendor)" == 'ASUSTeK COMPUTER INC.' ]] &&
    [[ "$(board_name)" == 'PRIME B760M-A D4' ]] &&
    return 0
  [[ "$IAM" == ubuntu ]] &&
    ((IMG_VERSION == 2004)) &&
    hwe_image &&
    [[ "$(board_vendor)" == 'ASUSTeK COMPUTER INC.' ]] &&
    [[ "$(board_name)" == 'PRIME B760M-A D4' ]] &&
    return 0
  {
    { [[ "$IAM" == debian ]] && ((IMG_VERSION < 1300)) } ||
    { [[ "$IAM" == ubuntu ]] && ((IMG_VERSION < 2204)) }
  } &&
    [[ "$(board_vendor)" == 'Gigabyte Technology Co., Ltd.' ]] &&
    has_b360hd3p_board &&
    return 0
  return 1
}

buggy_kernel_modules() {
  if board_requires_drm_blacklisting; then
    echo i915
    [[ "$IAM" == ubuntu ]] && echo i915_bdw
    printf '%s\n' amdgpu drm nouveau radeon
  fi
  if [[ "$IAM" == archlinux ]] || debian_based_image; then
    printf '%s\n' mei mei-me
  fi
  echo sm750fb
}

blacklist_unwanted_and_buggy_kernel_modules() {
  local blacklist_conf="$FOLD/hdd/etc/modprobe.d/blacklist-$C_SHORT.conf"

  # skip if virtual machine
  is_virtual_machine && return

  debug '# blacklisting unwanted and buggy kernel modules'
  {
    echo "### $COMPANY - installimage"
    echo "### unwanted kernel modules"
    while read m; do
      echo "blacklist $m"
    done < <(unwanted_kernel_modules)
    echo "### buggy kernel modules"
    while read m; do
      echo "blacklist $m"
    done < <(buggy_kernel_modules)
  } > "$blacklist_conf"
  diff -Naur /dev/null "$blacklist_conf" | debugoutput
}

configure_kernel_modules() {
  local conf="$FOLD/hdd/etc/modprobe.d/$C_SHORT.conf"

  # skip if drm is blacklisted
  board_requires_drm_blacklisting && return
  # skip if virtual machine
  is_virtual_machine && return

  debug '# configuring kernel modules'
  {
    echo "### $COMPANY - installimage"
    echo 'options drm edid_firmware=edid/1280x1024.bin'
  } > "$conf"
  diff -Naur /dev/null "$conf" | debugoutput
}

# vim: ai:ts=2:sw=2:et
