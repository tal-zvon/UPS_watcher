#!/bin/bash

##################################
######USER EDITABLE SECTION#######
##################################

#The battery percentage below which the computer will start taking action
BATTERY_THRESHOLD_IN_PERCENT='90'

#Log file
LOG='/var/log/UPS_watcher.log'

#Hibernation requires enough swap to save your RAM to it
#If the script detects that you do not have enough swap for this,
#it can create a swap file that it will temporarily use
#Specify where to store this file, or leave blank (SWAP_FILE='')
#not to have a swap file
#SWAP_FILE='/tmp/SWAPFILE'
SWAP_FILE='/home/tal/Desktop/SWAPFILE'

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

#Check if we have enough swap space to hibernate
SwapCheck()
{
	#Only run the following check if we are hibernating
	if echo $SHUTOFF_COMMAND | grep -q hibernate
	then
		#Clear disk cache
		echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

		#Figure out some info about how much RAM, swap, and HDD space we have
		TOTAL_RAM=$(free -m | grep Mem | tr -s ' ' | cut -d ' ' -f 2)
		#Truncated to be a whole number:
		TOTAL_RAM_PLUS_5_PERCENT=$(echo "$TOTAL_RAM * 1.05" | bc | grep -o '^[0-9]*')
		USED_RAM=$(free -m | grep Mem | tr -s ' ' | cut -d ' ' -f 3)
		#Truncated to be a whole number:
		USED_RAM_PLUS_20_PERCENT=$(echo "$USED_RAM * 1.20" | bc | grep -o '^[0-9]*')
		FREE_SWAP=$(free -m | grep Swap | tr -s ' ' | cut -d ' ' -f 4)
		FREE_HDD_SPACE_IN_MB=$(df -BM `dirname $SWAP_FILE` | grep dev | tr -s ' ' | cut -d ' ' -f 4 | grep -o '[0-9]*')

		#Check how much swap space we need
		#This is either:
		#Used RAM + 20%
		#OR
		#Total RAM + 5%
		#whichever is smaller
		MIN_SWAP_SIZE=$(
			if [[ $USED_RAM_PLUS_20_PERCENT -lt $TOTAL_RAM_PLUS_5_PERCENT ]]
			then
				echo "$USED_RAM_PLUS_20_PERCENT"
			else
				echo "$TOTAL_RAM_PLUS_5_PERCENT"
			fi
		)

		#Check if we have enough swap to hibernate
		if [[ $FREE_SWAP -gt $MIN_SWAP_SIZE ]]
		then
			return
		else
			#Not enough swap space for hibernation
			echo "$(date +"%b %e %H:%M:%S"), PID $$: Not enough swap space to hibernate"'!' | tee -a $LOG

			#Check if we are allowed to make a swap file
			if [[ -z $SWAP_FILE ]]
			then
				echo "$(date +"%b %e %H:%M:%S"), PID $$: No swap file specified" | tee -a $LOG
			elif [[ ! -d `dirname $SWAP_FILE` ]]
			then
				#Directory for swap file does NOT exist
				echo "$(date +"%b %e %H:%M:%S"), PID $$: Swap directory ($(dirname $SWAP_FILE)) does not exist"'!' | tee -a $LOG
			else
				#Check if there is enough hard drive space
				#to make a swap file
				if [[ $FREE_HDD_SPACE_IN_MB -gt $MIN_SWAP_SIZE ]]
				then
					#Create swap file
					dd if=/dev/zero of=$SWAP_FILE bs=1M count=$MIN_SWAP_SIZE &&
					mkswap $SWAP_FILE &&
					swapon $SWAP_FILE

					#Check how much swap we have now
					FREE_SWAP=$(free -m | grep Swap | tr -s ' ' | cut -d ' ' -f 4)

					if [[ $FREE_SWAP -gt $MIN_SWAP_SIZE ]]
					then
						return
					else
						#Creating swap file failed
						#Delete it
						echo "$(date +"%b %e %H:%M:%S"), PID $$: Failed to create swap file"'!' | tee -a $LOG
						swapoff $SWAP_FILE &&
						rm -f $SWAP_FILE
					fi
					
				else
					#Not enough space on HDD for swap file
					#Fall back plan (suspend?)
					echo "$(date +"%b %e %H:%M:%S"), PID $$: Not enough space on HDD (only ${FREE_HDD_SPACE_IN_MB}MB) for swap file of size $MIN_SWAP_SIZE"'!' | tee -a $LOG
				fi
			fi

			#If we weren't hibernating in the first place, or swap file creation was successful,
			#we have already returned from this function. If we are at this stage however,
			#something failed and we are going to fallback (suspend)
			echo "$(date +"%b %e %H:%M:%S"), PID $$: Going to fallback plan (suspend)" | tee -a $LOG
			SHUTOFF_COMMAND=$(which pm-suspend)
		fi
	fi
}

#Make sure people read the INSTALL file and don't run the script without cron
if [[ "$@" != "--cron" ]]
then
	echo "This script is not meant to be run manually. Are you really planning to run the script by hand every time there's a power outage? Read the INSTALL.rst file." | fmt -w `tput cols`
	exit 1
fi

#Only run if user is root
uid=$(/usr/bin/id -u) && [ "$uid" = "0" ] ||
{ echo "Only root can run $0, and unless you know what you are doing, only from cron. See INSTALL.rst" | fmt -w `tput cols`; exit 1; }

#Make sure this script is not running already
if [[ `pgrep -cf "/bin/bash [^ ]*$(basename $0)"` -gt 1 ]]
then
	echo "$(date +"%b %e %H:%M:%S"), PID $$: script already running" >> $LOG
	exit 0
#DEBUG:else
#DEBUG:	echo "$(date +"%b %e %H:%M:%S"), PID $$: no script currently running. Proceeding..." >> $LOG
fi

#Check if upower is installed
which upower &>/dev/null || { echo "$(date +"%b %e %H:%M:%S"), PID $$: upower not installed. This script will NOT work without it"'!' | tee -a $LOG; exit 1; }

#Check if we have enough swap space to hibernate (if hibernation is what we want)
SwapCheck

#Check if $SHUTOFF_COMMAND is an actual command
[[ -x "${SHUTOFF_COMMAND}" ]] || { echo "$(date +"%b %e %H:%M:%S"), PID $$: ${SHUTOFF_COMMAND} is not a valid command"'!' | tee -a $LOG; exit 1; }

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
