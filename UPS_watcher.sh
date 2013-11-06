#!/bin/bash

##################################
######USER EDITABLE SECTION#######
##################################

#The battery percentage below which the computer will start taking action
BATTERY_THRESHOLD_IN_PERCENT='20'

#Log file
LOG='/var/log/UPS_watcher.log'

#Command to hibernate. This can be changed to something like 'poweroff',
#'pm-hibernate', 'pm-suspend', 'pm-suspend-hybrid', or anything else you want
SHUTOFF_COMMAND='pm-hibernate'

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
	echo "PID $$: script already running" >> $LOG
	exit 0
else
	echo "PID $$: no script currently running. Proceeding..." >> $LOG
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
		echo "PID $$: hibernating..." >> $LOG
		#Run BeforeHibernation function
		BeforeHibernation
		
		#Hibernate
		${SHUTOFF_COMMAND}
		
		#After the computer wakes up, give upower 2 minutes to update its status to make sure it doesn't still say
		#that the UPS is on battery power if it's not
		echo "PID $$: Computer just woke up. Waiting 120s" >> $LOG
		sleep 120
	fi

	#Exit script if the UPS gets power again
	if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "no" ]]
	then
		echo "PID $$: Power restored" >> $LOG
		#Run AfterHibernation function
		AfterHibernation
		break
	else
		echo "PID $$: Still on battery. Waiting 30s..." >> $LOG
	fi

	#Wait before checking percentage again
	sleep 30
done

exit 0
