#!/bin/bash

#
# CoreOS specific functions
#
# (c) 2014-2023, Hetzner Online GmbH
#
# This file isn't ready for production!
#

# create partitons on the given drive
# create_partitions "DRIVE"
create_partitions() {
  touch "$FOLD/fstab"
  return 0
}

make_swraid() {
  return 0
}

mount_partitions() {
  return 0
}

make_lvm() {
  return 0
}

format_partitions() {
  return 0
}

# validate image with detached signature
#validate_image() {
#  # no detached sign found
#  return 2
#}

# extract image file to hdd
extract_image() {
  return 0
}

setup_network_config() {
  return 0
}

# generate_config_mdadm "NIL"
generate_config_mdadm() {
  return 0
}

# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  return 0
}

set_udev_rules() {
  return 0
}

# copy_mtab "NIL"
copy_mtab() {
  return 0
}

generate_new_sshkeys() {
  return 0
}

generate_ntp_config() {
  return 0
}

set_hostname() {
  if [ -f "$CLOUDINIT" ]; then
    {
      echo "hostname: $1"
      echo ""
    } >>"$CLOUDINIT"
    return 0
  else
    return 1
  fi
}

setup_cpufreq() {
  return 0
}

generate_resolvconf() {
  return 0
}

generate_hosts() {
  return 0
}

generate_sysctlconf() {
  return 0
}

set_rootpassword() {
  if [ -n "$1" ] && [ -n "$2" ]; then
    if [ "$2" != '*' ]; then
      {
        echo "users:"
        echo "  - name: core"
        echo "    passwd: $2"
        echo "  - name: root"
        echo "    passwd: $2"
      } >>"$CLOUDINIT"
    fi
    return 0
  else
    return 1
  fi
}

# set sshd PermitRootLogin
set_ssh_rootlogin() {
  if [ -n "$1" ]; then
    local permit="$1"
    export COREOS_SSH_PERMIT_ROOT_LOGIN="$permit"
  else
    return 1
  fi
}

# copy_ssh_keys $OPT_SSHKEYS_URL
copy_ssh_keys() {
  return 0
}

# generate_config_grub <version>
generate_config_grub() {
  return 0
}

write_grub() {
  return 0
}

add_coreos_oem_scripts() {
  return 0
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
#  local ROOT_DEV; ROOT_DEV=$(blkid -t "LABEL=ROOT" -o device "${DRIVE1}"*)
#  local OEM_DEV; OEM_DEV=$(blkid -t "LABEL=OEM" -o device "${DRIVE1}"*)
#  local is_ext4; is_ext4=$(blkid -o value "$ROOT_DEV" | grep ext4)
#  if [ -n "$is_ext4" ]; then
#    mount "${ROOT_DEV}" "$FOLD/hdd" 2>&1 | debugoutput ; EXITCODE=$?
#  else
#    mount -t btrfs -o subvol=root "${ROOT_DEV}" "$FOLD/hdd" 2>&1 | debugoutput ; EXITCODE=$?
#  fi
#  [ "$EXITCODE" -ne "0" ] && return 1
#
#  # mount OEM partition as well
#  mount "${OEM_DEV}" "$FOLD/hdd/usr" 2>&1 | debugoutput ; EXITCODE=$?
#  [ "$EXITCODE" -ne "0" ] && return 1
#
#  if ! isVServer; then
#    add_coreos_oem_scripts "$FOLD/hdd/usr"
#  fi
#  add_coreos_oem_cloudconfig "$FOLD/hdd/usr"
#
#  mkdir -p "$FOLD/hdd/var/lib/coreos-install"
#  debugoutput < "$CLOUDINIT"
#  cp "$CLOUDINIT" "$FOLD/hdd/var/lib/coreos-install/user_data"
run_os_specific_functions() {
  #  apt-get update -y && apt-get install gcc g++ pkg-config libssl-dev libzstd-dev -y

  local ROOT_INDEX=""
  declare -a PART_LABEL
  for ((i = 1; i <= PART_COUNT; i++)); do
    if [ "${PART_MOUNT[$i]}" = "/" ] && [ "$ROOT_INDEX" = "" ]; then
      ROOT_INDEX="$i"
    fi
    PART_LABEL[$i]="$(echo "${PART_MOUNT[$i]}" | sed 's/^\///g' | sed 's|\/$||g' | sed 's/\//-/g')"
  done

  echo "ROOT_INDEX: $ROOT_INDEX"
  echo "${PART_MOUNT[@]}"

  local CRYPT_OTHER_PARTS="0"
  for ((i = 1; i <= PART_COUNT; i++)); do
    if [ "$i" != "$ROOT_INDEX" ] && [ "${PART_CRYPT[$i]}" = "1" ]; then
      CRYPT_OTHER_PARTS="1"
      break
    fi
  done

  BUTANE_CONFIG="/tmp/installimage.bu"
  {
    echo "variant: fcos"
    echo "version: 1.4.0"
    echo "passwd:"
    echo "  users:"
    echo "    - name: core"
    echo "      groups:"
    echo "        - wheel"
    echo "        - sudo"
    echo "      ssh_authorized_keys:"
    while read -r line; do
      if [ -n "$line" ]; then
        echo "        - $line"
      fi
    done <"$FOLD/authorized_keys"
    if [ "$SWRAID" = "1" ] || [ "$CRYPT" = "1" ]; then
      echo "boot_device:"
      if [ "$SWRAID" = "1" ]; then
        echo "  mirror:"
        echo "    devices:"
        echo "      - $DRIVE1"
        echo "      - $DRIVE2"
      fi
      if [ "${PART_CRYPT[$ROOT_INDEX]}" = "1" ]; then
        echo "  luks:"
        echo "    tpm2: true"
      fi
      echo "storage:"
      echo "  disks:"
      echo "    - device: $DRIVE1"
      echo "      partitions:"
      if [ "$SWRAID" = "1" ]; then
        echo "        - label: root-1"
        echo "          size_mib: ${PART_SIZE[$ROOT_INDEX]}"
        for ((i = 1; i <= PART_COUNT; i++)); do
          if [ "$i" != "$ROOT_INDEX" ]; then
            echo "        - label: ${PART_LABEL[$i]}-1"
            echo "          size_mib: ${PART_SIZE[$i]}"
          fi
        done
      else
        echo "        - label: root"
        echo "          number: 4"
        echo "          resize: true"
        echo "          size_mib: ${PART_SIZE[$ROOT_INDEX]}"
        for ((i = 1; i <= PART_COUNT; i++)); do
          if [ "$i" != "$ROOT_INDEX" ]; then
            echo "        - label: ${PART_LABEL[$i]}"
            echo "          size_mib: ${PART_SIZE[$i]}"
          fi
        done
      fi
      echo "    - device: $DRIVE2"
      echo "      partitions:"
      if [ "$SWRAID" = "1" ]; then
        echo "        - label: root-2"
        echo "          size_mib: ${PART_SIZE[$ROOT_INDEX]}"
        for ((i = 1; i <= PART_COUNT; i++)); do
          if [ "$i" != "$ROOT_INDEX" ]; then
            echo "        - label: ${PART_LABEL[$i]}-2"
            echo "          size_mib: ${PART_SIZE[$i]}"
          fi
        done
      fi
      if [ "$SWRAID" = "1" ]; then
        echo "  raid:"
        for ((i = 1; i <= PART_COUNT; i++)); do
          if [ "$i" != "$ROOT_INDEX" ]; then
            echo "    - name: ${PART_LABEL[$i]}"
            echo "      level: raid1"
            echo "      devices:"
            echo "        - /dev/disk/by-partlabel/${PART_LABEL[$i]}-1"
            echo "        - /dev/disk/by-partlabel/${PART_LABEL[$i]}-2"
          fi
        done
      fi
      if [ "$CRYPT_OTHER_PARTS" = "1" ]; then
        echo "  luks:"
        for ((i = 1; i <= PART_COUNT; i++)); do
          if [ "${PART_CRYPT[$i]}" = "1" ] && [ "$i" != "$ROOT_INDEX" ]; then
            echo "    - name: ${PART_LABEL[$i]}"
            echo "      label: ${PART_LABEL[$i]}"
            echo "      wipe_volume: true"
            echo "      device: /dev/disk/by-partlabel/${PART_LABEL[$i]}"
          fi
        done
      fi
    fi
  } >"$BUTANE_CONFIG"

  return 0
}

# vim: ai:ts=2:sw=2:et
