#!/bin/bash

### Configs
#HOME="~"
BACKUP="$HOME/.backups"
BACKUPURI="local://$BACKUP"
MOUNT="/tmp/s3ql_backup_$$"
MOUNTOPTS="--compress lzma-9"

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
UNISON_REMOTE_ROOT="ssh://user@example.com/backups"
UNISON_OPTS=""

# Configure for Unison sync/lock protocol
LOCKFILE="$BACKUP/lock"
MAXRETRY=10
WAITTIME=30

### Executables
PYTHON2=python2
EXPIREPY="/usr/share/doc/s3ql/contrib/expire_backups.py"
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

RSYNCOPTS="-aHAXxrS --partial --delete-during --delete-excluded"

### Copy commands
copy_files(){
  if [ ! -d "$new_backup" ]; then
    $MKDIR -p "$new_backup"
  fi

  pushd "$new_backup"

  mkdir -p ./pacman-local/etc
  cp /etc/pacman.conf ./pacman-local/etc/pacman.conf
  cp /etc/makepkg.conf ./pacman-local/etc/makepkg.conf
  cp /etc/yaourtrc ./pacman-local/etc/yaourtrc
  echo "# Pipe to pacman -S to reinstall" > ./pacman-local/pacman.lst
  pacman -Qenq >> ./pacman-local/pacman.lst
  echo "# Pipe to yaourt -S to reinstall" > ./pacman-local/yaourt.lst
  pacman -Qemq >> ./pacman-local/yaourt.lst

  $RSYNC $RSYNCOPTS \
    --include-from "$HOME/backup.lst" \
    "$HOME/" \
    "./home" || true

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

  -m        A string representation the hostname, used to create a separately expired set of intervals for each host. Defaults to '\$HOSTNAME' or 'hostname'.
  -n        Generate expire options using 'seq 1 n', where n is given by this option.
  -v        Enable verbose output messages.
  -h        Prints this message, silly.
  --mount   Manually mount the backup filesystem. If distributed protocol is enabled, synchronizes and locks the filesystem first.
  --unmount Manually unmount the backup filesystem. If distributed protocol is enabled, synchronizes and unlocks the filesystem after.

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

main(){
  if [ ! -d $BACKUP ]; then
    error "Backup dir doesn't exist" 6
  fi

  VERBOSE=false
  HOSTNAME=${HOSTNAME:-"`hostname`"}
  EXPIREPYOPTS=${EXPIREPYOPTS:-1 3 7 14 31 60 90 180 360}

  local MOUNT_AND_RETURN
  MOUNT_AND_RETURN=false

  local UNMOUNT_AND_RETURN
  UNMOUNT_AND_RETURN=false

  local DO_BACKUP
  DO_BACKUP=true

  local TEMP
  TEMP=`getopt -o m:n:vh -l help,mount,unmount -n "${0}" -- "${@}"`

  if [ $? != 0 ] ; then error "Parsing arguments failed" 2 ; fi

  eval set -- "$TEMP"

  while true ; do
    case "$1" in
      -m) HOSTNAME="${2}" ; shift 2 ;;
      -n) EXPIREPYOPTS="`seq 1 $2`" ; shift 2 ;;
      -v) VERBOSE=true ; shift ;;
      -h|--help) usage ; exit 0 ;;
      --mount) MOUNT_AND_RETURN=true ; shift ;;
      --unmount) UNMOUNT_AND_RETURN=true ; shift ;;
      --) shift ; break ;;
      *) echo "Invalid argument: ${1}" ; exit 3 ;;
    esac
  done
  if $VERBOSE; then
      RSYNCOPTS="$RSYNCOPTS -v"
  else
      UNISON_OPTS="$UNISON_OPTS -silent"
  fi
  verbose "HOSTNAME set to \"$HOSTNAME\""
  INTERVAL="$1"
  verbose "INTERVAL set to \"$INTERVAL\""
  EXPIREPYOPTS=${EXPIREPYOPTS:-"${@}"}
  verbose "EXPIREPYOPTS set to \"$EXPIREPYOPTS\""

  if $MOUNT_AND_RETURN && $UNMOUNT_AND_RETURN; then
      error "--mount and --unmount are mutually exclusive." 9
  fi

  if $MOUNT_AND_RETURN; then
      DO_BACKUP=false
      mount_and_return
      echo "Mounted at $MOUNT"
  fi

  if $UNMOUNT_AND_RETURN; then
      DO_BACKUP=false
      MOUNT="/tmp/s3ql_backup_$(tr -d "$HOSTNAME" < $LOCKFILE)"
      unmount_and_return
  fi

  if $DO_BACKUP; then
      do_backup
  fi
  return 0
}

# Unison lock protocol. A hand rolled protocol to obtain agreement by
# multiple machines, that this machine is the only one mounting the s3ql
# filesystem.

# TODO XXX HACK NB
# This protocol is totally suspect. It probably doesn't work. Don't use
# it. Srsly.

unison_sync(){
  if $CLIENT; then
    $UNISON $UNISON_PROFILE $UNISON_OPTS $WHO -batch
  fi
}

sync_lock(){
  if $CLIENT; then
    $UNISON $UNISON_PROFILE $UNISON_OPTS -batch -path \
      $(basename $LOCKFILE) $WHO
  fi
}

clear_lock(){
  echo -n '' > $LOCKFILE
}

acquire_lock(){
  WHO="-prefer $UNISON_REMOTE_ROOT" sync_lock
}

release_lock(){
  clear_lock
  WHO="-prefer $BACKUP" sync_lock
}

aquire_filesystem(){
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
        trap "clear_lock" EXIT

        acquire_lock

        if ! cat $LOCKFILE | grep "$HOSTNAME$$" > /dev/null; then
          verbose "Invalid lockfile string"
          sleep $WAITTIME
          acquire_lock
        else
          FLAG=1
        fi
      else
        verbose "Lock file not empty"
        sleep $WAITTIME
        acquire_lock
      fi
    done

    if [ "$FLAG" -eq "0" ]; then
      error "Couldn't obtain a lock" 8
    fi
    verbose "Got a lock!"
    find $BACKUP -iname "lock (conflict *on*" -not -path -delete
    trap "release_lock" EXIT
    WHO="-force $UNISON_REMOTE_ROOT" unison_sync

    # Move conflicted files
    #find $BACKUP -iname "*(conflict *on*" -not -path "$BACKUP/conflicts/*" -exec mv {} $BACKUP/conflicts/ \;
  fi
}

mount() {
  aquire_filesystem
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
  trap "cd /; $S3QLUMOUNT '$MOUNT'; $RMDIR '$MOUNT'; release_lock" EXIT
}

mount_and_return(){
  mount
  trap "" EXIT
}

unmount(){
  cd /
  if $UNSAFE_IM_REALLY_STUPID; then
    trap "$S3QLUMOUNT '$MOUNT'; $RMDIR '$MOUNT'; release_lock" EXIT
    $S3QLCTRL upload-meta "$MOUNT"
    $S3QLCTRL flushcache "$MOUNT"
    # s3ql umount will block until copies/uploads are complete.
    $S3QLUMOUNT "$MOUNT"
    trap "$RMDIR '$MOUNT'; release_lock" EXIT

    verbose "Waiting for sync..."
    WHO="-force $BACKUP" unison_sync

    release_lock
    trap "$RMDIR '$MOUNT'" EXIT
  else
    $S3QLUMOUNT "$MOUNT"
    $RMDIR "$MOUNT"
    trap "" EXIT
  fi
}

unmount_and_return(){
  unmount
}

do_backup() {
  mount
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
  unmount
}

# Abort entire script if any command fails
set -e

main "${@}"
