#!/bin/bash

#
# set all necessary vars and functions
#
# originally written by Florian Wicke and David Mayr
# (c) 2007-2015, Hetzner Online GmbH
#


DEBUGFILE=/root/debug.txt


# set up standard env
SCRIPTPATH=`dirname $0`
DISABLEDFILE=$SCRIPTPATH"/disabled"
SETUPFILE=$SCRIPTPATH"/setup.sh"
AUTOSETUPFILE=$SCRIPTPATH"/autosetup.sh"
AUTOSETUPCONFIG="/autosetup"
INSTALLFILE=$SCRIPTPATH"/install.sh"
FUNCTIONSFILE=$SCRIPTPATH"/functions.sh"
GETOPTIONSFILE=$SCRIPTPATH"/get_options.sh"
STANDARDCONFIG=$SCRIPTPATH"/standard.conf"
CONFIGSPATH=$SCRIPTPATH"/configs"
POSTINSTALLPATH=$SCRIPTPATH"/post-install"
IMAGESPATH=$SCRIPTPATH"/../images/"
OLDIMAGESPATH=$SCRIPTPATH"/../images.old/"
IMAGESPATHTYPE="local"
IMAGESEXT="tar.gz"
IMAGEFILETYPE="tgz"
HETZNER_PUBKEY=$SCRIPTPATH"/gpg/public-key.asc"

MODULES="virtio_pci virtio_blk via82cxxx sata_via sata_sil sata_nv sd_mod ahci atiixp raid0 raid1 raid5 raid6 raid10 3w-xxxx 3w-9xxx aacraid powernow-k8"
STATSSERVER="rz-admin.hetzner.de"
#STATSSERVER="192.168.100.1"
CURL_OPTIONS="-q -s -S --ftp-create-dirs"
HDDMINSIZE="70000000"

NAMESERVER=("213.133.98.98" "213.133.99.99" "213.133.100.100")
DNSRESOLVER_V6=("2a01:4f8:0:a111::add:9898" "2a01:4f8:0:a102::add:9999" "2a01:4f8:0:a0a1::add:1010")

DEFAULTPARTS="PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 all"
DEFAULTPARTS_BIG="PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 1024G\nPART /home ext4 all"
DEFAULTPARTS_LARGE="PART swap swap SWAPSIZE##G\nPART /boot ext3 512M\nPART / ext4 2015G\nPART /home ext4 all"
DEFAULTPARTS_VSERVER="PART / ext3 all"
DEFAULTSWRAID="1"
DEFAULTTWODRIVESWRAIDLEVEL="1"
DEFAULTTHREEDRIVESWRAIDLEVEL="5"
DEFAULTFOURDRIVESWRAIDLEVEL="6"
DEFAULTLVM="0"
DEFAULTLOADER="grub"
DEFAULTGOVERNOR="powersave"

V6ONLY="0"

# dialog settings
DIATITLE='Hetzner Online GmbH'
OSMENULIST='Debian (official) '
OSMENULIST=$OSMENULIST'Ubuntu (official) '
OSMENULIST=$OSMENULIST'CentOS (official) '
OSMENULIST=$OSMENULIST'openSUSE (official) '
OSMENULIST=$OSMENULIST'Archlinux (!!NO_SUPPORT!!) '
OSMENULIST=$OSMENULIST'Virtualization (!!NO_SUPPORT!!) '
OSMENULIST=$OSMENULIST'old_images (!!NO_SUPPORT!!) '
OSMENULIST=$OSMENULIST'custom_image (blanco_config_for_user_images) '

PROXMOX3_BASE_IMAGE="Debian-78-wheezy-64-minimal"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
MANGENTA="\033[0;35m"
CYAN="\033[1;36m"
GREY="\033[0;37m"
WHITE="\033[1;39m"
NOCOL="\033[00m"

# write log entries in debugfile - single line as second argument
debug() {
  line="$@"
  echo -e "[$(date '+%H:%M:%S')] $line" >> $DEBUGFILE;
}


# write log entries in debugfile - multiple lines at once
debugoutput() {
  while read line ; do
    echo -e "[$(date '+%H:%M:%S')] :   $line" >> $DEBUGFILE;
  done
}

. $FUNCTIONSFILE

