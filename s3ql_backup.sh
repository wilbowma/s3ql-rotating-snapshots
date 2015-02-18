#!/bin/bash

### Configs
#HOME="~"
BACKUP="$HOME/.backups"
BACKUPURI="local://$BACKUP"
MOUNT="/tmp/s3ql_backup_$$"
# 100MB cache should be sufficient for a local backend
MOUNTOPTS="--compress lzma-9 --cachesize 97656.25"

### If you want to use this script with multiple machines accessing a
### single filesystem that is synced over Unison, you need to read the
### disclaimers below about the "Dropbox lock protocol". Then set this
### flag to true.

### If you just want to use this script, extended with the
### machine/interval features, don't touch this.
UNSAFE_IM_REALLY_STUPID=false
SERVER=false
CLIENT=false
UNISON_PROFILE=s3ql-backup
UNISON_OPTS=""

# Configure for Unison sync/lock protocol
LOCKFILE="$BACKUP/lock"
MAXRETRY=10
WAITTIME=30

### Executables
PYTHON2=python2
EXPIREPY="`dirname \"$0\"`/expire_backups.py"
S3QLMOUNT=mount.s3ql
S3QLUMOUNT=umount.s3ql
S3QLFSCK=fsck.s3ql
S3QLCTRL=s3qlctrl
S3QLLOCK=s3qllock
S3QLCP=s3qlcp
S3QLRM=s3qlrm
RSYNC=rsync
RM=rm
CP=cp
MV=mv
MKDIR=mkdir
RMDIR=rmdir
UNISON=unison

RSYNCOPTS="-aHAXxvr --partial --delete-during --delete-excluded"

### Copy commands
copy_files(){
  if [ ! -d "$new_backup" ]; then
    $MKDIR -p "$new_backup"
  fi

  pushd "$new_backup"

  $RSYNC $RSYNCOPTS \
    --include-from "$HOME/backup.lst" \
    "$HOME/" \
    "./home"

  popd
}

# ========================================================================
# End of configuration
# ========================================================================

usage(){
cat << EOF
Usage: ${0} [OPTION]... [INTERVAL] [EXPIREOPTS]

  INTERVAL should be a string naming a separately expired interval.
  EXPIREOPTS should be a list of numbers which will be passed to expire_backups.py

  -m    A string representation the hostname, used to create a separately expired set of intervals for each host. Defaults to '\$HOSTNAME' or 'hostname'.
  -n    Generate expire options using 'seq 1 n', where n is given by this option.
  -v    Enable verbose output messages.
  -h    Prints this message, silly.

EOF
}

verbose(){
  if $VERBOSE; then
    echo $1
  fi
}


error(){
  echo "${0}: ERROR: ${1}">&2
  exit $2
}

parse_arguments(){
  VERBOSE=false
  HOSTNAME=${HOSTNAME:-"`hostname`"}
  EXPIREPYOPTS=${EXPIREPYOPTS:-1 3 7 14 31 60 90 180 360}

  local TEMP
  TEMP=`getopt -o m:n:vh --long ,,,help -n "${0}" -- "${@}"`

  if [ $? != 0 ] ; then error "Parsing arguments failed" 2 ; fi

  eval set -- "$TEMP"

  while true ; do
    case "$1" in
      -m) HOSTNAME="${2}" ; shift 2 ;;
      -n) EXPIREPYOPTS="`seq 1 $2`" ; shift 2 ;;
      -v) VERBOSE=true ; shift ;;
      -h|--help) usage ; exit 0 ;;
      --) shift ; break ;;
      *) echo "Invalid argument: ${1}" ; exit 3 ;;
    esac
  done
  verbose "HOSTNAME set to \"$HOSTNAME\""
  INTERVAL="$1"
  verbose "INTERVAL set to \"$INTERVAL\""
  EXPIREPYOPTS=${EXPIREPYOPTS:-"${@}"}
  verbose "EXPIREPYOPTS set to \"$EXPIREPYOPTS\""
  return 0
}

parse_arguments "${@}"

UNISON_OPTS="$UNISON_OPTS$(if $VERBOSE; then echo ""; else echo " -silent"; fi)"

# Unison lock protocol. A hand rolled protocol to obtain agreement by
# multiple machines, that this machine is the only one mounting the s3ql
# filesystem.

# TODO XXX HACK NB
# This protocol is totally suspect. It probably doesn't work. Don't use
# it. Srsly.

# Abort entire script if any command fails
set -e

if [ ! -d $BACKUP ]; then
  error "Backup dir doesn't exist" 6
fi

unison_sync(){
  if $CLIENT; then
    $UNISON $UNISON_PROFILE $UNISON_OPTS -batch
  fi
}

sync_lock(){
  if $CLIENT; then
    $UNISON $UNISON_PROFILE $UNISON_OPTS -batch -path $(basename $LOCKFILE) -prefer newer
  fi
}

locktrap(){
  echo -n '' > $LOCKFILE
  sync_lock
}

if $UNSAFE_IM_REALLY_STUPID; then
  if (! ($CLIENT || $SERVER)) || ($CLIENT && $SERVER); then
    error "You have to choose; set SERVER xor CLIENT" 1
  fi

  verbose "Greedily grab the Lock"

  if [ ! -e $LOCKFILE ]; then
    touch $LOCKFILE
  fi

  RETRY=0
  FLAG=0
  while [[ "$RETRY" -le "$MAXRETRY"  &&  "$FLAG" -eq "0" ]]; do
    let "RETRY+=1"
    if [ ! -s $LOCKFILE ]; then
      echo "$HOSTNAME$$" > $LOCKFILE

      sync_lock

      if ! cat $LOCKFILE | grep "$HOSTNAME$$" > /dev/null; then
        verbose "Invalid lockfile string"
        sleep $WAITTIME
        sync_lock
      else
        FLAG=1
      fi
    else
      verbose "Lock file not empty"
      sleep $WAITTIME
      sync_lock
    fi
  done

  if [ "$FLAG" -eq "0" ]; then
    error "Couldn't obtain a lock" 8
  fi
  verbose "Got a lock!"
  trap "locktrap" EXIT
  unison_sync
fi


# Recover cache if e.g. system was shut down while fs was mounted
$S3QLFSCK --batch "$BACKUPURI"

if [ -d $MOUNT ]; then
  error "Mount point exists and shouldn't" 2
fi

# Create a temporary MOUNT and mount file system
$MKDIR -p "$MOUNT"
$S3QLMOUNT $MOUNTOPTS "$BACKUPURI" "$MOUNT"

# Make sure the file system is unmounted when we are done
# Note that this overwrites the earlier trap, so we
# also delete the lock file here.
trap "cd /; $S3QLUMOUNT '$MOUNT'; $RMDIR '$MOUNT'; locktrap" EXIT

$MKDIR -p "$MOUNT/$HOSTNAME/$INTERVAL"
cd "$MOUNT/$HOSTNAME/$INTERVAL"

# Figure out the most recent backup
last_backup=`$PYTHON2 <<EOF
import os
import re
backups=sorted(x for x in os.listdir('.') if re.match(r'^[\\d-]{10}_[\\d:]{8}$', x))
if backups:
    print backups[-1]
EOF`

# Duplicate the most recent backup unless this is the first backup
new_backup=`date "+%Y-%m-%d_%H:%M:%S"`
if [ -n "$last_backup" ]; then
  echo "Copying $last_backup to $new_backup..."
  $S3QLCP "$last_backup" "$new_backup"

  # Make the last backup immutable
  # (in case the previous backup was interrupted prematurely)
  $S3QLLOCK "$last_backup"
fi

copy_files

# Make the new backup immutable
$S3QLLOCK "$new_backup"

cd "$MOUNT/$HOSTNAME/$INTERVAL"

# Expire old backups

# Note that expire_backups.py comes from contrib/ and is not installed
# by default when you install from the source tarball. If you have
# installed an S3QL package for your distribution, this script *may*
# be installed, and it *may* also not have the .py ending.

$EXPIREPY --use-s3qlrm $EXPIREPYOPTS

if $UNSAFE_IM_REALLY_STUPID && $CLIENT; then
  cd /
  trap "$S3QLUMOUNT '$MOUNT'; $RMDIR '$MOUNT'; locktrap" EXIT
  $S3QLCTRL upload-meta "$MOUNT"
  $S3QLCTRL flushcache "$MOUNT"
  # s3ql umount will block until copies/uploads are complete.
  $S3QLUMOUNT "$MOUNT"
  trap "$RMDIR '$MOUNT'; locktrap" EXIT

  verbose "Waiting for sync..."
  unison_sync

  locktrap
  trap "$RMDIR '$MOUNT'" EXIT
fi
