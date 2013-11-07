How it works
============


Installing the Script
---------------------

First, run `upower -d`, and make sure that the `on-battery` field,
and the `percentage` field always reflect your UPS's actual status.
If these 2 fields are not accurate, or the command doesn't exist,
the script will NOT work!

Move the script to /sbin::

	sudo cp -v UPS_watcher.sh /sbin/

Now, edit your cron table::

	sudo crontab -e

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


Uninstall
---------

To uninstall the script, delete it from /sbin::

	sudo rm -v /sbin/UPS_watcher.sh

and delete the line you added during script installation to the cron table::

	sudo crontab -e
	#Delete line that starts with */1 and has
	#the words "UPS_watcher.sh" in it
