#!/bin/zsh

# Contributed by Michael Zukrow ("@Michael Z" on Macadmins Slack)


logPATH="/private/var/log/Patchomator.log"
lastLine=$( tail -n 1 $logPATH | cut -d" " -f 1,2 )
echo "last line is " + $lastLine 
if [ $lastLine = "Patchomator finished:" ];
	then
		lastRun=$( tail -n 1 $logPATH | cut -d" " -f3 )
		echo "<result>$lastRun</result>"
	else 	
		echo "<result>error</result>"
fi 

exit 0 