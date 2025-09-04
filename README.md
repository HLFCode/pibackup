# pibackup
Bash commands to backup and restore used space only (not the entire sd card)

Simple wrapper for bash dd to backup only the partitions declared by fdisk to an image file
This file can be used by the Raspberry Pi Imager to create a copy of the backed up system

Sometimes it is useful to have more than the default 2 partitions (boot and system)
This wrapper command checks the last used sector and instructs dd to copy up to that sector - no matter how may partitoons there are on the sd card

A third partition is useful if you want to run a read-only file system BUT retain a user home space as read-write.

# Usage

Backup & restore will usually be done on a separate Pi (or VM) with the sd card to be backed up accessible through an sd card/USB adapter.
The image file to be created can be on the Pi/VM or a mounted network image as needed

```
Usage: backup.sh --device <device to backup> --image <image to backup to> [--compress] [--blocksize <size>]
        (-d | -- device <device>)    The device to backup (required)
        (-i | --image <image>)       The file to backup to (required)
        (-c | --compress)            Compress the backup file (optional, default no compression)
        (-bs | --blocksize <size>    The block size in bytes to use (optonal, default is 65536). Pick a size divisible by the sector size
        (-h | -- help)               Print this help
        (-v | --version)             Print the version
```

The device will normally be /dev/sda if a USB adapter is used
The --compress option compresses the image on the fly into a file <imagename>.gz so if the image is backup.img the file created will be backup.img.gz and contain backup.img

```
Usage: restore.sh --device <device to resore to> --image <image to backup from>
        (-d | -- device <device>)    The device to restore to (required). Use /dev/null to test
        (-i | --image <image>)       The file to backup from. It can be a gzip compressed file (required)
        (-bs | --blocksize <size>    The block size in bytes to use (optonal, default is 65536)
        (-k | --keepmounted)         If compressed source image, do not unmount it when finished
        (-h | -- help)               Print this help
        (-v | --version)             Print the version
```

The parameters are the same as for backup.sh

If the image file is a compressed image it will be uncompressed first and mounted using losetup and if --keepmounted is present the uncompressed image will not be dismounted and deleted after the restore
