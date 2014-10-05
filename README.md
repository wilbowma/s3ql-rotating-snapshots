s3ql-rotating-snapshots
====================

The [s3ql file system][https://bitbucket.org/nikratio/s3ql/wiki/Home] is
a user-level file system with compression, encryption, and data
deduplication features. It also has support for using efficiently
Amazon's S3, Google Cloud Storage, and numerous other cloud backends.
This makes it very well suited for using to store offsite backups. It
also includes support for a local file backend, which can be used to
sync file over sshfs, or even Dropbox.

This project extends `s3ql_backup.sh` from the s3ql with a couple of
features to simplify configuring the script, and enabling rotating
snapshots in the style `rsnapshot`.

## Multiple machines
Use the variable `$MACHINE` to create a separately rotated set of
backups for each machine.

## Intervals
Use the variable `$TAG` to create a new rotated tag.  This variable
could be, for instance, set to `hourly` in one invocation, and `daily`
in another. It's essentially equivalent to `rsnapshot' intervals.

The backups under each tag are rotated separately, and can have
different expiration options set via the `$EXPIREPYOPTS` variable. This
variable is a list of arguments to pass to `expire_python.py`, so see
the [s3ql documentation][http://www.rath.org/s3ql-docs/contrib.html] for
how to use `expire_python.py`.

The file `crontab` contains an example of invoking `s3ql_backup.sh` with
an `hourly` and `daily` tag, with different expiration options.

## Adding new source/destinations
Simply add a call to `rsync`, or your favorite file copier, in the
function `copy_files`, in the configuration section of the
`s3ql_backup.sh`.

##Dropbox Sync
This is project also extend `s3ql_backup.sh` with a feature I use in my
own backups. It is turned off by default because you really shouldn't
use it.

I use a local file system synchronized by Dropbox in my own backups.
However, many of my machines have common files (config file, git repos,
etc), the s3ql file system only supports being mounted in one place at a
time, so my previous solution was a separte file system for each
machine. This really prevented optimal use of data deduplication.

This feature enables a single s3ql file system, synchronized over
Dropbox, to be used by multiple machines. This feature includes an
ad-hoc protocol to ensure only one machine mounts the file system at a
time.  This protocol is probably broken, but seems to work for me in
practice.

Don't use it. Really.

But please feel free to play with it, tell me how the protocol is
broken, or help me fix it.

This feature requires the
[Dropbox command line interface][http://www.dropboxwiki.com/tips-and-tricks/using-the-official-dropbox-command-line-interface-cli#Installation].

##License
Large chunks of `s3ql_backup.sh` and the entirety of `expire_backups.py`
are copied verbatim from the s3ql project. See `LICENSE`.
