#!/bin/bash
# A wrapper to detect errors and cause s3ql_backup.sh to fail.
DROPBOX=dropbox

TMPOUT=`mktemp`
TMPERR=`mktemp`

cmd="${1}"
$DROPBOX ${@} 2>"$TMPERR" >"$TMPOUT"
code=$?

mexit(){
  if [ "$cmd" = "running" ]; then
    exit 0
  else
    exit $1
  fi
}

if grep Error "$TMPERR" > /dev/null; then
  echo "Dropbox encountered an error"
  cat $TMPOUT
  mexit 9001
else
  cat $TMPOUT
  exit $code
fi
