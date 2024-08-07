#!/bin/bash

#
# CentOS specific functions
#
# (c) 2008-2021, Hetzner Online GmbH
#


# generate_config_mdadm "NIL"
generate_config_mdadm() {
  if [ -n "$1" ]; then
    local mdadmconf="/etc/mdadm.conf"
    {
      echo "DEVICE partitions"
      echo "MAILADDR root"
    } > "$FOLD/hdd$mdadmconf"
    execute_chroot_command "mdadm --examine --scan >> $mdadmconf"; declare -i EXITCODE=$?
    return $EXITCODE
  fi
}

# generate_new_ramdisk "NIL"
generate_new_ramdisk() {
  if [ -n "$1" ]; then

    # pick the latest kernel
    VERSION="$(find "$FOLD/hdd/boot/" -name "vmlinuz-*" | cut -d '-' -f 2- | sort -V | tail -1)"

    blacklist_unwanted_and_buggy_kernel_modules
    configure_kernel_modules

    local dracutfile="$FOLD/hdd/etc/dracut.conf.d/99-$C_SHORT.conf"
    {
      echo "### $COMPANY - installimage"
      echo 'add_dracutmodules+=" lvm mdraid "'
      echo 'add_drivers+=" raid0 raid1 raid10 raid456 "'
      #echo 'early_microcode="no"'
      echo 'hostonly="no"'
      echo 'hostonly_cmdline="no"'
      echo 'lvmconf="yes"'
      echo 'mdadmconf="yes"'
      echo 'persistent_policy="by-uuid"'
    } > "$dracutfile"

    execute_chroot_command "dracut -f --kver $VERSION"
    declare -i EXITCODE=$?
    return "$EXITCODE"
  fi
}

#
# generate_config_grub <version>
#
# Generate the GRUB bootloader configuration.
#
generate_config_grub() {
  [ -n "$1" ] || return
  # we should not have to do anything, as grubby (new-kernel-pkg) should have
  # already generated a grub.conf
  # even though grub2-mkconfig will generate a device.map on the fly, the
  # anaconda installer still creates this
  DMAPFILE="$FOLD/hdd/boot/grub2/device.map"
  [ -f "$DMAPFILE" ] && rm "$DMAPFILE"

  local -i i=0
  for ((i=1; i<=COUNT_DRIVES; i++)); do
    local j; j="$((i - 1))"
    local disk; disk="$(eval echo "\$DRIVE$i")"
    echo "(hd$j) $disk" >> "$DMAPFILE"
  done
  debug '# device map:'
  cat "$DMAPFILE" | debugoutput

  local elevator=''
  if is_virtual_machine; then
    elevator='elevator=noop'
  fi

  local grub_cmdline_linux='biosdevname=0 crashkernel=auto'
  is_virtual_machine && grub_cmdline_linux+=' elevator=noop'
  (( USE_KERNEL_MODE_SETTING == 0 )) && grub_linux_default+=' nomodeset'
  grub_cmdline_linux+=' rd.auto=1 consoleblank=0'

  if has_threadripper_cpu; then
    grub_cmdline_linux+=' pci=nommconf'
  fi

  if [ "$SYSARCH" == "arm64" ]; then
    grub_cmdline_linux+=' console=ttyAMA0 console=tty0'
  fi

  sed -i "s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"$grub_cmdline_linux\"/" "$FOLD/hdd/etc/default/grub"

  if ((IMG_VERSION > 80)) && ((IMG_VERSION <= 90)) && ((IMG_VERSION != 610)) && [[ -z "$GRUB_DEFAULT_OVERRIDE" ]]; then
    GRUB_DEFAULT_OVERRIDE='saved'
  fi

  if [[ -n "$GRUB_DEFAULT_OVERRIDE" ]]; then sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=$GRUB_DEFAULT_OVERRIDE/" "$FOLD/hdd/etc/default/grub"; fi

  rm -f "$FOLD/hdd/boot/grub2/grub.cfg"
  if [ "$UEFI" -eq 1 ]; then
    execute_chroot_command "grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg 2>&1"; declare -i EXITCODE="$?"
  else
    execute_chroot_command "grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1"; declare -i EXITCODE="$?"
  fi
  uuid_bugfix
  return "$EXITCODE"
}

write_grub() {
  if [ "$UEFI" -eq 1 ]; then
    # we must NOT use grub2-install here. This will replace the prebaked
    # grubx64.efi (which looks for grub.cfg in ESP) with a new one, which
    # looks for in in /boot/grub2 (which may be more difficult to read)
    rm -f "$FOLD/hdd/boot/grub2/grubenv"
    execute_chroot_command "ln -s /boot/efi/EFI/centos/grubenv /boot/grub2/grubenv"
    declare -i EXITCODE=$?
  else
    # only install grub2 in mbr of all other drives if we use swraid
    for ((i=1; i<=COUNT_DRIVES; i++)); do
      if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
        local disk; disk="$(eval echo "\$DRIVE"$i)"
        execute_chroot_command "grub2-install --no-floppy --recheck $disk 2>&1"
        declare -i EXITCODE=$?
      fi
    done
  fi

  return "$EXITCODE"
}

#
# os specific functions
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
run_os_specific_functions() {
  randomize_mdadm_array_check_time

  execute_chroot_command "chkconfig iptables off"
  execute_chroot_command "chkconfig ip6tables off"
  is_plesk_install || execute_chroot_command "chkconfig postfix off"

  #
  # setup env in cpanel image
  #
  debug "# Testing and setup of cpanel image"
  if [ -f "$FOLD/hdd/etc/wwwacct.conf" ] && [ -f "$FOLD/hdd/etc/cpupdate.conf" ] ; then
    grep -q -i cpanel <<< "$IMAGE_FILE" && {
      setup_cpanel || return 1
    }
  fi

  # selinux autorelabel if enabled
  egrep -q "SELINUX=(enforcing|permissive)" "$FOLD/hdd/etc/sysconfig/selinux" &&
    touch "$FOLD/hdd/.autorelabel"

  ((IMG_VERSION >= 69)) && mkdir -p "$FOLD/hdd/var/run/netreport"

  if ((IMG_VERSION >= 74)) && ((IMG_VERSION != 610)) && ((IMG_VERSION < 80)); then
    execute_chroot_command 'yum check-update' # || return 1
    execute_chroot_command 'yum -y install polkit' || return 1
  fi

  return 0
}

# vim: ai:ts=2:sw=2:et
