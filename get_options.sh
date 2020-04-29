#!/bin/bash

# read config
#. /tmp/install.vars
#
# (c) 2009-2018, Hetzner Online GmbH
#



# check command line params / options
while getopts "han:b:r:l:i:p:v:d:f:c:R:s:z:x:gkK:t:u:G:" OPTION ; do
  case $OPTION in

    # help
    h)
      echo
      echo "usage:  installimage [options]"
      echo
      echo "  without any options, installimage starts in interactive mode."
      echo "  possible options are:"
      echo
      echo "  -h                    display this help"
      echo
      echo "  -a                    automatic mode / batch mode - use this in combination"
      echo "                        with the options below to install without further"
      echo "                        interaction. there will be no further confirmations"
      echo "                        for deleting disks / all your data, so use with care!"
      echo
      echo "  -c <configfile>       use the specified config file in"
      echo "                        $CONFIGSPATH for autosetup. when using"
      echo "                        this option, no other options except '-a' are accepted."
      echo
      echo "  -x <post-install>     Use this file as post-install script, that will be executed after"
      echo "                        installation inside the chroot."
      echo
      echo "  -n <hostname>         set the specified hostNAME."
      echo "  -r <yes|no>           activate software RAID or not."
      echo "  -l <0|1|5|6|10>       set the specified raid LEVEL."
      echo "  -i <imagepath>        use the specified IMAGE to install (full path to the OS image)"
      echo "                        - supported image sources: local dir, ftp, http, nfs"
      echo "                        - supported image types: tar,tar.gz,tar.bz,tar.bz2,tar.xz,tgz,tbz,txz"
      echo "                        - supported binary image types: bin,bin.bz2 (CoreOS only)"
      echo "                        examples:"
      echo "                        - local: /path/to/image/filename.tar.gz"
      echo "                        - ftp:   ftp://<user>:<password>@hostname/path/to/image/filename.tar.bz2"
      echo "                        - http:  http://<user>:<password>@hostname/path/to/image/filename.tbz"
      echo "                        - https: https://<user>:<password>@hostname/path/to/image/filename.tbz"
      echo "                        - nfs:   hostname:/path/to/image/filename.tgz"
      echo "  -g                    Use this to force validation of the image file with detached GPG signature."
      echo "                        If the image is not valid, the installation will abort."
      echo "  -p <partitions>       define the PARTITIONS to create, example:"
      echo "                        - regular partitions:  swap:swap:4G,/:ext3:all"
      echo "                        - lvm setup example:   /boot:ext2:256M,lvm:vg0:all"
      echo "  -v <logical volumes>  define the logical VOLUMES you want to be created"
      echo "                        - example: vg0:root:/:ext3:20G,vg0:swap:swap:swap:4G"
      echo "  -d <drives>           list of hardDRIVES to use, e.g.:  sda  or  sda,sdb"
      echo "  -f <yes|no>           FORMAT the second drive (if not used for raid)?"
      echo "  -s <de|en>            Language to use for different things (e.g.PLESK)"
      echo "  -z PLESK_<Version>    Install optional software like PLESK with version <Version>"
      echo "  -K <path/url>         Install SSH-Keys from file/URL"
      echo '  -t <yes|no>           Take over rescue system SSH public keys'
      echo '  -u <yes|no>           Allow usb drives'
      echo '  -G <yes|no>           Generate new SSH host keys (default: yes)'
      echo
      exit 0
    ;;

    # config file  (file.name)
    c)
      if [ -e "$CONFIGSPATH/$OPTARG" ] ; then
        OPT_CONFIGFILE=$CONFIGSPATH/$OPTARG
      elif [ -e "$OPTARG" ] ; then
        OPT_CONFIGFILE=$OPTARG
      else
        msg="=> FAILED: config file $OPT_CONFIGFILE for autosetup not found"
        debug "$msg"
        echo -e "${RED}$msg${NOCOL}"
        exit 1
      fi
      debug "# use config file $OPT_CONFIGFILE for autosetup"
      echo "$OPT_CONFIGFILE" | grep "^/" >/dev/null || OPT_CONFIGFILE="$(pwd)/$OPT_CONFIGFILE"
      cp "$OPT_CONFIGFILE" /autosetup
      if grep -q PASSWD /autosetup ; then
        echo -e "\n\n${RED}Please enter the PASSWORD for $OPT_CONFIGFILE:${NOCOL}"
        echo -e "${YELLOW}(or edit /autosetup manually and run installimage without params)${NOCOL}\n"
        echo -en "PASSWORD:  "
        read -s imagepasswd
        sed -i /autosetup -e "s/PASSWD/$imagepasswd/"
      fi
    ;;

    # post-install file  (file.name)
    x)
      if [ -e "$POSTINSTALLPATH/$OPTARG" ] ; then
        OPT_POSTINSTALLFILE=$POSTINSTALLPATH/$OPTARG
      elif [ -e "$OPTARG" ] ; then
        OPT_POSTINSTALLFILE=$OPTARG
      else
        msg="=> FAILED: post-install file $OPT_POSTINSTALLFILE not found or not executable"
        debug "$msg"
        echo -e "${RED}$msg${NOCOL}"
        exit 1
      fi
      debug "# use post-install file $OPT_POSTINSTALLFILE"
      echo "$OPT_POSTINSTALLFILE" | grep "^/" >/dev/null || OPT_POSTINSTALLFILE="$(pwd)/$OPT_POSTINSTALLFILE"
      ln -sf "$OPT_POSTINSTALLFILE" /post-install
    ;;

    # automatic mode
    a) OPT_AUTOMODE=1 ;;

    # hostname  (host.domain.tld)
    n)
      OPT_HOSTNAME=$OPTARG
      if [ -e /autosetup ]; then
	sed -i /autosetup -e "s/HOSTNAME.*/HOSTNAME $OPT_HOSTNAME/"
      fi
    ;;

    # raid  (on|off|true|false|yes|no|0|1)
    r)
      case $OPTARG in
        off|false|no|0) OPT_SWRAID=0 ;;
        on|true|yes|1)  OPT_SWRAID=1 ;;
      esac
    ;;

    # raidlevel  (0|1)
    l) OPT_SWRAIDLEVEL=$OPTARG ;;

    # image
    # e.g.: file.tar.gz | http://domain.tld/file.tar.gz
    i)
      [ -f "$IMAGESPATH/$OPTARG" ] && OPT_IMAGE="$IMAGESPATH/$OPTARG" || OPT_IMAGE="$OPTARG"
      IMAGENAME=$(basename "$OPT_IMAGE")
      IMAGENAME=${IMAGENAME/.tar.gz/}
      IMAGENAME=${IMAGENAME/.tar.bz/}
      IMAGENAME=${IMAGENAME/.tar.bz2/}
      IMAGENAME=${IMAGENAME/.tar.xz/}
      IMAGENAME=${IMAGENAME/.tar/}
      IMAGENAME=${IMAGENAME/.tgz/}
      IMAGENAME=${IMAGENAME/.tbz/}
      IMAGENAME=${IMAGENAME/.txz/}
      IMAGENAME=${IMAGENAME/.bin.bz2/}
      IMAGENAME=${IMAGENAME/.bin/}
      if [[ "$IMAGENAME" == 'Archlinux-2017-64-minimal' ]] && ! [[ -s "$OPT_IMAGE" ]]; then
        IMAGENAME='archlinux-latest-64-minimal'
        OPT_IMAGE="$IMAGESPATH$IMAGENAME.tar.gz"
      fi
      if [[ "$IMAGENAME" == 'Archlinux-latest-64-minimal' ]] && ! [[ -s "$OPT_IMAGE" ]]; then
        IMAGENAME='archlinux-latest-64-minimal'
        OPT_IMAGE="$IMAGESPATH$IMAGENAME.tar.gz"
      fi
    ;;

    # partitions
    # e.g.: swap:swap:4G,/boot:ext2:256M,/:ext3:all | /boot:ext2:256M,lvm:vg0:all
    p)
      OPT_PARTITIONS=$OPTARG
      OPT_PARTS=''
      OLD_IFS="$IFS"
      IFS=","
      for part in $OPT_PARTITIONS ; do
        OPT_PARTS="$OPT_PARTS\nPART "
        IFS=":"
        for val in $part ; do
          OPT_PARTS="$OPT_PARTS $val "
        done
      done
      IFS="$OLD_IFS"
    ;;

    # logical volumes
    # e.g.: vg0:swap:swap:swap:4G,vg0:root:/:ext3:20G,vg0:tmp:/tmp:ext3:5G
    v)
      OPT_VOLUMES=$OPTARG
      OPT_LVS=''
      OLD_IFS="$IFS"
      IFS=","
      for lv in $OPT_VOLUMES ; do
        OPT_LVS="$OPT_LVS\nLV "
        IFS=":"
        for val in $lv ; do
          OPT_LVS="$OPT_LVS $val "
        done
      done
      IFS="$OLD_IFS"
    ;;

    # drives
    # e.g.: sda,sdb | sda
    d)
      OPT_DRIVES=$OPTARG
      sel_drives="${OPT_DRIVES//,/ }"
      i=1
      for optdrive in $sel_drives ; do
        eval OPT_DRIVE$i="$optdrive"
        let i=i+1
      done
    ;;

    # format second drive  (on|off|true|false|yes|no|0|1)
    f)
      case $OPTARG in
        off|false|no|0) export OPT_FORMATDRIVE2=0 ;;
        on|true|yes|1)  export OPT_FORMATDRIVE2=1 ;;
      esac
    ;;
	s)
	  export OPT_LANGUAGE="$OPTARG"
	  ;;
	z)
	  export OPT_INSTALL="$OPTARG"
	  ;;
    # URL to open after first boot of the new system. Used by the
    # Robot for automatic installations.
    R)
      export ROBOTURL="$OPTARG"
      ;;

    # force signature validating of the image file
    g)
     export OPT_FORCE_SIGN="1"
     ;;
    K)
     if [ "$OPTARG" ]; then
       export OPT_SSHKEYS_URL="$OPTARG"
       export OPT_USE_SSHKEYS="1"
     else
       msg="=> FAILED: cannot install ssh-keys without a source"
       debug "$msg"
       echo -e "${RED}$msg${NOCOL}"
       exit 1
     fi
     ;;
    t)
      if [[ -z "$OPTARG" ]] || [[ "${OPTARG,,}" == 'yes' ]]; then
        export OPT_TAKE_OVER_RESCUE_SYSTEM_SSH_PUBLIC_KEYS='yes'
      else
        export OPT_TAKE_OVER_RESCUE_SYSTEM_SSH_PUBLIC_KEYS='no'
      fi
    ;;
    u)
      [[ -z "$OPTARG" ]] || [[ "${OPTARG,,}" == 'yes' ]] && export ALLOW_USB_DRIVES='1'
    ;;
    G)
      if [[ -n "$OPTARG" ]]; then
        if [[ "${OPTARG,,}" == 'no' ]]; then
          export GENERATE_NEW_SSH_HOST_KEYS=no
        else
          export GENERATE_NEW_SSH_HOST_KEYS=yes
        fi
      fi
    ;;
  esac
done


# VALIDATION
if [ "$OPT_AUTOMODE" -a -z "$OPT_IMAGE" -a -z "$OPT_CONFIGFILE" ] ; then
  echo -e "\n${RED}ERROR: in automatic mode you need to specify an image and a config file!${NOCOL}\n"
  debug "=> FAILED, no image given"
  exit 1
fi

if [ "$OPT_USE_SSHKEYS" -a -z "$OPT_SSHKEYS_URL" ]; then
  msg="=> FAILED: Should install SSH keys, but key URL not set."
  debug "$msg"
  echo -e "${RED}$msg${NOCOL}"
  exit 1
fi

# DEBUG:
[ "$OPT_CONFIGFILE" ]   && debug "# OPT_CONFIGFILE:   $OPT_CONFIGFILE"
[ "$OPT_HOSTNAME" ]     && debug "# OPT_HOSTNAME:     $OPT_HOSTNAME"
[ "$OPT_SWRAID" ]       && debug "# OPT_SWRAID:       $OPT_SWRAID"
[ "$OPT_SWRAIDLEVEL" ]  && debug "# OPT_SWRAIDLEVEL:  $OPT_SWRAIDLEVEL"
[ "$OPT_IMAGE" ]        && debug "# OPT_IMAGE:        $OPT_IMAGE"
[ "$OPT_PARTITIONS" ]   && debug "# OPT_PARTITIONS:   $OPT_PARTITIONS"
[ "$OPT_VOLUMES" ]      && debug "# OPT_VOLUMES:      $OPT_VOLUMES"
[ "$OPT_DRIVES" ]       && debug "# OPT_DRIVES:       $OPT_DRIVES"
[ "$OPT_FORMATDRIVE2" ] && debug "# OPT_FORMATDRIVE2: $OPT_FORMATDRIVE2"
[ "$OPT_INSTALL" ]      && debug "# OPT_INSTALL:      $OPT_INSTALL"
[ "$OPT_FORCE_SIGN" ]   && debug "# OPT_FORCE_SIGN:   $OPT_FORCE_SIGN"
[ "$OPT_USE_SSHKEYS" ]  && debug "# OPT_USE_SSHKEYS:  $OPT_USE_SSHKEYS"
[ "$OPT_SSHKEYS_URL" ]  && debug "# OPT_SSHKEYS_URL:  $OPT_SSHKEYS_URL"
[ "$OPT_TAKE_OVER_RESCUE_SYSTEM_SSH_PUBLIC_KEYS" ] && debug "# OPT_TAKE_OVER_RESCUE_SYSTEM_SSH_PUBLIC_KEYS: $OPT_TAKE_OVER_RESCUE_SYSTEM_SSH_PUBLIC_KEYS"

# vim: ai:ts=2:sw=2:et
