#!/bin/bash
# A wrapper to detect errors and cause s3ql_backup.sh to fail.
DROPBOX=dropbox

TMP=`mktemp`

if $DROPBOX ${@} 2>&1 >"$TMP" | grep Error > /dev/null; then
  echo "Dropbox encountered an error"
  cat $TMP
  exit 1
else
  cat $TMP
  exit 0
fi
