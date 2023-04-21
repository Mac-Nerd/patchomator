# Patchomator
A management script for Installomator. Work in progress.

## What does it do?
Installomator uses small scripts designed to check if a specified app is installed, and if so, what version. If the latest version is not already installed, Installomator proceeds to download and install the necessary update. Each of these script fragments is a "label" used to call Installomator to install or update a particular app.

Patchomator extends Installomator into a more general purpose patching tool. The Patchomator script processes all of the available labels, and uses them to determine which apps are already installed on the Mac. This list is passed to Installomator to proceed with updating any that are out of date, and optionally saved in a configuration file to speed up subsequent runs.

Large portions of Patchomator code came directly from Installomator:
https://github.com/Installomator/Installomator

_Installomator is Copyright 2020 Armin Briegel, Scripting OS X_


## Installation

*Patchomator install packages suitable for distribution via Jamf or other management platform are coming soon.* 
For now, download or clone this repo, copy or move patchomator.sh to a path that you have write access to, and set it executable.

```
curl -LO https://github.com/Mac-Nerd/patchomator/raw/main/patchomator.sh
chmod a+x patchomator.sh
mv patchomator.sh /usr/local/Installomator/
```


## Usage

 `./patchomator.sh`
*Dry Run.* Without the `--install` option, Patchomator will run interactively, and search the system for applications that can be upgraded by Installomator. The user will be prompted to yes/no when duplicate or ambiguous app names are found.

 `--yes`
The `--yes` option will accept the default or first choice at each prompt. Frustratingly, this is sometimes "No".

When finished, the script will output its findings but not install anything. The configuration won't be saved unless `--write` is specified.

 `--write` 
Runs as normal, and creates or updates a configuration file at the default plist path `/Library/Application Support/Patchomator/patchomator.plist`.

 `./patchomator.sh --read`
*Read Config.*
Displays the current configuration, based on an existing configuration file at the default plist path `/Library/Application Support/Patchomator/patchomator.plist`. 

 `./patchomator.sh --install [ --ignored "label1 label2" --required "label3 label4" ]`

*Install mode.* Scans the system for installed apps and matches them to Installomator labels. Launches Installomator to update any that are not current. If an existing configuration file is found, it will be used to skip the discovery step. *Test before use.*


*Additional switches.*
`--ignored "list of labels to ignore"`
`--required "list of labels to require"`
Optional lists of ignored and/or required labels can be added to fine-tune the installation operation. See the section "*Ignored and Required Labels*" for more details.

`--config "path to config file"`	Override the default configuration file location for `--read --write` or `--install` options.

`--pathtoinstallomator "path to Installomator.sh"`	Overrides the default Installomator path for `--install` option.

`-q` | `--quiet`	 *Quiet mode*. Minimal output.

`-v` | `--verbose`	 *Verbose mode*. Logs more information to stdout. Overrides -q

`-h` | `--help` 	 Show usage message and exits.


When run, Patchomator will prompt you to install Installomator, if it doesn't already exist at the default path or the one specified with `-p [InstallomatorPATH]`. Patchomator will happily run without Installomator, but won't actually install any updates by itself.

If the Installomator label files are not present, or are older than 30 days, they will be downloaded from the latest Installomator release on GitHub and put in a directory called "fragments" in the same directory as patchomator.sh

## Configuration

When written using the `--write` option, the file `patchomator.plist` contains a list of the applications found on the system, and the corresponding Installomator labels which can be used to install or update each. By default, Patchomator will look for its configuration file in `/Library/Preferences/Patchomator` but the full path can be overridden with the `-c` or `--config` command line switch.

The current state of the configuration can be read with the following command 

```
defaults read /Library/Preferences/Patchomator/patchomator.plist

{
    "/Applications/1Password 7.app" = 1password7;
    "/Applications/BBEdit.app" = bbedit;
    "/Applications/Discord.app" = discord;
    "/Applications/Dropbox.app" = dropbox;
    "/Applications/Suspicious Package.app" = suspiciouspackage;
    "/Applications/Utilities/DEPNotify.app" = depnotify;
    "/Applications/VLC.app" = vlc;
    IgnoredLabels =     (
        googlechrome,
        firefox,
        zoom
    );
    RequiredLabels =     (
        depnotify,
        gotomeeting
    );
}

```

or by running Patchomator.sh with the `-r` or `--read` command line switch.

This will also display two lists of Installomator labels, marked `IgnoredLabels` and `RequiredLabels`. See the next section for details. 


## Ignored and Required Labels

By default, if Patchomator detects an application is installed that corresponds to a known label, it will be added to the configuration and updated on subsequent runs. However, there are some apps that are best left alone - either to be updated via some other mechanism, or to be kept at a specific stable version. There are also apps that will match to multiple labels. For example, "Firefox.app" can be installed by any of the following labels: firefox_da, firefox_intl, firefox, firefoxdeveloperedition, firefoxesr_intl, firefoxesr, firefoxpkg_intl, firefoxpkg. To prevent an update clobbering an installed app, or grabbing the wrong version of an ambiguous one, labels can be set to "ignored".

Specific labels can be ignored in two ways. First, the `IgnoredLabels` array can be added to an existing `patchomator.plist` with the following command

```defaults write /path/to/patchomator.plist IgnoredLabels -array label1 label2 label3```

_Note: This will replace any existing `IgnoredLabels` array that already exists in the plist._

Alternately, you may ignore labels at runtime by listing them on the command line with the `--ignored` command line switch. The list of labels follows `--ignored` as a quoted string, separated by spaces.

```patchomator.sh --ignored "googlechrome googlechromeenterprise zoomclient zoomgov"```

Like ignored labels, you can also specify required labels. These are useful for apps that you want to be certain are consistently installed on every system, and reinstalled if they have been moved or uninstalled.

The `RequiredLabels` array works the same way in `patchomator.plist` as `IgnoredLabels`

```defaults write /path/to/patchomator.plist RequiredLabels -array label1 label2 label3```

and as a one-time switch on the command line with `--required`

```patchomator.sh --required "googlechromepkg zoom"```


## Patching with Patchomator




## Help! It's not working!

Sorry. It's not 100% finished and ready for production yet. If you're willing and able to help test, please report any problems by [opening an issue](https://github.com/Mac-Nerd/patchomator/issues) .


## Example Use


