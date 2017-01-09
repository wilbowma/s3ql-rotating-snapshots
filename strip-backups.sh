#!/bin/bash

rsync="rsync -azh --progress"
BACKUP=`ls --color=never -d /tmp/s3ql_backup_*`
MACHINES="home work server"

function cleanup(){
    find $1 \
         -ipath "*/.Trash-1000/*" -or \
         -ipath "*/.unison/fp*" -or \
         -ipath "*/.unison/ar*" -or \
         -ipath "*/.emacs.d/elpa" -or \
         -ipath "*/.emacs.d/var" -or \
         -ipath "*/.emacs.d/auto-save-list" -or \
         -ipath "*/.mutt/cache" -or \
         -ipath "*/.mutt/sent" -or \
         -iname "*.o" -or \
         -iname "*.out" -or \
         -iname "*.class" -or \
         -iname "*.pyc" -or \
         -iname "*.xpi" -or \
         -iname "*.aux" -or \
         -iname "*.bbl" -or \
         -iname "*.glob" -or \
         -iname "*.vo" -or \
         -iname "*.zo" -or \
         -iname "*.toc" -or \
         -iname ".*.trash" -or \
         -iname ".*.swp" -or \
         -iname "*~" -or \
         -iname "#*#" -or \
         -iname ".#*" -or \
         -iname "y" \
         -delete
}

set -e

source=$BACKUP
target="$source/stripped"

for machine in $MACHINES; do
    for type in yearly monthly weekly daily hourly; do
        first_snapshot=`ls --color=never $source/$machine/$type/ | sort | head -n 1`
        mkdir -p $target/$machine/$type/
        $rsync $source/$machine/$type/$first_snapshot $target/$machine/$type/
        cleanup $target/$machine/$type/$first_snapshot
        s3qllock $target/$machine/$type/$first_snapshot
        last_snapshot=$first_snapshot
        for snapshot in `ls --color=never $source/$machine/$type/ | sort | grep -v "$first_snapshot" | xargs echo`; do
            if [ ! -d $target/$machine/$type/$snapshot ]; then
               s3qlcp $target/$machine/$type/$last_snapshot $target/$machine/$type/$snapshot
            fi
            $rsync $source/$machine/$type/$snapshot $target/$machine/$type/
            cleanup $target/$machine/$type/$snapshot
            s3qllock $target/$machine/$type/$snapshot
            last_snapshot=$snapshot
        done
    done
done
