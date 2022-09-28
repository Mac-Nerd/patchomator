#!/bin/zsh

# Version: 2022.09.28.NFY
# (Not Finished Yet)

# To Do:
# system-level config file in case running via sudo?
# force self-update and/or switch branches

# Changed:
# Uses git sparse-checkout to grab and update the labels from 
#   https://github.com/Installomator/Installomator/tree/release/fragments/labels
# No longer requires root for normal operation. (thanks, @tlark)
# Downloads XCode Command Line Tools to provide git (Thanks Adam Codega)

# Done:
# use release version of installomator, not dev. (Thanks Adam Codega)
# selfupdate when labels are older than 7 days
# parse label name, expectedTeamID, packageID
# match to codesign -dvvv of *.app 
# packageID to Identifier
# expectedTeamID to TeamIdentifier
# added quiet mode, noninteractive mode
# choose between labels that install the same app (firefox, etc) 
# - offer user selection
# - pick the first match (noninteractive mode)
# on duplicate labels, skip subsequent verification
# on -I, parse generated config, pipe to Installomator to install updates
#   Installomator requires root


# Environment checks

OSVERSION=$(defaults read /System/Library/CoreServices/SystemVersion ProductVersion | awk '{print $1}')
OSMAJOR=$(echo "${OSVERSION}" | cut -d . -f1)
OSMINOR=$(echo "${OSVERSION}" | cut -d . -f2)

# default paths
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

InstallomatorPATH=("/usr/local/Installomator/Installomator.sh")
configfile=("$HOME/Library/Preferences/Patchomator/patchomator.plist")
fragmentsPATH=("$(pwd)/Installomator/fragments")

# requires git - easiest way to get that is install the Xcode command line tools.

makepath() {
  mkdir -p $(sed 's/\(.*\)\/.*/\1/' <<< $1) # && touch $1
}

error() {
	echo "[ERROR] $1"
}

notice() {
    if [[ ${#verbose} -eq 1 ]]; then
        echo "[NOTICE] $1"
    fi
}

infoOut() {
	if ! [[ ${#quietmode} -eq 1 ]]; then
		echo "$1"
	fi
}

installCommandLineTools() {

	#Check your privilege
	if [ $(whoami) != "root" ]
	then
		error "This function requires root. Either install from developer.apple.com or re-run Patchomator with sudo"
		exit 1
	fi

	# creates a temporary file to allow swupdate to list and install the command line tools
	TMPFILE="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
	touch ${TMPFILE}

	echo "Checking availability of Command Line Tools."
	CLTAVAILABLE=$(/usr/sbin/softwareupdate -l | grep -B 1 -E 'Command Line Tools' | awk -F'*' '/^ *\\*/ {print $2}' | sed -e 's/^ *Label: //' -e 's/^ *//' | sort -V | tail -n1)

	if [[ -n ${CLTAVAILABLE} ]]
	then
		echo "Installing ${CLTAVAILABLE}"

		/usr/sbin/softwareupdate -i "${CLTAVAILABLE}"

		rm -f ${TMPFILE}

		/usr/bin/xcode-select --switch /Library/Developer/CommandLineTools

	else 
		echo "Something went wrong. The Command Line Tools are already installed. Confirm git is working and try again."
		exit 1
	fi
					  
}

if [[ $OSMAJOR -lt 11 ]] && [[ $OSMINOR -lt 13 ]]
then
	error "Patchomator and its prerequisites require MacOS 10.13 or higher."
	exit 1
else

	if ! gitBinary=$(which git 2> /dev/null) 
	then 
		error "Patchomator requires git, which is provided by the XCode Command Line Tools."
		echo -n "Download and install them now? [y/N]: "
		read DownloadCLT
		if [[ $DownloadCLT =~ '[Yy]' ]]; then
			installCommandLineTools
			gitBinary=$(which git 2> /dev/null)
		else
			error "Unable to continue. Exiting now."
			exit 1	
		fi
	fi	
fi
 
# check for existence of labels, and if there, how old they are

labelsAge=$((($(date +%s) - $(stat -t %s -f %m -- "$fragmentsPATH")) / 86400))

infoOut "Labels last updated ${labelsAge} days ago."

if [[ ! -d $fragmentsPATH ]] || [[ $labelsAge -gt 7 ]]
then
	notice "Installomator labels not present or out of date. Performing self-update."
	selfupdate
fi

# Functions
source "$fragmentsPATH/functions.sh"

# Additional Functions: 

selfupdate() {
# Needs error checking (did git complete without errors, etc)
	notice "Using git at ${gitBinary}"
	$gitBinary clone --branch "$releaseversion" --depth 1 --filter=blob:none --sparse https://github.com/Installomator/Installomator/tree/release/
	cd Installomator
	$gitBinary sparse-checkout set fragments/labels/
	$gitBinary pull
}



makepath() {
  mkdir -p $(sed 's/\(.*\)\/.*/\1/' <<< $1) # && touch $1
}

error() {
	echo "[ERROR] $1"
}

notice() {
    if [[ ${#verbose} -eq 1 ]]; then
        echo "[NOTICE] $1"
    fi
}

infoOut() {
	if ! [[ ${#quietmode} -eq 1 ]]; then
		echo "$1"
	fi
}


usage() {
	echo "Usage:"
	echo "patchomator.sh [ -cyqvxiIh  -c configfile  -i InstallomatorPATH ]"
	echo "With no options, this will create a new, or refresh an existing configuration. Scans the system for installed apps and matches them to Installomator labels."
	echo ""
	echo "	-c \"path to config file\" - Default configuration file location ~/Library/Preferences/Patchomator/patchomator.plist"
	echo "  -y - Non-interactive mode. Accepts the first label that matches an existing app. Use with caution."
	echo "	-q - Quiet mode. Minimal output."
	echo "	-v - Verbose mode. Logs more information to stdout. Overrides -q"
	echo "  -x - Use the latest development branch of Installomator labels. Otherwise, defaults to latest release branch. Use with caution."
	echo "	-i \"path to Installomator.sh\" - Default Installomator Path /usr/local/Installomator/Installomator.sh"
	echo "  -I - Install mode. This parses an existing configuration and sends the commands to Installomator to update. Requires sudo"
	echo "	-h | --help - Show this text."
	exit 0
}


# Command line options
zparseopts -D -E -F -K -- h+=showhelp -help+=showhelp x=devmode I=installmode q=quietmode y=noninteractive v=verbose c:=configfile i:=InstallomatorPATH

if [[ ${#devmode} -eq 1 ]]; then
	releaseversion="main"
	notice "Using development branch of Installomator labels from Github. Some things may not work as expected."
else
	releaseversion="release"
fi


installInstallomator() {
	# Get the URL of the latest PKG From the Installomator GitHub repo
	PKGurl=$(curl --silent --fail "https://api.github.com/repos/Installomator/Installomator/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
	# Expected Team ID of the downloaded PKG
	expectedTeamID="JME5BW3F3R"

	tempDirectory=$( mktemp -d )
	notice "Created working directory '$tempDirectory'"
	# Download the installer package
	notice "Downloading Installomator package"
	curl --location --silent "$PKGurl" -o "$tempDirectory/Installomator.pkg"

	# Verify the download
	teamID=$(spctl -a -vv -t install "$tempDirectory/Installomator.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
	notice "Team ID for downloaded package: $teamID"

	# Install the package if Team ID validates
	if [ "$expectedTeamID" = "$teamID" ] || [ "$expectedTeamID" = "" ]; then
		notice "Package verified. Installing package Installomator.pkg"
		if ! installer -pkg "$tempDirectory/Installomator.pkg" -target / -verbose
		then
			error "Installation failed. See /var/log/installer.log for details."
			exit 1
		fi
			
	else
		error "Package verification failed before package installation could start. Download link may be invalid. Aborting."
		exit 1
	fi

	# Remove the temporary working directory when done
	notice "Deleting working directory '$tempDirectory' and its contents"
	rm -Rf "$tempDirectory"

}

caffexit () {
	kill "$caffeinatepid"
	exit $1
}

doInstallations() {

	# No sleeping
	/usr/bin/caffeinate -d -i -m -u &
	caffeinatepid=$!

	# Count errors
	errorCount=0

	# build array of labels from config file
	labelsArray=($(defaults read $configfile | grep -o -E '\S+\;'))


	for label in $labelsArray; do
		label=$(echo $label | cut -d ';' -f1) # trim the trailing semicolon
		echo "Installing ${label}..."
		${InstallomatorPATH} ${label} BLOCKING_PROCESS_ACTION=tell_user NOTIFY=success
		if [ $? != 0 ]; then
			error "Error installing ${label}. Exit code $?"
			let errorCount++
		fi
	done

	echo "Errors: $errorCount"

	caffexit $errorCount

}

InstallomatorPATH=$InstallomatorPATH[-1]

notice "Path to Installomator.sh: $InstallomatorPATH"

if ! [[ -f $InstallomatorPATH ]]
then
	error "Installomator.sh not found at $InstallomatorPATH."

	#Check your privilege
	if [ $(whoami) != "root" ]
	then
		error "Either install it from https://github.com/Installomator/Installomator or re-run Patchomator with sudo"
		exit 1
	fi

	echo -n "Download and install it now? [y/N]: "
	read DownloadFromGithub
	
	if [[ $DownloadFromGithub =~ '[Yy]' ]]; then

		installInstallomator
		
	else
		error "Unable to continue. Exiting now."
		exit 1	
	fi
fi



# install mode. Requires root, check for existing config.
if [[ ${#installmode} -eq 1 ]]
then

	#Check your privilege
	if [ $(whoami) != "root" ]
	then
		error "Install mode must be run with root/sudo privileges."
		exit 1
	fi

	configfile=$configfile[-1]
	notice "Config file: $configfile"

	if ! [[ -f $configfile ]] 
	then
		infoOut "No config file at $configfile. Re-run Patchomator without -I to create one."
	else
	# read existing config. One label per line. Send labels to Installomator for updates.
		infoOut "Existing config found at $configfile."
		infoOut "Passing labels to Installomator."

		doInstallations
	
		exit 0		
	fi

fi # end install mode

notice "Verbose Mode enabled." # and if it's not? This won't echo.

if ! [[ -f $configfile ]] 
then
	infoOut "No config file at $configfile. Creating one now."
	makepath "$configfile"
	/usr/libexec/PlistBuddy -c "clear dict" "$configfile"
else
	infoOut "Refreshing $configfile"
	/usr/libexec/PlistBuddy -c "clear dict" "$configfile"
fi


if [[ ${#noninteractive} -eq 1 ]]
then
	echo "Running in non-interactive mode. Check ${configfile} when done to confirm the correct labels are applied."
fi


if [[ ${#showhelp} -gt 0 ]]
then
	usage
fi






# Variables
# get current user
currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')

uid=$(id -u "$currentUser")
        
notice "Current User: $currentUser"
notice "UID: $uid"
userLanguage=$(runAsUser defaults read .GlobalPreferences AppleLocale)
notice "User Language: $userLanguage"




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

		infoOut "Found $applist"
		
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
			else
				if exists=$(defaults read $configfile "$installedAppPath" 2> /dev/null)
				# if [ -n "$exists" ]
				then 					
# compare $installedAppPath	with installedAppPath keys in config plist.
					echo "${appPath} already linked to label ${exists}."
					if [[ ${#noninteractive} -eq 1 ]]
					then
						return
					else
						echo -n "Replace label ${exists} with $label_name? [y/N]: "
						read replaceLabel 

						if [[ $replaceLabel =~ '[Yy]' ]]
						then
							echo "Replacing."
							defaults write $configfile $installedAppPath $label_name

						else
							echo "Skipping."
							return
						fi
					fi					
				else 
					verifyApp $installedAppPath
				fi
			fi
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

		/usr/libexec/PlistBuddy -c "add \":${appPath}\" string ${label_name}" "$configfile"

		notice "--- Installed version: ${appversion}"
		[[ -n "$newversion" ]] && notice "--- Newest version: ${newversion}"

		if [[ "$appversion" == "$newversion" ]]
		then
			notice "--- Latest version installed."
		fi
		
	fi
}


# the main attraction.

# start of label pattern
label_re='^([a-z0-9\_-]*)(\)|\|\\)$'

# comment
comment_re='^\#$'

# end of label pattern
endlabel_re='^;;'

targetDir="/"
versionKey="CFBundleShortVersionString"

IFS=$'\n'
in_label=0
current_label=""

# for each .sh file in fragments/labels/ strip out the switch/case lines and any comments. 

for labelFragment in $fragmentsPATH/labels/*.sh; do 

	labelFile=$(basename -- "$labelFragment")
	labelFile="${labelFile%.*}"
	infoOut "Processing label $labelFile."

	exec 3< "${labelFragment}"

	while read -r -u 3 line; do 

		# strip spaces and tabs 
		scrubbedLine="$(echo $line | sed -E 's/^( |\t)*//g')"

		if [ -n $scrubbedLine ]; then

			if [[ $in_label -eq 0 && "$scrubbedLine" =~ $label_re ]]; then
			   label_name=${match[1]}
			   in_label=1
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

				  'name='*|'packageID'*|'expectedTeamID'*)
					  eval "$scrubbedLine"
				  ;;

				esac
			fi
		fi
	done
done

echo "Done."