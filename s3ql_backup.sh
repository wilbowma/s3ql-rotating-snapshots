#!/bin/bash

### Configs
#HOME="~"
BACKUP="$HOME/Dropbox/.backups"
BACKUPURI="local://$BACKUP"
MOUNT="/tmp/s3ql_backup_$$"
MOUNTOPTS="--compress lzma-9"

# Interval should be a rotating interval, such as "hourly" "daily" etc.
# Can be given on the commandline
INTERVAL=${INTERVAL:-"daily"}
EXPIREPYOPTS=${EXPIREPYOPTS:-1 3 7 14 31 60 90 180 360}

# Machine should be a unique name if you are using Dropbox sync, or if
# you want to rotate snapshots for different machines separately.
HOSTNAME="`hostname`"

### If you want to use this script with multiple machines accessing a
### single filesystem that is synced over dropbox, you need to read the
### disclaimers below about the "Dropbox lock protocol". Then set this
### flag to true.

### If you just want to use this script, extended with the
### machine/interval features, don't touch this.
UNSAFE_IM_REALLY_STUPID=false

# Configure for dropbox sync/lock protocol
LOCKFILE="$BACKUP/lock"
MAXRETRY=3
WAITTIME=300

### Executables
PYTHON2=python2
DROPBOX="`dirname \"$0\"`/dropbox.sh"
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

RSYNCOPTS="-aHAXxvr --partial --delete --delete-excluded"

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

debug(){
  echo $1
}
# ========================================================================
# End of configuration
# ========================================================================

# Dropbox lock protocol. A hand rolled protocol to obtain agreement by
# multiple machines, via a lock file stored on dropbox, that this
# machine is the only one mounting the s3ql filesystem.

# TODO XXX HACK NB
# This protocol is totally suspect. It probably doesn't work. Don't use
# it. Srsly.

# Abort entire script if any command fails
set -e
dropbox_ready(){
  debug "Is dropbox running?"
  if $DROPBOX running; then
    debug "Starting Dropbox"
    $DROPBOX start
  fi
  while $DROPBOX status | grep -e "Starting" -e "Connecting" > /dev/null; do
    sleep 5
  done
}

lock_sync(){
  sleep 2
  dropbox_ready
   while $DROPBOX filestatus $LOCKFILE | grep syncing > /dev/null; do
    sleep 5
  done
}

fs_sync(){
  sleep 2
  dropbox_ready
  while $DROPBOX filestatus $BACKUP | grep syncing > /dev/null; do
    sleep 5
  done
}

if [ ! -d $BACKUP ]; then
  echo "Backup dir doesn't exist"
  exit 6
fi

if $UNSAFE_IM_REALLY_STUPID; then

  debug "Is filesystem ready?"
  fs_sync

  if [ ! -e $LOCKFILE ]; then
    touch $LOCKFILE
  fi

  if [ ! "`find $BACKUP -iname '*conflicted copy*' -and -not -iname 'lock*'`" = "" ]; then
    echo "There are conflicts. Some went wrong on previous run. Remove conflicts and fsck manually."
    exit 10
  fi

  RETRY=0
  FLAG=0
  while [[ "$RETRY" -le "$MAXRETRY"  &&  "$FLAG" -eq "0" ]]; do
    let "RETRY+=1"
    debug "Waiting for lock to sync"
    lock_sync
    if [ ! -s $LOCKFILE ]; then
      echo "$HOSTNAME$$" > $LOCKFILE
      trap "echo -n '' > $LOCKFILE" EXIT
      lock_sync
      if ! cat $LOCKFILE | grep "$HOSTNAME$$" > /dev/null; then
        echo "Invalid lockfile string"
        sleep $WAITTIME
      else
        FLAG=1
      fi
    else
      debug "Lock file not empty"
      sleep $WAITTIME
    fi
  done

  if [ "$FLAG" -eq "0" ]; then
    echo "Couldn't obtain a lock"
    exit 8
  fi
  debug "Got a lock!"

  fs_sync

  $DROPBOX stop
  trap "echo -n '' > $LOCKFILE; $DROPBOX start" EXIT
fi


# Recover cache if e.g. system was shut down while fs was mounted
$S3QLFSCK --batch "$BACKUPURI"

if [ -d $MOUNT ]; then
  echo "Mount point exists and shouldn't"
  exit 2
fi

# Create a temporary MOUNT and mount file system
$MKDIR -p "$MOUNT"
$S3QLMOUNT $MOUNTOPTS "$BACKUPURI" "$MOUNT"

# Make sure the file system is unmounted when we are done
# Note that this overwrites the earlier trap, so we
# also delete the lock file here.
if $UNSAFE_IM_REALLY_STUPID; then
  trap "cd /; $S3QLUMOUNT '$MOUNT'; $RMDIR '$MOUNT'; echo -n '' > '$LOCKFILE'; $DROPBOX start" EXIT
else
  trap "cd /; $S3QLUMOUNT '$MOUNT'; $RMDIR '$MOUNT'; echo -n '' > '$LOCKFILE'" EXIT
fi

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

if $UNSAFE_IM_REALLY_STUPID; then
  $CP .expire_backups.dat .expire_backups.dat.bak
fi

$EXPIREPY --use-s3qlrm $EXPIREPYOPTS

if $UNSAFE_IM_REALLY_STUPID; then
  cd /
  trap "$S3QLUMOUNT '$MOUNT'; $RMDIR '$MOUNT'; echo -n '' > '$LOCKFILE'; $DROPBOX start" EXIT
  $S3QLCTRL upload-meta "$MOUNT"
  $S3QLCTRL flushcache "$MOUNT"
  # s3ql umount will block until copies/uploads are complete.
  $S3QLUMOUNT "$MOUNT"
  trap "$RMDIR '$MOUNT'; echo -n '' > '$LOCKFILE'; $DROPBOX start" EXIT

  $DROPBOX start

  echo "Waiting for sync..."
  fs_sync

  echo -n '' > "$LOCKFILE"
  trap "$RMDIR '$MOUNT'" EXIT

  fs_sync
fi
