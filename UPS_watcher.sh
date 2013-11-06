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
SHUTOFF_COMMAND='pm-suspend'

#Code to run before hibernating
BeforeHibernation()
{
		#A function cannot be empty. If you don't want the script to do anything other than hibernate,
		#leave the following echo line in place
		echo -n ''
		date >> /home/mint/Desktop/BeforeHibernation
}

#Code to run after power is restored
AfterHibernation()
{

		#A function cannot be empty. If you don't want the script to do anything other than stop hibernating,
		#leave the following echo line in place
		echo -n ''
		date >> /home/mint/Desktop/AfterHibernation
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
	#Check if battery is below $BATTERY_THRESHOLD_IN_PERCENT
	if [[ $(upower -d | grep percentage | grep -o '[0-9]*') -lt $BATTERY_THRESHOLD_IN_PERCENT ]]
	then
		echo "PID $$: battery is below the ${BATTERY_THRESHOLD_IN_PERCENT}% threshold" >> $LOG

		#Check if UPS is still on battery power
		if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "yes" ]]
		then
			echo "PID $$: UPS is on battery. Running pre-hibernation code..." >> $LOG
	                #Run BeforeHibernation function
	                BeforeHibernation

			#Hibernate
			${SHUTOFF_COMMAND}

			#After the computer wakes up, give upower 2 minutes to update its status to make sure it doesn't still say
			#that the UPS is on battery power if it's not
			echo "PID $$: Computer just woke up. Waiting 120s" >> $LOG
			sleep 120

			#Check if UPS has power again
			if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "no" ]]
			then
				#Run AfterHibernation function
				AfterHibernation
				break
			else
				#Give it another 30 seconds, and run the while loop again
				sleep 30
			fi
		else
			echo "PID $$: Power restored" >> $LOG
			break
		fi
	else
		echo "PID $$: battery is still above the ${BATTERY_THRESHOLD_IN_PERCENT}% threshold. Waiting 30 seconds..." >> $LOG
		sleep 30
	fi
done

exit 0
