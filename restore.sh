#!/bin/bash
if [ ! -f ./utils.cfg ] ; then
	echo "Unable to find utils.cfg"
	exit 1
fi
. ./utils.cfg --source-only

declare bs intval
defaultsectorsize=65536
version=1.0

usage ()
{
	printf "Restores from an image file to a device (V$version)
Usage: restore.sh --device <device to resore to> --image <image to backup from>
\t(-d | -- device <device>)    The device to restore to (required). Use /dev/null to test
\t(-i | --image <image>)       The file to backup from. It can be a gzip compressed file (required)
\t(-bs | --blocksize <size>    The block size in bytes to use (optonal, default is $defaultsectorsize)
\t(-k | --keepmounted)         If compressed source image, do not unmount it when finished
\t(-h | -- help)               Print this help
\t(-v | --version)             Print the version\n"
}

device=
image=
bs=$defaultsectorsize
keepmounted=0

while [ "$1" != "" ]; do
	case $1 in
		-d | --device )         shift
					device=$1
					;;
		-i | --image )          shift
					image=$1
					;;
		-h | --help )           usage
					exit
					;;
		-bs | --blocksize )	shift
					bs=$1
					;;
		-k | --keepmounted )	keepmounted=1
					;;
		-v | --version )           echo $version
					exit
					;;
		* )                     usage
					exit 1
	esac
	shift
done

if (( EUID != 0 )); then
  echo "ERROR: You need to be running as root."
  exit -3
fi
if (( $bs == 0 )) ; then
	echo "ERROR: Bad block size ($bs), needs to be a sensible integer"
	exit 1
fi
if [ "$device" == "" ] ; then
	echo 'ERROR: You need to specify a device like /dev/sda'
	usage
	exit 1
fi
#if [ ! -b $device ] ; then
#	echo "ERROR: Device $device does not exist or is not a block device"
#	exit 1
#fi
if [ ! -b $device -a "$device" != "/dev/null" ] ; then
	echo "ERROR: $device does not exist or is not a block device"
	exit 1
fi
if [ "$image" == "" ] ; then
	echo 'ERROR: You need to specify a backup file like /mnt/backup/image.img'
	usage
	exit 1
fi
if [ ! -f $image ] ; then
	echo "ERROR: $image does not exist."
	usage
	exit 1
fi
isMounted $device -q
if [[ $? -eq 0 ]] ; then
	echo "ERROR: $device is mounted, unmount first"
	usage
	exit 1
fi

compressed_mount_dir=
# make sure we have the commands we need and if the image is compresed
declare -a cmds=("fdisk" "blockdev" "dd")
file $image | grep -iq "gzip compressed"
if (( $? == 0 )) ; then
	# compressed image
	cmds+=('archivemount')
	compressed_mount_dir=/tmp/compressed
fi

for command in ${cmds[@]}; do
	which $command 2>&1 >/dev/null
	if (( $? != 0 )); then
		echo "ERROR: $command is not installed."
		if [ $command == "archivemount" ] ; then
			echo "try sudo apt-get install $command"
		fi
		exit 1
	fi
done

source=$image
if [ ! -z $compressed_mount_dir ] ; then
	# source is compressed
	echo "$source is a compressed file"
	if [ ! -d $compressed_mount_dir ] ; then
		echo "Created $compressed_mount_dir"
		mkdir $compressed_mount_dir
	fi
	#check if compressed source already mounted, if not mount it
	echo "Mounting $image on $compressed_mount_dir..."
	mountpoint -q $compressed_mount_dir || archivemount -o formatraw $image $compressed_mount_dir
	if (( $? != 0 )) ; then
		# failed to mount
		rm $compressed_mount_dir
		echo "ERROR: failed to mount $image, check the archive"
		exit 1
	fi
	source=$compressed_mount_dir/data
fi
#echo "About to get info for $source..."
declare -A source_info
getInfo source_info $source


if [ "$device" == "/dev/null" ] ; then
	available_spaceMb=999999
else
	available_spaceMb=$(($(blockdev --getsize64 $device)/1024/1024))
fi
available_spaceGb=$(printf %.2f $((100 * $available_spaceMb / 1024))e-2)
echo "source has ${source_info[used_mb]}Mb, destination has $available_spaceMb Mb available"

if [[ $available_spaceMb -lt ${source_info[used_mb]} ]] ; then
	echo "ERROR: Not enough space on destination, need ${source_info[used_gb]} GB, have $available_spaceGb GB"
	exit 1
fi

 
text="Restoring $image to $device" 

if [[ -z "$bs" ]] ; then
	bs=$defaultsectorsize
fi
sectors_per_block=$(($bs / ${source_info[sector_size]}))
count=$(((${source_info[last_sector]} + 1) / $sectors_per_block ))
if [[ $(($count * $bs)) -lt $((${source_info[sector_size]} * (${source_info[last_sector]} + 1))) ]] ; then
	# need to add an extra block
	echo "Added an extra block..."
	count=$(($count + 1))
fi

cmd="dd if=$source bs=$bs count=$count conv=sparse,noerror,sync status=progress of=$device"
echo
echo "Source image"
echo "-------------------"
echo "${source_info[fdisk_output]}"
echo "-------------------"
echo
if [ "$device" == "/dev/null" ] ; then
	echo "Testing restore to $device"
else
	echo "Device to be restored to:"
	echo "------------------------"
	fdisk -l $device
	echo "------------------------"
fi
if [[ $keepmounted -eq 0 ]]; then
	echo "Will Not keep $image mounted when finished"
else
	echo "Will keep $image mounted on $compressed_mount_dir when finished"
fi
echo
echo "COMMAND: $cmd"
read -p "Continue (y/n)?" choice
case "$choice" in 
	y|Y )	$(eval "$cmd")
		sync
		;;
	n|N ) 	echo "cancelled"
		;;
	* ) 	echo "cancelled"
		;;
esac

if [ ! -z "$compressed_mount_dir" ] ; then
	if [ "$keepmounted" == 1 ] ; then
		echo "$image is still mounted on $compressed_mount_dir, use sudo umount $compressed_mount_dir to unmount it"
	else
		umount $compressed_mount_dir
		rm -d $compressed_mount_dir
	fi
fi
