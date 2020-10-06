#!/bin/sh
# Script to start the backup script "bkup_rpimage.sh" via a simple crontab entry
BACKUPDIR=/mnt/Backup/$(uname -n)/
BACKUPFILE=$(uname -n)-$(date +%F).img

LOGDIR=/var/log/rpimage
LOGFILE=$LOGDIR/rpimage.log

# checking for Log

if [ ! -d "$LOGFILE" ]; then

	if [ ! -d "$LOGDIR" ]; then
		echo "$LOGDIR doesn't exist, creating $LOGDIR"
		mkdir -p -- "$LOGDIR"
	fi
	
	echo "touching $LOGFILE..."
		touch $LOGFILE || exit
else
	echo "LOGFILE $LOGFILE was there..."
fi

# Let target auto mount
if [ -d "$BACKUPDIR" ]; then
	# start script
	/usr/bin/bkup_rpimage.sh start -czd $BACKUPDIR/$BACKUPFILE

else
	echo "Failed starting a backup, $BACKUPDIR doesn't exist:	$(date)" >> $LOGFILE
fi
