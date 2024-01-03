# Contributed MDM Utilities

## Jamf-lastrun-EA
### Contributed by Michael Zukrow ("@Michael Z" on Macadmins Slack)

Add this Extension Attributes to JAMF to get date of last run from your end points
You can use this to create smart groups to scope actions
for example you could offer Installomator as a self service policy and as an auto run policy
If a user runs the self service it would update the EA and smart group so the auto run doesn't occur in window
allowing more flexibility to keep end points updated and give users a better experience

## patchomator jamf pro execution script
### Contributed by Jordy Thery

This script will check if Installomator and Patchomator are found locally in their respecitve folders. 
If found, it will execute Patchomator silently (--yes) to install (--install) updates if found.

Jamf Pro script parameters 
$4 = ignored labels (space separated) 
$5 = required labels (space separated).

This could be adapted to replace triggers at the end of the script by more Jamf Pro script parameters to have more control. 
