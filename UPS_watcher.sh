#!/bin/bash

##################################
######USER EDITABLE SECTION#######
##################################

#The battery percentage below which the computer will start taking action
BATTERY_THRESHOLD_IN_PERCENT='20'

#Log file
LOG='/var/log/UPS_watcher.log'

#Code to run before hibernating
BeforeHibernation()
{
		#A function cannot be empty. If you don't want the script to do anything other than hibernate,
		#leave the following echo line in place
		echo -n ''
}

#Code to run after power is restored
AfterHibernation()
{

		#A function cannot be empty. If you don't want the script to do anything other than stop hibernating,
		#leave the following echo line in place
		echo -n ''
}

##################################
###END OF USER EDITABLE SECTION###
##################################

#Make sure this script is not running already
if [[ `pgrep -cf "/bin/bash [^ ]*$(basename $0)"` -gt 1 ]]
then
#DEBUG:	echo "PID $$: script already running" >> $LOG
	exit 0
#DEBUG:else
#DEBUG:	echo "PID $$: no script currently running. Proceeding..." >> $LOG
fi

#Check if upower is installed
which upower &>/dev/null || { echo 'upower not installed. This script will NOT work without it!'; exit 1; }

#Keep checking the UPS status until power returns to it
while [[ true ]]
do
	#Make sure that the battery is below $BATTERY_THRESHOLD_IN_PERCENT and that the UPS is still on battery power before taking action
	if [[ $(upower -d | grep percentage | grep -o '[0-9]*') -lt $BATTERY_THRESHOLD_IN_PERCENT ]] && [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "yes" ]]
	then
		#Hibernate (or sleep or w/e)
#DEBUG:		echo "PID $$: hibernating..." >> $LOG
		#Run BeforeHibernation function
		BeforeHibernation
		
		#Hibernate
		#Right now, the script is using a suspend/hibernate hybrid, where the system is suspended, and after a certain period of time, the system
		#hibernates. Ideally, the script would do a true hybrid, where it prepares to hibernate and suspends. In that case, if power is restored
		#before the UPS runs out of battery life, the system would wake up quickly. If the UPS runs out of power while the system is suspended,
		#the next time it is powered up, it will restore all programs that were running. This functionality has been added to Linux kernel 3.6.
		#I'll have to see if it can easily be done on older kernels
		sudo pm-suspend-hybrid
		
		#After the computer wakes up, give upower 2 minutes to update its status to make sure it doesn't still say
		#that the UPS is on battery power if it's not
#DEBUG:		echo "PID $$: Computer just woke up. Waiting 120s" >> $LOG
		sleep 120
	fi

	#Exit script if the UPS gets power again
	if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "no" ]]
	then
#DEBUG:		echo "PID $$: Power restored" >> $LOG
		break
#DEBUG:	else
#DEBUG:		echo "PID $$: Still on battery. Waiting 30s..." >> $LOG
	fi

	#Wait before checking percentage again
	sleep 30
done

exit 0
