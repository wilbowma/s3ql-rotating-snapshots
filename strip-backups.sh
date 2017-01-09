#!/bin/bash

# Expects backups to be mounted in $BACKUPS. Strips all backups, using s3qlcp for efficient copying of
# similar snapshots. Leaves stripped version in $BACKUP/stripper

BACKUP=`ls --color=never -d /tmp/s3ql_backup_*`
MACHINES="home work server"

function cleanup(){
    echo Cleaning $1
    find $1 \
         \( \
         -ipath "*/.Trash-1000/*" -or \
         -ipath "*/.unison/fp*" -or \
         -ipath "*/.unison/ar*" -or \
         -ipath "*/.emacs.d/elpa*" -or \
         -ipath "*/.emacs.d/var*" -or \
         -ipath "*/.emacs.d/auto-save-list*" -or \
         -ipath "*/.mutt/cache*" -or \
         -ipath "*/.mutt/sent*" -or \
         -iname ".~lock*.odp#" -or \
         -iname "*.agdai" -or \
         -iname "*.hi" -or \
         -iname "*.o" -or \
         -iname "*.out" -or \
         -iname "*.class" -or \
         -iname "*.pyc" -or \
         -iname "*.xpi" -or \
         -iname "*.aux" -or \
         -iname "*.bbl" -or \
         -iname "*.glob" -or \
         -iname "*.fdb_latexmk" -or \
         -iname "*.fls" -or \
         -iname "*.tdo" -or \
         -iname "*.vo" -or \
         -iname "*.zo" -or \
         -iname "*.toc" -or \
         -iname ".*.trash" -or \
         -iname ".*.swp" -or \
         -iname "*~" -or \
         -iname "#*#" -or \
         -iname ".#*" -or \
         -iname "y" \
         \) -and -print -and -delete > $1.log
}

set -e

source=$BACKUP
target="$source/stripped"

for machine in $MACHINES; do
    for type in yearly monthly weekly daily hourly; do
        mkdir -p $target/$machine/$type/
        cp $source/$machine/$type/.expire_backups.dat $target/$machine/$type
        for snapshot in `ls --color=never $source/$machine/$type/ | sort | xargs echo`; do
            s3qlcp $source/$machine/$type/$snapshot $target/$machine/$type/$snapshot
            cleanup $target/$machine/$type/$snapshot
            s3qllock $target/$machine/$type/$snapshot
        done
    done
done
