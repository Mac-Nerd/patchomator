# patchomator
Management script for Installomator. Work in progress.

Large portions of this come directly from Installomator:
https://github.com/Installomator/Installomator

Installomator is Copyright 2020 Armin Briegel, Scripting OS X

This script must be run with root/sudo privileges, and requires Installomator already be installed.

Usage:
`patchomator.sh [ -r -v  -c configfile  -i InstallomatorPATH ]`

With no options, this will parse the config file for a list of labels, and execute Installomator to update each label. (TBD)

```
-r - Refresh config. Scans the system for installed apps and matches them to Installomator labels. Rebuilds the configuration file.
-c "path to config file" - Default configuration file location /etc/patchomator/config.txt
-i "path to Installomator.sh" - Default Installomator Path /usr/local/Installomator/Installomator.sh
-v - Verbose mode. Logs more information to stdout.
-h | --help - Shows this text.
