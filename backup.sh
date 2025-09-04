#!/bin/bash
if [ ! -f utils.cfg ] ; then
	echo "Unable to find utils.cfg"
	exit 1
fi

. ./utils.cfg --source-only

declare bs intval
defaultsectorsize=65536
version=1.0

usage ()
{
	printf "Backs up a device to an image file (V$version)
Usage: backup.sh --device <device to backup> --image <image to backup to> [--compress] [--blocksize <size>]
\t(-d | -- device <device>)    The device to backup (required)
\t(-i | --image <image>)       The file to backup to (required)
\t(-c | --compress)            Compress the backup file (optional, default no compression)
\t(-bs | --blocksize <size>    The block size in bytes to use (optonal, default is $defaultsectorsize). Pick a size divisible by the sector size
\t(-h | -- help)               Print this help
\t(-v | --version)             Print the version\n"
}

device=
image=
compress=0
bs=$defaultsectorsize

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
		-c | --compress )	compress=1
					;;
		-bs | --blocksize )	shift
					bs=$1
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
	echo "ERROR: Bad block size, needs to be a sensible integer"
	exit 1
fi
if [ "$device" == "" ] ; then
	echo 'ERROR: You need to specify a device like /dev/sda'
	usage
	exit 1
fi
if [ ! -b $device ] ; then
	echo "ERROR: $device does not exist"
	exit 1
fi
if [ "$image" == "" ] ; then
	echo 'ERROR: You need to specify a backup file like /mnt/backup/image.img'
	usage
	exit 1
fi
if [ -f $image ] ; then
	echo "ERROR: $image already exists."
	exit 1
fi

touch $image > /dev/null
if (( $? != 0 )) ; then
	echo "ERROR: $image is not a valid device/file name or cannot be written to."
	exit 1
fi
rm -f $image

declare -A device_info
getInfo device_info $device

available_spaceMb=$(($(stat -f --format="%a*%S" $(dirname $image))/1024/1024))
available_spaceGb=$(printf %.2f $((100 * $available_spaceMb / 1024))e-2)
if [[ $available_spaceMb -lt ${device_info[used_mb]} ]]
then
	echo "ERROR: Not enough space on destination, need $total_sizeGb GB, have ${device_info[used_mb]} GB"
	exit 1
fi
 
text="Backing up $device to $image" 

if (( $compress == 0 )); then
	output=" of=$image"
else
	output=" | gzip > $image.gz"
	text="$text.gz"
fi

if [[ -z "$bs" ]] ; then
	bs=$defaultsectorsize
fi
sectors_per_block=$(($bs / ${device_info[sector_size]}))
count=$(((${device_info[last_sector]} + 1) / $sectors_per_block ))
if [[ $(($count * $bs)) -lt $((${device_info[sector_size]} * (${device_info[last_sector]} + 1))) ]] ; then
	# need to add an extra block
	echo "Added an extra block..."
	count=$(($count + 1))
fi

cmd="dd if=$device bs=$bs count=$count conv=sparse,noerror,sync status=progress $output"

echo "Device to be backed up:"
echo "-----------------------"
fdisk -l $device
echo "-----------------------"
echo
echo $text
echo "${device_info[no_of_partitions]} partitions, total size ${device_info[used_gb]} GB (${device_info[last_sector]} sectors of ${device_info[sector_size]} B)"
echo "Available space for backup $available_spaceGb GB"
echo "COMMAND: $cmd"
isMounted $device -q
if [[ $? -eq 0 ]] ; then
	echo "Warning: $device is mounted!"
fi
read -p "Continue (y/n)?" choice
case "$choice" in 
	y|Y ) ;;
	n|N ) echo "cancelled"; exit 1;;
	* ) echo "cancelled"; exit 1;;
esac

$(eval "$cmd")
sync

