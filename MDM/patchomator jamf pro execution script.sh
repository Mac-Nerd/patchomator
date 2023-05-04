#!/bin/zsh
#
# This script will check if Installomator and Patchomator are found locally in their respecitve folders. 
# If found, it will execute Patchomator silently (--yes) to install (--install) updates if found.

# Jamf Pro script parameters 
# $4 = ignored labels (space separated) 
# $5 = required labels (space separated).

# This could be adapted to replace triggers at the end of the script by more Jamf Pro script parameters to have more control. 

InstallomatorPath=("/usr/local/Installomator/Installomator.sh")
PatchomatorPath=("/usr/local/Installomator/patchomator.sh")
#
# Check if Installomator is found locally.
#
if [ ! -f $InstallomatorPath ]
then 
	echo "Installomator is not installed. Exiting."
	exit 1
fi
echo "Installomator is installed. Continuing."

#
# Check if Patchomator is found locally.
#
if [ ! -f $PatchomatorPath ]
then 
	echo "Patchomator is not installed. Exiting."
	exit 2
fi
echo "Patchomator is installed. Continuing."

#
# Run Patchomator silently with optional exclusions and requirements.
# This uses Jamf Pro script parameter 4 for ignored labels and parameter 5 for required labels.
#
echo "Running \"patchomator.sh --yes --install --ignored --required\""
zsh "$PatchomatorPath" --yes --install --ignored "$4" --required "$5"
echo "Patchomator script has finished. Exiting."
exit 0

#
# End of file.
#
