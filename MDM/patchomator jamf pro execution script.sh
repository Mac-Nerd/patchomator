#!/bin/zsh
#
# This script will check if Installomator and Patchomtor are found locally in their folder. 
# If found it will execute Patchomator silently (--yes) to install (--install) updates if found.
# Jamf Pro script parameter 4 is used to pass on ignored labels (space separated) and parameter 5 to pass on required labels (space separated).
# This could be adapted to replace triggers in bottom of the script by more Jamf Pro script parameters to have more control. 
#
InstallomatorPath=("/usr/local/Installomator/Installomator.sh")
PatchomatorPath=("/usr/local/Installomator/patchomator.sh")
#
# Check if Installomator is found locally.
#
if [ ! -f $InstallomatorPath ]
then 
echo Installomator is not installed. Exitting...
exit 1
fi
echo Installomator is installed. Continuing...
#
# Check if Patchomator is found locally.
#
if [ ! -f $PatchomatorPath ]
then 
	echo Patchomator is not installed. Exitting...
	exit 2
fi
echo Patchomator is installed. Continuing...
#
# Run Patchomator silently with optional exclusions and requirements.
# This uses Jamf Pro script parameter 4 for ignored labels and parameter 5 for required labels.
#
echo Running Patchomator with triggers --yes --install --ignored --required...
zsh "$PatchomatorPath" --yes --install --ignored "$4" --required "$5"
echo Patchomator script has finished. Exitting...
exit
#
# End of file.
#