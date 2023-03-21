# Patchomator
Management script for Installomator. Work in progress.

## What does it do?
Installomator uses small scripts designed to check if a specified app is installed, and if so, what version. If the latest version is not already installed, Installomator proceeds to download and install the necessary update. Each of these script fragments is a "label" used to call Installomator to install or update a particular app.

Patchomator extends Installomator to a more general purpose patching script. The Patchomator script processes all of the available labels, and uses them to determine which apps are already installed on the Mac. This list is then saved in a configuration file, and optionally passed to Installomator to proceed with updating any that are out of date. 

Large portions of this come directly from Installomator:
https://github.com/Installomator/Installomator

_Installomator is Copyright 2020 Armin Briegel, Scripting OS X_


## Installation

*Patchomator install packages suitable for distribution via Jamf or other management platform are coming soon.* 
For now, download or clone this repo, copy or move patchomator.sh to a path that you have write access to, and set it executable.

```
curl -LO https://github.com/Mac-Nerd/patchomator/raw/main/patchomator.sh
chmod a+x patchomator.sh
mv patchomator.sh "path to patchomator install"
```


## Usage
`patchomator.sh [ -r -v -I -c configfile  -i InstallomatorPATH ]`

All switches are optional.

 - `-r` - Refresh config. Scans the system for installed apps and matches them to Installomator labels. Rebuilds the configuration file.

 - `-c "path to config file"` - Default configuration file location ~/Library/Preferences/Patchomator/patchomator.plist

 - `-i "path to Installomator.sh"` - Default Installomator Path /usr/local/Installomator/Installomator.sh

 - `-v` - Verbose mode. Logs more information to stdout.

 - `-I` - Reads configuration file and passes commands to Installomator to install detected packages. _Requires sudo._

 - `-h` | `--help` - Shows this text.

On first run, patchomator will offer to install Installomator, if it's not found at the default path or the one specified with `-i [InstallomatorPATH]`.

If the label files are not present, or older than 7 days, they will be downloaded from the latest Installomator release and put in a directory called "fragments" in the same directory as patchomator.

With no other options selected, the script will create or refresh its configuration file (default ~/Library/Preferences/Patchomator/patchomator.plist). This keeps a list of the installed apps detected by patchomator, and their corresponding Installomator labels. 

When run with `sudo patchomator.sh -I` those labels are passed as parameters to the installed version of Installomator, which then runs through the installation/update process.

## Help! It's not working!

Sorry. It's not 100% finished and ready for production yet. If you're willing and able to help test, please report any problems by [opening an issue](https://github.com/Mac-Nerd/patchomator/issues) .



