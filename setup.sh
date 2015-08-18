#!/bin/bash

#
# mainmenu - choose which image should be installed
#
# originally written by Florian Wicke and David Mayr
# (c) 2007-2015, Hetzner Online GmbH
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


if [ "$OPT_AUTOMODE" ] ; then

  ### automatic mode ------------------------------------------------
  
  debug "# AUTOMATIC MODE: start"

  # create config
  debug "# AUTOMATIC MODE: create config"
  create_config $IMAGENAME ; EXITCODE=$?
  if [ $EXITCODE != 0 ] ; then
    debug "=> FAILED"
    cleanup
    exit 1
  fi
    

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

  # display information about automatic mode
  echo -e "\n\033[01;32mStarting AUTOMATIC MODE\033[00m"
  echo -e "\033[01;33mRunning unattended installimage installation ...\033[00m\n"
  cat $FOLD/install.conf | grep -v "^#" | grep -v "^$"
  echo -e "\n"

  # print warning
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

  # start install
  debug "# AUTOMATIC MODE: start installation"
  . $INSTALLFILE ; EXITCODE=$?
  [ $EXITCODE != 0 ] && debug "=> FAILED"

else

  ### interactive mode ----------------------------------------------

  # start the mainmenu and loop while not chosen "exit" or a config and finished configuration
  ACCEPTED=""
  while [ -z "$ACCEPTED" ]; do

    if [ "$OPT_IMAGE" ] ; then
      # use image from option, do not display image menu
      NOIMAGEMENU=true
    else
      # display the image menu
      IMAGENAME=""
      debug "# starting menu..."
      while [ -z "$IMAGENAME" -o "$IMAGENAME" = "back" ]; do
        dialog --backtitle "$DIATITLE" --title "o/s list" --no-cancel --menu "choose o/s" 0 0 0 $OSMENULIST "exit" "" 2>$FOLD/mainmenu.chosen
        MAINMENUCHOSEN=`cat $FOLD/mainmenu.chosen`
        case $MAINMENUCHOSEN in
          "exit")
            debug "=> user exited from menu"
            cleanup
            exit 1
          ;;
          "custom_image")
            IMAGENAME="custom"
          ;;
          *)
            generate_menu $MAINMENUCHOSEN
          ;;
        esac
      done
    fi

    debug "# chosen image: [ $IMAGENAME ]"
    
    debug "# copy & create config..."
    create_config $IMAGENAME; EXITCODE=$?
    if [ $EXITCODE != 0 ] ; then
      debug "=> FAILED"
      cleanup
      exit 1
    fi

    if [ "$PROXMOX" = "true" ]; then
        graph_notice "\nPlease note: This image isn't supported by us.";
    fi

    text='\n    An editor will now show you the config for the image.\n
    You can edit the parameters for your needs.\n
    To accept all changes and continue the installation\n
    just save and exit the editor with F10.'

    [ $COUNT_DRIVES -gt 1 ] && text=$text'\n\n\Z1  Please note!:  by default all disks are used for software raid\n
  change this to (SWRAID 0) if you want to leave your other harddisk(s)\n  untouched!\Zn'

    dialog --backtitle "$DIATITLE" --title " NOTICE " --colors --msgbox "$text" 14 75
    VALIDATED="false"
    CANCELLED="false"
    while [ "$VALIDATED" = "false" ]; do
      debug "# starting mcedit..."
      whoami $IMAGENAME
      mcedit $FOLD/install.conf; EXITCODE=$?
      [ $EXITCODE != 0 ] && debug "=> FAILED"
      debug "# validating vars..."
      validate_vars "$FOLD/install.conf"; EXITCODE=$?
      if [ $EXITCODE = 0 ]; then
        VALIDATED="true"
      else
        if [ "$CANCELLED" = "true" ]; then
          debug "=> CANCELLED"
          VALIDATED="true"
        else
          debug "=> FAILED"
        fi
      fi
    done

    if [ "$LVM" = "1" ]; then
        graph_notice "Please note that ALL existing LVs and VGs will be removed during the installation!"       
    fi
 


    
    if [ "$CANCELLED" = "false" ]; then 
      debug "# asking for confirmation..."
      for i in $(seq 1 $COUNT_DRIVES) ; do
        ask_format="$(eval echo \$FORMAT_DRIVE$i)"
        ask_drive="$(eval echo \$DRIVE$i)"
        if [ "$SWRAID" = "1" -o "$ask_format" = "1" -o $i -eq 1 ]; then
          dialog --backtitle "$DIATITLE" --title "Confirmation" --colors --yesno "\n\Z1WARNING!: DATA ON THE FOLLOWING DRIVE WILL BE DELETED:\n\n $ask_drive\n\nDo you want to continue?\Zn\n" 0 0
          if [ $? -ne 0 ]; then
            debug "# Confirmation for drive $ask_drive NOT accepted"
            ACCEPTED=""
            [ "$NOIMAGEMENU" ] && exit || break
          else
            debug "# Confirmation for drive $ask_drive accepted"
            ACCEPTED="true"
          fi
        fi
      done
    fi
  done


  debug "# executing installfile..."
  if [ -f $INSTALLFILE -a "$ACCEPTED" = "true" -a "$VALIDATED" = "true" -a "$IMAGENAME" ] ; then
     . $INSTALLFILE ; EXITCODE=$?
  else
    debug "=> FAILED"
    echo -e "\n\033[01;31mERROR: Cant find files\033[00m"
  fi

fi


if [ "$EXITCODE" = "1" ]; then
  cleanup
  exit 1
fi

