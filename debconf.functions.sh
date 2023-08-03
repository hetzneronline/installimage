#!/usr/bin/env bash

#
# debconf functions
#
# (c) 2018, Hetzner Online GmbH
#

debconf_set() {
  debug "# debconf set $@"
  echo "$@" | execute_chroot_command debconf-set-selections
}

debconf_set_grub_install_devices() {
  {
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ATTR{wwid}=="?*", SYMLINK+="disk/by-id/nvme-$attr{wwid}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]p*[0-9]", ENV{DEVTYPE}=="partition", ATTRS{wwid}=="?*", SYMLINK+="disk/by-id/nvme-$attr{wwid}-part%n"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ENV{DEVTYPE}=="disk", ATTRS{serial}=="?*", ENV{ID_SERIAL_SHORT}="$attr{serial}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ENV{DEVTYPE}=="disk", ATTRS{wwid}=="?*", ENV{ID_WWN}="$attr{wwid}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ENV{DEVTYPE}=="disk", ATTRS{model}=="?*", ENV{ID_MODEL}="$attr{model}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]", ENV{DEVTYPE}=="disk", ENV{ID_MODEL}=="?*", ENV{ID_SERIAL_SHORT}=="?*", \'
    echo '  ENV{ID_SERIAL}="$env{ID_MODEL}_$env{ID_SERIAL_SHORT}", SYMLINK+="disk/by-id/nvme-$env{ID_SERIAL}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]p*[0-9]", ENV{DEVTYPE}=="partition", ATTRS{serial}=="?*", ENV{ID_SERIAL_SHORT}="$attr{serial}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]p*[0-9]", ENV{DEVTYPE}=="partition", ATTRS{model}=="?*", ENV{ID_MODEL}="$attr{model}"'
    echo 'KERNEL=="nvme*[0-9]n*[0-9]p*[0-9]", ENV{DEVTYPE}=="partition", ENV{ID_MODEL}=="?*", ENV{ID_SERIAL_SHORT}=="?*", \'
    echo '  ENV{ID_SERIAL}="$env{ID_MODEL}_$env{ID_SERIAL_SHORT}", SYMLINK+="disk/by-id/nvme-$env{ID_SERIAL}-part%n"'
  } > /etc/udev/rules.d/99-installimage.rules
  udevadm control -R && udevadm trigger && udevadm settle
  local paths; paths=(); local part; local path_number
  while read drive; do
    # check if ESP partition exsists and then add ESP partition to path, or if not add the whole drive to the path
    path_number+=("$(drive_disk_by_id_path "$drive")")

    path_raw=$(sgdisk -p $path_number 2>&1)
    part="$(echo "${path_raw}" | grep 'EF00' | awk '{print $1;}')"
    echo "${path_raw}" | debugoutput

    if [ "$IAM" == "ubuntu" -a "$IMG_VERSION" -ge 2004 ] && [ "$UEFI" -eq 1 ] && [ -n "$(echo $part)" ] ; then
     paths+=("$(drive_disk_by_id_path "$drive")-part$part")
    else
     paths+=("$(drive_disk_by_id_path "$drive")")
    fi
  done < <(grub_install_devices)
  # Generate a random MS-DOS serial for for all ESP partions
  local value; value=''; local uuidefi; uuidefi="$(uuidgen | head -c8)"
  for path in "${paths[@]}"; do
    [[ -z "$path" ]] && return 1
    value+="$path, "
    # Change the MS-DOS label of all existing ESP partitions to the same serial
    if [ "$IAM" == "ubuntu" -a "$IMG_VERSION" -ge 2004 ] && [ "$UEFI" -eq 1 ] && [ -n "$(echo $part)" ]; then
      mlabel -N $uuidefi -i $path
    fi
  done
  # set install_devices for grub-efi and run dpkg-reconfigure to install grub on all ESPs listed
  if [ "$IAM" == "ubuntu" -a "$IMG_VERSION" -ge 2004 ] && [ "$UEFI" -eq 1 ] && [ -n "$(echo $part)" ]; then
    local grub_pkg_name
    if [ "$SYSARCH" == "x86_64" ]; then
      grub_pkg_name="grub-efi-amd64"
    else
      grub_pkg_name="grub-efi-$SYSARCH"
    fi
    debconf_set "$grub_pkg_name grub-efi/install_devices string ${value::-2}"
    execute_chroot_command "dpkg-reconfigure -f noninteractive $grub_pkg_name"
  else
    debconf_set "grub-pc grub-pc/install_devices multiselect ${value::-2}"
  fi
}

debconf_reset_grub_install_devices() {
  for p in grub-common grub-efi-amd64 grub-efi-arm64 grub-pc; do
    debug "# debconf RESET $p grub-efi/install_devices"
    echo 'RESET grub-efi/install_devices' | execute_chroot_command_wo_debug debconf-communicate "$p" | debugoutput
    if execute_chroot_command_wo_debug "dpkg -s $p &> /dev/null"; then
      debug "# dpkg-reconfigure $p"
      execute_chroot_command_wo_debug "dpkg-reconfigure -f noninteractive $p 2>&1" | debugoutput
    fi
  done
}
