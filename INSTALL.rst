How it works
============

Overview
--------

The script is a single file that gets triggered by cron when your
UPS starts using battery power (as determined by `upower -d`). 

Note: When the script runs, if you read the log file, you'll see
lines that say "script already running". This is because cron
doesn't care if the script is already running or not - if the
UPS is on battery power, it will try to launch the script again
and again once a minute. That log message is coming from another
instance of the script that got run by cron. It simply figures out
that the script is already running, and exits, leaving behind a log
message for easier debugging. This is normal.


Installing the Script
---------------------

First, run `upower -d`, and make sure that the `on-battery` field,
and the `percentage` field always reflect your UPS's actual status.
If these 2 fields are not accurate, or the command doesn't exist,
the script will NOT work!

Move the script to /sbin::

	sudo cp -v UPS_watcher.sh /sbin/

Configure the script::

	See `Configuration` section below

Now, edit your cron table::

	sudo crontab -e

	NOTE: If you don't know how vi works (the default text editor
	on most systems), try:

		sudo EDITOR=gedit crontab -e
		OR
		sudo EDITOR=pluma crontab -e

and paste this at the end::

	*/1 * * * * /bin/bash -c 'if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "yes" ]]; then /sbin/UPS_watcher.sh --cron; fi'

to tell cron to watch the status of the UPS every minute and run
the script as soon as the UPS is on battery power.

Note: If you are concerned about letting cron run the above line every
minute because you think it takes a lot of resources, I wouldn't worry
about it. My system takes exactly 0.016 seconds to run that line and
exit, assuming everything is ok - it's not exactly a resource hog.


Configuration
-------------

To configure which commands will be run just before the system hibernates,
where the log file goes, or what percentage the UPS should be at before
the system should hibernate, edit the UPS_watcher.sh script directly. The
user editable section is at the top, and clearly marked.

The only configurable section that merits further explanation is the swap
file. See below.


Using a swap file
-----------------
Hibernation requires enough swap space to save your RAM to it. If you have
a swap partition - great. If not, you can have the script automatically
create a swap file on your hard drive to use as swap every time the system
needs to hibernate, and destroy the file when it is done hibernation.

To do this:

Stop the kernel from using the swap file for swapping::
	sudo sysctl -w vm.swappiness=1 
	echo vm.swappiness=1 | sudo tee -a /etc/sysctl.d/local.conf
Install hibernate and uswsusp::
	sudo apt-get install hibernate uswsusp
	NOTE: If it asks "Continue without a valid swap space?" - answer yes
Edit /etc/default/grub::
	Add 'resume=/dev/sda1' to GRUB_CMDLINE_LINUX_DEFAULT
	NOTE: where /dev/sda1 is the same as the 'resume device' from /etc/uswsusp.conf.
Update the grub menu::
	sudo update-grub
And enable usage of a swap file in the UPS_watcher script by setting::
	ENABLE_SWAP=true
After doing all this, I highly recommend testing the script to make sure
hibernation works properly.


Seeing it in action
-------------------

To observe what the script is doing while it's doing it, I just open 3
terminal windows, running the following 3 commands, one per window::

	#This command just follows the log file as it gets updated
	#Note: The UPS_watcher.log files does NOT exist until the first
	#time the script runs
	$ less +F /var/log/UPS_watcher.log

	#This shows the status of the UPS, as determined by the upower command
	#This information is how cron, and the script both determine if the
	#UPS is using battery power or not
	$ watch -n1 'upower -d | grep "on-battery\|percent\|state" | tr -s " "'

	#This will tell you if/when the script is actually running
	#Note: Only happens when cron sees that the UPS is running
	#on battery power
	$ watch -n1 'ps -Af | grep UPS | grep -v "grep\|vim\|watch \|less"'

then I unplug my UPS from the wall to see what happens.

Note: Don't forget that many UPS's have several slots that are only protected
from surges, and not actually on battery backup. If you unplug your UPS,
anything in these slots will lose power.


Uninstall
---------

To uninstall the script, delete it from /sbin::

	sudo rm -v /sbin/UPS_watcher.sh

and delete the line you added during script installation to the cron table::

	sudo crontab -e
	#Delete line that starts with */1 and has
	#the words "UPS_watcher.sh" in it
