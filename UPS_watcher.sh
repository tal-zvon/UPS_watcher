#!/bin/bash

##################################
######USER EDITABLE SECTION#######
##################################

#The battery percentage below which the computer will start taking action
BATTERY_THRESHOLD_IN_PERCENT='20'

#Log file
LOG='/var/log/UPS_watcher.log'

#Hibernation requires enough swap space to save your RAM to it
#If you have no swap partition, you can use a temporary swap file
#that will be created every time the system needs to hibernate, and
#destroyed right after it comes out of hibernation
#To see how to do this, read the 'Using a swap file' section of INSTALL.rst
ENABLE_SWAP=false

#Location for the temporary swap file
SWAP_FILE='/swap'

#Command to hibernate. This can be changed to something like '/sbin/poweroff',
#'/usr/sbin/pm-hibernate', '/usr/sbin/pm-suspend', '/usr/sbin/pm-suspend-hybrid', or anything else you want
#Make sure to use the full path here!
SHUTOFF_COMMAND='/usr/sbin/pm-hibernate'

#Code to run before hibernating
BeforeHibernation()
{ :
	#Put any code you want to run before hibernation happens here
}

#Code to run after power is restored
AfterHibernation()
{ :
	#Put any code you want to run after power is restored here
}

##################################
###END OF USER EDITABLE SECTION###
##################################

#Create swap file
CreateSwap()
{
	#Check if uswsusp is installed
	if ! type s2disk &>/dev/null
	then
		echo "$(date +"%b %e %H:%M:%S"), PID $$: uswsusp does not appear to be installed. Cannot hibernate from swap image without it"'!'" See INSTALL.rst" | tee -a $LOG
		echo "$(date +"%b %e %H:%M:%S"), PID $$: Going to fallback plan (suspend)" | tee -a $LOG

		SHUTOFF_COMMAND=$(which pm-suspend)
		echo "$(date +"%b %e %H:%M:%S"), PID $$: Suspending..." >> $LOG

		return
	fi

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
	#If SWAP_FILE is empty, it will get cought later on and the FREE_HDD_SPACE_IN_MB var won't
	#be used anyway, so this prevents dirname from showing an error when SWAP_FILE is empty
	[[ -n $SWAP_FILE ]] && FREE_HDD_SPACE_IN_MB=$(df -BM `dirname $SWAP_FILE` | grep dev | tr -s ' ' | cut -d ' ' -f 4 | grep -o '[0-9]*')

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

	#Check if we are able to make a swap file
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
			echo "$(date +"%b %e %H:%M:%S"), PID $$: Creating swap file at $SWAP_FILE" | tee -a $LOG

			fallocate -l ${MIN_SWAP_SIZE}m ${SWAP_FILE} &&
			mkswap ${SWAP_FILE} >/dev/null &&
			echo "${SWAP_FILE}	swap	swap	defaults	0	0" >> /etc/fstab &&
			swapon ${SWAP_FILE} &&
			if [[ -e /etc/uswsusp.conf ]]
			then
				#Update 'resume offset'
				sed -i '/resume offset =/d' /etc/uswsusp.conf
				swap-offset ${SWAP_FILE} >> /etc/uswsusp.conf
				dpkg-reconfigure -fnoninteractive uswsusp &>/dev/null
			else
				dpkg-reconfigure -fnoninteractive uswsusp &>/dev/null
				#Update 'resume offset'
				sed -i '/resume offset =/d' /etc/uswsusp.conf
				swap-offset ${SWAP_FILE} >> /etc/uswsusp.conf
			fi

			#Check how much swap we have now
			FREE_SWAP=$(free -m | grep Swap | tr -s ' ' | cut -d ' ' -f 4)

			#Check if swap file created successfully
			#If you started out with 0 swap, and you just added MIN_SWAP_SIZE, you might have
			#slightly less free swap than MIN_SWAP_SIZE
			if [[ $FREE_SWAP -gt `expr $MIN_SWAP_SIZE - 100` ]]
			then
				echo "$(date +"%b %e %H:%M:%S"), PID $$: Hibernating..." >> $LOG

				#Change to the uswsusp way of hibernating,
				#which allows for hibernating from a swap file
				SHUTOFF_COMMAND=$(which s2disk)
				return
			else
				echo "$(date +"%b %e %H:%M:%S"), PID $$: Failed to create swap file"'!' >> $LOG

				#Undo what we did with swap file
				if [[ -e $SWAP_FILE ]]
				then
					swapoff $SWAP_FILE 2>/dev/null &&
					rm -f $SWAP_FILE
					sed -i '\#$SWAP_FILE#d' /etc/fstab
					sed -i '/resume offset =/d' /etc/uswsusp.conf
				fi
			fi
		else
			#Not enough space on HDD for swap file
			echo "$(date +"%b %e %H:%M:%S"), PID $$: Not enough space on HDD (only ${FREE_HDD_SPACE_IN_MB}MB) for swap file of size ${MIN_SWAP_SIZE}MB"'!' | tee -a $LOG
		fi
	fi

	#If swap file creation was successful, we have already returned from this function.
	#If we are at this stage however, something failed and we are going to fallback (suspend)
	echo "$(date +"%b %e %H:%M:%S"), PID $$: Going to fallback plan (suspend)" | tee -a $LOG
	SHUTOFF_COMMAND=$(which pm-suspend)

	echo "$(date +"%b %e %H:%M:%S"), PID $$: Suspending..." >> $LOG
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

#Make sure swap file doesn't already exist, and isn't mounted
if [[ `swapon -s | wc -l` -gt 1 ]]
then
	#Swap file exists, and is mounted
	IFS=$'\n'
	for LINE in $(swapon -s | grep -v Filename | sed -e 's/\t.*//g' -e 's/  .*//g')
	do
		swapoff $LINE && 2>/dev/null
		rm -f $LINE 2>/dev/null
	done

	sed -i '/swap/d' /etc/fstab 2>/dev/null
	sed -i '/resume offset =/d' /etc/uswsusp.conf 2>/dev/null
fi

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

			#Check if we are hibernating, suspening, or something else
			if echo $SHUTOFF_COMMAND | grep -q hibernate || echo $SHUTOFF_COMMAND | grep -q s2disk
			then
				#Check if we should make a swap file
				if $ENABLE_SWAP
				then
					CreateSwap
				else
					#Check if we have enough swap to hibernate
					#Check how much swap we have now
					FREE_SWAP=$(free -m | grep Swap | tr -s ' ' | cut -d ' ' -f 4)

					#Check how much ram we have now
					TOTAL_RAM=$(free -m | grep Mem | tr -s ' ' | cut -d ' ' -f 2)

					#Check if we have more SWAP than RAM
					if [[ $FREE_SWAP -gt $TOTAL_RAM ]]
					then
						echo "$(date +"%b %e %H:%M:%S"), PID $$: Hibernating..." >> $LOG	
					else
						echo "$(date +"%b %e %H:%M:%S"), PID $$: Not enough free swap space to hibernate"'!' | tee -a $LOG
						echo "$(date +"%b %e %H:%M:%S"), PID $$: Going to fallback plan (suspend)" | tee -a $LOG
						SHUTOFF_COMMAND=$(which pm-suspend)

						echo "$(date +"%b %e %H:%M:%S"), PID $$: Suspending..." >> $LOG
					fi
				fi
			elif echo $SHUTOFF_COMMAND | grep -q 'suspend$'
			then
				echo "$(date +"%b %e %H:%M:%S"), PID $$: Suspending..." >> $LOG
			else
				echo "$(date +"%b %e %H:%M:%S"), PID $$: Running ${SHUTOFF_COMMAND}..." >> $LOG
			fi

			#Hibernate
			${SHUTOFF_COMMAND}

			#After the computer wakes up, give upower 2 minutes to update its status to make sure it doesn't still say
			#that the UPS is on battery power if it's not
			echo "$(date +"%b %e %H:%M:%S"), PID $$: Computer just woke up. Waiting up to 120s for update to battery status" >> $LOG
			for VAR in {1..120}
			do
				sleep 1
				[[ $(upower -d | grep on-battery | grep -o "yes\|no") == "no" ]] && break
			done

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

#Check if we should remove SWAP_FILE
if [[ -e $SWAP_FILE ]]
then
	echo "$(date +"%b %e %H:%M:%S"), PID $$: Removing temp swap file..." >> $LOG
	swapoff $SWAP_FILE &&
	rm -f $SWAP_FILE
	sed -i '\#$SWAP_FILE#d' /etc/fstab
	sed -i '/resume offset =/d' /etc/uswsusp.conf
fi

echo "$(date +"%b %e %H:%M:%S"), PID $$: Exiting..." >> $LOG

exit 0
