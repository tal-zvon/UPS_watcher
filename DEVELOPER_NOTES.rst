Known issues::

	AfterHibernation function doesn't run if computer comes back online after the additional 30 seconds it waits
		This was fixed with the addition of the PREHIB_RAN boolean variable, but never tested because of the next bug
			Post hibernation code should only kick in if hibernation actually happened
			Test with:
				power comes back on before hibernation happens
				power comes back on while machine is hibernating
				power comes back on during the 30 second window
				it hibernates twice

	*The if statement that checks if UPS is on battery power should be above the one that checks the percentage, so that if power is restored before the threshold is hit, it doesn't keep waiting until it reaches the threshold
		Fix added. Needs testing

Ideas for features::

	Make it so that it can't be run without an argument so that it can't be run directly without cron
		This is so that people who have no idea how the script works, and who haven't read the INSTALL file don't just run the script and say it doesn't work

	Find out how to edit cron table with gedit, and add that to the INSTALL file so people who don't know how to use vim can use gedit

	Make script check if it is being run by root, and exit if not. This should prevent the need for doing a chmod on the script, and chown already seems unnecessary, so I can remove those from the INSTALL file
