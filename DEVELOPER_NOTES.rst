Known issues::

	"date >> /home/mint/Desktop/BeforeHibernation" lines got into the git repo. I only meant to use them during testing. Get rid of them

Ideas for features::

	Make it so that it can't be run without an argument so that it can't be run directly without cron
		This is so that people who have no idea how the script works, and who haven't read the INSTALL file don't just run the script and say it doesn't work

	Find out how to edit cron table with gedit, and add that to the INSTALL file so people who don't know how to use vim can use gedit

	Make script check if it is being run by root, and exit if not. This should prevent the need for doing a chmod on the script, and chown already seems unnecessary, so I can remove those from the INSTALL file
