#!/bin/zsh

VERSION="1.1.4"
VERSIONDATE="2025-06-27"
VERSIONNAME="JuneBug Free - Hopefully"

# Gigantic Thanks to:
#	rondelltron
#	Skinflint

# Big Thanks to:
# 	Adam Codega
# 	@tlark
# 	@mickl089
# 	Shad Hass
# 	Derek McKenzie
# 	Armin Briegel
#	Jordy Thery
#	Trevor Sysock
#	Michael Zukrow
#	Sjur Lohne
#	Max Roy

# To Fix:


# To Do:
# Add MDM optimized Non-interactive Mode --mdm "MDMName"
# apps installed in other weird locations should be identifiable by their pkg receipt.

# Recent Changes/Fixes:
# Script Checks
# Version output from --version
# Consistent messages for exiting and logging
# Set maximum rolled logs to 5 by default. Configured via backupLogsMax
# Roll logs if greater than 1MB by default. Configured via logSizeMax in bytes
# Use appCustomVersion from label file for a check
# Detect Swift Dialog
# remove extra spaces, and use requiredLabelsList
# 1.1.2 Installomator 10.8 version check
# Only search for apps in /Applications by default, optionally --everywhere
# Passing installomator options with spaces in.
# Automatically ignore labels that conflict with required ones
# Swift Dialog support
# labels with dashes. Seriously.
# Added logging to /var/log/Patchomator.log
# Interactive mode overhaul, automatically adding skipped labels as ignored
# 1.1 Ignored labels from CLI added into preferences on --write
# [speed] --skip-verify to skip the step of verifying discovered apps. Does *not* skip the verification on install.
# [speed] Defer verification step until discovery is complete. Parallelize as much as possible.
# Offers to install Installomator update, but requires user intervention.
# On --write, add any found label to the config, even if the latest version is installed
# Messaging for missing config file on --write
# Respects --installomatoroptions setting for ignoring App Store apps (or not)

# Older:
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
# - Installomator requires root

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

autoload -Uz is-at-least

# log levels from Installomator/fragments/arguments.sh

if [[ $DEBUG -ne 0 ]]; then
	LOGGING=DEBUG
elif [[ -z $LOGGING ]]; then
	LOGGING=INFO
	datadogLoggingLevel=INFO
fi

logPATH="/private/var/log/Patchomator.log"
backupLogsMax=5
logSizeMax=$((1024 * 1024)) # 1 MB in bytes

declare -A levels=(DEBUG 0 INFO 1 WARN 2 ERROR 3 REQ 4)
declare -A configArray=()

declare -A InstallomatorOptions=()

declare -A foundLabelsArray=()
declare -A ignoredLabelsArray=()
declare -A requiredLabelsArray=()

declare -A foundLabelsTeamID=()
declare -A foundLabelsAppVersion=()
declare -A foundLabelsPackageID=()
declare -A foundLabelsVersionKey=()
declare -A requiredLabelsPath=()

# default paths
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

InstallomatorPATH=("/usr/local/Installomator/Installomator.sh")
defaultConfigfile=("/Library/Application Support/Patchomator/patchomator.plist")
managedConfigfile=("/Library/Managed Preferences/com.mac-nerd.patchomator.plist")
#patchomatorPath=$(dirname $(realpath $0)) # default install at /usr/local/Installomator/

# "realpath" doesn't exist on Monterey.
patchomatorPath="/usr/local/Installomator/"
fragmentsPATH=("${patchomatorPath}fragments")

# Pretty print, ignored if no terminal (eg, running via MDM)
BOLD=$(tput bold 2>/dev/null)
RESET=$(tput sgr0 2>/dev/null)
RED=$(tput setaf 1 2>/dev/null)
YELLOW=$(tput setaf 3 2>/dev/null)

if [[ -f /usr/local/bin/dialog ]]; then
	DialogPATH="/var/tmp/patch_dialog.log"
 	rm -rf $DialogPATH
	touch "$DialogPATH" 2> /dev/null && chmod a+rw "$DialogPATH" || error "$DialogPATH not writable."
fi

[[ -w "$DialogPATH" ]] || DialogPATH="/dev/null"

recommendedIgnores=("bbedit" "firefox" "firefox_da" "firefox_intl" "firefoxesr" "firefoxesr_intl" "firefoxpkg_intl" "googlechrome" "googlechromeenterprise"
	"microsoftofficebusinesspro" "microsoftonedrive-deferred" "microsoftonedrive-rollingout" "microsoftonedrive-rollingoutdeferred" "microsoftonedrivesuinsiders"
 	"microsoftonedrivesuprod" "microsoftoutlook-monthly")

#######################################
# Functions

usage() {
	echo "\n${BOLD}Usage:${RESET}"
	echo "\tpatchomator.sh [ -ryqvIh -c configfile -p InstallomatorPATH ]\n"
	echo "${BOLD}Default:${RESET}"
	echo "\tScans the system for installed apps and matches them to Installomator labels.\n"
	echo "\t${BOLD}--version \t${RESET} Show version and exit."
	echo "\t${BOLD}--fullversion \t${RESET} Show full version and exit."
	echo "\t${BOLD}--proxy \"proxyIP:Port\" \t${RESET} Show version and exit."
	echo "\t${BOLD}--required \"space-separated list of labels to require\""
	echo "\t${BOLD}--ignored \"space-separated list of labels to ignore\"${RESET}\n\t\t If list contains ${YELLOW}'ALL'${RESET} then discovery will be skipped\n\t\t If list contains ${YELLOW}'RECOMMENDEDIGNORES'${RESET} then the recommended list of ignores will be appended.\n"
	echo "\t${BOLD}-h | --help \t${RESET} Show this text and exit."
	echo "\t${BOLD}-w | --write \t${RESET} Write Config. Creates a new config file or refreshes an existing one."
	echo "\t${BOLD}-r | --read \t${RESET} Read Config. Parses and displays an existing config file."
	echo "\t${BOLD}-c | --config \"path to config file\" \t${RESET} Overrides default configuration file location. \n\t\tDefault path ${YELLOW}$defaultConfigfile${RESET}"
	echo "\t${BOLD}-e | --everywhere\t${RESET} Search the entire filesystem for matching apps."
	echo "\t${BOLD}-y | --yes \t${RESET} Non-interactive mode. Accepts the default (usually nondestructive) choice at each prompt. Use with caution."
	echo "\t${BOLD}-q | --quiet \t${RESET} Quiet mode. Minimal output."
	echo "\t${BOLD}-v | --verbose \t${RESET} Verbose mode. Logs more information to stdout. Overrides ${BOLD}--quiet${RESET}"
	echo "\t${BOLD}-s | --skipverify \t${RESET} Skips the signature verification step for discovered apps. ${BOLD}Does not skip verifying on installation.${RESET}"
	echo "\t${BOLD}-g | --gatekeeper \t${RESET} Use spctl to check app against gatekeeper instead of using codesign."
	echo "\t${BOLD}-I | --install \t${RESET} Install mode. This parses an existing configuration and sends the commands to Installomator to update. ${BOLD}Requires sudo${RESET}"
	echo "\t${BOLD}-u | --updatescripts \t${RESET} Update scripts mode. This can be used with install mode to update the installomator and patchomator scripts.\n\t\tThis mode only updates scripts if they have been discovered or added to required list.${BOLD}Requires sudo${RESET}\n"
	echo "\t${BOLD}-p | --pathtoinstallomator \"path to Installomator.sh\"${RESET}\n\t\tDefault Installomator Path ${YELLOW}/usr/local/Installomator/Installomator.sh${RESET}"
	echo "\t${BOLD}-o | --options \"option1=value option2=value ...\"${RESET}\tCommand line options passed through to Installomator.${RESET}"
	echo "${YELLOW}See readme for more options and examples: ${BOLD}https://github.com/mac-nerd/Patchomator${RESET}"
	exit 0
}

caffexit () {
	kill "$caffeinatepid"
	finishAndExit $1
}

finishAndExit () {
	echo "Patchomator finished: $(date '+%F %H:%M:%S')" | tee -a "$logPATH"
	(( ${#quietmode} )) || (( ${#readconfig} )) || echo "quit:" >> $DialogPATH
	exit $1
}

makepath() { # creates the full path to a file, but not the file itself
	mkdir -p "$(sed 's/\(.*\)\/.*/\1/' <<< $1)" # && touch $1
}

notice() { # verbose mode
	if (( ${#verbose} )); then
		echo "${YELLOW}[NOTICE]${RESET} $1" | tee -a "$logPATH"
	fi
}

infoOut() { # normal messages
	if (( ! ${#quietmode} )); then
		echo "$1" | tee -a "$logPATH"
		echo "progresstext: $1" >> $DialogPATH
	fi
}

error() { # bad, but recoverable
	echo "${BOLD}[ERROR]${RESET} $1" | tee -a "$logPATH"
	let errorCount++
}

fatal() { # something bad happened.
	echo "\n${BOLD}${RED}[FATAL ERROR]${RESET} $1\n\n" | tee -a "$logPATH"
	finishAndExit 1
}

# --read
# --write
displayConfig() {
	# if a config file exists and write or read config mode then read from file
	if [[ -f $defaultConfigfile ]] && ( (( ${#writeconfig} )) || (( ${#readconfig} )) )
	then
		echo "\n${BOLD}Currently configured labels:${RESET}"
		column -t -s "=;\"\"" <<< $(defaults read "$defaultConfigfile" | tr -d "{}()\"")
	else
		# if no config was saved, show the results of the discovery process
		echo "\n${BOLD}Found labels:${RESET}"
		printf "%s\n" ${(o)configArray}

		echo "\n${BOLD}Ignored Labels:${RESET}"
		printf "%s\n" ${(o)${(k)ignoredLabelsArray//\"/}}

		echo "\n${BOLD}Required Labels:${RESET}"
		printf "%s\n" ${(o)${(k)requiredLabelsArray//\"/}}
		echo ""
	fi
}

checkInstallomator() {

	infoOut "Checking Installomator version."
	# check for existence of Installomator to enable installation of updates
	notice "Looking for Installomator.sh at ${YELLOW}$InstallomatorPATH ${RESET}"

	if ! [[ -f $InstallomatorPATH ]]
	then
		error "Installomator was not found at ${YELLOW}$InstallomatorPATH ${RESET}"
		if (( ${#noninteractive} )); then
			notice "Running in non-interactive mode. Skipping Installomator install."
		else
			OfferToInstall
		fi
	fi

	InstalledVersion="$($InstallomatorPATH version | tail -1)"

	if [ $(echo $InstalledVersion | cut -d . -f 1) -lt 10 ]
	then
		fatal "Installomator is installed, but is out of date. Versions prior to 10.0 function unpredictably with Patchomator.\nYou can probably update it by running \n\t${YELLOW}sudo $InstallomatorPATH installomator ${RESET}"
	fi

	LatestVersion="$(versionFromGit Installomator Installomator)"
	[[ "$LatestVersion" == *"could not retrieve version"* ]] && LatestVersion=""

	if [[ -z "$LatestVersion" ]] && [[ -n "$InstalledVersion" ]]; then
		notice "Installomator is installed, but cannot check for latest version."
	fi

	if [[ -n "$LatestVersion" ]] && [[ -n "$InstalledVersion" ]]; then
		notice "Latest Version: $LatestVersion - Installed Version: $InstalledVersion"
		if ! is-at-least "$LatestVersion" "$InstalledVersion"; then
			error "Installomator was found, but is out of date. You can update it by running \n\t${YELLOW}sudo $InstallomatorPATH installomator ${RESET}"
			if (( ${#noninteractive} ))
			then
				notice "Running in non-interactive mode. Skipping Installomator update."
			else
				OfferToInstall
			fi
		fi
	fi

	if (( ${#installmode} )) && ! [[ -f $InstallomatorPATH ]]; then
		fatal "Cannot run patchomator in install mode without installomator."
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
			if (( ${#installmode} ))
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

	infoOut "Checking for latest labels."
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
				infoOut "Package labels are out of date. Last updated ${labelsAge} days ago. Attempting to download from https://github.com/installomator/"
				downloadLatestLabels
			else
				fatal "Package labels are out of date. Last updated ${labelsAge} days ago. Re-run patchomator with sudo to update them."

			fi

		else
			infoOut "Package labels installed. Last updated ${labelsAge} days ago."
		fi
	fi

}

dialogProgress() {
	if (( ! ${#quietmode} )); then
		echo "message: $1" >> $DialogPATH
		echo "progress: reset" >> $DialogPATH
	fi
}

dialogPercent() { # steps / max
	if (( ! ${#quietmode} )); then
		echo "progress: $((100*$1/$2))" >> $DialogPATH
	fi
}
dialogReset() {
	if (( ! ${#quietmode} )); then
		echo "progress: reset" >> $DialogPATH
	fi
}

rollLogs() {
	notice "Rolling over logs. Max logs is $backupLogsMax."
	for (( i=backupLogsMax; i>=1; i-- )); do
		prevLog=$((i-1))
		if [[ $prevLog -eq 0 ]]; then
			srcLog="$logPATH"
		else
			srcLog="$logPATH.$prev"
		fi
		destLog="$logPATH.$i"

	 	if [[ -f "$srcLog" ]]; then
			mv -f "$srcLog" "$destLog"
		fi
	done
	touch "$logPATH" 2> /dev/null && chmod a+rw "$logPATH" || error "$logPATH not writable."
}

downloadLatestLabels() {

	dialogProgress "Downloading latest labels."

	dialogPercent 1 5
	# gets the latest release version tarball.
	latestURL=$(curl -sSL -o - "https://api.github.com/repos/Installomator/Installomator/releases/latest" | grep tarball_url | awk '{gsub(/[",]/,"")}{print $2}') # remove quotes and comma from the returned string
	#eg "https://api.github.com/repos/Installomator/Installomator/tarball/v10.3"

	temptarDirectory=$( mktemp -d )
	tarPath="$temptarDirectory/installomator.latest.tar.gz"

	notice "Downloading ${latestURL} to ${tarPath}"
	dialogPercent 2 5

	curl -sSL -o "$tarPath" "$latestURL" || fatal "Unable to download. Check ${temptarDirectory} is writable or re-run as root."

	dialogPercent 3 5

	notice "Extracting ${tarPath} into ${patchomatorPath}"
	tar -xz --include='*/fragments/*' -f "$tarPath" --strip-components 1 -C "$patchomatorPath" || fatal "Unable to extract ${tarPath}. Corrupt or incomplete download?"
	touch "${fragmentsPATH}/labels/"
	dialogPercent 5 5

	# Remove the temporary working directory when done
	notice "Deleting working directory '$temptarDirectory' and its contents"
	rm -Rf "$temptarDirectory"
}

# --install
doInstallations() {

	infoOut "Performing installations."

	# No sleeping
	/usr/bin/caffeinate -d -i -m -u &
	caffeinatepid=$!

	# Count errors
	errorCount=0

	InstallomatorOptionsString=""

	if [[ -n "$OptionsString" ]]; then
		InstallomatorOptionsString+="$OptionsString"
	else
		# convert InstallomatorOptions array to string
		for key value in ${(kv)InstallomatorOptions}; do
			InstallomatorOptionsString+=" $key=\"$value\""
		done
	fi

	installedLabels=0
	dialogProgress "Installing $numLabels items."

	for label in $queuedLabelsArray
	do
		let installedLabels++
		dialogPercent $installedLabels $numLabels

		infoOut "Installing ${label}..."

		if [[ "$label" == "installomator" ]] || [[ "$label" == "patchomator" ]]; then
			if (( ! ${#updatescripts} )); then
				infoOut "${BOLD}Skipping $label.${RESET}\n"
				continue
			fi
		fi

		${InstallomatorPATH} ${label} ${InstallomatorOptionsString}
		installomatorStatus=$(echo $?)
		if [ $installomatorStatus != 0 ]; then
			error "Error installing ${label}. Exit code $installomatorStatus\n"
		fi
	done

	infoOut "Errors: $errorCount"
	caffexit $errorCount

}


FindAppFromLabel() {
# appname label_name packageID
	label_name=$1
	installLocation=""
	applist=""

	notice "Label: $label_name"

	if [ -z "$appName" ]; then
		# when not given derive from name
		appName="$name.app"
	fi

	# if the appversion is already set, there is an appCustomVersion function defined
	# check the funtion to see if it uses defaults read for an Info.plist for the app
	# if that exists, we can parse the file path from the function

	if [[ -n "$appversion" ]]; then
		if echo "$appCustomVersion" | grep -q 'Contents/Info\.plist'; then
			installLocation=$(echo "$appCustomVersion" | tr -d '\n' | sed -n 's|.*defaults read *"\{0,1\}\([^"]\{1,\}\)/Contents/Info.plist.*|\1|p')
			if [[ -d "$installLocation" ]]; then
				notice "Found: ${installLocation}"
				applist="$installLocation"
			fi
		fi
	fi

	# shortcut: pkgs contains a version number, if it's installed then we don't have to search the HD for the file
	# still need to confirm it's installed, tho. Receipts can be unreliable.

	if [[ -n "$packageID" ]] && [[ -z "$applist" ]]; then
		notice "Searching system for $packageID"
		appversion="$(pkgutil --pkg-info-plist ${packageID} 2>/dev/null | grep -A 1 pkg-version | tail -1 | sed -E 's/.*>([0-9.]*)<.*/\1/g')"
		if [[ -n "$appversion" ]]; then
			notice "--- found packageID $packageID version $appversion installed"
			installLocation="$(pkgutil --pkg-info-plist ${packageID} 2>/dev/null | grep -A 1 install-location | tail -1 | sed -E 's/.*>(.*)<.*/\1/g')"
			installLocation=${installLocation%/}
			if [ -f "/${installLocation}/$name.sh" ]; then
				notice "Found: /${installLocation}/$name.sh"
				applist="/${installLocation}/$name.sh"
			else
				for ext in .app .plugin .prefPane .framework .kext; do
					if [ -d "/${installLocation}${ext}" ]; then
						notice "Found: /${installLocation}${ext}"
						applist="/${installLocation}${ext}"
						break
					fi
				done
			fi
		fi
	fi

	# get app in /Applications, or /Applications/Utilities, or find using Spotlight if not already found

	if [[ -z "$applist" ]]; then
		notice "Searching system for $appName"
		if [[ -z "$mdfindAppList" ]]; then
			if (( ${#everywhere} )); then
				mdfindAppList=$(mdfind "kMDItemContentType == 'com.apple.application-bundle'")
			else
				mdfindAppList=$(mdfind -onlyin "/Applications/" -onlyin "/usr/local/" -onlyin "/Library/" "kMDItemContentType == 'com.apple.application-bundle'")
			fi
		fi
		applist=$(grep "/$appName" <<< "$mdfindAppList")
	fi

	appPathArray=( ${(0)applist} )

	if [[ ${#appPathArray} -gt 0 ]]
	then

		filteredAppPaths=( ${(M)appPathArray:#${targetDir}*} )

		if [[ ${#filteredAppPaths} -eq 1 ]]
		then
			installedAppPath=$filteredAppPaths[1]

			[[ -n "$appversion" ]] || appversion=$(defaults read "$installedAppPath/Contents/Info.plist" "$versionKey" 2> /dev/null)

			infoOut "-- Found $name version $appversion"

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
				foundLabelsTeamID[$label_name]="$expectedTeamID"
				foundLabelsAppVersion[$label_name]="$appversion"
				foundLabelsPackageID[$label_name]="$packageID"
				foundLabelsVersionKey[$label_name]="$versionKey"

				if [[ "${requiredLabelsArray[$label_name]}" == 1 ]]; then
					requiredLabelsPath["$installedAppPath"]="$label_name"
				fi
			fi
		fi
	fi
}


verifyApp() {
	foundLabel="$1"
	appPath="$2"
	appNewVersion=""

	infoOut "Verifying: $appPath"
	notice "--- Processing Label $foundLabel at $appPath"

	if [[ -n "$configArray[$appPath]" ]]
	then
		infoOut "$appPath already verified."
	else
		if (( ! ${#skipVerify} ))
		then
			# verify with spctl or codesign
			if (( ${#useSpctl} )); then
				appVerify=$(spctl -a -vv "$appPath" 2>&1 )
			else
				appVerify=$(codesign -dv "$appPath" 2>&1 )
			fi
			appVerifyStatus=$(echo $?)

			# If there is no usable signature and the app type is .plugin, then try another method
			# Found useful for JRE since Oracle does not sign JRE Plugin, but does sign in bin

			if [[ "$appVerify" == *"not signed at all" ]] || [[ "$appVerify" == *"no usable signature" ]]; then
				if [[ "$appPath" == *".plugin" ]]; then
					teamIdentifiers="$(find "$appPath/Contents/Home/Bin" -type f -exec codesign -dv {} 2>&1 \; | grep TeamIdentifier | sort -u)"
					if [[ -n "$teamIdentifiers" ]]; then
						idCount=$(printf "%s\n" "$teamIdentifiers" | wc -l | tr -d ' ')
						if ((idCount > 1)); then
							error "Error verifying $appPath"
							notice "Team IDs do not match: expected: $expectedTeamID, found multiple IDs in plugin Home/Bin directory"
							return
						fi
						teamID="${teamIdentifiers#*=}"
					else
	 					error "Error verifying $appPath"
						notice "Team IDs do not match: expected: $expectedTeamID, found no IDs in plugin Home/Bin directory"
	 					return
					fi
				elif [[ "$appPath" == *".sh" ]]; then
					verifyScript
					verifyScriptStatus=$(echo $?)
					if [[ $verifyScriptStatus -gt 1 ]]; then
						error "Error verifying the script."
						return
					elif [[ $verifyScriptStatus -eq 1 ]]; then
						infoOut "The script has been modified from it's original version."
						infoOut "\t${BOLD}Skipping.${RESET}"
						return
					fi
				fi
			else
				if [[ $appVerifyStatus -ne 0 ]]; then
					error "Error verifying $appPath: Returned $appVerifyStatus"
					return
				fi
				if (( ${#useSpctl} )); then
					teamID=$(echo $appVerify | awk '/origin=/ {print $NF }' | tr -d '()' )
				else
					teamID=${$(grep 'TeamIdentifier' <<< "$appVerify")#*=}
				fi
			fi

			if [ "$expectedTeamID" != "$teamID" ]; then
				error "Error verifying $appPath"
				notice "Team IDs do not match: expected: $expectedTeamID, found $teamID"
				return
			fi

		fi
	fi
	# build array of labels for the config and/or installation
	# push label to array
	# if in write config mode, writes to plist. Otherwise to an array.
	if [[ -n "$configArray[$appPath]" ]]
	then
		exists="$configArray[$appPath]"

		infoOut "${appPath} already linked to label ${exists}."
		if (( ${#noninteractive} ))
		then
			infoOut "\t${BOLD}Skipping.${RESET}"
			return
		else
			echo -n "${BOLD}Replace label ${exists} with $foundLabel? ${YELLOW}[y/N]${RESET} "
			read replaceLabel

			if [[ $replaceLabel =~ '[Yy]' ]]
			then
				infoOut "\t${BOLD}Replacing.${RESET}"
				configArray[$appPath]=$foundLabel

				# add replaced label to Ignored list
				ignoredLabelsArray["$exists"]=1

				if (( ${#writeconfig} ))
				then
					/usr/libexec/PlistBuddy -c "set \":${appPath}\" ${foundLabel}" "$defaultConfigfile"
					/usr/libexec/PlistBuddy -c "add \":IgnoredLabels:\" string \"${exists}\"" $defaultConfigfile
				fi
			else
				infoOut "\t${BOLD}Skipping.${RESET}"
				# add skipped label to Ignored list
				ignoredLabelsArray["$foundLabel"]=1

				if (( ${#writeconfig} ))
				then
					/usr/libexec/PlistBuddy -c "add \":IgnoredLabels:\" string \"${foundLabel}\"" $defaultConfigfile
				fi
				return
			fi
		fi
	else
		configArray[$appPath]=$foundLabel
		if (( ${#writeconfig} ))
		then
			/usr/libexec/PlistBuddy -c "add \":${appPath}\" string ${foundLabel}" "$defaultConfigfile"
		fi
	fi

	# If appversion was not found from eval then try a couple other methods
	[[ -n "$appversion" ]] || appversion="$(pkgutil --pkg-info-plist ${packageID} 2>/dev/null | grep -A 1 pkg-version | tail -1 | sed -E 's/.*>([0-9.]*)<.*/\1/g')"
	[[ -n "$appversion" ]] || appversion=$(defaults read "$appPath/Contents/Info.plist" "$versionKey" 2>/dev/null)

	[[ -n "$appversion" ]] && notice "--- Installed version: ${appversion}"

	if [[ -z "$appNewVersion" ]] && grep -q '^\s*appNewVersion' "$labelFragment" && (( ! ${#quietmode} )); then
		linesToEval="case $foundLabel in
			$foundLabel|\
			$(cat $labelFragment)
			esac"
		appNewVersion=$(zsh <<-EOF
			DEBUG=1 && INSTALL="force"
			declare -A levels=(DEBUG 0 INFO 1 WARN 2 ERROR 3 REQ 4)
			currentUser=$currentUser
			source "$fragmentsPATH/functions.sh"
			printlog() { }
			cleanupAndExit() { }
			$(printf '%s\n' "${linesToEval}") 2>/dev/null
			echo "\$appNewVersion"
			EOF
		)
	fi

	if [[ -n "$appNewVersion" ]]; then
		notice "--- Newest version: ${appNewVersion}"
		if is-at-least "$appNewVersion" "$appversion"; then
			infoOut "--- Latest version installed."
			appUpToDateList+=($foundLabel)
		else
			infoOut "--- Newer version available."
			let appNeedsUpdates++
		fi
	else
		infoOut "--- Unable to find newest version."
		let appNeedsUpdates++
	fi

	if (( ${#installmode} )); then
		labelsList+="$foundLabel "
	fi

	let uniqueAppTotal++
}

verifyScript() {
	downloadURL=""
	type=""
	local retval=0
	eval $(grep -E -m1 '^\s*type' "$labelFragment") 2>/dev/null
	labelDownloadUrl=$(grep -E -m1 '^\s*downloadURL' "$labelFragment")
	if grep -q '^\s*appNewVersion' "$labelFragment"; then
		linesToEval="case $foundLabel in
			$foundLabel|\
			$(cat $labelFragment)
			esac"
		appNewVersion=$(zsh <<-EOF
			DEBUG=1 && INSTALL="force"
			declare -A levels=(DEBUG 0 INFO 1 WARN 2 ERROR 3 REQ 4)
			currentUser=$currentUser
			source "$fragmentsPATH/functions.sh"
			printlog() { }
			cleanupAndExit() { }
			$(printf '%s\n' "${linesToEval}") 2>/dev/null
			echo "\$appNewVersion"
			EOF
		)
	fi
	if [[ "$appNewVersion" == "$appversion" ]]; then
		eval "$labelDownloadUrl" 2>/dev/null
	elif [[ "$labelDownloadUrl" == *"downloadURLFromGit"* ]]; then
		labelDownloadUrl=(${(s: :)labelDownloadUrl})
		local gitusername=$(echo "$labelDownloadUrl" | awk '{print $2}')
		local gitreponame=$(echo "$labelDownloadUrl" | awk '{print $3}')
		downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/tags/$appversion" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }")
		[[ -z "$downloadURL" ]] && downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/tags/v$appversion" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }")
	else
		notice "Unsure how to handle a download URL that is not the latest release from anywhere but github."
		return 2
	fi
	if [[ -n "$downloadURL" ]] && [[ "$type" == "pkg" ]]; then
		tmpPkgFile="/tmp/$foundLabel.pkg"
		notice "Downloading $downloadURL"
		curl -sfL "$downloadURL" > "$tmpPkgFile" 2>/dev/null
		if (( ${#useSpctl} )); then
			scriptVerify=$(spctl -a -vv -t install "$tmpPkgFile" 2>&1 )
		else
			scriptVerify=$(pkgutil --check-signature "$tmpPkgFile" 2>&1 )
		fi
		scriptVerifyStatus=$(echo $?)
		if [[ $scriptVerifyStatus -eq 0 ]]; then
			if (( ${#useSpctl} )); then
				teamID=$(echo $scriptVerify | awk '/origin=/ {print $NF }' | tr -d '()' )
			else
				teamID=$(echo $scriptVerify | awk '/Developer ID Installer/ {print $NF }' | tr -d '()' )
			fi
			if [[ "$expectedTeamID" == "$teamID" ]]; then
				baseTmpPkgFile=$(basename $tmpPkgFile)
				expandedPkg="/tmp/${baseTmpPkgFile}_pkg"
				pkgutil --expand-full "$tmpPkgFile" "$expandedPkg" 2>/dev/null
				if [[ -d "$expandedPkg" ]]; then
					fileHashFromPkg=$(md5 -q "$expandedPkg"/*.pkg/Payload/*.sh || md5 -q "$expandedPkg"/Payload/*.sh) 2>/dev/null
					if [[ -n "$fileHashFromPkg" ]]; then
						fileHashFromHD=$(md5 -q "${appPath}") 2>/dev/null
						notice "Pkg Hash:$fileHashFromPkg - File Hash:$fileHashFromHD"
						if [[ "$fileHashFromPkg" != "$fileHashFromHD" ]]; then
							notice "Script file hashes do not match."
							retval=1
						fi
					else
						notice "Unable to get hash from pkg payload."
						retval=2
					fi
					rm -rf "$expandedPkg"
				else
					notice "Could not expand $archiveName to $expandedPkg"
					retval=2
				fi
			else
				notice "Team IDs do not match: expected: $expectedTeamID, found $teamID"
				retval=2
			fi
		else
			notice "Error verifying $archiveName: Returned $scriptVerifyStatus"
			notice "$scriptVerify"
			retval=2
		fi
		rm -rf "$tmpPkgFile"
	else
		notice "Unable to verify scripts not installed via a PKG"
		retval=2
	fi

	(( retval > 0 )) && teamID=""

	return $retval
}

#######################################
# You're probably wondering why I've called you all here...


# Command line options

#zparseopts -D -E -F -K -- \
zparseopts -D -E -F -K -- \
-help+=showhelp h+=showhelp \
-version+=showversion \
-fullversion+=showfullversion \
-install=installmode I=installmode \
-updatescripts=updatescripts u=updatesscripts \
-quiet=quietmode q=quietmode \
-yes=noninteractive y=noninteractive \
-verbose=verbose v=verbose \
-read=readconfig r=readconfig \
-write=writeconfig w=writeconfig \
-config:=configfile c:=configfile \
-skipverify=skipVerify s=skipVerify \
-gatekeeper=useSpctl g=useSpctl \
-pathtoinstallomator:=InstallomatorPATH p:=InstallomatorPATH \
-ignored:=ignoredLabels \
-required:=requiredLabels \
-mdm:=MDMName m:=MDMName \
-everywhere=everywhere e=everywhere \
-options:=CLIOptions o:=CLIOptions \
-proxy:=PROXY \
|| fatal "Bad command line option. See patchomator.sh --help"

# -h --help
#    --version
#    --fullversion
# -I --install
# -u --updatescripts
# -q --quiet
# -y --yes
# -v --verbose
# -r --read
# -w --write
# -c --config <config file path>
# -s --skip-verify
# -g --gatekeeper
# -p --pathtoinstallomator <installomator path>
#    --ignored <list of ignored apps>
#    --required <list of required apps>
# -m --mdm [one of jamf, mosyleb, mosylem, addigy, microsoft, ws1, other ] Any other Mac MDM solutions worth mentioning?
# -e --everywhere
# -o --options "list of installomator options to pass through"
#    --proxy <proxyIP:port>


# Show usage
# -h --help
if (( ${#showhelp} )); then
	usage
fi

if (( ${#showversion} )); then
	echo "$VERSION"
	exit 0
fi

if (( ${#showfullversion} )); then
	echo "$VERSIONDATE - $VERSION"
	echo "$VERSIONNAME"
	exit 0
fi

notice "Verbose Mode enabled." # and if it's not? This won't echo.

if [[ ${#configfile} -eq 0 ]] && [[ -f $managedConfigfile ]]; then
	defaultConfigfile=$managedConfigfile
elif [[ ${#configfile} -gt 0 ]]; then
	defaultConfigfile=$configfile[-1] # either provided on the command line, or default path
fi


# prevent patchomator modify the content of the managed config
if [[ $defaultConfigfile == $managedConfigfile ]] && (( ${#writeconfig} ))
then
	fatal "You should not manualy overwrite ${YELLOW}$managedConfigfile${RESET}"
fi

InstallomatorPATH=$InstallomatorPATH[-1] # either provided on the command line, or default /usr/local/Installomator

if [[ -n $PROXY[-1] ]]; then
	infoOut "Proxy defined: $PROXY[-1], testing access to it"
	proxyAddress=$(echo $PROXY[-1] | cut -d ":" -f1)
	portNumber=$(echo $PROXY[-1] | cut -d ":" -f2)
	infoOut "Proxy: $proxyAddress, Port: $portNumber"
	if cmdOutput=$(! nc -z -v -G 10 ${proxyAddress} ${portNumber} 2>&1) ; then
		infoOut "$cmdOutput"
		infoOut "ERROR : No proxy connection, skipping this."
	else
		infoOut "Proxy access detected, so using that."
		export ALL_PROXY="$PROXY[-1]"
	fi
fi

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
[DEBUG]=-1
)

# Parse command line --options
OptionsString=$CLIOptions[-1]

# split on spaces, then on =
# 	AddOptions=$(echo "$OptionsString" | awk -v OFS="\n" '{$1=$1}1' | awk -v FS="=" '{print "InstallomatorOptions+=\(["$1"]="$2"\)"}')

# Add them to the InstallomatorOptions array
#	eval "$AddOptions"

# Additional optional settings by MDM
#	if [ "$MDMName" ]
#	then
#		quietmode[1]=true
#	#	installmode=true
#		noninteractive[1]=true
#	fi
#
#	if [ "$MDMName" ]
#	then
#		# set logos for known MDM vendors
#		if [ "$MDMName" != "other" ]
#		then
#			InstallomatorOptions[LOGO]="$MDMName"
#		fi
#	fi

## Starting up. Need to log options, etc

## check log is writable and rollover if over size
if [[ -w "$logPATH" ]] then
#	#exists and writable check size
	fileSize=$(stat -f%z "$logPATH" 2>/dev/null)
	if (( fileSize > logSizeMax )); then
		rollLogs
	fi
elif [[ ! -f "$logPATH" ]] then
#	#doesn't exist
	touch "$logPATH" 2> /dev/null && chmod a+rw "$logPATH" || error "$logPATH not writable."
fi

echo "Patchomator starting: $(date '+%F %H:%M:%S')" | tee -a "$logPATH"

notice "Option Count ${#InstallomatorOptions[@]}"
notice "Installomator Options:"

for key value in ${(kv)InstallomatorOptions}; do
	notice " - $key=\"$value\""
done

# ReadConfig mode - read existing plist and display in pretty columns
# skips discovery and all the rest
# --read
if (( ${#readconfig} ))
then
	notice "Reading Config"

	if ! [[ -f $defaultConfigfile ]]
	then
		fatal "No config file at $defaultConfigfile. Run patchomator again with ${YELLOW}--write${RESET} to create one now.\n"
	else
		displayConfig
	fi

	finishAndExit 0
fi

# can't do anything without the label files.
checkLabels

## initiate swiftdialog if we're doing more than just reading config.

if (( ! ${#quietmode} )) && [[ -f /usr/local/bin/dialog ]] && [[ "$DialogPATH" != "/dev/null" ]]; then
	/usr/local/bin/dialog --title "Patchomator Progress" \
		--message "Starting Patchomator." \
		--icon "/usr/local/Installomator/patch-o-mater-icon.png" \
		--mini \
		--progress 100 \
		--button1text "..." \
		--ontop \
		--movable \
		--commandfile $DialogPATH & dialogPID=$!
	sleep 0.1
fi

if [[ -f $defaultConfigfile ]] && (( ! ${#writeconfig} ))
then
	infoOut "Reading existing configuration for labels"

	# parse the config for existing labels
	labelsFromConfig=($(defaults read "$defaultConfigfile" | grep -e ';$' | awk '{printf "%s ",$NF}' | tr -c -d "[:alnum:][:space:][\-_]" | tr -s "[:space:]"))
	ignoredLabelsFromConfig=($(defaults read "$defaultConfigfile" IgnoredLabels | awk '{printf "%s ",$NF}' | tr -c -d "[:alnum:][:space:][\-_]" | tr -s "[:space:]"))
	requiredLabelsFromConfig=($(defaults read "$defaultConfigfile" RequiredLabels | awk '{printf "%s ",$NF}' | tr -c -d "[:alnum:][:space:][\-_]" | tr -s "[:space:]"))

	for ignoredLabel in $ignoredLabelsFromConfig; do
		[[ -f "${fragmentsPATH}/labels/${ignoredLabel}.sh" ]] && ignoredLabelsArray["$ignoredLabel"]=1
	done

	for requiredLabel in $requiredLabelsFromConfig; do
		[[ -f "${fragmentsPATH}/labels/${requiredLabel}.sh" ]] && requiredLabelsArray["$requiredLabel"]=1
	done
fi


if (( ${#writeconfig} )); then
	# Create Config file if none already exists
	if ! [[ -f $defaultConfigfile ]] # no existing config
	then
		if [[ -d $defaultConfigfile ]] # common mistake, select a directory, not a filename
		then
			fatal "Please specify a file name for the configuration, not a directory.\n\tExample: ${YELLOW}patchomator --write --config \"/etc/patchomator.plist\""
		fi

		if [[ -d "$(dirname $defaultConfigfile)" ]] # directory exists
		then
			if [[ -w "$(dirname $defaultConfigfile)" ]] #directory is writable
			then
				infoOut "No existing config file at $defaultConfigfile. Creating one now."
			else
				# exists, but not writable
				fatal "$(dirname $defaultConfigfile) exists, but is not writable. Re-run patchomator with sudo to create the config file there, or use a writable path with\n\t ${YELLOW}--config \"path to config file\"${RESET}"
			fi
		else # directory doesn't exist
			infoOut "The path to $defaultConfigfile does not exist. Making path and creating file now."
			makepath "$defaultConfigfile"
		fi

		# creates a blank plist
		plutil -create xml1 "$defaultConfigfile" || fatal "Unable to create $defaultConfigfile. Re-run patchomator with sudo to create the config file there, or use a writable path with\n\t ${YELLOW}--config \"path to config file\"${RESET}"

		# add sections for label arrays
		/usr/libexec/PlistBuddy -c 'add ":IgnoredLabels" array' "${defaultConfigfile}"
		/usr/libexec/PlistBuddy -c 'add ":RequiredLabels" array' "${defaultConfigfile}"
	else
		# Clear config to write
		notice "Writing Config"

		if ! [[ -w $defaultConfigfile ]]
		then
			fatal "$defaultConfigfile is not writable. Re-run patchomator with sudo, or use a writable path with\n\t ${YELLOW}--config \"path to config file\"${RESET}"
		fi

		infoOut "Refreshing $defaultConfigfile"

		# empty the existing plist
		/usr/libexec/PlistBuddy -c "clear dict" "${defaultConfigfile}" &>/dev/null

		# add sections for label arrays
		/usr/libexec/PlistBuddy -c 'add ":IgnoredLabels" array' "${defaultConfigfile}"
		/usr/libexec/PlistBuddy -c 'add ":RequiredLabels" array' "${defaultConfigfile}"
	fi
fi


# MOAR Functions! miscellaneous pieces referenced in the occasional label
# Needs to confirm that labels exist first.
source "$fragmentsPATH/functions.sh"

# can't install without the 'mator
# can't check version without the functions.
checkInstallomator


if (( ${#installmode} )); then
	# Check your privilege
	if ! $IAMROOT
	then
		fatal "Install mode must be run with root/sudo privileges. Re-run Patchomator with\n\t ${YELLOW}sudo zsh patchomator.sh --install${RESET}"
	fi
fi


# --required
if [[ -n "$requiredLabels" ]]
then
	requiredLabelsList=("${(@s/ /)requiredLabels[-1]}")
	notice "[CLI] Requiring labels: $requiredLabelsList"

	for requiredLabel in $requiredLabelsList; do
		[[ ${requiredLabelsArray["$requiredLabel"]} == 1 ]] && continue
		if [[ -f "${fragmentsPATH}/labels/${requiredLabel}.sh" ]]
		then
			if (( ${#writeconfig} ))
			then
				/usr/libexec/PlistBuddy -c "add \":RequiredLabels:\" string \"${requiredLabel}\"" $defaultConfigfile
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

	notice "[CLI] Ignoring labels: $ignoredLabelsList"

	for ignoredLabel in $ignoredLabelsList; do
		[[ ${ignoredLabelsArray["$ignoredLabel"]} == 1 ]] && continue
		lowerLabel="${ignoredLabel:l}"
		if [[ "$lowerLabel" == "all" ]]; then
			notice "[CLI] Ignored=all. Skipping discovery."
			skipDiscovery=true
			break
		fi
		if [[ "$lowerLabel" == "recommendedignores" ]]; then
			notice "[CLI] Also ignoring labels: $recommendedIgnores"
			for recIgnoreLabel in $recommendedIgnores; do
				if [[ -f "${fragmentsPATH}/labels/${recIgnoreLabel}.sh" ]]; then
					if [[ ${#writeconfig} -eq 1 ]]; then
						/usr/libexec/PlistBuddy -c "add \":IgnoredLabels:\" string \"${recIgnoreLabel}\"" $defaultConfigfile
					fi
					ignoredLabelsArray["$recIgnoreLabel"]=1
				else
					error "No such label ${ignoredLabel}"
				fi
			done
			continue
		fi
		if [[ -f "${fragmentsPATH}/labels/${ignoredLabel}.sh" ]]; then
			if [[ ${#writeconfig} -eq 1 ]]; then
				/usr/libexec/PlistBuddy -c "add \":IgnoredLabels:\" string \"${ignoredLabel}\"" $defaultConfigfile
			fi
			ignoredLabelsArray["$ignoredLabel"]=1
		else
			error "No such label ${ignoredLabel}"
		fi
	done
fi


# discovery mode
# the main attraction.


# DISCOVERY PHASE

# get current user
currentUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')

uid=$(id -u "$currentUser")

notice "Current User: $currentUser (UID $uid)"

targetDir="/"
versionKey="CFBundleShortVersionString"

IFS=$'\n'

### MAIN EVENT

# for each .sh file in fragments/labels/ strip out the switch/case lines and any comments.
# get app name, label name, packageID


if [[ $skipDiscovery != true ]]; then
	# Discovery
	numFragments=$(ls "$fragmentsPATH"/labels/*.sh | wc -l | xargs)
	processedFragments=0

	dialogProgress "Processing $numFragments labels"

	for labelFragment in "$fragmentsPATH"/labels/*.sh; do

		let processedFragments++

		dialogPercent $processedFragments $numFragments

		labelFile=$(basename -- "$labelFragment")
		labelFile=${labelFile%.*}

		infoOut "Processing label $labelFile."

		while read -r labelInFile
		do
			if [[ $ignoredLabelsArray["$labelInFile"] -eq 1 ]]
			then
				notice "Ignoring labels in $labelFile."
				continue 2 # we're done here. Move along.
			fi

		done < <(grep -E '^([a-z0-9\_-]*)(\)|\|\\)$' "$labelFragment" | sed -e 's/[\|\\\)]//g' )

		eval $(grep -E -m1 '^\s*expectedTeamID' "$labelFragment") 2>/dev/null
		eval $(grep -E -m1 '^\s*name=' "$labelFragment") 2>/dev/null
		eval $(grep -E -m1 '^\s*packageID' "$labelFragment") 2>/dev/null
		eval $(grep -E -m1 '^\s*versionKey' "$labelFragment") 2>/dev/null
		eval $(grep -E -m1 '^\s*appName' "$labelFragment") 2>/dev/null
		versionKey="${versionKey:-CFBundleShortVersionString}"

		if grep -q '^\s*appCustomVersion\s*()' "$labelFragment"; then
			appCustomVersion=$(grep -E -m1 '^\s*appCustomVersion' "$labelFragment" | sed -E 's/^.*\(\)[[:space:]]*\{[[:space:]]*(.*)[[:space:]]*\}/\1/')
			if [[ -z "$appCustomVersion" ]] || [[ "$appCustomVersion" == *"{"$ ]]; then
				appCustomVersion=$(awk '
					/^[[:space:]]*appCustomVersion[[:space:]]*\(\)[[:space:]]*\{/ { inside=1; next }
					inside {
						if ($0 ~ /^[[:space:]]*\}/) { inside=0; exit }
						print
					}' "$labelFragment")
			fi
			if [[ ! "$appCustomVersion" =~ ^[[:space:]]*strings ]] || [[ -x /Library/Developer/CommandLineTools/usr/bin/strings ]]; then
				appversion=$(eval "$appCustomVersion" 2>/dev/null)
			fi
		fi

		if [[ -z $expectedTeamID ]] && (( ! ${#skipVerify} )); then
			error "Error in $labelFile. No Team ID."
		else
			FindAppFromLabel "$labelFile"
		fi

		#CLEANUP MODIFIED PARAMETERS
		expectedTeamID=""
		name=""
		packageID=""
		versionKey=""
		appName=""
		appCustomVersion=""
		appversion=""
	done

	totalFoundLabels=${#foundLabelsArray}
	processedLabels=0
	appNeedsUpdates=0
	appUpToDateList=()
	uniqueAppTotal=0

	dialogProgress "Processing $totalFoundLabels discovered labels"

	# for each app found, check version and verify
	for foundLabel appPath in ${(kv)foundLabelsArray};
	do
		let processedLabels++
		dialogPercent $processedLabels $totalFoundLabels

		if [[ -n ${requiredLabelsPath["$appPath"]} ]] && [[ "${requiredLabelsPath[\"$appPath\"]}" != "$foundLabel" ]]; then
			notice "$appPath assigned to required label ${requiredLabelsPath[\"$appPath\"]}"
			continue
		fi

		if [[ $ignoredLabelsArray["$foundLabel"] -ne 1 ]]; then
			expectedTeamID="${foundLabelsTeamID[$foundLabel]}"
			appversion="${foundLabelsAppVersion[$foundLabel]}"
			packageID="${foundLabelsPackageID[$foundLabel]}"
			versionKey="${foundLabelsVersionKey[$foundLabel]}"
			labelFragment="${fragmentsPATH}/labels/${foundLabel}.sh"

			if [[ -n $expectedTeamID ]] || (( ${#skipVerify} )); then
				verifyApp "$foundLabel" "$appPath"
			fi
		fi
	done

	if (( appNeedsUpdates > 0 )); then
		infoOut "${BOLD}$appNeedsUpdates of the $uniqueAppTotal found labels need updates.${RESET}"
	elif (( processedLabels > 0 )); then
		infoOut "${BOLD}None of the found apps need updates.${RESET}"
	fi
fi
# end discovery

# install mode. Requires root and Installomator
# --install
if (( ${#installmode} )); then
	IFS=' '
	#add variables discovered earlier to these lists
	if [[ $skipDiscovery == true ]]; then
		labelsList+=($labelsFromConfig)
	fi
	ignoredLabelsList+=($ignoredLabelsFromConfig)
	requiredLabelsList+=($requiredLabelsFromConfig)

	# add required labels to list
	labelsList+=($requiredLabelsList)

	# deduplicate labels and remove extra spacing with awk
	ignoredLabelsList=($(tr ' ' '\n' <<< "${ignoredLabelsList[@]}" | sort -u | awk 'NF' | tr '\n' ' '))
	requiredLabelsList=($(tr ' ' '\n' <<< "${requiredLabelsList[@]}" | sort -u | awk 'NF' | tr '\n' ' '))
	labelsList=($(tr ' ' '\n' <<< "${labelsList[@]}" | sort -u | awk 'NF' | tr '\n' ' '))
	appUpToDateList=($(tr ' ' '\n' <<< "${appUpToDateList[@]}" | sort -u | awk 'NF' | tr '\n' ' '))

	# remove ignored labels and up to date labels
	filteredLabelsList=("${ignoredLabelsList[@]}" "${appUpToDateList[@]}") 
	installLabelsList=()
	for label in "${labelsList[@]}"; do
		if [[ ! " ${filteredLabelsList[@]} " =~ " ${label} " ]]; then
			installLabelsList+=("$label")
		fi
	done
	labelsList=("${installLabelsList[@]}")

	[[ ${#appUpToDateList} -gt 0 ]] && notice "Up to date apps: $appUpToDateList"
	notice "Labels to install: $labelsList"
	notice "Ignoring labels: $ignoredLabelsList"
	notice "Required labels: $requiredLabelsList"

	queuedLabelsArray=("${(@s/ /)labelsList}")
	numLabels=${#queuedLabelsArray[@]}

	if [[ $numLabels > 0 ]]
	then
		infoOut "Passing $numLabels labels to Installomator: $queuedLabelsArray"
		doInstallations
	else
		infoOut "Nothing to do." # inbox zero
	fi

	finishAndExit 0
fi

# end install mode

if [ "$errorCount" -gt 0 ]
then
	infoOut "${BOLD}Completed with $errorCount errors.${RESET}\n"
else
	infoOut "${BOLD}Done.${RESET}\n"
fi

if (( ! (${#quietmode} && ${#writeconfig}) )); then
	displayConfig
fi

finishAndExit 0

#### That's a wrap. Don't forget to tip your server. You don't have to go home, but you can't stay here.
