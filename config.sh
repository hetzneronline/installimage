#!/bin/bash

#
# set all necessary vars and functions
#
# (c) 2007-2022, Hetzner Online GmbH
#


DEBUGFILE=/root/debug.txt


# set up standard env
export SCRIPTPATH; SCRIPTPATH=$(dirname "$0")
export DISABLEDFILE="$SCRIPTPATH/disabled"
export SETUPFILE="$SCRIPTPATH/setup.sh"
export AUTOSETUPFILE="$SCRIPTPATH/autosetup.sh"
export AUTOSETUPCONFIG="/autosetup"
export INSTALLFILE="$SCRIPTPATH/install.sh"
export FUNCTIONSFILE="$SCRIPTPATH/functions.sh"
export GETOPTIONSFILE="$SCRIPTPATH/get_options.sh"
export STANDARDCONFIG="$SCRIPTPATH/standard.conf"
export CONFIGSPATH="$SCRIPTPATH/configs"
export POSTINSTALLPATH="$SCRIPTPATH/post-install"
export IMAGESPATH="$SCRIPTPATH/../images/"
export OLDIMAGESPATH="$SCRIPTPATH/../images.old/"
export IMAGESPATHTYPE="local"
export IMAGESEXT="tar.gz"
export IMAGEFILETYPE="tgz"
export COMPANY_PUBKEY="$SCRIPTPATH/gpg/public-key.asc"
export COMPANY_PUBKEYS=(
  "$COMPANY_PUBKEY"
  "$SCRIPTPATH/gpg/public-key-2018.asc"
  "$SCRIPTPATH/gpg/public-key-2023.asc"
)
export COMPANY="Hetzner Online GmbH"
export C_SHORT="hetzner"
export LOCKFILE='/run/lock/installimage'
export SYSTEMD_NSPAWN_TMP_DIR="$FOLD/systemd_nspawn"

export MODULES="virtio_pci virtio_blk via82cxxx sata_via sata_sil sata_nv sd_mod ahci atiixp raid0 raid1 raid5 raid6 raid10 3w-xxxx 3w-9xxx aacraid powernow-k8"
export STATSSERVER4="88.198.31.148"
export STATSSERVER6="[2a01:4f8:0:a0a1::bad:1]"
export HDDMINSIZE="7000000"

export DNSRESOLVER=("185.12.64.1" "185.12.64.2")
export DNSRESOLVER_V6=("2a01:4ff:ff00::add:1" "2a01:4ff:ff00::add:2")
export NTPSERVERS=("ntp1.hetzner.de" "ntp2.hetzner.com" "ntp3.hetzner.net")
export AUTH_DNS1="ns1.first-ns.de"
export AUTH_DNS2="robotns2.second-ns.de"
export AUTH_DNS3="robotns3.second-ns.com"

export DEFAULTPARTS="UEFI##PART swap swap SWAPSIZE##G\nPART /boot ext3 1024M\nPART / ext4 all"
export DEFAULTPARTS_BIG="UEFI##PART swap swap SWAPSIZE##G\nPART /boot ext3 1024M\nPART / ext4 1024G\nPART /home ext4 all"
export DEFAULTPARTS_LARGE="UEFI##PART swap swap SWAPSIZE##G\nPART /boot ext3 1024M\nPART / ext4 2014G\nPART /home ext4 all"
export DEFAULTPARTS_VSERVER="UEFI##PART / ext4 all"
export DEFAULTSWRAID="1"
export DEFAULTTWODRIVESWRAIDLEVEL="1"
export DEFAULTTHREEDRIVESWRAIDLEVEL="5"
export DEFAULTFOURDRIVESWRAIDLEVEL="6"
export DEFAULTLVM="0"
export DEFAULTLOADER="grub"
export DEFAULTGOVERNOR="ondemand"

export UEFI="0"
declare -x -i BTRFS=0

# dialog settings
export DIATITLE="$COMPANY"
export OSMENULIST=(
  "Debian"        "(Official)"
  "Ubuntu"        "(Official)"
  "CentOS"        "(Official)"
  "Arch Linux"    "(Official)"
)
if (($(find "$IMAGESPATH" -type f -iname '*centos*stream*' -printf '.' | wc -c) > 0)); then
  export OSMENULIST+=("CentOS Stream" "(Official)")
fi
if (($(find "$IMAGESPATH" -type f -iname '*alma*' -printf '.' | wc -c) > 0)); then
  export OSMENULIST+=("AlmaLinux"     "(Official)")
fi
if (($(find "$IMAGESPATH" -type f -iname '*rocky*' -printf '.' | wc -c) > 0)); then
 export OSMENULIST+=("Rocky Linux"   "(Official)")
fi
export OSMENULIST+=(
  "Other"         "(!!NO SUPPORT!!)"
  "Old images"    "(!!NO SUPPORT!!)"
  "Custom image"  "(Config for custom images)"
)

export PROXMOX7_BASE_IMAGE="Debian-bullseye-latest-amd64-base"
export PROXMOX8_BASE_IMAGE="Debian-bookworm-latest-amd64-base"

export CPANEL_INSTALLER_SRC=http://mirror.hetzner.com/tools/cpanelinc/cpanel

export PLESK_INSTALLER_SRC=http://mirror.hetzner.com/tools/parallels/plesk
export PLESK_MIRROR=http://mirror.hetzner.com/plesk
export PLESK_STD_VERSION=PLESK_18_0_57
export PLESK_DOWNLOAD_RETRY_COUNT=999
export PLESK_COMPONENTS=(
  awstats
  bind
  config-troubleshooter
  dovecot
  heavy-metal-skin
  horde
  l10n
  mailman
  mod-bw
  mod_fcgid
  mod_python
  mysqlgroup
  nginx
  panel
  php5.6
  phpgroup
  pmm
  postfix
  proftpd
  psa-firewall
  roundcube
  spamassassin
  Troubleshooter
  webalizer
  web-hosting
  webservers
)

export RED="\033[1;31m"
export GREEN="\033[1;32m"
export YELLOW="\033[1;33m"
export BLUE="\033[0;34m"
export MANGENTA="\033[0;35m"
export CYAN="\033[1;36m"
export GREY="\033[0;37m"
export WHITE="\033[1;39m"
export NOCOL="\033[00m"

export ARCHLINUX_DIR="$SCRIPTPATH/../archlinux"
export ARCHLINUX_RELEASE_KEY="$ARCHLINUX_DIR/release-key.pgp"
export ARCHLINUX_BOOTSTRAP="$ARCHLINUX_DIR/archlinux-bootstrap-latest-x86_64.tar.gz"

other_images() {
  find "$IMAGESPATH"/ -maxdepth 1 -type f -name "CoreOS*" -a -not -name "*.sig" -printf '%f\n'
  echo 'Proxmox-Virtualization-Environment-on-Debian-Bookworm'
  echo 'Proxmox-Virtualization-Environment-on-Debian-Bullseye'
  find "$IMAGESPATH/" -maxdepth 1 -type f -iname '*beta*' -a -not -name '*.sig' -printf '%f\n'
}

other_image_warning() {
  echo 'The image you have chosen is in a beta stage and we do not offer any support.'
  echo 'There is no guarantee that the installation will work!'
}

old_image_warning() {
  echo 'The image you have chosen is no longer supported by us as it has reached the end of its life.'
  echo 'Updates and security patches are either no longer available or not applied by us anymore.'
  echo 'There is no guarantee that the installation will work!'
}

# write log entries in debugfile - single line as second argument
debug() {
  local line="${@}"
  #(
  #  flock 200
    printf '[%(%H:%M:%S)T] %s\n' -1 "${line}" >> ${DEBUGFILE}
  #) 200> ${LOCKFILE}
}

# write log entries in debugfile - multiple lines at once
debugoutput() {
  while read -r line; do
    #(
    #  flock 200
      printf '[%(%H:%M:%S)T] :   %s\n' -1 "${line}" >> ${DEBUGFILE}
    #) 200> ${LOCKFILE}
  done
}

. "$FUNCTIONSFILE"

for f in $SCRIPTPATH/*.functions.sh; do
  . $f
done

# vim: ai:ts=2:sw=2:et
