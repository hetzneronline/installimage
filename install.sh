#!/bin/bash

#
# install - installation commands
#
# (c) 2007-2017, Hetzner Online GmbH
#


STATUS_POSITION="\033[60G"

TOTALSTEPS=15
CURSTEP=0

# read global variables and functions
clear
. /tmp/install.vars


inc_step() {
  CURSTEP=$(($CURSTEP + 1))
}

status_busy() {
  local step="$CURSTEP"
  test $CURSTEP -lt 10 && step=" $CURSTEP"
  echo -ne "  $step/$TOTALSTEPS  :  $@ $STATUS_POSITION${CYAN} busy $NOCOL"
  debug "# $@"
}

status_busy_nostep() {
  echo -ne "         :  $@ $STATUS_POSITION${CYAN} busy $NOCOL"
}

status_none() {
  local step="$CURSTEP"
  test $CURSTEP -lt 10 && step=" $CURSTEP"
  echo -e "  $step/$TOTALSTEPS  :  $@"
}

status_none_nostep() {
  echo -e "         :  $@"
}

status_done() {
  echo -e "$STATUS_POSITION${GREEN} done $NOCOL"
}

status_failed() {
  echo -e "$STATUS_POSITION${RED}failed$NOCOL"
  [ $# -gt 0 ] && echo -e "${RED}         :  $@${NOCOL}"
  debug "=> FAILED"
  exit_function
  exit 1
}

status_warn() {
  echo -e "$STATUS_POSITION${YELLOW} warn"
  echo -e "         :  $@${NOCOL}"
}

status_donefailed() {
  if [ "$1" -a $1 -eq 0 ]; then
    status_done
  else
    status_failed
  fi
}

echo
echo_bold "                $COMPANY - installimage\n"
echo_bold "  Your server will be installed now, this will take some minutes"
echo_bold "             You can abort at any time with CTRL+C ...\n"

#
# get active nic and gather network information
#
get_active_eth_dev
gather_network_information


#
# Read configuration
#
status_busy_nostep "Reading configuration"
read_vars $FOLD/install.conf
status_donefailed $?

#
# Load image variables
#
status_busy_nostep "Loading image file variables"
get_image_info "$IMAGE_PATH" "$IMAGE_PATH_TYPE" "$IMAGE_FILE"
status_donefailed $?


# change sizes of DOS partitions
check_dos_partitions "no_output"

whoami $IMAGE_FILE
status_busy_nostep "Loading $IAM specific functions "
debug "# load $IAM specific functions..."
if [ -e "$SCRIPTPATH/$IAM.sh" ]; then
  . $SCRIPTPATH/$IAM.sh 2>&1 > /dev/null
  status_done
else
  status_failed
fi

test "$SWRAID" = "1" && TOTALSTEPS=$(($TOTALSTEPS + 1))
test "$LVM" = "1" && TOTALSTEPS=$(($TOTALSTEPS + 1))
test "$OPT_INSTALL" && TOTALSTEPS=$(($TOTALSTEPS + 1))
test "$IMAGE_PATH_TYPE" = "http" && TOTALSTEPS=$(($TOTALSTEPS + 1))

#
# Remove partitions
#
inc_step
status_busy "Deleting partitions"

# Unmount all partitions and print an error message if it fails
output=$(unmount_all) ; EXITCODE=$?
if [ $EXITCODE -ne 0 ] ; then
  echo ""
  echo -e "${RED}ERROR unmounting device(s):$NOCOL"
  echo "$output"
  echo ""
  echo -e "${RED}Cannot continue, device(s) seem to be in use.$NOCOL"
  echo "Please unmount used devices manually or reboot the rescuesystem and retry."
  echo ""
  exit 1
fi

stop_lvm_raid ; EXITCODE=$?
if [ $EXITCODE -ne 0 ] ; then
  echo ""
  echo -e "${RED}ERROR stopping LVM and/or RAID device(s):$NOCOL"
  echo ""
  echo -e "${RED}Cannot continue, device(s) seem to be in use.$NOCOL"
  echo "Please stop used lvm/raid manually or reboot the rescuesystem and retry."
  echo ""
  exit 1
fi

for part_inc in $(seq 1 $COUNT_DRIVES) ; do
  if [ "$(eval echo \$FORMAT_DRIVE${part_inc})" = "1" -o "$SWRAID" = "1" -o $part_inc -eq 1 ] ; then
    TARGETDISK="$(eval echo \$DRIVE${part_inc})"
    debug "# Deleting partitions on $TARGETDISK"
    delete_partitions "$TARGETDISK" || status_failed
  fi
done

status_done

wait_for_udev

#
# Test partition size
#
inc_step
status_busy "Test partition size"
part_test_size
check_dos_partitions "no_output"
status_done


#
# Create partitions
#
inc_step
status_busy "Creating partitions and /etc/fstab"

for part_inc in $(seq 1 $COUNT_DRIVES) ; do
  if [ "$SWRAID" = "1" -o $part_inc -eq 1 ] ; then
    TARGETDISK="$(eval echo \$DRIVE${part_inc})"
    debug "# Creating partitions on $TARGETDISK"
    create_partitions $TARGETDISK || status_failed
  fi
done

status_done

wait_for_udev

#
# Software RAID
#
if [ "$SWRAID" = "1" ]; then
  inc_step
  status_busy "Creating software RAID level $SWRAIDLEVEL"
  make_swraid "$FOLD/fstab"
  suspend_swraid_resync
  status_donefailed $?
fi

wait_for_udev

#
# LVM
#
if [ "$LVM" = "1" ]; then
  inc_step
  status_busy "Creating LVM volumes"
  make_lvm "$FOLD/fstab" 
  LVM_EXIT=$?
  if [ $LVM_EXIT -eq 2 ] ; then
    status_failed "LVM thin-pool detected! Can't remove automatically!"
  else
    status_donefailed $LVM_EXIT
  fi
fi

wait_for_udev

#
# Format partitions
#
inc_step
status_none "Formatting partitions"
cat $FOLD/fstab | grep "^/dev/" > /tmp/fstab.tmp
while read line ; do
  DEV="$(echo $line |cut -d " " -f 1)"
  FS="$(echo $line |cut -d " " -f 3)"
  status_busy_nostep "  formatting $DEV with $FS"
  format_partitions "$DEV" "$FS"
  status_donefailed $?
done < /tmp/fstab.tmp


#
# Mount filesystems
#
inc_step
status_busy "Mounting partitions"
mount_partitions "$FOLD/fstab" "$FOLD/hdd" || status_failed
status_donefailed $?


#
# Look for a post-mount script and call it if existing
#
# this can be used e.g. for asking the user if
# he wants to restore from an ebackup-server
#
if has_postmount_script ; then
  status_none_nostep "Executing post mount script"
  execute_postmount_script || exit 0
fi

#
# ntp resync
#
inc_step
status_busy "Sync time via ntp"
set_ntp_time
status_donefailed $?

#
# Download image
#
if [ "$IMAGE_PATH_TYPE" = "http" ] ; then
  inc_step
  status_busy "Downloading image ($IMAGE_PATH_TYPE)"
  get_image_url "$IMAGE_PATH" "$IMAGE_FILE"
  status_donefailed $?
fi

#
# Import public key for image validation
#
status_busy_nostep "Importing public key for image validation"
import_imagekey
IMPORT_EXIT=$?
if [ $IMPORT_EXIT -eq 2 ] ; then
  status_warn "No public key found!"
else
  status_donefailed $IMPORT_EXIT
fi

#
# Validate image
#
inc_step
status_busy "Validating image before starting extraction"
validate_image
VALIDATE_EXIT=$?
if [ -n "$FORCE_SIGN" -o -n "$OPT_FORCE_SIGN" ] && [ $VALIDATE_EXIT -gt 0 ] ; then
  debug "FORCE_SIGN set, but validation failed!"
  status_failed
fi
if [ $VALIDATE_EXIT -eq 3 ] ; then
  status_warn "No imported public key found!"
elif [ $VALIDATE_EXIT -eq 2 ] ; then
  status_warn "No detached signature file found!"
else
  status_donefailed $VALIDATE_EXIT
fi

#
# Extract image
#
inc_step
status_busy "Extracting image ($IMAGE_PATH_TYPE)"
extract_image "$IMAGE_PATH_TYPE" "$IMAGE_FILE_TYPE"
status_donefailed $?

#
# Setup network
#
inc_step
if [[ "$IAM" == 'centos' ]] || [[ "$IAM" == 'debian' ]] || [[ "$IAM" == 'archlinux' ]]; then
  status_busy "Setting up network config"
  setup_network_config_new
  status_donefailed $?
elif [[ "$IAM" == 'ubuntu' ]] && ((IMG_VERSION == 1404)); then
  status_busy "Setting up network config"
  setup_network_config_new
  status_donefailed $?
elif [[ "$IAM" == 'ubuntu' ]] && ((IMG_VERSION >= 1604)); then
  status_busy "Setting up network config"
  setup_network_config_new
  status_donefailed $?
elif [[ "$IAM" == 'suse' ]] && ((IMG_VERSION >= 422)); then
  status_busy "Setting up network config"
  setup_network_config_new
  status_donefailed $?
else
  status_busy "Setting up network for $ETHDEV"
  setup_network_config "$ETHDEV" "$HWADDR" "$IPADDR" "$BROADCAST" "$SUBNETMASK" "$GATEWAY" "$NETWORK" "$IP6ADDR" "$IP6PREFLEN" "$IP6GATEWAY"
  status_donefailed $?
fi

if [[ "$IAM" == 'centos' ]] && ((IMG_VERSION >= 70)); then
  :
elif [[ "$IAM" == 'debian' ]] && ((IMG_VERSION >= 80)) && ((IMG_VERSION != 710)) && ((IMG_VERSION != 711)); then
  :
elif [[ "$IAM" == 'ubuntu' ]] && ((IMG_VERSION >= 1604)); then
  :
elif [[ "$IAM" == 'suse' ]] && ((IMG_VERSION >= 422)); then
  :
else
  #
  # Set udev rules
  #
  set_udev_rules
fi

#
# chroot commands
#
inc_step
status_none "Executing additional commands"

copy_mtab "NIL"

status_busy_nostep "  Setting hostname"
debug "# Setting hostname"
#set_hostname "$NEWHOSTNAME" || status_failed
set_hostname "$NEWHOSTNAME" "$IPADDR" "$IP6ADDR" || status_failed
status_done

status_busy_nostep "  Generating new SSH keys"
debug "# Generating new SSH keys"
generate_new_sshkeys "NIL" || status_failed
status_done

if [ "$SWRAID" = "1" ]; then
  status_busy_nostep "  Generating mdadm config"
  debug "# Generating mdadm configuration"
  generate_config_mdadm "NIL" || status_failed
  status_done
fi

status_busy_nostep "  Generating ramdisk"
debug "# Generating ramdisk"
generate_new_ramdisk "NIL" || status_failed
status_done

status_busy_nostep "  Generating ntp config"
debug "# Generating ntp config"
generate_ntp_config "NIL" || status_failed
status_done



#
# Cool'n'Quiet
#
#inc_step
#status_busy "Setting CPU frequency scaling to $GOVERNOR"
setup_cpufreq "$GOVERNOR" || {
  debug "=> FAILED"
#  exit 1
}
#status_donefailed $?



#
# Set up misc files
#
inc_step
status_busy "Setting up miscellaneous files"
generate_resolvconf || status_failed
# already done in set_hostname
#generate_hosts "$IPADDR" "$IP6ADDR" || status_failed
generate_sysctlconf || status_failed
status_done


#
# Set root password and/or install ssh keys
#
inc_step
status_none "Configuring authentication"

if [ -n "$OPT_SSHKEYS_URL" ] ; then
    status_busy_nostep "  Fetching SSH keys"
    debug "# Fetch public SSH keys"
    fetch_ssh_keys "$OPT_SSHKEYS_URL"
    status_donefailed $?
fi

if [ "$OPT_USE_SSHKEYS" = "1" -a -z "$FORCE_PASSWORD" ]; then
  status_busy_nostep "  Disabling root password"
  set_rootpassword "$FOLD/hdd/etc/shadow" "*"
  status_donefailed $?
  status_busy_nostep "  Disabling SSH root login without password"
  set_ssh_rootlogin "without-password"
  status_donefailed $?
else
  status_busy_nostep "  Setting root password"
  get_rootpassword "/etc/shadow" || status_failed
  set_rootpassword "$FOLD/hdd/etc/shadow" "$ROOTHASH"
  status_donefailed $?
  status_busy_nostep "  Enabling SSH root login with password"
  set_ssh_rootlogin "yes"
  status_donefailed $?
fi

if [ "$OPT_USE_SSHKEYS" = "1" ] ; then
    status_busy_nostep "  Copying SSH keys"
    debug "# Adding public SSH keys"
    copy_ssh_keys
    status_donefailed $?
fi

#
# Write Bootloader
#
inc_step
status_busy "Installing bootloader $BOOTLOADER"

debug "# Generating config for $BOOTLOADER"
if [ "$BOOTLOADER" = "grub" -o "$BOOTLOADER" = "GRUB" ]; then
  generate_config_grub "$VERSION" || status_failed
else
  generate_config_lilo "$VERSION" || status_failed
fi

debug "# Writing bootloader $BOOTLOADER into MBR"
if [ "$BOOTLOADER" = "grub" -o "$BOOTLOADER" = "GRUB" ]; then
  write_grub "NIL" || status_failed
else
  write_lilo "NIL" || status_failed
fi

status_done

#
# installing optional software (e.g. Plesk)
#

if [ "$OPT_INSTALL" ]; then
  inc_step
  status_none "Installing additional software"
  opt_install_items="$(echo $OPT_INSTALL | sed s/,/\\n/g)"
  for opt_item in $opt_install_items; do
    opt_item=$(echo $opt_item | tr [:upper:] [:lower:])
    case "$opt_item" in
      cpanel)
        status_busy_nostep "  Installing cPanel Control Panel"
        debug "# installing cpanel"
        install_cpanel
        status_donefailed $?
        ;;
      plesk*)
        status_busy_nostep "  Installing PLESK Control Panel"
        debug "# installing PLESK"
        install_plesk "$opt_item"
	status_donefailed $?
        ;;
      omsa)
        status_busy_nostep "  Installing Open Manage"
        debug "# installing OMSA"
        install_omsa
	status_donefailed $?
        ;;
    esac
  done
fi

#
# os specific functions
# details in debian.sh / suse.sh / ubuntu.sh
# for purpose of e.g. debian-sys-maint mysql user password in debian/ubuntu LAMP
#
inc_step
status_busy "Running some $IAM specific functions"
run_os_specific_functions || status_failed
if [[ -e "$FOLD/hdd/password.txt" ]]; then
  chmod 600 "$FOLD/hdd/password.txt"
  install_password_txt_hint || status_failed
  install_remove_password_txt_hint
fi
status_done

#
# Clear log files
#
inc_step
status_busy "Clearing log files"
clear_logs "NIL"
status_donefailed $?

#
# Execute post installation script
#
if has_postinstall_script; then
  status_none_nostep "Executing post installation script"
  execute_postinstall_script
fi

#
# Install robot script for automatic installations
#
if [ "$ROBOTURL" ]; then
  install_robot_report_script || status_failed
fi

#
### report SSH fingerprints to URL where we got the pubkeys from (or not)
if [ -n "$OPT_SSHKEYS_URL" ] ; then
  case $OPT_SSHKEYS_URL in
    https:*|http:*)
      debug "# Reporting SSH fingerprints..."
      curl -s -m 10 -X POST -H "Content-Type: application/json" -d @"$FOLD/ssh_fingerprints" $OPT_SSHKEYS_URL -o /dev/null
    ;;
    *)
      debug "# cannot POST SSH fingerprints to non-HTTP URLs"
   esac
fi

#
# Report install.conf to rz-admin
# Report debug.txt to rz-admin
#
report_id="$(report_config)"
report_debuglog $report_id

#
# Save installimage configuration and debug file on the new system
#
(
  echo "#"
  echo "# $COMPANY - installimage"
  echo "#"
  echo "# This file contains the configuration used to install this"
  echo "# system via installimage script. Comments have been removed."
  echo "#"
  echo "# More information about the installimage script and"
  echo "# automatic installations can be found in our wiki:"
  echo "#"
  echo "# http://wiki.hetzner.de/index.php/Installimage"
  echo "#"
  echo
  cat $FOLD/install.conf | grep -v "^#" | grep -v "^$"
) > $FOLD/hdd/installimage.conf
cat /root/debug.txt > $FOLD/hdd/installimage.debug
chmod 640 $FOLD/hdd/installimage.conf
chmod 640 $FOLD/hdd/installimage.debug

echo
echo_bold "                  INSTALLATION COMPLETE"
echo_bold "   You can now reboot and log in to your new system with"
echo_bold "  the same password as you logged in to the rescue system.\n"

# vim: ai:ts=2:sw=2:et
