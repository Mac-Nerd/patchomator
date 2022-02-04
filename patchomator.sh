#!/bin/zsh

# Done:
# read through Installomator script for labels.
# parse label name and expectedTeamID packageID
# match to codesign -dvvv of *.app 
# packageID to Identifier
# expectedTeamID to TeamIdentifier

# To Do:
# differentiate between labels that install the same app (firefox, etc) 
# without -r, parse generated config, pipe to Installomator to install updates


# default paths
InstallomatorPATH=("/usr/local/Installomator/Installomator.sh")
configfile=("/etc/patchomator/config.txt")


# Functions
makefile() {
  mkdir -p $(sed 's/\(.*\)\/.*/\1/' <<< $1) && touch $1
}

notice() {
    if [[ ${#verbose} -eq 1 ]]; then
        echo "[NOTICE] $1"
    fi
}

error() {
	echo "[ERROR] $1"
}

usage() {
	echo "This script must be run with root/sudo privileges."
	echo "Usage:"
	echo "patchomator.sh [ -r -v  -c configfile  -i InstallomatorPATH ]"
	echo "  With no options, this will parse the config file for a list of labels, and execute Installomator to update each label."
	echo "	-r - Refresh config. Scans the system for installed apps and matches them to Installomator labels. Rebuilds the configuration file."
	echo ""
	echo "	-c \"path to config file\" - Default configuration file location /etc/patchomator/config.txt"
	echo "	-i \"path to Installomator.sh\" - Default Installomator Path /usr/local/Installomator/Installomator.sh"
	echo "	-v - Verbose mode. Logs more information to stdout."
	echo "	-h | --help - Show this text."
	exit 0
}


# Command line options
zparseopts -D -E -F -K -- h+=showhelp -help+=showhelp v=verbose r=refresh c:=configfile i:=InstallomatorPATH

notice "Verbose Mode enabled." # and if it's not? This won't echo.

if [ ${#showhelp} -gt 0 ] 
then
	usage
fi

# Check your privilege
if [ $(whoami) != "root" ]; then
    echo "This script must be run with root/sudo privileges."
    exit 1
fi


notice "path to Installomator.sh: $InstallomatorPATH[-1]"

if ! [[ -f $InstallomatorPATH ]]
then
	error "[ERROR] Installomator.sh not found at $InstallomatorPATH."
	exit 1
fi


notice "Config file: $configfile[-1]"


if ! [[ -f $configfile[-1] ]] 
then
	notice "No config file at $configfile[-1]. Creating one now."
	makefile $configfile[-1]
elif [[ ${#refresh} -eq 1 ]]
then 
	echo "Refreshing $configfile"
	makefile $configfile[-1]
fi




# Variables
# get current user
currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')

#label_re='^([a-z0-9\_-]*)(\)|\|\\)$'
label_re='^([a-z0-9\_-]*)(\))$'
endlabel_re='^(    |\t);;$'

targetDir="/"
versionKey="CFBundleShortVersionString"

# Array to store what's installed, so we can save it for later
InstalledLabelsArray=()






getAppVersion() {

	# pkgs contains a version number, then we don't have to search for an app
	if [[ $packageID != "" ]]; then
		
		appversion="$(pkgutil --pkg-info-plist ${packageID} 2>/dev/null | grep -A 1 pkg-version | tail -1 | sed -E 's/.*>([0-9.]*)<.*/\1/g')"
		
		if [[ $appversion != "" ]]; then
			notice "Label: $label_name"
			notice "--- found packageID $packageID installed"
			
			InstalledLabelsArray+=( "$label_name" )
			
			return
		fi
	fi

	if [ -z "$appName" ]; then
		# when not given derive from name
		appName="$name.app"
	fi
	
	# get app in /Applications, or /Applications/Utilities, or find using Spotlight

	notice "Searching system for $appName"
	
	if [[ -d "/Applications/$appName" ]]; then
		applist="/Applications/$appName"
	elif [[ -d "/Applications/Utilities/$appName" ]]; then
		applist="/Applications/Utilities/$appName"
	else
#        applist=$(mdfind "kind:application $appName" -0 )
		applist=$(mdfind -literal "kMDItemFSName == '$appName'" -0 )
	fi
	
	appPathArray=( ${(0)applist} )

	if [[ ${#appPathArray} -gt 0 ]]; then

		echo "Found $applist"

		filteredAppPaths=( ${(M)appPathArray:#${targetDir}*} )

		if [[ ${#filteredAppPaths} -eq 1 ]]; then
			installedAppPath=$filteredAppPaths[1]
			
			appversion=$(defaults read $installedAppPath/Contents/Info.plist $versionKey) #Not dependant on Spotlight indexing

			notice "Label: $label_name"
			notice "--- found app at $installedAppPath"
			
			# Is current app from App Store
			if [[ -d "$installedAppPath"/Contents/_MASReceipt ]];then
				notice "--- $appName is from App Store. Skipping."
			else
				verifyTeamID $installedAppPath

			fi
			
		fi

	fi
}



verifyTeamID() {

	appPath=$1

    # verify with spctl
    notice "Verifying: $appPath"
    
    if ! teamID=$(spctl -a -vv "$appPath" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()' ); then
        error "Error verifying $appPath"
        return
    fi


    if [ "$expectedTeamID" != "$teamID" ]; then
        error "Team IDs do not match"
        return
    else
		InstalledLabelsArray+=( "$label_name" )

# run the commands in current_label to check for the new version string
		newversion=$(zsh << SCRIPT_EOF
source "./functions.sh"
${current_label}
echo "\$appNewVersion" 
SCRIPT_EOF
)
		 
		notice "--- Installed version: ${appversion}"
		[[ -n "$newversion" ]] && notice "--- Newest version: ${newversion}"

		if [[ "$appversion" == "$newversion" ]]
		then
			notice "--- Latest version installed."
		fi
		
	fi
}


IFS=$'\n'
in_label=0
current_label=""

while read -r line; do 
    if [[ $in_label -eq 0 && "$line" =~ $label_re ]]; then
        label_name=${match[1]}
#		echo "Label: $label_name"
        in_label=1
        continue # skips to the next iteration
    fi
    
 
     if [[ $in_label -eq 1 && "$line" =~ $endlabel_re ]]; then
		
		# label complete. A valid label includes a Team ID. If we have one, we can check for installed
		[[ -n $expectedTeamID ]] && getAppVersion

        in_label=0
		packageID=""
		name=""
		appName=""
		expectedTeamID=""
		current_label=""
		appNewVersion=""
		
		continue # skips to the next iteration
    fi

    
    if [[ $in_label -eq 1 && ! "$line" =~ ^(    |\t)\# ]] ; then

# add the label lines to create a "subscript" to check versions and whatnot
# if empty, add the first line. Otherwise, you'll get a null line
		[[ -z $current_label ]] && current_label=$line || current_label=$current_label$'\n'$line

# generally, first line will contain the app name
		if [[ $(echo $line | xargs 2> /dev/null)  =~ ^name\= ]] 
		then		
			eval $line	# name="..."
#			appName=$(echo "$line" | cut -d'=' -f2)
#			echo "APP NAME: ${appName}"

# some installers use a packageID instead 
		elif [[ $(echo $line | xargs 2> /dev/null) =~ ^packageID\= ]]
		then
			eval $line	# packageID="..."
#			packageID=$(echo "$line" | cut -d'=' -f2 | tr -d "\"")
#			echo "PACKAGE ID: ${packageID}"
		
# installed apps will have a team ID
		elif [[ $(echo $line | xargs 2> /dev/null) =~ ^expectedTeamID\= ]]
		then
			eval $line # expectedTeamID="..."
#			expectedTeamID=$(echo "$line" | cut -d'=' -f2 | tr -d "\"")
		fi
		
    fi

    
done <${InstallomatorPATH}


printf "%s\n" "$InstalledLabelsArray[@]"