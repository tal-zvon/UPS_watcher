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

Next, make sure it's owned by root, and can't be run as a regular user::

	sudo chown -v root:root /sbin/UPS_watcher.sh
	sudo chmod -v 744 /sbin/UPS_watcher.sh

Now, edit your cron table::

	sudo crontab -e

and paste this at the end::

	*/5 * * * * /bin/bash -c 'if [[ $(upower -d | grep on-battery | grep -o "yes\|no") == "yes" ]]; then /sbin/UPS_watcher.sh; fi'


to tell cron to watch the status of the UPS every 5 minutes, and run the script as soon as the UPS is on battery power.


Uninstall
---------

To uninstall the script, delete it from /sbin::

	sudo rm /sbin/UPS_watcher.sh

and delete the line you added during script installation to the cron table::

	sudo crontab -e
	#Delete line that starts with */5 and has the words "UPS_watcher.sh" in it
