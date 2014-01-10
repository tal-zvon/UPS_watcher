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
#You can also include any arguments to the command
#Make sure to use the full path here!
SHUTOFF_COMMAND='/usr/sbin/pm-hibernate'

#Set to 'false' to show log files on stdout and write them to $LOG
#Set to 'true' to only write them to $LOG
QUIET=true

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

#Either ouput logs to $LOG file only, or to stdout
#as well, depending on what $QUIET is set to
LOGGER()
{
	if $QUIET
	then
		echo "$(date +"%b %e %H:%M:%S"), PID $$: $@" >> $LOG
	else
		echo "$(date +"%b %e %H:%M:%S"), PID $$: $@" | tee -a $LOG
	fi
}

#Log that we are suspending instead of doing what they asked for
#and change SHUTOFF_COMMAND to suspend
SuspendFallback()
{
	LOGGER "Going to fallback plan (suspend)"

	SHUTOFF_COMMAND=$(which pm-suspend)
	LOGGER "Suspending..."
}

#Create swap file
CreateSwap()
{
	#Check if uswsusp is installed
	if ! type s2disk &>/dev/null
	then
		LOGGER "uswsusp does not appear to be installed. Cannot hibernate from swap image without it"'!'" See INSTALL.rst"

		#Log that we are suspending
		SuspendFallback
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
	#or the directory doesn't exist
	[[ -n $SWAP_FILE ]] && [[ -d `dirname $SWAP_FILE` ]] && FREE_HDD_SPACE_IN_MB=$(df -BM `dirname $SWAP_FILE` | grep dev | tr -s ' ' | cut -d ' ' -f 4 | grep -o '[0-9]*')

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
		LOGGER "No swap file specified"
		#Switch SHUTOFF_COMMAND to suspend
		SuspendFallback
		return
	elif [[ ! -d `dirname $SWAP_FILE` ]]
	then
		#Directory for swap file does NOT exist
		LOGGER "Swap directory ($(dirname $SWAP_FILE)) does not exist"'!'
		#Switch SHUTOFF_COMMAND to suspend
		SuspendFallback
		return
	else
		#Check if there is enough hard drive space
		#to make a swap file
		if [[ $FREE_HDD_SPACE_IN_MB -gt $MIN_SWAP_SIZE ]]
		then
			LOGGER "Creating swap file at $SWAP_FILE"

			fallocate -l ${MIN_SWAP_SIZE}m ${SWAP_FILE} &&
			mkswap ${SWAP_FILE} >/dev/null &&
			echo "${SWAP_FILE}	swap	swap	defaults	0	0" >> /etc/fstab &&
			swapon ${SWAP_FILE} &&
			if [[ -e /etc/uswsusp.conf ]]
			then
				#uswsusp.conf exists. Update its 'resume offset'
				sed -i '/resume offset =/d' /etc/uswsusp.conf
				swap-offset ${SWAP_FILE} >> /etc/uswsusp.conf
				dpkg-reconfigure -fnoninteractive uswsusp &>/dev/null
			else
				#uswsusp.conf doesn't exist. Let dpkg-reconfigure create it
				#then update its 'resume offset'
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
				LOGGER "Hibernating..."

				#If we are actually hibernating, add line to /etc/rc.local that will ensure that
				#if the machine doesn't come back from hibernation (crashes during hibernation)
				#on next boot, the swap file will still be removed
				grep -q swap /etc/rc.local || sed -i '$i if [ \$(swapon -s | wc -l) -gt 1 ]; then IFS=\$(echo -en "\\n\\b"); for LINE in \$(swapon -s | grep -v Filename | sed -e "s/\t.*//g" -e "s/  .*//g"); do swapoff \$LINE && 2>/dev/null; rm -f \$LINE 2>/dev/null; done; sed -i "/swap/d" /etc/fstab 2>/dev/null; sed -i "/resume offset =/d" /etc/uswsusp.conf 2>/dev/null; fi; sed -i "/swap/d" /etc/rc.local' /etc/rc.local

				#pm-hibernate does NOT support swap files. If pm-hibernate or pm-suspend-both is
				#being used, change to the uswsusp way of hibernating which allows for hibernating
				#from a swap file
				echo $SHUTOFF_COMMAND | grep -q 'pm-' && SHUTOFF_COMMAND=$(which hibernate 2>/dev/null || which s2disk)
				return
			else
				LOGGER "Failed to create swap file"'!'

				#Undo what we did with swap file
				DEL_SWAP_FILES

				#Change SHUTOFF_COMMAND to suspend
				SuspendFallback
				return
			fi
		else
			#Not enough space on HDD for swap file
			LOGGER "Not enough space on HDD (only ${FREE_HDD_SPACE_IN_MB}MB) for swap file of size ${MIN_SWAP_SIZE}MB"'!'
			#Change SHUTOFF_COMMAND to suspend
			SuspendFallback
			return
		fi
	fi

	#If swap file creation was successful, we have already returned from this function.
	#If we are at this stage however, something failed and we are going to fallback (suspend)
	SuspendFallback
}

#Make sure swap file doesn't already exist, and isn't mounted
DEL_SWAP_FILES()
{
	SWAP_FOUND=false

	if [[ `swapon -s | wc -l` -gt 1 ]]
	then
		#Swap file exists, and is mounted
		IFS=$'\n'
		for LINE in $(swapon -s | grep -v Filename | sed -e 's/\t.*//g' -e 's/  .*//g')
		do
			#Make sure it is a swap file and not a swap partition
			#before unmounting and attempting to delete
			if file $LINE | grep -q 'swap file'
			then
				#Indicate that we found a mounted swap file
				SWAP_FOUND=true

				swapoff $LINE 2>/dev/null &&
				rm -f $LINE 2>/dev/null
			fi
		done
	fi

	#Check if the swap file exists (if it wasn't mounted)
	if [[ -n $SWAP_FILE ]] && [[ -e $SWAP_FILE ]]
	then
		#Make sure it didn't just fail to swapoff earlier
		if ! swapon -s | grep -v Filename | sed -e 's/\t.*//g' -e 's/  .*//g' | grep -q "^${SWAP_FILE}$"
		then
			#Indicate that we found a mounted swap file
			SWAP_FOUND=true

			#Remove it
			rm -f "${SWAP_FILE}"
		fi
	fi

	#Check if there's a record of a swap file in fstab
	#Swap file exists, and is mounted
	IFS=$'\n'
	for LINE in $(grep -v '^#' /etc/fstab | cut -d ' ' -f 1 | sed 's#\\040# #g' | sed -e 's/\t.*//g' -e 's/  .*//g')
	do
		if [[ -e "$LINE" ]] && file "$LINE" | grep -q 'swap file'
		then
			#Check if $LINE is mounted
			#We trust that all active swap files that could be removed have
			#already been up above. This is only in case the above swapoff failed
			#If a swap file/partition did fail to be swapped off, it may be used
			#by the system to store part of the hibernation data, in which case,
			#we should definately NOT remove it from fstab, so that when the machine
			#wakes up, it mounts that swap file/partition again
			if ! swapon -s | grep -v Filename | sed -e 's/\t.*//g' -e 's/  .*//g' | grep -q "^${LINE}$"
			then
				#Indicate that we found a swap file in fstab that exists, but
				#is NOT mounted
				SWAP_FOUND=true

				#REMOVE
				rm -f "$LINE"

				#Remove line from fstab
				LINE=$(echo "$LINE" | sed 's# #\\\\040#g')
				sed -i -e "\#$LINE\t#d" -e "\#$LINE  #d" /etc/fstab
			else
				LOGGER "$LINE is still mounted"'!'
			fi
		fi
	done

	#Check if there's a resume offset in uswsusp.conf
	if grep -q 'resume offset' /etc/uswsusp.conf 2>/dev/null
	then
			#Indicate that we found a mounted swap file
			SWAP_FOUND=true

			#Remove the line from uswsusp.conf
			sed -i '/resume offset =/d' /etc/uswsusp.conf 2>/dev/null
	fi

	#Remove swap line in /etc/rc.local, if it's there
	if grep -q 'swap' /etc/rc.local 2>/dev/null
	then
		#Indicate that we found a swap line in rc.local
		SWAP_FOUND=true

		#Remove swap line
		sed -i '/swap/d' /etc/rc.local
	fi
	
	#Indicate if a swap file was found
	return $(${SWAP_FOUND})
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
	LOGGER "script already running"
	exit 0
fi

#Check if upower is installed
which upower &>/dev/null || { LOGGER "upower not installed. This script will NOT work without it"'!'; exit 1; }

#Make sure swap file doesn't already exist, and isn't mounted
DEL_SWAP_FILES && LOGGER "Old temporary swap file detected. It has been unmounted and removed..."

#Check if $SHUTOFF_COMMAND is an actual command
#Ignore arguments to the command
[[ -x $(echo "${SHUTOFF_COMMAND}" | sed 's/ .*//g') ]] || { LOGGER "$(echo ${SHUTOFF_COMMAND} | sed 's/ .*//g') is not a valid command"'!'; exit 1; }

#This boolean variable is set to true if the BeforeHibernation code ran
#indicating that the AfterHibernation code should run too
PREHIB_RAN=false

#This boolean variable is set to true when the CreateSwap code ran
SWAP_CREATED=false

#Keep checking the UPS status until power returns to it
while [[ true ]]
do
	#Check if UPS is still on battery power
	if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "yes" ]]
	then
		#Check if battery is below $BATTERY_THRESHOLD_IN_PERCENT
		if [[ $(upower -d | grep percentage | grep -o '[0-9]*') -lt $BATTERY_THRESHOLD_IN_PERCENT ]]
		then
			LOGGER "UPS battery is below the ${BATTERY_THRESHOLD_IN_PERCENT}% threshold, and the UPS is still running on battery power."

			#Only run pre-hibernation code if it hasn't already run
			#This prevents it from running if machine already went into hibernation, woke up, realized we still have no power,
			#and is going down again
			if ! $PREHIB_RAN
			then
				LOGGER "Running pre-hibernation code..."
				#Run BeforeHibernation function
				BeforeHibernation

				#Set PREHIB_RAN variable to true to indicate the BeforeHibernation function ran
				PREHIB_RAN=true
			fi

			#Check if we are hibernating, suspening, or something else
			#Swap needs to be dealt with in cases where:
				#we are hibernating with pm-hibernate
				#we are hibernating with s2disk
				#we are hibernating with /usr/sbin/hibernate script (uses uswsusp)
				#we are doing a suspend and hibernate with pm-suspend-hybrid
				#we are doing a suspend and hibernate with s2both
			if echo $SHUTOFF_COMMAND | grep -q hibernate || echo $SHUTOFF_COMMAND | grep -q s2disk || echo $SHUTOFF_COMMAND | grep -q s2both || echo $SHUTOFF_COMMAND | grep -q hybrid
			then
				#If this is the second time we're doing this (we just woke up and are going down again),
				#ignore creating a swap file. This already either succeeded and we have a swap file, or failed
				#and we don't
				if ! $SWAP_CREATED
				then
					#Check if we should make a swap file
					if $ENABLE_SWAP
					then
						CreateSwap
						SWAP_CREATED=true
					else
						#Check if we have enough swap to hibernate
						#Check how much swap we have now
						FREE_SWAP=$(free -m | grep Swap | tr -s ' ' | cut -d ' ' -f 4)

						#Check how much ram we have now
						TOTAL_RAM=$(free -m | grep Mem | tr -s ' ' | cut -d ' ' -f 2)

						#Check if we have more SWAP than RAM
						if [[ $FREE_SWAP -gt $TOTAL_RAM ]]
						then
							LOGGER "Hibernating..."

							#If we are actually hibernating, add line to /etc/rc.local that will ensure that
							#if the machine doesn't come back from hibernation (crashes during hibernation)
							#on next boot, the swap file will still be removed
							grep -q swap /etc/rc.local || sed -i '$i if [ \$(swapon -s | wc -l) -gt 1 ]; then IFS=\$(echo -en "\\n\\b"); for LINE in \$(swapon -s | grep -v Filename | sed -e "s/\t.*//g" -e "s/  .*//g"); do swapoff \$LINE && 2>/dev/null; rm -f \$LINE 2>/dev/null; done; sed -i "/swap/d" /etc/fstab 2>/dev/null; sed -i "/resume offset =/d" /etc/uswsusp.conf 2>/dev/null; fi; sed -i "/swap/d" /etc/rc.local' /etc/rc.local
						else
							LOGGER "Not enough free swap space to hibernate"'!'
							#Log that we are suspending
							SuspendFallback
						fi
					fi
				else
					LOGGER "Hibernating..."

					#If we are actually hibernating, add line to /etc/rc.local that will ensure that
					#if the machine doesn't come back from hibernation (crashes during hibernation)
					#on next boot, the swap file will still be removed
					grep -q swap /etc/rc.local || sed -i '$i if [ \$(swapon -s | wc -l) -gt 1 ]; then IFS=\$(echo -en "\\n\\b"); for LINE in \$(swapon -s | grep -v Filename | sed -e "s/\t.*//g" -e "s/  .*//g"); do swapoff \$LINE && 2>/dev/null; rm -f \$LINE 2>/dev/null; done; sed -i "/swap/d" /etc/fstab 2>/dev/null; sed -i "/resume offset =/d" /etc/uswsusp.conf 2>/dev/null; fi; sed -i "/swap/d" /etc/rc.local' /etc/rc.local
				fi
			elif echo $SHUTOFF_COMMAND | grep -q 'suspend$'
			then
				LOGGER "Suspending..."
			else
				LOGGER "Running ${SHUTOFF_COMMAND}..."
			fi

			#Hibernate
			${SHUTOFF_COMMAND} || { LOGGER "Failed to run ${SHUTOFF_COMMAND}"'!'; SuspendFallback; ${SHUTOFF_COMMAND}; }

			#After the computer wakes up, give upower 2 minutes to update its status to make sure it doesn't still say
			#that the UPS is on battery power if it's not
			LOGGER "Computer just woke up. Waiting up to 120s for update to battery status"
			for VAR in {1..120}
			do
				sleep 1
				[[ $(upower -d | grep on-battery | grep -o "yes\|no") == "no" ]] && break
			done

			#Check if UPS has power again
			if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "no" ]]
			then
				LOGGER "Power restored"
				break
			else
				LOGGER "UPS still running off of battery. If it doesn't come back online in 30 seconds, the computer is going into hibernation again as soon as it's below the threshold."
				#Give it another 30 seconds, and run the while loop again
				sleep 30
			fi
		else
			LOGGER "battery is still above the ${BATTERY_THRESHOLD_IN_PERCENT}% threshold. Waiting 30 seconds..."
			sleep 30
		fi
	else
		LOGGER "Power restored before hibernation could take place"
		break
	fi
done

#Check if AfterHibernation function should run (if BeforeHibernation function ran)
if $PREHIB_RAN
then
	#Run AfterHibernation function
	AfterHibernation
	LOGGER "post-hibernation code execution complete"
fi

#Check if we should remove SWAP_FILE
DEL_SWAP_FILES && LOGGER "Old temp swap file removed..."

LOGGER "Exiting..."

exit 0
