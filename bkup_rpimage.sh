#!/bin/bash
#
# Utility script to backup Raspberry Pi's SD Card to a sparse image file
# mounted as a filesystem in a file, allowing for efficient incremental
# backups using rsync
#
# The backup is taken while the system is up, so it's a good idea to stop
# programs and services which modifies the filesystem and needed a consistant state
# of their file.
# Especially applications which use databases needs to be stopped (and the database systems too).
#
#  So it's a smart idea to put all these stop commands in a script and perfom it before
#  starting the backup. After the backup terminates normally you may restart all stopped
#  applications or just reboot the system.
#

VERSION=v1.6
SDCARD=/dev/mmcblk0

setup () {
    #
    # Define some fancy colors only if connected to a terminal.
    # Thus output to file is no more cluttered
    #
        [ -t 1 ] && {
                RED=$(tput setaf 1)
                GREEN=$(tput setaf 2)
                YELLOW=$(tput setaf 3)
                BLUE=$(tput setaf 4)
                MAGENTA=$(tput setaf 5)
                CYAN=$(tput setaf 6)
                WHITE=$(tput setaf 7)
                RESET=$(tput setaf 9)
                BOLD=$(tput bold)
                NOATT=$(tput sgr0)
        }||{
                RED=""
                GREEN=""
                YELLOW=""
                BLUE=""
                MAGENTA=""
                CYAN=""
                WHITE=""
                RESET=""
                BOLD=""
                NOATT=""
        }
        MYNAME=$(basename $0)
}


# Echos traces with yellow text to distinguish from other output
trace () {
    echo -e "${YELLOW}${1}${NOATT}"
}

# Echos en error string in red text and exit
error () {
    echo -e "${RED}${1}${NOATT}" >&2
    exit 1
}

# Creates a sparse "${IMAGE}" clone of ${SDCARD} and attaches to ${LOOPBACK}
do_create () {
    trace "Creating sparse "${IMAGE}", the apparent size of $SDCARD"
    dd if=/dev/zero of="${IMAGE}" bs=${BLOCKSIZE} count=0 seek=${SIZE}

    if [ -s "${IMAGE}" ]; then
        trace "Attaching "${IMAGE}" to ${LOOPBACK}"
        losetup ${LOOPBACK} "${IMAGE}"
    else
        error "${IMAGE} was not created or has zero size"
    fi

    trace "Copying partition table from ${SDCARD} to ${LOOPBACK}"
    parted -s ${LOOPBACK} mklabel msdos
    sfdisk --dump ${SDCARD} | sfdisk --force ${LOOPBACK}

    trace "Formatting partitions"
    partx --add ${LOOPBACK}
    mkfs.vfat -I ${LOOPBACK}p1
    mkfs.ext4 ${LOOPBACK}p2
	clone

}

do_cloneid () {
    # Check if do_create already attached the SD Image
    if [ $(losetup -f) = ${LOOPBACK} ]; then
        trace "Attaching ${IMAGE} to ${LOOPBACK}"
        losetup ${LOOPBACK} "${IMAGE}"
        partx --add ${LOOPBACK}
    fi
    clone
    partx --delete ${LOOPBACK}
    losetup -d ${LOOPBACK}
}

clone () {
    # cloning UUID and PARTUUID
    UUID=$(blkid -s UUID -o value ${SDCARD}p2)
    PTUUID=$(blkid -s PTUUID -o value ${SDCARD})
    e2fsck -f -y ${LOOPBACK}p2
    echo y|tune2fs ${LOOPBACK}p2 -U $UUID
    printf 'p\nx\ni\n%s\nr\np\nw\n' 0x${PTUUID}|fdisk "${LOOPBACK}"
    sync
}

# Mounts the ${IMAGE} to ${LOOPBACK} (if needed) and ${MOUNTDIR}
do_mount () {
    # Check if do_create already attached the SD Image
    if [ $(losetup -f) = ${LOOPBACK} ]; then
        trace "Attaching ${IMAGE} to ${LOOPBACK}"
        losetup ${LOOPBACK} "${IMAGE}"
        partx --add ${LOOPBACK}
    fi

    trace "Mounting ${LOOPBACK}1 and ${LOOPBACK}2 to ${MOUNTDIR}"
    if [ ! -n "${opt_mountdir}" ]; then
        mkdir ${MOUNTDIR}
    fi
    mount ${LOOPBACK}p2 ${MOUNTDIR}
    mkdir -p ${MOUNTDIR}/boot
    mount ${LOOPBACK}p1 ${MOUNTDIR}/boot
}

# Rsyncs content of ${SDCARD} to ${IMAGE} if properly mounted
do_backup () {
    if mountpoint -q ${MOUNTDIR}; then
        trace "Starting rsync backup of / and /boot/ to ${MOUNTDIR}"
        if [ -n "${opt_log}" ]; then
            rsync -aEvx --del --stats --log-file ${LOG} --exclude-from='exclude-file.txt' /boot/ ${MOUNTDIR}/boot/
            rsync -aEvx --del --stats --log-file ${LOG} --exclude-from='exclude-file.txt' / ${MOUNTDIR}/
        else
            rsync -aEvx --del --stats --exclude-from='exclude-file.txt' /boot/ ${MOUNTDIR}/boot/
            rsync -aEvx --del --stats --exclude-from='exclude-file.txt' / ${MOUNTDIR}/
        fi
    else
        trace "Skipping rsync since ${MOUNTDIR} is not a mount point"
    fi
}

do_showdf () {

    echo -n "${GREEN}"
    df -m ${LOOPBACK}p1 ${LOOPBACK}p2
    echo -n "$NOATT"
}

# Unmounts the ${IMAGE} from ${MOUNTDIR} and ${LOOPBACK}
do_umount () {
    trace "Flushing to disk"
    sync; sync

    trace "Unmounting ${LOOPBACK}1 and ${LOOPBACK}2 from ${MOUNTDIR}"
    umount ${MOUNTDIR}/boot
    umount ${MOUNTDIR}
    if [ ! -n "${opt_mountdir}" ]; then
        rmdir ${MOUNTDIR}
    fi

    trace "Detaching ${IMAGE} from ${LOOPBACK}"
    partx --delete ${LOOPBACK}
    losetup -d ${LOOPBACK}
}

# Shrink the ${IMAGE} to the minimal size possible
do_shrink () {
    trace "Shrinking "${IMAGE}

    PARTITION_START=$(fdisk -lu "${IMAGE}" | grep Linux | awk '{print $2}')
    PARTITION_SIZE=$(( $(fdisk -lu "${IMAGE}" | grep Linux | awk '{print $3}') * 1024 ))

    trace "Attaching ${IMAGE} to ${LOOPBACK}"
    losetup ${LOOPBACK} "${IMAGE}" -o $(($PARTITION_START * 512)) --sizelimit $PARTITION_SIZE
    fsck -f ${LOOPBACK}
    resize2fs -M ${LOOPBACK}
    fsck -f ${LOOPBACK}

    PARTITION_NEWSIZE=$( dumpe2fs ${LOOPBACK} 2>/dev/null | grep '^Block count:' | awk '{print $3}' )
    PARTITION_NEWEND=$(( $PARTITION_START + ($PARTITION_NEWSIZE * 8) + 1 ))
    losetup -d ${LOOPBACK}
    echo -e "p\nd\n2\nn\np\n2\n$PARTITION_START\n$PARTITION_NEWEND\np\nw\n" | fdisk "${IMAGE}"
    IMAGE_NEWSIZE=$((($PARTITION_NEWEND + 1) * 512))
    truncate -s $IMAGE_NEWSIZE "${IMAGE}"
}

# Compresses ${IMAGE} to ${IMAGE}.gz using a temp file during compression
do_compress () {
    trace "Compressing ${IMAGE} to ${IMAGE}.gz"
    pv -tpreb "${IMAGE}" | pigz > "${IMAGE}.gz.tmp"
    if [ -s "${IMAGE}.gz.tmp" ]; then
        mv -f "${IMAGE}.gz.tmp" "${IMAGE}.gz"
        if [ -n "${opt_delete}" ]; then
            rm -f "${IMAGE}"
        fi
    fi
}

# Tries to cleanup after Ctrl-C interrupt
ctrl_c () {
    trace "Ctrl-C detected."

    if [ -s "${IMAGE}.gz.tmp" ]; then
        rm "${IMAGE}.gz.tmp"
    else
        do_umount
    fi

    if [ -n "${opt_log}" ]; then
        trace "See rsync log in ${LOG}"
    fi

    error "SD Image backup process interrupted"
}

# Prints usage information
usage () {
    cat <<-EOF

    ${MYNAME} ${VERSION} by jinx

    Usage:

        ${MYNAME} ${BOLD}start${NOATT} [-clzdf] [-L logfile] [-i sdcard] sdimage
        ${MYNAME} ${BOLD}mount${NOATT} [-c] sdimage [mountdir]
        ${MYNAME} ${BOLD}umount${NOATT} sdimage [mountdir]
        ${MYNAME} ${BOLD}pigz${NOATT} [-df] sdimage

        Commands:

            ${BOLD}start${NOATT}      starts complete backup of RPi's SD Card to 'sdimage'
            ${BOLD}mount${NOATT}      mounts the 'sdimage' to 'mountdir' (default: /mnt/'sdimage'/)
            ${BOLD}umount${NOATT}     unmounts the 'sdimage' from 'mountdir'
            ${BOLD}pigz${NOATT}       compresses the 'sdimage' to 'sdimage'.gz
            ${BOLD}cloneid${NOATT}    clones the UUID/PTUUID from the actual disk to the image
            ${BOLD}shodf${NOATT}      shows allocation of the image

        Options:

            ${BOLD}-c${NOATT}         creates the SD Image if it does not exist
            ${BOLD}-l${NOATT}         writes rsync log to 'sdimage'-YYYYmmddHHMMSS.log
            ${BOLD}-z${NOATT}         compresses the SD Image (after backup) to 'sdimage'.gz
            ${BOLD}-d${NOATT}         deletes the SD Image after successful compression
            ${BOLD}-f${NOATT}         forces overwrite of 'sdimage'.gz if it exists
            ${BOLD}-L logfile${NOATT} writes rsync log to 'logfile'
            ${BOLD}-i sdcard${NOATT}  specifies the SD Card location (default: $SDCARD)
            ${BOLD}-s Mb${NOATT}      specifies the size of image in MB (default: Size of $SDCARD)

    Examples:

        ${MYNAME} start -c /path/to/rpi_backup.img
            starts backup to 'rpi_backup.img', creating it if it does not exist

        ${MYNAME} start -c -s 8000 /path/to/rpi_backup.img
            starts backup to 'rpi_backup.img', creating it
            with a size of 8000mb if it does not exist

        ${MYNAME} start /path/to/\$(uname -n).img
            uses the RPi's hostname as the SD Image filename

        ${MYNAME} start -cz /path/to/\$(uname -n)-\$(date +%Y-%m-%d).img
            uses the RPi's hostname and today's date as the SD Image filename,
            creating it if it does not exist, and compressing it after backup

        ${MYNAME} mount /path/to/\$(uname -n).img /mnt/rpi_image
            mounts the RPi's SD Image in /mnt/rpi_image

        ${MYNAME} umount /path/to/raspi-$(date +%Y-%m-%d).img
            unmounts the SD Image from default mountdir (/mnt/raspi-$(date +%Y-%m-%d).img/)

EOF
}

setup

# Read the command from command line
case ${1} in
    start|mount|umount|shrink|pigz|cloneid|showdf) 
        opt_command=${1}
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    --version)
        trace "${MYNAME} ${VERSION} by jinx"
        exit 0
        ;;
    *)
        error "Invalid command or option: ${1}\nSee '${MYNAME} --help' for usage";;
esac
shift 1

# Make sure we have root rights
if [ $(id -u) -ne 0 ]; then
    error "Please run as root. Try sudo."
fi

# Default size, can be overwritten by the -s option
SIZE=$(blockdev --getsz $SDCARD)
BLOCKSIZE=$(blockdev --getss $SDCARD)

# Read the options from command line
while getopts ":czrdflL:i:s:" opt; do
    case ${opt} in
        c)  opt_create=1;;
        z)  opt_compress=1;;
        r)  opt_shrink=1;;
        d)  opt_delete=1;;
        f)  opt_force=1;;
        l)  opt_log=1;;
        L)  opt_log=1
            LOG=${OPTARG}
            ;;
        i)  SDCARD=${OPTARG};;
        s)  SIZE=${OPTARG}
            BLOCKSIZE=1M ;;
        \?) error "Invalid option: -${OPTARG}\nSee '${MYNAME} --help' for usage";;
        :)  error "Option -${OPTARG} requires an argument\nSee '${MYNAME} --help' for usage";;
    esac
done
shift $((OPTIND-1))

# Read the sdimage path from command line
IMAGE=${1}
if [ -z "${IMAGE}" ]; then
    error "No sdimage specified"
fi

# Check if sdimage exists
if [ ${opt_command} = umount ] || [ ${opt_command} = pigz ]; then
    if [ ! -f "${IMAGE}" ]; then
        error "${IMAGE} does not exist"
    fi
else
    if [ ! -f "${IMAGE}" ] && [ ! -n "${opt_create}" ]; then
        error "${IMAGE} does not exist\nUse -c to allow creation"
    fi
fi

# Check if we should compress and sdimage.gz exists
if [ -n "${opt_compress}" ] || [ ${opt_command} = pigz ]; then
    if [ -s "${IMAGE}".gz ] && [ ! -n "${opt_force}" ]; then
        error "${IMAGE}.gz already exists\nUse -f to force overwriting"
    fi
fi

# Define default rsync logfile if not defined
if [ -z ${LOG} ]; then
    LOG="${IMAGE}-$(date +%Y%m%d%H%M%S).log"
fi

# Identify which loopback device to use
LOOPBACK=$(losetup -j "${IMAGE}" | grep -o ^[^:]*)
if [ ${opt_command} = umount ]; then
    if [ -z ${LOOPBACK} ]; then
        error "No /dev/loop<X> attached to ${IMAGE}"
    fi
elif [ ! -z ${LOOPBACK} ]; then
    error "${IMAGE} already attached to ${LOOPBACK} mounted on $(grep ${LOOPBACK}p2 /etc/mtab | cut -d ' ' -f 2)/"
else
    LOOPBACK=$(losetup -f)
fi


# Read the optional mountdir from command line
MOUNTDIR=${2}
if [ -z ${MOUNTDIR} ]; then
    MOUNTDIR=/mnt/$(basename "${IMAGE}")/
else
    opt_mountdir=1
    if [ ! -d ${MOUNTDIR} ]; then
        error "Mount point ${MOUNTDIR} does not exist"
    fi
fi

# Check if default mount point exists
if [ ${opt_command} = umount ]; then
    if [ ! -d ${MOUNTDIR} ]; then
        error "Default mount point ${MOUNTDIR} does not exist"
    fi
else
    if [ ! -n "${opt_mountdir}" ] && [ -d ${MOUNTDIR} ]; then
        error "Default mount point ${MOUNTDIR} already exists"
    fi
fi

# Trap keyboard interrupt (ctrl-c)
trap ctrl_c SIGINT SIGTERM

# Check for dependencies
for c in dd losetup parted sfdisk partx mkfs.vfat mkfs.ext4 mountpoint rsync; do
    command -v ${c} >/dev/null 2>&1 || error "Required program ${c} is not installed"
done
if [ -n "${opt_compress}" ] || [ ${opt_command} = pigz ]; then
    for c in pv pigz; do
        command -v ${c} >/dev/null 2>&1 || error "Required program ${c} is not installed"
    done
fi

# Do the requested functionality
case ${opt_command} in
    start)
            trace "Starting SD Image backup process"
            if [ ! -f "${IMAGE}" ] && [ -n "${opt_create}" ]; then
                do_create
            fi
            do_mount
            do_backup
            do_showdf
            do_umount
            if [ -n "${opt_shrink}" ]; then
                do_shrink
            fi
            if [ -n "${opt_compress}" ]; then
                do_compress
            fi
            trace "SD Image backup process completed."
            if [ -n "${opt_log}" ]; then
                trace "See rsync log in ${LOG}"
            fi
            ;;
    mount)
            if [ ! -f "${IMAGE}" ] && [ -n "${opt_create}" ]; then
                do_create
            fi
            do_mount
            trace "SD Image has been mounted and can be accessed at:\n    ${MOUNTDIR}"
            ;;
    umount)
            do_umount
            ;;
    shrink)
            do_shrink
            ;;
    pigz)
            do_compress
            ;;
    cloneid)
            do_cloneid
            ;;
    showdf)
            do_mount
            do_showdf
            do_umount
            ;;
    *)
            error "Unknown command: ${opt_command}"
            ;;
esac

exit 0
