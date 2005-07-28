#!/bin/bash
#
#  ALSA Configurator
#
#  Copyright (c) 1999-2002  SuSE GmbH
#                           Jan ONDREJ
#
#  written by Takashi Iwai <tiwai@suse.de>
#             Bernd Kaindl <bk@suse.de>
#             Jan ONDREJ (SAL) <ondrejj@salstar.sk>
#
#  based on the original version of Jan ONDREJ's alsaconf for ALSA 0.4.
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#

export TEXTDOMAIN=alsaconf

prefix=/usr
exec_prefix=${prefix}
bindir=${exec_prefix}/bin
sbindir=${exec_prefix}/sbin
version=1.0.9a
USE_NLS=yes

# i18n stuff
if test "$USE_NLS" = "yes" && which gettext > /dev/null; then
  xecho() {
    gettext -s "$*"
  }
else
  xecho() {
    echo "$*"
  }
  gettext() {
    echo -n "$*"
  }
fi
xmsg() {
  msg=$(gettext "$1")
  shift
  printf "$msg" $*
}

# Check for GNU/Linux distributions
if [ -f /etc/SuSE-release -o -f /etc/UnitedLinux-release ]; then
  distribution="suse"
elif [ -f /etc/gentoo-release ]; then
  distribution="gentoo"
elif [ -f /etc/debian_version ]; then
  distribution="debian"
elif [ -f /etc/mandrake-release ]; then
  distribution="mandrake"
elif test -f /etc/redhat-release && grep -q "Red Hat" /etc/redhat-release; then
  distribution="redhat"
elif test -f /etc/fedora-release && grep -q "Fedora" /etc/fedora-release; then
  distribution="fedora"
else
  distribution="unknown"
fi

if false; then
for prog in lspci lsmod; do
	for path in /sbin /usr/sbin /bin /usr/bin;do
		[[ -x $path/$prog ]] && eval $prog=$path/$prog
	done
done
unset prog path
else
# debian patch
lspci=lspci
lsmod=lsmod
fi

usage() {
    xecho "ALSA configurator"
    echo "  version $version"
    xecho "usage: alsaconf [options]
  -l|--legacy    check only legacy non-isapnp cards
  -s|--sound wav-file
                 use the specified wav file as a test sound
  -u|--uid uid   set the uid for the ALSA devices (default = 0) [obsoleted]
  -g|--gid gid   set the gid for the ALSA devices (default = 0) [obsoleted]
  -d|--devmode mode
                 set the permission for ALSA devices (default = 0666) [obs.]
  -r|--strict    set strict device mode (equiv. with -g 17 -d 0660) [obsoleted]
  -L|--log file  logging on the specified file (for debugging purpose only)
  -p|--probe card-name
                 probe a legacy non-isapnp card and print module options
  -P|--listprobe list the supported legacy card modules
  -c|--config file
                 specify the module config file
  -U|--safe-unattented
                 install without asking questions and don't do legacy!
  -h|--help      what you're reading"
}

OPTS=`getopt -o UlmL:hp:Pu:g:d:rs:c: --long safe-unattended,legacy,modinfo,log:,help,probe:,listprobe,uid:,gid:,devmode:,strict,sound:,config: -n alsaconf -- "$@"` || exit 1
eval set -- "$OPTS"

do_legacy_only=0
use_modinfo_db=0
alsa_uid=0
alsa_gid=29
alsa_mode=0660
legacy_probe_card=""
LOGFILE=""
TESTSOUND="/usr/share/sounds/alsa/test.wav"
try_all_combination=0
INTERACTIVE="y";

# legacy support
LEGACY_CARDS="opl3sa2 cs4236 cs4232 cs4231 es18xx es1688 sb16 sb8"

while true ; do
    case "$1" in
    -l|--legacy)
	do_legacy_only=1; shift ;;
# In Debian the tool always operates in modinfo mode
#    -m|--modinfo)
#	use_modinfo_db=1; shift ;;
    -s|--sound)
	TESTSOUND=$2; shift 2;;
    -h|--help)
	usage; exit 0 ;;
    -L|--log)
	LOGFILE="$2"; shift 2;;
    -p|--probe)
	legacy_probe_card="$2"; shift 2;;
    -P|--listprobe)
	echo "$LEGACY_CARDS"; exit 0;;
    -u|--uid)
	alsa_uid="$2"; shift 2;;
    -g|--gid)
	alsa_gid="$2"; shift 2;;
    -d|--devmode)
	alsa_mode="$2"; shift 2;;
    -r|--strict)
	alsa_uid=0; alsa_gid=17; alsa_mode=0660; shift;;
    -c|--config)
	cfgfile="$2"; shift 2;;
    -U|--safe-unattended)
        INTERACTIVE="n"; SAFE_UNATTENDED="y"; shift;;
    --) shift ; break ;;
    *) usage ; exit 1 ;;
    esac
done

# Check for root privileges
if [ `id -u` -ne 0 ]; then
  xecho "You must be root to use this script."
  exit 1
fi

#
# check the snd_ prefix for ALSA module options
# snd_ prefix is obsoleted since 0.9.0rc4.
#
if /sbin/modinfo -p snd | grep -q snd_ ; then
  mpfx="snd_"
else
  mpfx=""
fi

alsa_device_opts=""
if /sbin/modinfo -p snd | grep -q uid ; then
  if [ x"$alsa_uid" != x0 ]; then
    alsa_device_opts="$alsa_device_opts ${mpfx}device_uid=$alsa_uid"
  fi
  if [ x"$alsa_gid" != x0 ]; then
    alsa_device_opts="$alsa_device_opts ${mpfx}device_gid=$alsa_gid"
  fi
fi
if /sbin/modinfo -p snd | grep -q device_mode ; then
  if [ x"$alsa_mode" != x0 ]; then
    alsa_device_opts="$alsa_device_opts ${mpfx}device_mode=$alsa_mode"
  fi
fi

case `uname -r` in
2.6.*)
  kernel="new"
  ;;
*)
  kernel="old"
  ;;
esac

# cfgfile = base config file to remove/update the sound setting
# cfgout = new config file to write the sound setting (if different from $cfgfile)
if [ -n "$cfgfile" ]; then
  if [ ! -r "$cfgfile" ]; then
    xecho "ERROR: The config file doesn't exist: "
    echo $cfgfile
    exit 1
  fi
else
if [ "$distribution" = "gentoo" ]; then
  cfgfile="/etc/modules.d/alsa"
elif [ "$kernel" = "new" ]; then
  if [ -d /etc/modprobe.d ]; then
    cfgout="/etc/modprobe.d/sound"
  fi
  cfgfile="/etc/modprobe.conf"
elif [ "$distribution" = "debian" ]; then
  cfgfile="/etc/modutils/sound"
elif [ -e /etc/modules.conf ]; then
  cfgfile="/etc/modules.conf"
elif [ -e /etc/conf.modules ]; then
  cfgfile="/etc/conf.modules"
else
  cfgfile="/etc/modules.conf"
  touch /etc/modules.conf
fi
fi

if [ "$INTERACTIVE" == "n" ]; then
	    unattended_wrapper() {
	      #echo $1 $2 $3 $4 $5 $6 $7 $8
	      X1="$1"
	      X2="$2"
	      X3=$3
	      if [ $1 = --title ]; then
	       
	        if [ $2 = "WARNING" ]; then
			# --title "WARNING" is for legacy ISA - put "NO!!!"
			echo $4 - NO
			return 1
	        elif [ $3 = --menu ]; then
			return $8
		fi
	      elif [ $1 = --yesno ]; then
		echo $2 - YES
	        # assume yes for everything else
	        return 0
	      elif [ $1 = --gauge ]; then
	        echo whiptail...
		shift 3
	        whiptail "$X1" "$X2" $X3 "$@"
	      else
	        # dunno yet
	        return 0
	      fi
	    }
	    DIALOG=unattended_wrapper

else
# Check for dialog, whiptail, gdialog, awk, ... ?
if which dialog > /dev/null; then
    DIALOG=dialog
else
  if which whiptail > /dev/null; then
    whiptail_wrapper() {
      X1="$1"
      X2="$2"
      if [ $1 = --yesno ]; then
        X3=`expr $3 + 2`
      else
        X3=$3
      fi
      shift 3
      whiptail "$X1" "$X2" $X3 "$@"
    }
    DIALOG=whiptail_wrapper
  else
    xecho "Error, dialog or whiptail not found."
    exit 1
  fi
fi
fi

if which awk > /dev/null; then :
else
  xecho "Error, awk not found. Can't continue."
  exit 1
fi

#
# remove entries by yast2 sound configurator
#
remove_y2_block() {
    awk '
    /^alias sound-slot-[0-9]/ { next }
    /^alias char-major-116 / { next }
    /^alias char-major-14 / { next }
    /^alias snd-card-[0-9] / { next }
    /^options snd / { next }
    /^options snd-/ { next }
    /^options off / { next }
    /^alias sound-service-[0-9]/ { next }
    /^# YaST2: sound / { next }
   { print }'
}

#
# remove entries by sndconfig sound configurator
#
# found strings to search for in WriteConfModules, 
# from sndconfig 0.68-4 (rawhide version)

remove_sndconfig_block() {
    awk '
    /^alias sound-slot-0/ { modulename = $3 ; next }
    /^alias sound-slot-[0-9]/ { next }
    /^post-install sound-slot-[0-9] / { next }
    /^pre-remove sound-slot-[0-9] / { next }
    /^options sound / { next }
    /^alias synth0 opl3/ { next }
    /^options opl3 / { next }
    /^alias midi / { mididev = $3 ; next }
    /^options / { if ($2 == mididev) next }
    /^pre-install / { if ($2 == mididev) next }
    /^alias synth0 / { synth = $3 ; next }
    /^post-install / { if ($2 == synth) next }
    /^options sb / { next }
    /^post-install .+ \/bin\/modprobe "aci"/ { if ($2 == modulename) next }
    /^options adlib_card / { next }
    /^options .+ isapnp=1/ { if ($2 == modulename) next }
    /^options i810_audio / { next }
    /^options / {if ($2 == modulename) next }
   { print }'
}

#
# remove the previous configuration by alsaconf
#
remove_ac_block() {
    awk '/^'"$ACB"'$/,/^'"$ACE"'$/ { next } { print }'
}

#
# set default mixer volumes
#
mixer() {
  amixer set "$1" "$2" unmute >/dev/null 2>&1
  amixer set "$1" unmute >/dev/null 2>&1
}

set_mixers() {
    mixer Master 75%
    mixer Front 75%
    mixer PCM 90%
    mixer Synth 90%
    mixer CD 90%
    # mute mic
    amixer set Mic 0% mute >/dev/null 2>&1
    # ESS 1969 chipset has 2 PCM channels
    mixer PCM,1 90%
    # Trident/YMFPCI/emu10k1
    mixer Wave 100%
    mixer Music 100%
    mixer AC97 100%
    # CS4237B chipset:
    mixer 'Master Digital' 75%
    # Envy24 chips with analog outs
    mixer DAC 90%
    mixer DAC,0 90%
    mixer DAC,1 90%
    # some notebooks use headphone instead of master
    mixer Headphone 75%
    mixer Playback 100%
    # turn off digital switches
    amixer set "SB Live Analog/Digital Output Jack" off >/dev/null 2>&1
    amixer set "Audigy Analog/Digital Output Jack" off >/dev/null 2>&1
}


# INTRO
intro() {
  local msg=$(xmsg "
                   ALSA  CONFIGURATOR
                   version %s

            This script is a configurator for
    Advanced Linux Sound Architecture (ALSA) driver.


  You should stop all sound applications now." $version)
  $DIALOG --msgbox "$msg" 20 63 || acex 0
}

# FAREWELL
farewell() {
  local msg=$(gettext "

     OK, sound driver is configured.

                  ALSA  CONFIGURATOR

          will prepare the card for playing now.

     Now I will load the ALSA sound driver and use
     amixer to raise the default volumes.
     You can change the volume later via a mixer
     program such as alsamixer or gamix.
  
  ")
  $DIALOG --msgbox "$msg" 17 60 || acex 0
}

clear() {
    echo
}

# Exit function
acex() {
  cleanup
  if [ "$1" = 0 ] ; then
      clear
  else
      # Don't clear error messages
      echo
  fi
  exit $1
}

#
# search for alsasound init script
#

if [ "$distribution" = "debian" ]; then
    rcalsasound=/etc/init.d/alsa
elif [ -x /etc/init.d/alsasound ]; then
    rcalsasound=/etc/init.d/alsasound
elif [ -x /usr/sbin/rcalsasound ]; then
    rcalsasound=/usr/sbin/rcalsasound
elif [ -x /sbin/rcalsasound ]; then
    rcalsasound=/sbin/rcalsasound
elif [ -x /etc/rc.d/init.d/alsasound ]; then
    rcalsasound=/etc/rc.d/init.d/alsasound
elif [ -x /etc/init.d/alsa ]; then
    rcalsasound=/etc/init.d/alsa
else
    rcalsasound=rcalsasound
fi

cleanup () {
    killall -9 aplay arecord >/dev/null 2>&1
    /sbin/modprobe -r isapnp >/dev/null 2>&1
    /sbin/modprobe -r isa-pnp >/dev/null 2>&1
    rm -f "$CARDID_DB" "$TMP" "$addcfg" "$FOUND" "$DUMP"
}
trap cleanup 0 

CARDID_DB=`mktemp -q /tmp/alsaconf.cards.XXXXXX`
if [ $? -ne 0 ]; then
	xecho "Can't create temp file, exiting..."
        exit 1
fi
TMP=`mktemp -q /tmp/alsaconf.XXXXXX`
if [ $? -ne 0 ]; then
	xecho "Can't create temp file, exiting..."
        exit 1
fi
addcfg=`mktemp -q /tmp/alsaconf.XXXXXX`
if [ $? -ne 0 ]; then
	xecho "Can't create temp file, exiting..."
        exit 1
fi
FOUND=`mktemp -q /tmp/alsaconf.XXXXXX`
if [ $? -ne 0 ]; then
	xecho "Can't create temp file, exiting..."
        exit 1
fi
DUMP=`mktemp -q /tmp/alsaconf.XXXXXX`
if [ $? -ne 0 ]; then
	xecho "Can't create temp file, exiting..."
        exit 1
fi

# convert ISA PnP id number to string 'ABC'
convert_isapnp_id () {
    if [ -z "$1" ]; then
	echo "XXXX"
	return
    fi
    let a='('$1'>>2) & 0x3f'
    let b='(('$1' & 0x03) << 3) | (('$1' >> 13) & 0x07)'
    let c='('$1'>> 8) & 0x1f'
    strs='@ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    echo ${strs:$a:1}${strs:$b:1}${strs:$c:1}
}

# swap high & low bytes
swap_number () {
    if [ -z "$1" ]; then
	echo "0000"
	return
    fi
    let v='(('$1'>>8)&0xff)|(('$1'&0xff)<<8)'
    printf "%04x" $v
}

# build card database
# build_card_db filename
build_card_db () {
    MODDIR=/lib/modules/`uname -r`
    last_driver=""
    echo -n > $1

    # list pci cards
    while read driver vendor device dummy; do
	if expr $driver : 'snd-.*' >/dev/null ; then
	    if [ "$last_driver" != "$driver" ]; then
		echo $driver.o
		last_driver=$driver
	    fi
	    id1=`printf '0x%04x' $vendor`
	    id2=`printf '0x%04x' $device`
	    echo "PCI: $id1=$id2"
	fi
    done < $MODDIR/modules.pcimap >> $1

    # list isapnp cards
    while read driver cardvendor carddevice data vendor func; do
	if expr $driver : 'snd-.*' >/dev/null ; then
	    if [ "$last_driver" != "$driver" ]; then
		echo $driver.o
		last_driver=$driver
	    fi
	    id1=`convert_isapnp_id $cardvendor`
	    dev1=`swap_number $carddevice`
	    id2=`convert_isapnp_id $vendor`
	    dev2=`swap_number $func`
	    echo "ISAPNP: $id1$dev1=$id2$dev2"
	fi
    done < $MODDIR/modules.isapnpmap >> $1
}

#
# probe cards
#
probe_cards () {
    test -r /proc/isapnp || /sbin/modprobe isapnp >/dev/null 2>&1
    test -r /proc/isapnp || /sbin/modprobe isa-pnp >/dev/null 2>&1
    if [ -r /proc/isapnp ]; then
	cat /proc/isapnp >"$DUMP"
    elif [ -d /sys/bus/pnp/devices/00:01.00 ]; then
	# use 2.6 kernel's sysfs output
	# fake the isapnp dump
	# unfortunately, there is no card name information!
	( cd /sys/bus/pnp/devices
	  for i in *:*.00; do
	    id=`cat $i/id`
	    echo "Card 0 '$id:ISAPnP $id' " >> "$DUMP"
	  done
	)
    else
	echo -n >"$DUMP"
    fi
if true; then
    # Debian code
    # CARDID_DB was set earlier
    xecho "Building card database..."
    build_card_db $CARDID_DB
    if [ ! -e $CARDID_DB ]; then
	xecho "No card database. Aborting."
	exit 1
    fi
else
    CARDID_DB=/var/tmp/alsaconf.cards
    if [ ! -r $CARDID_DB ]; then
        use_modinfo_db=1
    fi
    if [ $use_modinfo_db != 1 ]; then
	if [ $CARDID_DB -ot /lib/modules/`uname -r`/modules.dep ]; then
	    use_modinfo_db=1
	fi
    fi
    if [ $use_modinfo_db = 1 ]; then
	xecho "Building card database.."
	build_card_db $CARDID_DB
    fi
    if [ ! -r $CARDID_DB ]; then
	xecho "No card database is found.."
	exit 1
    fi
fi
    ncards=`grep '^snd-.*\.o$' $CARDID_DB | wc -w`

    msg=$(gettext "Searching sound cards")
    awk '
BEGIN {
	format="%-40s %s\n";
	ncards='"$ncards"';
	idx=0;
}
/^snd-.*\.o$/{
	sub(/.o$/, "");
	driver=$0;
	perc=(idx * 100) / (ncards + 1);
	print int(perc);
	idx++;
}
/^[<literal space><literal tab>]*PCI: /{
	gsub(/0x/, "");
	gsub(/=/, ":");
	x = sprintf ("'$lspci' -n 2>/dev/null| grep '"' 040.: '"' | grep %s", $2);
	if (system (x) == 0)
		printf "%s %s\n", $2, driver >>"'"$FOUND"'"
}
/^[<literal space><literal tab>]*ISAPNP: /{
	gsub(/=.*/, "");
	x = sprintf ("grep '\''^Card [0-9] .%s:'\'' '"$DUMP"'", $2);
	if (system (x) == 0)
		printf "%s %s\n", $2, driver >>"'"$FOUND"'"
}' < $CARDID_DB |\
    $DIALOG --gauge "$msg" 6 40 0

    #
    # PowerMac
    #
    if grep -q MacRISC /proc/cpuinfo; then
	/sbin/modprobe -a -l | grep 'snd-powermac' | \
	while read i; do
	    i=${i##*/}
	    i=${i%%.o}
	    i=${i%%.ko}
	    echo "PowerMac $i" >> $FOUND
	done
    fi
}

#
# look for a descriptive device name from the given device id
#
find_device_name () {
    if expr "$1" : '[0-9a-f][0-9a-f][0-9a-f][0-9a-f]:[0-9a-f][0-9a-f][0-9a-f][0-9a-f]' >/dev/null; then
	$lspci -d $1 2>/dev/null| sed -e 's/^.*:..\.. Multimedia audio controller: //g'
	return
    elif expr "$1" : '[A-Z@][A-Z@][A-Z@][0-9a-f][0-9a-f][0-9a-f][0-9a-f]' >/dev/null; then
	cardname=`grep '^Card [0-9]\+ .'$1':' $DUMP | head -n 1 | sed -e 's/^Card [0-9]\+ '\''.*:\(.*\)'\'' .*$/\1/'`
	echo $cardname
    else
	echo $1
    fi
}

#
# configure and try test sound
#
ac_config_card () {

    CARD_DRIVER=snd-$1
    CARD_OPTS="${*:2}"

    if [ -n "$cfgout" ]; then
	msg=$(xmsg "
Configuring %s
Do you want to modify %s (and %s if present)?" $CARD_DRIVER $cfgout $cfgfile)
        $DIALOG --yesno "$msg" 8 50 || acex 0
    else
	msg=$(xmsg "
Configuring %s
Do you want to modify %s?" $CARD_DRIVER $cfgfile)
        $DIALOG --yesno "$msg" 8 50 || acex 0
    fi
    clear

    # Copy conf.modules and make changes.
    ACB="# --- BEGIN: Generated by ALSACONF, do not edit. ---"
    ACE="# --- END: Generated by ALSACONF, do not edit. ---"

    # Detect 2.2.X kernel
    KVER=`uname -r | tr ".-" "  "`
    KVER1=`echo $KVER | cut -d" " -f1`
    KVER2=`echo $KVER | cut -d" " -f2`
    if [ $KVER1 -ge 2 ] && [ $KVER2 -ge 2 ]; then
	SOUND_CORE="soundcore"
    else
	SOUND_CORE="snd"
    fi

    if [ -r $cfgfile ] ; then
        if [ "$distribution" = "redhat" -o "$distribution" = "fedora" ] ; then
            remove_ac_block < $cfgfile | remove_sndconfig_block | uniq > $TMP
        else
	    remove_ac_block < $cfgfile | remove_y2_block | uniq > $TMP
        fi
    fi

    if [ -z "$have_alias" -a "$kernel" = "new" ]; then
	if grep -q char-major-116 /lib/modules/`uname -r`/modules.alias; then
	    have_alias="yes"
	fi
    fi
if false ; then
    if [ -z "$have_alias" ]; then
echo "alias char-major-116 snd
alias char-major-14 $SOUND_CORE
alias sound-service-0-0 snd-mixer-oss
alias sound-service-0-1 snd-seq-oss
alias sound-service-0-3 snd-pcm-oss
alias sound-service-0-8 snd-seq-oss
alias sound-service-0-12 snd-pcm-oss" >> $addcfg
    fi
    if [ -n "$alsa_device_opts" ]; then
	echo "options snd $alsa_device_opts" >> $addcfg
    fi
echo "alias snd-card-0 $CARD_DRIVER
alias sound-slot-0 $CARD_DRIVER" >> $addcfg
    if [ -n "$CARD_OPTS" ]; then
	echo "options $CARD_DRIVER $CARD_OPTS" >> $addcfg
    fi
else
    # For Debian
    echo "alias snd-card-0 $CARD_DRIVER
options $CARD_DRIVER index=0${CARD_OPTS:+ $CARD_OPTS}" >> $addcfg
fi

    if [ -n "$cfgout" ]; then
	[ ! -r "$cfgfile" ] || cmp -s "$TMP" "$cfgfile" || cat "$TMP" > "$cfgfile"
if false ; then
	cmp -s "$addcfg" "$cfgout" || cat "$addcfg" > "$cfgout"
else
	# For Debian
	if [ "$kernel" = old ] ; then
		if [ -f /etc/modutils/alsa-base ] ; then
			# Don't duplicate any lines already in /etc/modutils/alsa-base
			grep -Fv -f /etc/modutils/alsa-base "$addcfg" > "$TMP"
		else
			cat "$addcfg" > "$TMP"
		fi
	else
		if [ -f /etc/modprobe.d/alsa-base ] ; then
			# Don't duplicate any lines already in /etc/modprobe.d/alsa-base
			grep -Fv -f /etc/modprobe.d/alsa-base "$addcfg" > "$TMP"
		else
			cat "$addcfg" > "$TMP"
		fi
	fi
	cmp -s "$TMP" "$cfgout" || cat "$TMP" > "$cfgout"
fi
    else
if false ; then
	echo "$ACB
# --- ALSACONF version $version ---" >> $TMP
        cat "$addcfg" >> "$TMP"
	echo "$ACE
" >> $TMP
else
	# For Debian
	if [ "$kernel" = old ] ; then
		if [ -f /etc/modutils/alsa-base ] ; then
			# Don't duplicate any lines already in /etc/modutils/alsa-base
			grep -Fv -f /etc/modutils/alsa-base "$addcfg" >> "$TMP"
		else
			cat "$addcfg" >> "$TMP"
		fi
	else
		if [ -f /etc/modprobe.d/alsa-base ] ; then
			# Don't duplicate any lines already in /etc/modprobe.d/alsa-base
			grep -Fv -f /etc/modprobe.d/alsa-base "$addcfg" >> "$TMP"
		else
			cat "$addcfg" >> "$TMP"
		fi
	fi
fi
        cmp -s "$TMP" "$cfgfile" || cat "$TMP" > "$cfgfile"
    fi

    /sbin/depmod -a 2>/dev/null

    # remove yast2 entries (- only for suse distro)
    if [ -f /var/lib/YaST/unique.inf ]; then
	awk '
BEGIN { in_sound=0; }
/^\[sound\]$/ { print; in_sound=1; next; }
/^\[.+\]$/ { print; in_sound=0; next; }
{ if (in_sound == 0) { print; } }
' < /var/lib/YaST/unique.inf > $TMP
	cp -f $TMP /var/lib/YaST/unique.inf
    fi

    farewell
    clear
    if [ "$distribution" = "gentoo" ]; then
      xecho "Running modules-update..."
      modules-update
    elif [ "$distribution" = "debian" ]; then
      xecho "Running update-modules..."
      update-modules
    fi
    echo Loading driver...
if false; then
    $rcalsasound start
else
    /sbin/modprobe $CARD_DRIVER
    sleep 4   # Wait for automatic "alsactl restore" to finish
fi
    echo Setting default volumes...
    if [ -x $bindir/set_default_volume ]; then
	$bindir/set_default_volume -f
    else
	set_mixers
    fi
    if [ -f $TESTSOUND ]; then
      msg=$(gettext "
       The mixer is set up now for for playing.
       Shall I try to play a sound sample now?

                           NOTE:
If you have a big amplifier, lower your volumes or say no.
    Otherwise check that your speaker volume is open,
          and look if you can hear test sound.
")
      if $DIALOG --yesno "$msg" 13 65 
      then
          clear
	  echo
	  aplay -N $TESTSOUND
      fi
    fi
    if [ ! -r /var/lib/alsa/asound.state ]; then
	xecho "Saving the mixer setup used for this in /var/lib/alsa/asound.state."
	$sbindir/alsactl store
    fi
    clear
    xecho "
===============================================================================

 Now ALSA is ready to use.
 For adjustment of volumes, use your favorite mixer.

 Have a lot of fun!

"
}

#
# probe legacy ISA cards
#

check_dma_avail () {
    if [ -r /proc/dma ]; then
	list=""
	for dma in $*; do
	    grep -q '^ *'$dma': ' /proc/dma || list="$list $dma"
	done
	echo $list
    fi
}

check_irq_avail () {
    if [ -r /proc/interrupts ]; then
	list=""
	for irq in $*; do
	    grep -q '^ *'$irq': ' /proc/interrupts || list="$list $irq"
	done
	echo $list
    fi
}

# check playback
# return 0 - OK, 1 - NG, 2 - not working (irq/dma problem)
ac_try_load () {
    test -n "$LOGFILE" && echo "$1 ${*:2}" >> "$LOGFILE"
if [ "$kernel" = old ] ; then
    /sbin/modprobe snd-$1 ${*:2} >/dev/null 2>&1
else
    /sbin/modprobe --ignore-install snd-$1 ${*:2} >/dev/null 2>&1
fi
    if $lsmod | grep -q -E '^(snd-|snd_)'$1' '; then
	: ;
    else
	modprobe -r snd-$1 >/dev/null 2>&1
	return 1
    fi

    # mute mixers
    amixer set Master 0% mute >/dev/null 2>&1
    amixer set PCM 0% mute >/dev/null 2>&1
    
    # output 0.5 sec
    head -c 4000 < /dev/zero | aplay -N -r8000 -fS16_LE -traw -c1 > /dev/null 2>&1 &
    # remember pid
    pp=$!
    # sleep for 2 seconds (to be sure -- 1 sec would be enough)
    sleep 2
    # kill the child process if still exists.
    kill -9 $pp > /dev/null 2>&1
    st=$?
    ac_cardname=`head -n 1 /proc/asound/cards | sed -e 's/^[0-9].* - \(.*\)$/\1/'`
    /sbin/modprobe -r snd-$1 >/dev/null 2>&1
    if [ $st = 0 ]; then
	# irq problem?
	test -n "$LOGFILE" && echo "no playback return" >> "$LOGFILE"
	return 2
    else
	# seems ok!
	test -n "$LOGFILE" && echo "playback OK" >> "$LOGFILE"
	return 0
    fi
}

# check capture
# return 0 - OK, 1 - NG, 2 - not working (irq/dma problem)
# ac_try_capture card duplex opts
ac_try_capture () {
    test -n "$LOGFILE" && echo "$1 ${*:2}" >> "$LOGFILE"
if [ "$kernel" = old ] ; then
    /sbin/modprobe snd-$1 ${*:3} >/dev/null 2>&1
else
    /sbin/modprobe --ignore-install snd-$1 ${*:3} >/dev/null 2>&1
fi
    if $lsmod | grep -q -E '^(snd-|snd_)'$1' '; then
	: ;
    else
	modprobe -r snd-$1 >/dev/null 2>&1
	return 1
    fi

    # mute mixers
    amixer set Master 0% mute >/dev/null 2>&1
    amixer set PCM 0% mute >/dev/null 2>&1

    play_pid=0
    if [ $2 = yes ]; then
	# try duplex - start dummy playing
	aplay -N -r8000 -fS16_LE -traw -c1 < /dev/zero > /dev/null 2>&1 &
	play_pid=$!
    fi
    # record 1sec
    arecord -N -d1 > /dev/null 2>&1 &
    # remember pid
    pp=$!
    # sleep for 2 seconds
    sleep 2
    # kill the child process if still exists.
    kill -9 $pp > /dev/null 2>&1
    st=$?
    # kill playback process if any
    test $play_pid != 0 && kill -9 $play_pid
    /sbin/modprobe -r snd-$1 >/dev/null 2>&1
    if [ $st = 0 ]; then
	test -n "$LOGFILE" && echo "capture no return" >> "$LOGFILE"
	return 2
    else
	test -n "$LOGFILE" && echo "capture OK" >> "$LOGFILE"
	return 0
    fi
}

get_dma_pair () {
    case $1 in
    0)
	echo 1 3 5;;
    1)
	echo 0 3 5;;
    3)
	echo 1 0 5;;
    5)
	echo 3 1 0;;
    esac
}

#
# check playback on specified irqs
#
# ac_try_irq card opts irqs...
# return 0 - OK, 1 - NG, 2 - not working (dma problem?)
#
ac_try_irq () {
    card=$1
    opts="$2 ${mpfx}irq=$3"
    ac_try_load $card $opts >/dev/null 2>&1
    result=$?
    case $result in
    0)
	ac_opts="$opts"
	return 0
	;;
    2)
	for irq in ${*:4}; do
	    opts="$2 ${mpfx}irq=$irq"
	    ac_try_load $card $opts >/dev/null 2>&1
	    if [ $? = 0 ]; then
		ac_opts="$opts"
		return 0
	    fi
	done
	return 2
	;;
    esac
    return 1
}

#
# check playback/capture on dma1 & dma2 & specified irqs
#
# ac_try_dmas card opts irqs...
# return 0 - OK, 1 - NG
#
ac_try_dmas () {
    dma_list=`check_dma_avail 1 0 3 5`
    for irq in ${*:3}; do
	for dma1 in $dma_list; do
	    for dma2 in `get_dma_pair $dma1`; do
		opts="$2 ${mpfx}dma1=$dma1 ${mpfx}dma2=$dma2 ${mpfx}irq=$irq"
		ac_try_load $1 $opts >/dev/null 2>&1
		result=$?
		if [ $result = 1 ]; then
		    if [ $try_all_combination = 1 ]; then
			continue
		    else
			return 1
		    fi
		elif [ $result = 0 ]; then
		    test -n "$LOGFILE" && echo "Now checking capture..." >> "$LOGFILE"
		    ac_opts="$opts"
		    ac_try_capture $1 yes $opts >/dev/null 2>&1 && return 0
		    for d in yes no; do
			for dma2 in $dma_list; do
			    if [ $dma1 != $dma2 ]; then
				opts="$2 ${mpfx}dma1=$dma1 ${mpfx}dma2=$dma2 ${mpfx}irq=$irq"
				ac_opts="$opts"
				ac_try_capture $1 $d $opts >/dev/null 2>&1 && return 0
			    fi
			done
		    done
		    return 0
		fi
	    done
	done
    done
    return 1
}

# check if the option $2 exists in card $1: set value $3
ac_check_option () {
    if /sbin/modinfo -p snd-$1 | grep -q $2; then
      echo "$2=$3"
    fi
}

ac_try_card_sb8 () {
    card=sb8
    irq_list=`check_irq_avail 5 3 9 10 7`
    for dma8 in `check_dma_avail 1 3`; do
	opts="${mpfx}dma8=$dma8"
	ac_try_irq $card "$opts" $irq_list && return 0
    done
    return 1
}

ac_try_card_sb16 () {
    card=sb16
    isapnp=`ac_check_option $card ${mpfx}isapnp 0`
    opts="$isapnp"
    irq_list=`check_irq_avail 5 9 10 7 3`
    dma_list=`check_dma_avail 0 1 3`
    dma16_list=`check_dma_avail 5 6 7`
    # at first try auto-probing by driver itself
    ac_try_load $card $opts >/dev/null 2>&1
    result=$?
    case $result in
    0)
	ac_opts="$opts"
	ac_try_capture $card yes $opts >/dev/null 2>&1 && return 0
	for d in yes no; do
	    for dma8 in $dma_list; do
		for irq in $irq_list; do
		    opts="${mpfx}dma8=$dma8 ${mpfx}irq=$irq $isapnp"
		    ac_try_capture $card $d $opts >/dev/null 2>&1 && return 0
		done
	    done
	done
	return 0
	;;
    2)
	for dma16 in $dma16_list; do
	    opts="${mpfx}dma16=$dma16 $isapnp"
	    if ac_try_irq $card "$opts" $irq_list ; then
		ac_try_capture $card yes $ac_opts >/dev/null 2>&1 && return 0
		ac_opts_saved="$ac_opts"
		for d in yes no; do
		    for dma8 in $dma_list; do
			ac_opts="$ac_opts_saved ${mpfx}dma8=$dma8"
			ac_try_capture $card $d $ac_opts >/dev/null 2>&1 && return 0
		    done
		done
		# return anyway here..
		return 0
	    fi
	done
	;;
    esac
    return 1
}

ac_try_card_es1688 () {
    card=es1688
    opts=""
    irq_list=`check_irq_avail 5 9 10 7`
    for dma8 in `check_dma_avail 1 3 0`; do
	opts="${mpfx}dma8=$dma8 ${mpfx}mpu_irq=-1"
	ac_try_irq $card "$opts" $irq_list && return 0
    done
    return 1
}

ac_try_card_es18xx () {
    card=es18xx
    opts=`ac_check_option $card ${mpfx}isapnp 0`
    ac_try_dmas $card "$opts" `check_irq_avail 5 9 10 7` && return 0
    return 1
}

ac_try_card_cs4236 () {
    card=cs4236
    irq_list=`check_irq_avail 5 7 9 11 12 15`
    isapnp=`ac_check_option $card ${mpfx}isapnp 0`
    for cport in 0x538 0x210 0xf00; do
	for port in 0x530 0x534; do
	    opts="${mpfx}port=$port ${mpfx}cport=$cport $isapnp"
	    ac_try_dmas $card "$opts" $irq_list && return 0
	done
    done
    return 1
}

ac_try_card_cs4232 () {
    card=cs4232
    irq_list=`check_irq_avail 5 7 9 11 12 15`
    isapnp=`ac_check_option $card ${mpfx}isapnp 0`
    for cport in 0x538 0x210 0xf00; do
	for port in 0x530 0x534; do
	    opts="${mpfx}port=$port ${mpfx}cport=$cport $isapnp"
	    ac_try_dmas $card "$opts" $irq_list && return 0
	done
    done
    return 1
}

ac_try_card_cs4231 () {
    card=cs4231
    irq_list=`check_irq_avail 5 7 9 11 12 15`
    for port in 0x530 0x534; do
	opts="${mpfx}port=$port"
	ac_try_dmas $card "$opts" $irq_list && return 0
    done
    return 1
}

ac_try_card_opl3sa2 () {
    card=opl3sa2
    irq_list=`check_irq_avail 5 9 3 1 11 12 15 0`
    isapnp=`ac_check_option $card ${mpfx}isapnp 0`
    for port in 0x370 0x538 0xf86 0x100; do
	for wss_port in 0x530 0xe80 0xf40 0x604; do
	    opts="${mpfx}fm_port=-1 ${mpfx}midi_port=-1 ${mpfx}port=$port ${mpfx}wss_port=$wss_port $isapnp"
	    ac_try_dmas $card "$opts" $irq_list && return 0
	done
    done
    return 1
}

ac_config_legacy () {
   title=$(gettext "WARNING")
   msg=$(gettext "
   Probing legacy ISA cards might make
   your system unstable.

        Are you sure to proceed?

")
    $DIALOG --title "$title" --yesno "$msg" 10 50 || acex 0

    if [ x"$1" = x ]; then
	probe_list="$LEGACY_CARDS"
    else
	probe_list=$*
    fi
    menu_args=()

    for card in $probe_list; do
	cardname=`/sbin/modinfo -d snd-$card | sed -e 's/^\"\(.*\)\"$/\1/g'`
	if [ x"$cardname" != x ]; then
	    menu_args=("${menu_args[@]}" "$card" "$cardname" "on")
	fi
    done
    if [ x$menu_args = x ]; then
	msg=$(gettext "No legacy drivers are available
   for your machine")
	$DIALOG --msgbox "$msg" 5 50
	return 1
    fi
    title=$(gettext "Driver Selection")
    msg=$(gettext "           Probing legacy ISA cards

        Please select the drivers to probe:")
    $DIALOG --title "$title" --checklist "$msg" \
	17 64 8 "${menu_args[@]}" 2> $FOUND || acex 0

    if [ $try_all_combination != 1 ]; then
	msg=$(gettext "
 Shall I try all possible DMA and IRQ combinations?
 With this option, some unconventional configuration
 might be found, but it will take much longer time.")
	if $DIALOG --yesno "$msg" 10 60
	    then
	    try_all_combination=1
	fi
    fi

    xecho "Probing legacy cards..   This may take a few minutes.."
    echo -n $(gettext "Probing: ")
    cards=`cat $FOUND | tr -d \"`
    for card in $cards; do
	echo -n " $card"
	ac_opts=""
	if eval ac_try_card_$card ; then
	    xecho " : FOUND!!"
	    ac_config_card $card $ac_opts
	    return 0
	fi
    done
    echo
    title=$(gettext "Result")
    msg=$(gettext "No legacy cards found")
    $DIALOG --title "$title" --msgbox "$msg" 5 50
    return 1
}

#
# main part continued..
#

if test -n "$LOGFILE" ; then
    touch "$LOGFILE"
    echo -n "Starting alsaconf: " >> "$LOGFILE"
    date >> "$LOGFILE"
fi

intro

[ -x /etc/init.d/alsa ] && /etc/init.d/alsa force-unload

if [ -d /proc/asound ]; then
  /sbin/rmmod dmasound dmasound_awacs 2>/dev/null
fi

# Try to unload all sound modules
for S in OSS ALSA ; do
	L="/usr/share/linux-sound-base/${S}-module-list"
	if [ -r "$L" ] ; then
		for M in $(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$L") ; do
			[ "$M" ] && /sbin/modprobe -r "$M" >/dev/null 2>&1 || :
		done
	fi
done

if [ x"$legacy_probe_card" != x ]; then
    ac_opts=""
    if eval ac_try_card_$legacy_probe_card >/dev/null 2>&1; then
	echo "$ac_opts"
	echo "$ac_cardname"
	exit 0
    else
	echo "FAILED"
	exit 1
    fi
fi

if [ $do_legacy_only = 1 ]; then
    ac_config_legacy
    exit 0
fi
    
probe_cards

devs_found=()

if [ -s "$FOUND" ]; then
    while read dev card ; do
	/sbin/modprobe -a -l | grep -q -E $card'\.(o|ko)' || continue
	cardname=`find_device_name $dev | cut -c 1-64`
	if [ -z "$cardname" ]; then
	    cardname="$card"
	fi
	card=${card##snd-}
	devs_found=("${devs_found[@]}" "$card" "$cardname")
    done <"$FOUND"
fi
if [ x$devs_found != x ]; then
    #
    # check for TP600E
    #
    if [ ${devs_found[0]} = cs46xx ]; then
	if $lspci -nv 2>/dev/null| grep -q "Subsystem: 1014:1010"; then
	    msg=$(gettext "
 Looks like you having a Thinkpad 600E or 770 notebook.
 On this notebook, CS4236 driver should be used
 although CS46xx chip is detected.

 Shall I try to snd-cs4236 driver and probe
 the legacy ISA configuration?")
	    if $DIALOG --yesno "$msg" 13 60
	    then
		try_all_combination=1
		ac_config_legacy cs4236
		exit 0
	    fi
	elif $lspci -nv 2>/dev/null| grep -q "Subsystem: 8086:8080"; then
	    msg=$(gettext "
 Looks like you having a Dell Dimension machine.
 On this machine, CS4232 driver should be used
 although CS46xx chip is detected.

 Shall I try to snd-cs4232 driver and probe
 the legacy ISA configuration?")
	    if $DIALOG --yesno "$msg" 13 60
	    then
		try_all_combination=1
		ac_config_legacy cs4232
		exit 0
	    fi
        fi	
    fi
   
    devs_found=("${devs_found[@]}" "legacy" "Probe legacy ISA (non-PnP) chips")
    title=$(gettext "Soundcard Selection")
    msg=$(gettext "
         Following card(s) are found on your system.
         Choose a soundcard to configure:
")
    if [ "$INTERACTIVE" == "y" ]; then
      $DIALOG --title "$title" --menu "$msg" 17 76 8 "${devs_found[@]}" 2> $FOUND || acex 0
      card=`head -n 1 $FOUND`
    else
      card="${devs_found[0]}"
      echo "Selecting first card $card"
    fi
    if [ "$card" = "legacy" ]; then
	ac_config_legacy
    else
	ac_config_card "$card"
    fi
    exit 0
else
    msg=$(gettext "
        No supported PnP or PCI card found.

 Would you like to probe legacy ISA sound cards/chips?

")
    if $DIALOG --yesno "$msg" 9 60 ; then
	ac_config_legacy
	exit 0
    fi
fi

rm -f "$FOUND" "$DUMP"
exit 0