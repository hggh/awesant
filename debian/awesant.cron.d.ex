#
# Regular cron jobs for the awesant package
#
0 4	* * *	root	[ -x /usr/bin/awesant_maintenance ] && /usr/bin/awesant_maintenance
