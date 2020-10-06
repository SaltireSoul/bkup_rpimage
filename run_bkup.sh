#!/bin/sh
# Script zum Starten des Backup-Scriptes "bkup_rpimage.sh" via einfachem Crontab-Eintrag
BACKUPDIR=/mnt/Backup/$(uname -n)/
BACKUPFILE=$(uname -n)-$(date +%F).img

LOGDIR=/var/log/rpimage
LOGFILE=$LOGDIR/rpimage.log

# checking for Log

if [ ! -d "$LOGFILE" ]; then

	if [ ! -d "$LOGDIR" ]; then
		echo "LOGDIR not existant, creating $LOGDIR"
		mkdir -p -- "$LOGDIR"
	fi
	
	echo "touching $LOGFILE..."
		touch $LOGFILE || exit
else
	echo "LOGFILE $LOGFILE was there..."
fi

# Target automounten lassen:
if [ -d "$BACKUPDIR" ]; then
	# script starten
	/usr/bin/bkup_rpimage.sh start -czd $BACKUPDIR/$BACKUPFILE

else
	echo "Tried starting a backup, $BACKUPDIR not existant:	$(date)" >> $LOGFILE
fi
