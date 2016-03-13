s3ql-rotating-snapshots
====================

The [s3ql file system](https://bitbucket.org/nikratio/s3ql/wiki/Home) is
a user-level file system with compression, encryption, and data
deduplication features. It also has support for using efficiently
Amazon's S3, Google Cloud Storage, and numerous other cloud backends.
This makes it very well suited for using to store offsite backups. It
also includes support for a local file backend, which can be used to
sync file over sshfs, or something like
[Unison](https://en.wikipedia.org/wiki/Unison_(file_synchronizer)).

This project extends `s3ql_backup.sh` from the s3ql with a couple of
features to simplify configuring the script, and enabling rotating
snapshots in the style `rsnapshot`.

## Multiple machines
The script will create a separately rotated set of backups for each
machine, by using the `$HOSTNAME` variable if it exists, otherwise using
`hostname`. To override this, use the `-m` flag.

## Intervals
The first implicit argument is interpreted as an interval, as in
`rsnapshot`.  The interval could be, for instance, set to `hourly` in
one invocation, and `daily` in another.

The backups under each interval are rotated separately, and can have
different expiration options. The expiration options can be set either
by passing a list of number as the final implicit argument, or using the
`-n` flag. These expiration options are passed to `expire_backups.py`, so
see the [s3ql documentation](http://www.rath.org/s3ql-docs/contrib.html)
for how to use `expire_backups.py`.

The file `crontab` contains an example of invoking `s3ql_backup.sh` with
an `hourly` and `daily` interval, with different expiration options.

## Adding new source/destinations
Simply add a call to `rsync`, or your favorite file copier, in the
function `copy_files`, in the configuration section of the
`s3ql_backup.sh`.

##Sync Protocol
This project also extends `s3ql_backup.sh` with a feature I use in my
own backups. It is turned off by default because you really shouldn't
use it.

I use a local file system synchronized by [Unison](https://en.wikipedia.org/wiki/Unison_(file_synchronizer)) in my own backups.
The s3ql file system only supports being mounted in one place at a time,
so my previous solution was a separate file system for each machine.
However, many of my machines have common files (config file, git repos,
etc), so multiple file systems really prevented optimal use of data
deduplication.

This feature enables a single s3ql file system, synchronized via
Unison, to be used by multiple machines. This feature includes an
ad-hoc protocol to ensure only one machine mounts the file system at a
time.

The current protocol seems to work in practice. I've been using it for
several months and have not corrupted the s3ql file-system yet.
However, when files are in conflict, files are created that seem to
stall s3ql, which can prevent backups from happening on schedule.

Don't use it. Really.

But please feel free to play with it, tell me how the protocol is
broken, or help me fix it.

##License
Large chunks of `s3ql_backup.sh` are copied verbatim from the s3ql project. See `LICENSE`.
