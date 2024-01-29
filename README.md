![Patchomator icon and text](https://github.com/Mac-Nerd/patchomator/blob/main/images/patchomator-banner.png?raw=true)

# Patchomator
A management script for Installomator. Work in progress.

## What does it do?
Installomator uses small scripts designed to check if a specified app is installed, and if so, what version. If the latest version is not already installed, Installomator proceeds to download and install the necessary update. Each of these script fragments is a "label" used to call Installomator to install or update a particular app.

Patchomator extends Installomator into a more general purpose patching tool. The Patchomator script processes all of the available labels, and uses them to determine which apps are already installed on the Mac. This list is passed to Installomator to proceed with updating any that are out of date, and optionally saved in a configuration file to speed up subsequent runs.

Large portions of Patchomator code came directly from Installomator:
https://github.com/Installomator/Installomator

_Installomator is Copyright 2020 Armin Briegel, Scripting OS X_


## Installation

Download the latest PKG installer from the [Releases page](https://github.com/Mac-Nerd/patchomator/releases). 

Or you can download or clone this repo, copy or move `patchomator.sh` to the same location as Installomator, and set it executable.

```
curl -LO https://github.com/Mac-Nerd/patchomator/raw/main/patchomator.sh
chmod a+x patchomator.sh
sudo mv patchomator.sh /usr/local/Installomator/
```


## Usage

### Command line

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

`--options "option1=value, option2=value..."` 	 Command line options to pass to Installomator during installation mode. Multiple command line option should be separated by commas, and inside quotes. For more information, see the [Installomator Wiki](https://github.com/Installomator/Installomator/wiki/Configuration-and-Variables)

`-s` | `--skipverify`	Skips the signature verification step for discovered apps. *Does not skip verifying on installation.*

`-q` | `--quiet`	 *Quiet mode*. Minimal output.

`-v` | `--verbose`	 *Verbose mode*. Logs more information to stdout. Overrides -q

`-h` | `--help` 	 Show usage message and exits.


When run, Patchomator will prompt you to install Installomator, if it doesn't already exist at the default path or the one specified with `-p [InstallomatorPATH]`. Patchomator will happily run without Installomator, but won't actually install any updates by itself.

If the Installomator label files are not present, or are older than 30 days, they will be downloaded from the latest Installomator release on GitHub and put in a directory called "fragments" in the same directory as patchomator.sh

### Configuration

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

### MDM instructions

More detail coming soon. For now, have a look at [the MDM folder](https://github.com/Mac-Nerd/patchomator/tree/main/MDM) for a starting point.

If you currently use Patchomator with an MDM, please [open an issue](https://github.com/Mac-Nerd/patchomator/issues) and let me know if you have any questions, or want to share your setup.


### Ignored and Required Labels

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


## Swift Dialog

As of 1.1, Patchomator will display progress and other messages via [Swift Dialog](https://github.com/swiftDialog/swiftDialog), if the system has it installed.

![Patchomator dialog example](https://github.com/Mac-Nerd/patchomator/blob/main/images/progress-dialog.png?raw=true)

You can suppress these dialogs with the `--quiet` command line switch.

Currently, the dialogs cannot be customized. If you would like to be able to, please [open an issue](https://github.com/Mac-Nerd/patchomator/issues) and let me know.


## Patching with Patchomator

### Run discovery

```
% sudo /usr/local/Installomator/patchomator.sh

Package labels not present at /usr/local/Installomator/fragments. Attempting to download from https://github.com/installomator/
Downloading https://api.github.com/repos/Installomator/Installomator/tarball/v10.3 to /usr/local/Installomator/installomator.latest.tar.gz
Extracting /usr/local/Installomator/installomator.latest.tar.gz into /usr/local/Installomator
Processing label 1password7.
Found 1Password 7.app version 7.9.10
Processing label 1password8.
Processing label 1passwordcli.
Processing label 4kvideodownloader.
Processing label 8x8.
[...]
Processing label bbedit.
Found BBEdit.app version 14.6.5
Processing label bbeditpkg.
Found BBEdit.app version 14.6.5
/Applications/BBEdit.app already linked to label bbedit.
Replace label bbedit with bbeditpkg? [y/N] y
	Replacing.
Processing label betterdisplay.
Processing label bettertouchtool.
[...]
Processing label googlechrome.
Found Google Chrome.app version 112.0.5615.49
Processing label googlechromeenterprise.
Found Google Chrome.app version 112.0.5615.49
/Applications/Google Chrome.app already linked to label googlechrome.
Replace label googlechrome with googlechromeenterprise? [y/N] n
	Skipping.
Processing label googlechromepkg.
Found Google Chrome.app version 112.0.5615.49
/Applications/Google Chrome.app already linked to label googlechrome.
Replace label googlechrome with googlechromepkg? [y/N] y
	Replacing.
[...]
Completed with 13 errors.


Currently configured labels:
obs
handbrake
suspiciouspackage
dropbox
apparency
discord
blender
bbeditpkg
lulu
depnotify
thunderbird
tunnelblick
gotomeeting
1password7
visualstudiocode
brave
vlc
zoom
utm
signal
knockknock
hancock
googlechromepkg

Ignored Labels:

Required Labels:
```

### Write configuration

``` % sudo /usr/local/Installomator/patchomator.sh --write

No config file at /Library/Application Support/Patchomator/patchomator.plist. Creating one now.

File Doesn't Exist, Will Create: /Library/Application Support/Patchomator/patchomator.plist
Initializing Plist...
Package labels installed. Last updated 0 days ago.
Processing label 1password7.
Found 1Password 7.app version 7.9.10
Processing label 1password8.
[...]

Completed with 13 errors.


Currently configured labels:
    /Applications/1Password 7.app              1password7
    /Applications/Apparency.app                apparency
    /Applications/BBEdit.app                   bbeditpkg
    /Applications/Brave Browser.app            brave
    /Applications/Discord.app                  discord
    /Applications/Dropbox.app                  dropbox
    /Applications/GoToMeeting.app              gotomeeting
    /Applications/Google Chrome.app            googlechromepkg
    /Applications/Hancock.app                  hancock
    /Applications/HandBrake.app                handbrake
    /Applications/KnockKnock.app               knockknock
    /Applications/LuLu.app                     lulu
    /Applications/OBS.app                      obs
    /Applications/Signal.app                   signal
    /Applications/Suspicious Package.app       suspiciouspackage
    /Applications/Thunderbird.app              thunderbird
    /Applications/Tunnelblick.app              tunnelblick
    /Applications/UTM.app                      utm
    /Applications/Utilities/DEPNotify.app      depnotify
    /Applications/VLC.app                      vlc
    /Applications/Visual Studio Code.app       visualstudiocode
    /Applications/blender.app                  blender
    /Applications/zoom.us.app                  zoom
    IgnoredLabels                                  
    
    RequiredLabels                                 
```    

### Install and update

```
% sudo /usr/local/Installomator/patchomator.sh --install

[ERROR] Installomator was not found at /usr/local/Installomator/Installomator.sh 
Patchomator can still discover apps on the system and create a configuration for later use, but will not be able to install or update anything without Installomator. 		
Download and install Installomator now? [y/N] y

installer: Package name is 
installer: Upgrading at base path /
installer: Preparing for installation….....
installer: Preparing the disk….....
installer: Preparing ….....
installer: Waiting for other installations to complete….....
installer: Configuring the installation….....
installer: 	
#
installer: Validating packages….....
#
installer: 	Running installer actions…
installer: 	
installer: Finishing the Installation….....
installer: 	
#
installer: The software was successfully installed......
installer: The upgrade was successful.
Existing config found at /Library/Application Support/Patchomator/patchomator.plist.
Passing 25 labels to Installomator.
Installing 1password7...
2023-04-26 16:46:41 : INFO  : 1password7 : setting variable from argument BLOCKING_PROCESS_ACTION=tell_user
2023-04-26 16:46:41 : INFO  : 1password7 : setting variable from argument NOTIFY=success
2023-04-26 16:46:41 : REQ   : 1password7 : ################## Start Installomator v. 10.3, date 2023-02-10
2023-04-26 16:46:41 : INFO  : 1password7 : ################## Version: 10.3
[...]
2023-04-26 16:46:42 : REQ   : 1password7 : ################## End Installomator, exit code 0 

```

## Help! It's not working!

Sorry about that. If you're willing and able to help test, please report any problems by [opening an issue](https://github.com/Mac-Nerd/patchomator/issues). And if you can see where I've messed something up, I'm open to pull requests.


