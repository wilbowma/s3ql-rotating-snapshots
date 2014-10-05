s3ql-rotating-snapshots
====================

This project extends `s3ql_backup.sh` from the s3ql project with a
couple of features to make configuring the script, and enabling
rotating snapshots in the style `rsnapshot`, simpler.

In short, new backups will be created under a folder named `$TAG`. This
variable could be, for instance, set to `hourly` in one invocation, and
`daily` in another. The backups under each tag are expired separately,
and can have different expiration options set via the `$EXPIREPY` variable.

The file `crontab` contains an example of invoking `s3ql_backup.sh` with
an `hourly` and `daily` tag, with different expiration options.

##Dropbox Sync
This is also extended with a feature I use in my own backups. It is
turned off by default because you really shouldn't use it.

This feature enables a single s3ql file system, synchronized over
Dropbox, to be used by multiple machines. This feature includes an ad-hoc
protocol to ensure only one machine mounts the file system at a time.
This protocol is probably broken, but seems to work for me in practice.

Don't use it. Really. But please feel free to tell me how the protocol
is broken and help me fix it.

##License
Large chunks of `s3ql_backup.sh` and the entirety of `expire_backups.py`
are copied verbatim from the s3ql project. See `LICENSE`.
