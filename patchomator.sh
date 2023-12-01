#!/bin/zsh

# Version: 2023.11.07 - 1.1.RC1
# ""

#  Big Thanks to:
# 	Adam Codega
# 	@tlark
# 	@mickl089
# 	Shad Hass
# 	Derek McKenzie
# 	Armin Briegel
#	Jordy Thery
#	Trevor Sysock


# To Fix: 


# To Do:
# 1.1 Add MDM deployed Non-interactive Mode --mdm "MDMName"
# 1.1 Swift Dialog support
# 1.1 Ignored labels from CLI into preferences on --write

# Changed/Fixed:
# [speed] --skip-verify to skip the step of verifying discovered apps. Does *not* skip the verification on install. 
# [speed] Defer verification step until discovery is complete. Parallelize as much as possible.
# Offers to install Installomator update, but requires user intervention.
# On --write, add any found label to the config, even if the latest version is installed
# Messaging for missing config file on --write
# Respects --installomatoroptions setting for ignoring App Store apps (or not)

# Done:
# Add --ignored "all" option to skip discovery all together
# Add --installomatoroptions to pass options to installomator
# Turn off pretty printed formatting for --quiet
# Monterey fix for working path
# Major overhaul based on MacAdmins #patchomator feedback
# 7 days -> 30 days
# Added required/excluded keys in preference file
# system-level config file for running via sudo, or deploying via MDM
# git and Xcode tools are optional now. Did you know GitHub has a pretty decent API?
# No longer requires root for normal operation. (thanks, @tlark)
# Downloads XCode Command Line Tools to provide git (Thanks Adam Codega)
# Install package/github release
# add back installomator install steps
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

# NGD:
# self-update switch branches from release to latest source



if [ -z "${ZSH_VERSION}" ]; then
	>&2 echo "[ERROR] This script is only compatible with Z shell (/bin/zsh). Re-run with"
	echo "\t zsh patchomator.sh"
	exit 1
fi

# Environment checks

OSVERSION=$(defaults read /System/Library/CoreServices/SystemVersion ProductVersion | awk '{print $1}')
OSMAJOR=$(echo "${OSVERSION}" | cut -d . -f1)
OSMINOR=$(echo "${OSVERSION}" | cut -d . -f2)


if [[ $OSMAJOR -lt 11 ]] && [[ $OSMINOR -lt 13 ]]
then
	echo "[ERROR] Patchomator requires MacOS 10.13 or higher."
	exit 1
fi


# Check your privilege
if [ $(whoami) = "root" ]
then
	IAMROOT=true
else
	IAMROOT=false
fi


# log levels from Installomator/fragments/arguments.sh

if [[ $DEBUG -ne 0 ]]; then
    LOGGING=DEBUG
elif [[ -z $LOGGING ]]; then
    LOGGING=INFO
    datadogLoggingLevel=INFO
fi

declare -A levels=(DEBUG 0 INFO 1 WARN 2 ERROR 3 REQ 4)
declare -A configArray=()

declare -A InstallomatorOptions=()

declare -A foundLabelsArray=()
declare -A ignoredLabelsArray=()
declare -A requiredLabelsArray=()



# default paths
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

InstallomatorPATH=("/usr/local/Installomator/Installomator.sh")
configfile=("/Library/Application Support/Patchomator/patchomator.plist")
#patchomatorPath=$(dirname $(realpath $0)) # default install at /usr/local/Installomator/

# "realpath" doesn't exist on Monterey. 
patchomatorPath="/usr/local/Installomator/"

fragmentsPATH=("$patchomatorPath/fragments")

# Pretty print, ignored if no terminal (eg, running via MDM)
BOLD=$(tput bold 2>/dev/null)
RESET=$(tput sgr0 2>/dev/null)
RED=$(tput setaf 1 2>/dev/null)
YELLOW=$(tput setaf 3 2>/dev/null)

skipDiscovery=false

[[ -f /usr/local/bin/dialog ]] && echo "## Swift Dialog support coming soon."



#######################################
# Functions

usage() {
	echo "\n${BOLD}Usage:${RESET}"
	echo "\tpatchomator.sh [ -ryqvIh  -c configfile  -p InstallomatorPATH ]\n"
	echo "${BOLD}Default:${RESET}"
	echo "\tScans the system for installed apps and matches them to Installomator labels."
	
	echo "\t${BOLD}--ignored \"space-separated list of labels to ignore\""
	echo "\t${BOLD}--required \"space-separated list of labels to require\""
	
	echo "\t${BOLD}-w | --write \t${RESET} Write Config. Creates a new config file or refreshes an existing one."
	echo "\t${BOLD}-r | --read \t${RESET} Read Config. Parses and displays an existing config file. \n\tDefault path ${YELLOW}/Library/Application Support/Patchomator/patchomator.plist${RESET}"
	echo "\t${BOLD}-c | --config \"path to config file\" \t${RESET} Overrides default configuration file location."
	echo "\t${BOLD}-y | --yes \t${RESET} Non-interactive mode. Accepts the default (usually nondestructive) choice at each prompt. Use with caution."
	echo "\t${BOLD}-q | --quiet \t${RESET} Quiet mode. Minimal output."
	echo "\t${BOLD}-v | --verbose \t${RESET} Verbose mode. Logs more information to stdout. Overrides ${BOLD}--quiet${RESET}"
	echo "\t${BOLD}-s | --skipverify \t${RESET} Skips the signature verification step for discovered apps. ${BOLD}Does not skip verifying on installation.${RESET}"
	echo "\t${BOLD}-I | --install \t${RESET} Install mode. This parses an existing configuration and sends the commands to Installomator to update. ${BOLD}Requires sudo${RESET}"
	echo "\t${BOLD}-p | --pathtoinstallomator \"path to Installomator.sh\"${RESET}\n\tDefault Installomator Path ${YELLOW}/usr/local/Installomator/Installomator.sh${RESET}"
	echo "\t${BOLD}--options \"option1=value, option2=value, ...\"${RESET}\n\tCommand line options passed through to Installomator.${RESET}"
	echo "\t${BOLD}-h | --help \t${RESET} Show this text and exit.\n"
	echo "${YELLOW}See readme for more options and examples: ${BOLD}https://github.com/mac-nerd/Patchomator{RESET}"
	exit 0
}

caffexit () {
	kill "$caffeinatepid"
	exit $1
}

makepath() { # creates the full path to a file, but not the file itself
	mkdir -p "$(sed 's/\(.*\)\/.*/\1/' <<< $1)" # && touch $1
}

notice() { # verbose mode
    if [[ ${#verbose} -eq 1 ]]; then
        echo "${YELLOW}[NOTICE]${RESET} $1"
    fi
}

infoOut() { # normal messages
	if ! [[ ${#quietmode} -eq 1 ]]; then
		echo "$1"
	fi
}

error() { # bad, but recoverable
	echo "${BOLD}[ERROR]${RESET} $1"
	let errorCount++
}

fatal() { # something bad happened.
	echo "\n${BOLD}${RED}[FATAL ERROR]${RESET} $1\n\n"
	exit 1
}

# --read 
# --write
displayConfig() {
	echo "\n${BOLD}Currently configured labels:${RESET}"	

# if a config file was created, show it at the end.
	if [[ -f $configfile ]] 
	then
		column -t -s "=;\"\"" <<< $(defaults read "$configfile" | tr -d "{}()\"")
	else
# if no config was saved, show the results of the discovery process
		for discoveredItem in $configArray
		do
			echo $discoveredItem
		done
		
		echo "\n${BOLD}Ignored Labels:${RESET}"
		for ignoredItem in $ignoredLabelsList
		do
			echo $ignoredItem
		done
		
		echo "\n${BOLD}Required Labels:${RESET}"
		for requiredItem in $requiredLabelsList
		do
			echo $requiredItem
		done
			
	fi

}

checkInstallomator() {
	
	# check for existence of Installomator to enable installation of updates
	notice "Checking for Installomator.sh at ${YELLOW}$InstallomatorPATH ${RESET}"

	InstalledVersion="$($InstallomatorPATH version)"
	LatestVersion="$(versionFromGit Installomator Installomator)"

	notice "Latest Version: $LatestVersion - Installed Version: $InstalledVersion"
	
	if [[ "$InstalledVersion" -ne "$LatestVersion" ]]
	then
		error "Installomator was found, but is out of date. You can update it by running \n\t${YELLOW}sudo $InstallomatorPATH installomator ${RESET}"

		if [[ ${#noninteractive} -eq 1 ]]
		then
			notice "Running in non-interactive mode. Skipping Installomator update."
		else
			OfferToInstall
		fi
	fi

	if ! [[ -f $InstallomatorPATH ]]
	then
		error "Installomator was not found at ${YELLOW}$InstallomatorPATH ${RESET}"
	
		LatestInstallomator=$(curl --silent --fail "https://api.github.com/repos/Installomator/Installomator/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

		if [[ ${#noninteractive} -eq 1 ]]
		then
			notice "Running in non-interactive mode. Skipping Installomator install."
		else
			OfferToInstall
		fi
		
		
	else
		if [ $($InstallomatorPATH version | cut -d . -f 1) -lt 10 ]
		then
			fatal "Installomator is installed, but is out of date. Versions prior to 10.0 function unpredictably with Patchomator.\nYou can probably update it by running \n\t${YELLOW}sudo $InstallomatorPATH installomator ${RESET}"
		fi
	fi	

}


# --install
OfferToInstall() {
	#Check your privilege
	if $IAMROOT
	then
		echo -n "Patchomator can still discover apps on the system and create a configuration for later use, but will not be able to install or update anything without Installomator. \
		\n${BOLD}Download and install Installomator now? ${YELLOW}[y/N]${RESET} "
			
		read DownloadFromGithub

		if [[ $DownloadFromGithub =~ '[Yy]' ]]
		then
			installInstallomator
		else
			echo "${BOLD}Continuing without Installomator.${RESET}"
			# disable installs
			if [[ $installmode ]]
			then
				fatal "Patchomator cannot install or update apps without the latest Installomator. If you would like to continue, either re-run Patchomator without ${YELLOW}--install${RESET}, or install Installomator from this URL:\
				\n\t ${YELLOW}https://github.com/Installomator/Installomator${RESET}"
			fi
		fi
	else
		fatal "Specify a different path with \"${YELLOW}-p [path to Installomator]${RESET}\" or download and install it from here:\
		\n\t ${YELLOW}https://github.com/Installomator/Installomator${RESET}\
		\n\nThis script can also attempt to install Installomator for you. Re-run patchomator with ${YELLOW}sudo${RESET} or without ${YELLOW}--install${RESET}"
	fi
}

installInstallomator() {
	# Get the URL of the latest PKG From the Installomator GitHub repo
	# no need for git, if there's an API
	PKGurl=$(curl --silent --fail "https://api.github.com/repos/Installomator/Installomator/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

	# Expected Team ID of the downloaded PKG
	expectedTeamID="JME5BW3F3R"

	tempDirectory=$( mktemp -d )
	notice "Created working directory '$tempDirectory'"

	# Download the installer package
	notice "Downloading Installomator package"
	curl --location --silent "$PKGurl" -o "$tempDirectory/Installomator.pkg" || fatal "Download failed."

	# Verify the download
	teamID=$(spctl -a -vv -t install "$tempDirectory/Installomator.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')
	notice "Team ID of downloaded package: $teamID"

	# Install the package, only if Team ID validates
	if [ "$expectedTeamID" = "$teamID" ]
	then
		notice "Package verified. Installing package Installomator.pkg"
		installer -pkg "$tempDirectory/Installomator.pkg" -target / -verbose || fatal "Installation failed. See /var/log/installer.log for details."			
	else
		fatal "Package verification failed. TeamID does not match."
	fi

	# Remove the temporary working directory when done
	notice "Deleting working directory '$tempDirectory' and its contents"
	rm -Rf "$tempDirectory"

}


checkLabels() {
	notice "Looking for labels in ${fragmentsPATH}/labels/"

	# use curl to get the labels - who needs git?
	if [[ ! -d "$fragmentsPATH" ]]
	then
		if [[ -w "$patchomatorPath" ]]
		then
			infoOut "Package labels not present at $fragmentsPATH. Attempting to download from https://github.com/installomator/"
			downloadLatestLabels
		else 
			fatal "Package labels not present and $patchomatorPath is not writable. Re-run patchomator with sudo to download and install them."
		fi
	
	else
		labelsAge=$((($(date +%s) - $(stat -t %s -f %m -- "$fragmentsPATH/labels")) / 86400))

		if [[ $labelsAge -gt 30 ]]
		then
			if [[ -w "$patchomatorPath" ]]
			then
				error "Package labels are out of date. Last updated ${labelsAge} days ago. Attempting to download from https://github.com/installomator/"
				downloadLatestLabels
			else
				fatal "Package labels are out of date. Last updated ${labelsAge} days ago. Re-run patchomator with sudo to update them."
				
			fi
		
		else 
			infoOut "Package labels installed. Last updated ${labelsAge} days ago."
		fi
	fi

}

downloadLatestLabels() {
	# gets the latest release version tarball.
	latestURL=$(curl -sSL -o - "https://api.github.com/repos/Installomator/Installomator/releases/latest" | grep tarball_url | awk '{gsub(/[",]/,"")}{print $2}') # remove quotes and comma from the returned string
	#eg "https://api.github.com/repos/Installomator/Installomator/tarball/v10.3"

	tarPath="$patchomatorPath/installomator.latest.tar.gz"

	echo "Downloading ${latestURL} to ${tarPath}"
		
	curl -sSL -o "$tarPath" "$latestURL" || fatal "Unable to download. Check ${patchomatorPath} is writable or re-run as root."

	echo "Extracting ${tarPath} into ${patchomatorPath}"
	tar -xz --include='*/fragments/*' -f "$tarPath" --strip-components 1 -C "$patchomatorPath" || fatal "Unable to extract ${tarPath}. Corrupt or incomplete download?"
	touch "${fragmentsPATH}/labels/"
}

# --install
doInstallations() {
	

	# No sleeping
	/usr/bin/caffeinate -d -i -m -u &
	caffeinatepid=$!

	# Count errors
	errorCount=0

	# convert InstallomatorOptions array to string
	InstallomatorOptionsString=""

	for key value in ${(kv)InstallomatorOptions}; do
		InstallomatorOptionsString+=" $key=\"$value\""
	done

	for label in $queuedLabelsArray
	do
		echo "Installing ${label}..."
		${InstallomatorPATH} ${label} ${InstallomatorOptionsString}
		if [ $? != 0 ]; then
			error "Error installing ${label}. Exit code $?"
			let errorCount++
		fi
	done

	echo "Errors: $errorCount"

	caffexit $errorCount

}


### 1.1 
# discover installed apps
# add labels to found apps list 
# do version check of found apps


FindAppFromLabel() {
# appname label_name packageID
	label_name=$1
	appversion=""

	if [ -z "$appName" ]; then
		# when not given derive from name
		appName="$name.app"
	fi

	# shortcut: pkgs contains a version number, if it's installed then we don't have to parse the plist. 
	# still need to confirm it's installed, tho. Receipts can be unreliable.
	if [[ "$packageID" != "" ]]
	then
		notice "Searching system for $packageID"
		
		appversion="$(pkgutil --pkg-info-plist ${packageID} 2>/dev/null | grep -A 1 pkg-version | tail -1 | sed -E 's/.*>([0-9.]*)<.*/\1/g')"
		
		if [[ -n $appversion ]]; then
			notice "Label: $label_name"
			notice "--- found packageID $packageID version $appversion installed"
			InstalledLabelsArray+=( "$label_name" )
		fi
	else 
		notice "Searching system for $appName"
	fi

	
	# get app in /Applications, or /Applications/Utilities, or find using Spotlight
	
	if [[ -d "/Applications/$appName" ]]; then
		applist="/Applications/$appName"
	elif [[ -d "/Applications/Utilities/$appName" ]]; then
		applist="/Applications/Utilities/$appName"
	else
#        applist=$(mdfind "kind:application $appName" -0 )
		applist=$(mdfind "kMDItemFSName == '$appName' && kMDItemContentType == 'com.apple.application-bundle'" -0 )
		# random files named *.app were potentially coming up in the list. Now it has to be an actual app bundle
	fi
	
	appPathArray=( ${(0)applist} )

	if [[ ${#appPathArray} -gt 0 ]]
	then
		
		filteredAppPaths=( ${(M)appPathArray:#${targetDir}*} )

		if [[ ${#filteredAppPaths} -eq 1 ]]
		then
			installedAppPath=$filteredAppPaths[1]
			
			[[ -n "$appversion" ]] || appversion=$(defaults read "$installedAppPath/Contents/Info.plist" "$versionKey")

			infoOut "Found $appName version $appversion"

			notice "Label: $label_name"
			notice "--- found app at $installedAppPath"
						
			# Is current app from App Store
			# AND is IGNORE_APP_STORE_APPS=yes?

			if [[ -d "$installedAppPath"/Contents/_MASReceipt ]] && [[ $InstallomatorOptions[IGNORE_APP_STORE_APPS] =~ [YyEeSs1] ]]
			then
				notice "$appName is from App Store. Ignoring."
				notice "Use the Installomator option \"IGNORE_APP_STORE_APPS=no\" to replace."
			
			else

				foundLabelsArray[$label_name]="$installedAppPath"
				
			fi
		fi

	fi

}


verifyApp() {
	foundLabel=$1
	appPath=$2

	if [[ -n "$configArray[$appPath]" ]]
	then
		infoOut "$appPath already verified."
	else
		if [[ $skipVerify == false ]]
		then
		
			infoOut "Verifying: $appPath"

			# verify with spctl
			appVerify=$(spctl -a -vv "$appPath" 2>&1 )
			appVerifyStatus=$(echo $?)
			teamID=$(echo $appVerify | awk '/origin=/ {print $NF }' | tr -d '()' )

			if [[ $appVerifyStatus -ne 0 ]]
			then
				error "Error verifying $appPath: Returned $appVerifyStatus"
				return
			fi

			if [ "$expectedTeamID" != "$teamID" ]
			then
				error "Error verifying $appPath"
				notice "Team IDs do not match: expected: $expectedTeamID, found $teamID"
				return
			fi

		fi
		notice "Checking: $appPath"
	# run the commands in current_label to check for the new version string
		newversion=$(zsh << SCRIPT_EOF
declare -A levels=(DEBUG 0 INFO 1 WARN 2 ERROR 3 REQ 4)
currentUser=$currentUser
source "$fragmentsPATH/functions.sh"
${current_label}
echo "\$appNewVersion" 
SCRIPT_EOF
		)

	fi
# build array of labels for the config and/or installation

# push label to array
# if in write config mode, writes to plist. Otherwise to an array.
	if [[ -n "$configArray[$appPath]" ]]
	then
		exists="$configArray[$appPath]"

		infoOut "${appPath} already linked to label ${exists}."
		if [[ ${#noninteractive} -eq 1 ]]
		then
			echo "\t${BOLD}Skipping.${RESET}"
			return
		else
			echo -n "${BOLD}Replace label ${exists} with $foundLabel? ${YELLOW}[y/N]${RESET} "
			read replaceLabel 

			if [[ $replaceLabel =~ '[Yy]' ]]
			then
				echo "\t${BOLD}Replacing.${RESET}"
				configArray[$appPath]=$label_name
				
				# Remove duplicate label already in queue:
				labelsList=$(echo "$labelsList" | sed s/"$exists "//)
				
				# add replaced label to Ignored list
				ignoredLabelsArray[$exists]=1

				if [[ ${#writeconfig} -eq 1 ]]
				then
					/usr/libexec/PlistBuddy -c "set \":${appPath}\" ${foundLabel}" "$configfile"
					/usr/libexec/PlistBuddy -c "add \":IgnoredLabels:\" string \"${exists}\"" $configfile
				fi

			else
				echo "\t${BOLD}Skipping.${RESET}"
				# add skipped label to Ignored list
				/usr/libexec/PlistBuddy -c "add \":IgnoredLabels:\" string \"${foundLabel}\"" $configfile

				return
			fi
		fi					
	else
		configArray[$appPath]=$foundLabel
		if [[ ${#writeconfig} -eq 1 ]]
		then
			/usr/libexec/PlistBuddy -c "add \":${appPath}\" string ${foundLabel}" "$configfile"
		fi
	fi


	appversion="$(pkgutil --pkg-info-plist ${packageID} 2>/dev/null | grep -A 1 pkg-version | tail -1 | sed -E 's/.*>([0-9.]*)<.*/\1/g')"
	[[ -n "$appversion" ]] || appversion=$(defaults read "$appPath/Contents/Info.plist" "$versionKey" 2>/dev/null)
	
	notice "--- Installed version: ${appversion}"
	
	[[ -n "$newversion" ]] && notice "--- Newest version: ${newversion}"

	if [[ "$appversion" == "$newversion" ]]
	then
		notice "--- Latest version installed."
	else
		queueLabel
	fi

}



# --install
queueLabel() {

	notice "Queueing $label_name"

	# add to queue if in install mode
	if [[ $installmode ]]
	then
		labelsList+="$label_name "
#		echo "$labelsList"
	fi
		
}

 
#######################################
# You're probably wondering why I've called you all here...


# Command line options

#zparseopts -D -E -F -K -- \
zparseopts -D -E -F -K -- \
-help+=showhelp h+=showhelp \
-install=installmode I=installmode \
-quiet=quietmode q=quietmode \
-yes=noninteractive y=noninteractive \
-verbose=verbose v=verbose \
-read=readconfig r=readconfig \
-write=writeconfig w=writeconfig \
-config:=configfile c:=configfile \
-skipverify=skipVerify s=skipVerify \
-pathtoinstallomator:=InstallomatorPATH p:=InstallomatorPATH \
-ignored:=ignoredLabels \
-required:=requiredLabels \
-mdm:=MDMName \
-options:=CLIOptions \
|| fatal "Bad command line option. See patchomator.sh --help"

# -h --help
# -I --install
# -q --quiet
# -y --yes
# -v --verbose
# -r --read
# -w --write
# -s --skip-verify
# -c / --config <config file path>
# -p / --pathtoinstallomator <installomator path>
# New in 1.1
# --mdm [one of jamf, mosyleb, mosylem, addigy, microsoft, ws1, other ] Any other Mac MDM solutions worth mentioning?
# --options "list of installomator options to pass through"




# Show usage
# --help
if [[ ${#showhelp} -gt 0 ]]
then
	usage
fi

notice "Verbose Mode enabled." # and if it's not? This won't echo.

configfile=$configfile[-1] # either provided on the command line, or default path
InstallomatorPATH=$InstallomatorPATH[-1] # either provided on the command line, or default /usr/local/Installomator

MDMName=$MDMName[-1] #[one of jamf, mosyleb, mosylem, addigy, microsoft, ws1, other ]

# --mdm
# Assumes certain settings when an MDM is declared:
# - Installomator options: 
# 	- logo
#	- ?
# --install
# --quiet
# --yes



### Default Installomator Options:

InstallomatorOptions=(\
[NOTIFY]=success \
[PROMPT_TIMEOUT]=86400 \
[BLOCKING_PROCESS_ACTION]=tell_user \
[LOGO]=appstore \
[IGNORE_APP_STORE_APPS]="no" \
[SYSTEMOWNER]=0 \
[REOPEN]="yes" \
[INTERRUPT_DND]="yes" \
[NOTIFY_DIALOG]=1 \
[LOGGING]="INFO" \
)

# Parse command line --options
OptionsString=$CLIOptions[-1]
# split on spaces, then on =
AddOptions=$(echo "$OptionsString" | awk -v OFS="\n" '{$1=$1}1' | awk -v FS="=" '{print "InstallomatorOptions+=\(["$1"]="$2"\)"}')

# Add them to the InstallomatorOptions array
eval "$AddOptions"

# Additional optional settings by MDM
if [ "$MDMName" ]
then
	quietmode[1]=true
#	installmode=true
	noninteractive[1]=true
fi

if [ "$MDMName" ]
then
	# set logos for known MDM vendors
	if [ "$MDMName" != "other" ]
	then
		InstallomatorOptions[LOGO]="$MDMName"
	fi
fi

notice "Option Count ${#InstallomatorOptions[@]}"
notice "Installomator Options:"

for key value in ${(kv)InstallomatorOptions}; do
    notice " - $key=\"$value\""
done

# ReadConfig mode - read existing plist and display in pretty columns
# skips discovery and all the rest
# --read
if [[ ${#readconfig} -eq 1 ]]
then

	notice "Reading Config"

	if ! [[ -f $configfile ]] 
	then
		fatal "No config file at $configfile. Run patchomator again with ${YELLOW}--write${RESET} to create one now.\n"
	else
		displayConfig
	fi
	exit 0
fi


if [[ -f $configfile ]] && [[ ${#writeconfig} -ne 1 ]] 
then
	infoOut "Reading existing configuration for ignored/required labels"

	# parse the config for existing ignored/required labels
	ignoredLabelsFromConfig=($(defaults read "$configfile" IgnoredLabels | awk '{printf "%s ",$NF}' | tr -c -d "[:alnum:][:space:][-_]" | tr -s "[:space:]"))
	
	requiredLabelsFromConfig=($(defaults read "$configfile" RequiredLabels | awk '{printf "%s ",$NF}' | tr -c -d "[:alnum:][:space:][-_]" | tr -s "[:space:]"))

	for ignoredLabel in $ignoredLabelsFromConfig
	do
		if [[ -f "${fragmentsPATH}/labels/${ignoredLabel}.sh" ]]
		then
			ignoredLabelsArray["$ignoredLabel"]=1		
			notice "Ignoring $ignoredLabel"	   
		fi
	done
	
	for requiredLabel in $requiredLabelsFromConfig
	do
		if [[ -f "${fragmentsPATH}/labels/${requiredLabel}.sh" ]]
		then
			requiredLabelsArray["$requiredLabel"]=1			   
			notice "Requiring $requiredLabel"	   
		fi
	done
	
fi


# Create Config file on --write, or if none already exists
# --write
if [[ ${#writeconfig} -eq 1 ]] || ! [[ -f $configfile ]]
then
	notice "Writing Config"

	if [[ -d $configfile ]] # common mistake, select a directory, not a filename
	then
		fatal "Please specify a file name for the configuration, not a directory.\n\tExample: ${YELLOW}patchomator --write --config \"/etc/patchomator.plist\""
	fi

	if ! [[ -f $configfile ]] # no existing config
	then
		if [[ -d "$(dirname $configfile)" ]] 
		# directory exists
		then			
			if [[ -w "$(dirname $configfile)" ]]
			#directory is writable
			then
				infoOut "No existing config file at $configfile. Creating one now."

			else
				# exists, but not writable
				fatal "$(dirname $configfile) exists, but is not writable. Re-run patchomator with sudo to create the config file there, or use a writable path with\n\t ${YELLOW}--config \"path to config file\"${RESET}"
			fi
		else
		# directory doesn't exist
			infoOut "No existing config file at $configfile. Creating one now."
			makepath "$configfile"
		fi
		# creates a blank plist
		plutil -create xml1 "$configfile" || fatal "Unable to create $configfile. Re-run patchomator with sudo to create the config file there, or use a writable path with\n\t ${YELLOW}--config \"path to config file\"${RESET}"

	else # file exists

		if [[ -w $configfile ]]
		then 
			infoOut "Refreshing $configfile"
			# create blank plist or empty an existing one
			/usr/libexec/PlistBuddy -c "clear dict" "${configfile}"
	
		else
			fatal "$configfile is not writable. Re-run patchomator with sudo, or use a writable path with\n\t ${YELLOW}--config \"path to config file\"${RESET}"
		fi	
	
	fi
	
	# add sections for label arrays
	/usr/libexec/PlistBuddy -c 'add ":IgnoredLabels" array' "${configfile}"	
	/usr/libexec/PlistBuddy -c 'add ":RequiredLabels" array' "${configfile}"	

fi
# END --write


# can't do discovery without the labels files.
checkLabels

# MOAR Functions! miscellaneous pieces referenced in the occasional label
# Needs to confirm that labels exist first.
source "$fragmentsPATH/functions.sh"

# can't install without the 'mator
# can't check version without the functions. 
checkInstallomator	


# speed up the discovery phase.
if [[ ${#skipVerify} -eq 1 ]]
then
	skipVerify=true
else
	skipVerify=false
fi


# --install
# some functions act differently based on install vs discovery/read
if [[ ${#installmode} -eq 1 ]]
then
	installmode=true
fi


if [[ $installmode ]]
then

	# Check your privilege
	if ! $IAMROOT
	then
		fatal "Install mode must be run with root/sudo privileges. Re-run Patchomator with\n\t ${YELLOW}sudo zsh patchomator.sh --install${RESET}"
	fi
	
fi

# discovery mode
# the main attraction.


# --required
if [[ -n "$requiredLabels" ]]
then
	
	requiredLabelsList=("${(@s/ /)requiredLabels[-1]}")
	notice "Required labels: $requiredLabelsList"

	for requiredLabel in $requiredLabelsList
	do
		if [[ -f "${fragmentsPATH}/labels/${requiredLabel}.sh" ]]
		then
			notice "[CLI] Requiring ${requiredLabel}."

			if [[ ${#writeconfig} -eq 1 ]]
			then
				/usr/libexec/PlistBuddy -c "add \":RequiredLabels:\" string \"${requiredLabel}\"" $configfile	
			fi

			if [[ $installmode ]]
			then
				label_name=$requiredLabel
				queueLabel # add to installer queue
			fi
			requiredLabelsArray[$requiredLabel]=1

		else
			error "No such label ${requiredLabel}"
		fi
		
	done

fi

# --ignored
if [[ -n "$ignoredLabels" ]]
then

	ignoredLabelsList=("${(@s/ /)ignoredLabels[-1]}")

	if [[ "$(echo $ignoredLabelsList | tr '[:upper:]' '[:lower:]')" == "all" ]] # ALL All all aLl etc.
	then
	
		notice "[CLI] Ignored=all. Skipping discovery."
		skipDiscovery=true
	
	else
		notice "[CLI] Ignoring labels: $ignoredLabelsList"

		for ignoredLabel in $ignoredLabelsList
		do
			if [[ -f "${fragmentsPATH}/labels/${ignoredLabel}.sh" ]]
			then
		
				if [[ ${#writeconfig} -eq 1 ]]
				then
					/usr/libexec/PlistBuddy -c "add \":IgnoredLabels:\" string \"${ignoredLabel}\"" $configfile
				fi
					
				ignoredLabelsArray[$ignoredLabel]=1
					
			else
				error "No such label ${ignoredLabel}"
			fi

		done
	fi

fi



# DISCOVERY PHASE

# get current user
currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')

uid=$(id -u "$currentUser")

notice "Current User: $currentUser (UID $uid)"

# start of label pattern
label_re='^([a-z0-9\_-]*)(\))$'
#label_re='^([a-z0-9\_-]*)(\)|\|\\)$' 

# ignore comments
comment_re='^\#$'

# end of label pattern
endlabel_re='^;;'

targetDir="/"
versionKey="CFBundleShortVersionString"

IFS=$'\n'
in_label=0
current_label=""

### MAIN EVENT

# for each .sh file in fragments/labels/ strip out the switch/case lines and any comments. 
# get app name, label name, packageID


if [[ $skipDiscovery != true ]]
then

	for labelFragment in "$fragmentsPATH"/labels/*.sh; do 

		labelFile=$(basename -- "$labelFragment")
		labelFile=${labelFile%.*}


		while read -r labelInFile
		do 

			if [[ $ignoredLabelsArray[$labelInFile] -eq 1 ]]
			then
				notice "Ignoring labels in $labelFile."
				continue 2 # we're done here. Move along.
			fi

		done < <(grep -E '^([a-z0-9\_-]*)(\)|\|\\)$' "$labelFragment" | sed -e 's/[\|\\\)]//g' )

		# clear for next iteration
		expectedTeamID=""
		packageID=""
		name=""
		appName=""
		current_label=""
		versionKey="CFBundleShortVersionString"


## for discovery phase, use grep: '^([a-z0-9\_-]*)(\)|\|\\)$' 
## labelFragment contains n label_names
## easier than parsing line by line


		# set variables
		eval $(grep -E -m1 '^\s*name=' "$labelFragment") 
		eval $(grep -E -m1 '^\s*packageID' "$labelFragment")
		eval $(grep -E -m1 '^\s*expectedTeamID' "$labelFragment")
				
		if [[ -n $expectedTeamID ]]
		then
			infoOut "Processing labels in $labelFile."
		 	FindAppFromLabel "$labelFile"
		else
			infoOut "Error in $labelFile. No Team ID."	
		fi
		 
	done

else
# read existing config. One label per line. Send labels to Installomator for updates.
	infoOut "Existing config found at $configfile."
	
	labelsFromConfig=($(defaults read "$configfile" | grep -e ';$' | awk '{printf "%s ",$NF}' | tr -c -d "[:alnum:][:space:][-_]" | tr -s "[:space:]"))
	
	ignoredLabelsFromConfig=($(defaults read "$configfile" IgnoredLabels | awk '{printf "%s ",$NF}' | tr -c -d "[:alnum:][:space:][-_]" | tr -s "[:space:]"))
	
	requiredLabelsFromConfig=($(defaults read "$configfile" RequiredLabels | awk '{printf "%s ",$NF}' | tr -c -d "[:alnum:][:space:][-_]" | tr -s "[:space:]"))
	
	ignoredLabelsList+=($ignoredLabelsFromConfig)
	requiredLabelsList+=($requiredLabelsFromConfig)

	labelsList+=($labelsFromConfig $requiredLabels $requiredLabelsFromConfig)
	
# 	# deduplicate ignored labels
	ignoredLabelsList=($(tr ' ' '\n' <<< "${ignoredLabelsList[@]}" | sort -u | tr '\n' ' '))

# 	# deduplicate required labels
	requiredLabelsList=($(tr ' ' '\n' <<< "${requiredLabelsList[@]}" | sort -u | tr '\n' ' '))

# 	# deduplicate labels list
	labelsList=($(tr ' ' '\n' <<< "${labelsList[@]}" | sort -u | tr '\n' ' '))

	labelsList=${labelsList:|ignoredLabelsList}

	notice "Labels to install: $labelsList"
	notice "Ignoring labels: $ignoredLabelsList"
	notice "Required labels: $requiredLabelsList"
	
	
fi	
# end discovery	


# for each app found, check version and verify
for foundLabel appPath in ${(kv)foundLabelsArray};
do

	if [[ $ignoredLabelsArray["$foundLabel"] -ne 1 ]]
	then

		# echo "$foundLabel == $appPath"
		labelFragment="${fragmentsPATH}/labels/${foundLabel}.sh"
	
		# read the label as a sub-script
		exec 3< "${labelFragment}"

		while read -r -u 3 line; do 

			# strip spaces and tabs 
			scrubbedLine="$(echo $line | sed -E -e 's/^( |\t)*//g' -e 's/^\s*#.*$//')"
	
			if [[ -n $scrubbedLine ]]; then
		
				if [[ $in_label -eq 0 && "$scrubbedLine" =~ $label_re ]]; then
								
					label_name=${match[1]}
					in_label=1
					continue # skips to the next iteration
				fi

				if [[ $in_label -eq 1 && "$scrubbedLine" =~ $endlabel_re ]]; then 
					# label complete. A valid label includes a Team ID. If we have one, we can check for installed
					[[ -n $expectedTeamID ]] && verifyApp "$foundLabel" "$appPath"

					in_label=0
					packageID=""
					name=""
					appName=""
					expectedTeamID=""
					current_label=""
					appNewVersion=""
					versionKey="CFBundleShortVersionString"

					continue # skips to the next iteration
				fi

				if [[ $in_label -eq 1 ]]; then
					[[ -z $current_label ]] && current_label=$line || current_label=$current_label$'\n'$line

					case $scrubbedLine in

					  'name='*|'packageID'*|'expectedTeamID'*)
						  eval "$scrubbedLine"
					  ;;

					esac
				fi
			fi
		done
	fi
done


# install mode. Requires root and Installomator, checks for existing config. 
# --install

if [[ $installmode ]]
then

	IFS=' '

	queuedLabelsArray=("${(@s/ /)labelsList}")	
	numLabels=$((${#queuedLabelsArray[@]} - 1))

	if [[ $numLabels > 0 ]]
	then
		infoOut "Passing $numLabels labels to Installomator: $queuedLabelsArray"
		doInstallations
	else
		infoOut "All apps up to date. Nothing to do." # inbox zero
	fi
	
	exit 0
	
fi

# end install mode

if [ "$errorCount" -gt 0 ]
then
	echo "${BOLD}Completed with $errorCount errors.${RESET}\n"
else
	echo "${BOLD}Done.${RESET}\n"
fi

displayConfig

#### That's a wrap. Don't forget to tip your server. You don't have to go home, but you can't stay here.
