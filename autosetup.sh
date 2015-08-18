#!/bin/bash

#
# skip menu - use "autosetup" file
#
# originally written by Florian Wicke and David Mayr
# (c) 2008-2015, Hetzner Online GmbH
#


# read global variables and functions
. /tmp/install.vars


# check if the script is temporary disabled due some maintenance or something
debug "# checking if the script is disabled"
if [ -f $DISABLEDFILE ]; then
 debug "=> script is DISABLED" 
 echo_red "Due to maintenance the installimage-script is temporarily unavailable.\nWe are sorry for the inconvenience."
 exit 1
fi


# display information about autosetup
echo -e "\n\033[01;32mFound AUTOSETUP file '$AUTOSETUPCONFIG'\033[00m"
echo -e "\033[01;33mRunning unattended installimage installation ...\033[00m\n"
cat $FOLD/install.conf | grep -v "^#" | grep -v "^$"
echo -e "\n"


# validate config
VALIDATED="false"
CANCELLED="false"
while [ "$VALIDATED" = "false" ]; do
 debug "# validating config ..."
 validate_vars "$FOLD/install.conf"; EXITCODE=$?
 if [ "$CANCELLED" = "true" ]; then
   echo "Cancelled."
   exit 1
 fi
 if [ $EXITCODE = 0 ]; then
   VALIDATED="true"
 else
   debug "=> FAILED"
   mcedit $FOLD/install.conf
 fi
done


# if we are using the config file option "-c" and not using the automatic mode,
# ask for confirmation before continuing ...
if [ "$OPT_CONFIGFILE" -a -z "$OPT_AUTOMODE" ] ; then
  echo -en "\n${RED}ALL DATA ON THE GIVEN DISKS WILL BE DESTROYED!\n"
  echo -en "${YELLOW}DO YOU REALLY WANT TO CONTINUE?${NOCOL} [y|N] "
  read -n1 aw
  case "$aw" in
    y|Y|j|J) echo -e "\n\n" ;;
    *) echo -e "\n\n${GREEN}ABORT${NOCOL}\n" ; exit 0 ;;
  esac
fi


# execute installfile
echo -e "\033[01;31mWARNING:"
echo -e "\033[01;33m  Starting installation in 20 seconds ..."
echo -e "\033[01;33m  Press X to continue immediately ...\033[00m"
echo -e "\033[01;31m  Installation will DELETE ALL DATA ON DISK(s)!"
echo -e "\033[01;33m  Press CTRL-C to abort now!\033[00m"
echo -n "  => "
for i in $(seq 1 20) ; do
  echo -n "."
  read -t1 -n1 anykey
  if [ "$anykey" = "x" -o "$anykey" = "X" ] ; then break ; fi
done
echo
#
debug "# executing installfile ..."
if [ -f $INSTALLFILE -a "$VALIDATED" = "true" ] ; then
   . $INSTALLFILE ; EXITCODE=$?
else
  debug "=> FAILED"
  echo -e "\n\033[01;31mERROR: Cant find files\033[00m"
fi


# abort on error
if [ "$EXITCODE" = "1" ]; then
  exit 1
fi

