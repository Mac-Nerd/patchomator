#!/bin/zsh

# Version: 2022.09.22.NFY
# (Not Finished Yet)

# To Do:
# differentiate between labels that install the same app (firefox, etc) 
# without -r, parse generated config, pipe to Installomator to install updates

# Changed:
# Uses git sparse-checkout to grab and update the labels from 
# https://github.com/Installomator/Installomator/tree/main/fragments/labels

# Done:
# parse label name, expectedTeamID, packageID
# match to codesign -dvvv of *.app 
# packageID to Identifier
# expectedTeamID to TeamIdentifier


# default paths
InstallomatorPATH=("/usr/local/Installomator/Installomator.sh")
configfile=("/etc/patchomator/config.txt")
fragmentsPATH=("$(pwd)/Installomator/fragments")

# check for existence of labels. 
if ! [[ -d $fragmentsPATH ]]
then
	notice "Installomator labels not present or out of date. Performing self-update."
	selfupdate
fi


# Functions
source "$fragmentsPATH/functions.sh"

# Additional Functions: 

selfupdate() {
# Needs error checking (did git complete without errors, etc)
	git clone --depth 1 --filter=blob:none --sparse https://github.com/Installomator/Installomator/
	cd Installomator
	git sparse-checkout set fragments/labels/
	git pull
}

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
	echo "  With no options, this will parse /etc/patchomator/config.txt for a list of labels, and execute Installomator to update each label."
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

InstallomatorPATH=$InstallomatorPATH[-1]

notice "path to Installomator.sh: $InstallomatorPATH"

if ! [[ -f $InstallomatorPATH ]]
then
	error "Installomator.sh not found at $InstallomatorPATH. Download and install it now?"
	read DownloadFromGithub
	
	if [[ $DownloadFromGithub =~ '[Yy]' ]]; then
		# this installer requires root/sudo - but since we already know we're root, it should be fine.
		curl -SsL "https://github.com/Installomator/Installomator/raw/main/MDM/InstallInstallomator.sh" | sh
	else
		error "Unable to continue. Exiting now."
		exit 1	
	fi
fi


configfile=$configfile[-1]

notice "Config file: $configfile"


if ! [[ -f $configfile ]] 
then
	notice "No config file at $configfile[-1]. Creating one now."
	makefile $configfile
elif [[ ${#refresh} -eq 1 ]]
then 
	echo "Refreshing $configfile"
	makefile $configfile
fi




# Variables
# get current user
currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')

uid=$(id -u "$currentUser")
        
notice "Current User: $currentUser"
notice "UID: $uid"
userLanguage=$(runAsUser defaults read .GlobalPreferences AppleLocale)
notice "User Language: $userLanguage"


# start of label pattern
#label_re='^([a-z0-9\_-]*)(\))$'
# how to acommodate ?
#firefoxesr|\
#firefoxesrpkg)
label_re='^([a-z0-9\_-]*)(\)|\|\\)$'

# lines are stripped of leading whitespace with sed - handy, since some labels are inconsistent tabs/spaces
# comment
comment_re='^\#$'

# end of label pattern
endlabel_re='^;;'

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
			if [[ -d "$installedAppPath"/Contents/_MASReceipt ]]
			then
				notice "--- $appName is from App Store. Skipping."
				return
			# Check disambiguation
			elif ! $disambiguation
			then
				echo "$installedAppPath is not '$label_name'"
				notice "--- Wrong version of $appName installed. Skipping."
				return
			fi

			verifyApp $installedAppPath
      
		fi

	fi
}

verifyApp() {

	appPath=$1
    notice "Verifying: $appPath"

    # verify with spctl
    appVerify=$(spctl -a -vv "$appPath" 2>&1 )
    appVerifyStatus=$(echo $?)
    teamID=$(echo $appVerify | awk '/origin=/ {print $NF }' | tr -d '()' )

    if [[ $appVerifyStatus -ne 0 ]] ; then
        error "Error verifying $appPath"
        return
    fi

    if [ "$expectedTeamID" != "$teamID" ]; then
    	error "Team IDs do not match: $teamID (expected: $expectedTeamID )"
        return
    else

# run the commands in current_label to check for the new version string
		newversion=$(zsh << SCRIPT_EOF
source "$fragmentsPATH/functions.sh"
${current_label}
echo "\$appNewVersion" 
SCRIPT_EOF
)

		InstalledLabelsArray+=( "$label_name" )

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



# the main attraction.
# for each .sh file in fragments/labels/ strip out the switch/case lines and any comments. 

for labelFragment in $fragmentsPATH/labels/*.sh; do 
	echo "Processing $labelFragment."

	while read -r line; do 

		# strip spaces and tabs 
		scrubbedLine="$(echo $line | sed -E 's/^( |\t)*//g')"

		if [ -n $scrubbedLine ]; then

		#	echo $in_label        

			if [[ $in_label -eq 0 && "$scrubbedLine" =~ $label_re ]]; then
			   label_name=${match[1]}
			   in_label=1
			   disambiguation=true
			   continue # skips to the next iteration
			fi
	
			if [[ $in_label -eq 1 && "$scrubbedLine" =~ $endlabel_re ]]; then 
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
	
			if [[ $in_label -eq 1 && ! "$scrubbedLine" =~ $comment_re ]]; then
		# add the label lines to create a "subscript" to check versions and whatnot
		# if empty, add the first line. Otherwise, you'll get a null line
				[[ -z $current_label ]] && current_label=$line || current_label=$current_label$'\n'$line

				case $scrubbedLine in

				  'name='*|'packageID'*|'expectedTeamID'*|*'disambiguation'*)
				  eval "$scrubbedLine"
				  ;;

				esac
 
			fi
		
		fi
	
	done <${labelFragment}
	
done




echo "Done."
printf "%s\n" "$InstalledLabelsArray[@]"
