#!/bin/bash

##################################
######USER EDITABLE SECTION#######
##################################

#The battery percentage below which the computer will start taking action
BATTERY_THRESHOLD_IN_PERCENT='20'

#Log file
LOG='/var/log/UPS_watcher.log'

#Command to hibernate. This can be changed to something like '/sbin/poweroff',
#'/usr/sbin/pm-hibernate', '/usr/sbin/pm-suspend', '/usr/sbin/pm-suspend-hybrid', or anything else you want
#Make sure to use the full path here!
SHUTOFF_COMMAND='/usr/sbin/pm-hibernate'

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
	echo "$(date +"%b %e %H:%M:%S"), PID $$: script already running" >> $LOG
	exit 0
#DEBUG:else
#DEBUG:	echo "$(date +"%b %e %H:%M:%S"), PID $$: no script currently running. Proceeding..." >> $LOG
fi

#Check if upower is installed
which upower &>/dev/null || { echo 'upower not installed. This script will NOT work without it!'; exit 1; }

#This boolean variable is set to true if the BeforeHibernation code ran
#indicating that the AfterHibernation code should run too
PREHIB_RAN=false

#Keep checking the UPS status until power returns to it
while [[ true ]]
do
	#Check if UPS is still on battery power
	if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "yes" ]]
	then
		#Check if battery is below $BATTERY_THRESHOLD_IN_PERCENT
		if [[ $(upower -d | grep percentage | grep -o '[0-9]*') -lt $BATTERY_THRESHOLD_IN_PERCENT ]]
		then
			echo "$(date +"%b %e %H:%M:%S"), PID $$: UPS battery is below the ${BATTERY_THRESHOLD_IN_PERCENT}% threshold, and the UPS is still running on battery power. Running pre-hibernation code..." >> $LOG
	                #Run BeforeHibernation function
	                BeforeHibernation

			#Set PREHIB_RAN variable to true to indicate the BeforeHibernation function ran
			PREHIB_RAN=true

			#Hibernate
			echo "$(date +"%b %e %H:%M:%S"), PID $$: Hibernating..." >> $LOG
			${SHUTOFF_COMMAND}

			#After the computer wakes up, give upower 2 minutes to update its status to make sure it doesn't still say
			#that the UPS is on battery power if it's not
			echo "$(date +"%b %e %H:%M:%S"), PID $$: Computer just woke up. Waiting 120s" >> $LOG
			sleep 120

			#Check if UPS has power again
			if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "no" ]]
			then
				echo "$(date +"%b %e %H:%M:%S"), PID $$: Power restored" >> $LOG
				break
			else
				echo "$(date +"%b %e %H:%M:%S"), PID $$: UPS still running off of battery. If it doesn't come back online in 30 seconds, the computer is going into hibernation again as soon as it's below the threshold." >> $LOG
				#Give it another 30 seconds, and run the while loop again
				sleep 30
			fi
		else
			echo "$(date +"%b %e %H:%M:%S"), PID $$: battery is still above the ${BATTERY_THRESHOLD_IN_PERCENT}% threshold. Waiting 30 seconds..." >> $LOG
			sleep 30
		fi
	else
		echo "$(date +"%b %e %H:%M:%S"), PID $$: Power restored before hibernation could take place" >> $LOG
		break
	fi
done

#Check if AfterHibernation function should run (if BeforeHibernation function ran)
if $PREHIB_RAN
then
	#Run AfterHibernation function
	AfterHibernation
	echo "$(date +"%b %e %H:%M:%S"), PID $$: post-hibernation code execution complete" >> $LOG
fi
echo "$(date +"%b %e %H:%M:%S"), PID $$: Exiting..." >> $LOG

exit 0
