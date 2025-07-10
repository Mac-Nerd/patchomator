![Patchomator icon and text](https://github.com/Mac-Nerd/patchomator/blob/1.1/images/patchomator-banner.png?raw=true)

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

 `-y` | `--yes`
The `--yes` option will accept the default or first choice at each prompt. Frustratingly, this is sometimes "No".

When finished, the script will output its findings but not install anything. The configuration won't be saved unless `--write` is specified.

 `-w` | `--write` 
Runs as normal, and creates or updates a configuration file at the default plist path `/Library/Application Support/Patchomator/patchomator.plist`.

 `-r` | `--read`
Displays the current configuration, based on an existing configuration file at the default plist path `/Library/Application Support/Patchomator/patchomator.plist`. 

 `-I` | `--install`
Scans the system for installed apps and matches them to Installomator labels. Launches Installomator to update any that are not up to date. If an existing configuration file is found, the ignored and required will be added or removed from the list of found apps. *Test before use.*

 `-I` | `--install` with `--ignored "ALL"`
Skips scanning the system for installed apps and launches Installomator to update all apps in a config file. If there is no config file, this will do nothing. *Test before use.*  
<br />

#### Additional switches

`--version`
Displays the current version of this script.

`--fullversion`
Displays the full version of this script including the build date and build name.

`--ignored "Space seperated list of labels to ignore"`  
`--required "Space seperated list of labels to require"`  
Optional list of ignored and/or required labels can be added to fine-tune the installation operation. See the section "*Ignored and Required Labels*" for more details.

`-e` | `--everywhere`
Allows for searching the entire filesystem for applications during discovery. By default, apps installed in /Applications, /usr/local and /Library are discovered.

`-c` | `--config "path to config file"`
Override the default configuration file location for `--read --write` or `--install` options.

`-p` | `--pathtoinstallomator "path to Installomator.sh"`
Overrides the default Installomator path for `--install` option.

`--options "option1=value option2=value ..."` 	 Command line options to pass to Installomator during installation mode. Multiple command line option should be separated by spaces, and inside quotes. For more information, see the [Installomator Wiki](https://github.com/Installomator/Installomator/wiki/Configuration-and-Variables)

`-s` | `--skipverify`
Skips the signature verification step for discovered apps. *Does not skip verifying on installation.*

`-q` | `--quiet`
*Quiet mode*. Minimal output.

`-v` | `--verbose`
*Verbose mode*. Logs more information to stdout. Overrides -q

`-h` | `--help`
Show usage message and exits.

`--proxy "pro.xy.addr.ess:port"`
Tests and sets the ALLPROXY environment variable if successful to the Proxy address using the specified port.

`-g` | `--gatekeeper`
Switches to using SPCTL to verify applications instead of the faster codesign. SPCTL checks Gatekeeper to make sure the application can run, while codesign just verifies the signature of the application.

`-u` | `--updatescripts`
Allow for Installomator and Patchomator scripts to be updated if they are not the latest version. *Test before use.*

When run, Patchomator will prompt you to install Installomator, if it doesn't already exist at the default path or the one specified with `-p [InstallomatorPATH]`. Patchomator will happily run without Installomator, but can't actually install any updates by itself.

If the Installomator label files are not present, or are older than 30 days, they will be downloaded from the latest Installomator release on GitHub and put in a directory called "fragments" in the same directory as patchomator.sh

### Configuration

When written using the `--write` option, the file `patchomator.plist` contains a list of the applications found on the system, and the corresponding Installomator labels which can be used to install or update each. By default, Patchomator will look for its configuration file in `/Library/Preferences/Patchomator` but the full path can be overridden with the `-c` or `--config` command line switch.

The current state of the configuration can be read with the following command 

```
defaults read /Library/Application\ Support/Patchomator/patchomator.plist

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

There are two special labels that can be added to the list at the command line that perform extra tasks. If you specify 'ALL' for an ignored label, then all discovery will be skipped. If you specify 'RECOMMENDEDIGNORES' for an ignored label, then a recommended list of ignores will be added to the ignore list.

### MDM instructions

More detail coming soon. For now, have a look at [the MDM folder](https://github.com/Mac-Nerd/patchomator/tree/main/MDM) for a starting point.

If you currently use Patchomator with an MDM, please [open an issue](https://github.com/Mac-Nerd/patchomator/issues) and let me know if you have any questions, or want to share your setup.


## Swift Dialog

As of 1.1, Patchomator will display progress and other messages via [Swift Dialog](https://github.com/swiftDialog/swiftDialog), if the system has it installed.

![Patchomator dialog example](https://github.com/Mac-Nerd/patchomator/blob/1.1/images/progress-dialog.png?raw=true)

You can suppress these dialogs with the `--quiet` command line switch.

Currently, the dialogs cannot be customized. If you would like to be able to, please [open an issue](https://github.com/Mac-Nerd/patchomator/issues) and let me know.


## Patching with Patchomator

### Run discovery
<pre><code>% sudo /usr/local/Installomator/patchomator.sh

Patchomator starting: 2025-06-30 00:00:00
Checking for latest labels.
Package labels not present at /usr/local/Installomator/fragments. Attempting to download from https://github.com/installomator/
Checking Installomator version.
Processing label 1password7.
Processing label 1password8.
[...]
Processing label finaldraft13.
Processing label findanyfile.
Processing label firefox.
-- Found Firefox version 140.0.4
Processing label firefox_da.
-- Found Firefox version 140.0.4
Processing label firefox_intl.
-- Found Firefox version 140.0.4
Processing label firefoxdeveloperedition.
Processing label firefoxesr.
-- Found Firefox version 140.0.4
Processing label firefoxesr_intl.
-- Found Firefox version 140.0.4
Processing label firefoxpkg.
-- Found Firefox version 140.0.4
Processing label firefoxpkg_intl.
-- Found Firefox version 140.0.4
Processing label flexoptixapp.
Processing label flowjo.
[...]
Verifying: /Applications/Firefox.app
--- Latest version installed.
Verifying: /Applications/Firefox.app
/Applications/Firefox.app already verified.
/Applications/Firefox.app already linked to label firefoxesr_intl.
<b>Replace label firefoxesr_intl with firefoxpkg? [y/N] y
	Replacing.</b>
--- Latest version installed.
Verifying: /Applications/Firefox.app
/Applications/Firefox.app already verified.
/Applications/Firefox.app already linked to label firefoxpkg.
<b>Replace label firefoxpkg with firefoxpkg_intl? [y/N] n
	Skipping.</b>
[...]
<b>3 of the 18 found labels need updates.
Done.</b>


Currently configured labels:
adobeacrobatprodc
adobecreativeclouddesktop
adobereaderdc
bbeditpkg
blender
dialog
firefoxpkg
googlechromepkg
installomator
jre8
microsoftautoupdate
microsoftexcel
microsoftonedrive
microsoftonenote
microsoftoutlook
microsoftpowerpoint
microsoftword
vlc

Ignored Labels:
bbedit
firefox
firefox_da
firefox_intl
firefoxesr
firefoxesr_intl
firefoxpkg_intl
googlechrome
googlechromeenterprise
microsoftofficebusinesspro
microsoftonedrive-deferred
microsoftonedrive-rollingout
microsoftonedrive-rollingoutdeferred
microsoftonedrivesuinsiders
microsoftonedrivesuprod
microsoftoutlook-monthly

Required Labels:

Patchomator finished: 2025-06-30 00:00:00
</code></pre>

### Write configuration

<pre><code>% sudo /usr/local/Installomator/patchomator.sh --write

Patchomator starting: 2025-06-30 00:00:00
Checking for latest labels.
Package labels installed. Last updated 0 days ago.
No existing config file at /Library/Application Support/Patchomator/patchomator.plist. Creating one now.
Checking Installomator version.
Processing label 1password7.
Processing label 1password8.
[...]
Processing label finaldraft13.
Processing label findanyfile.
Processing label firefox.
-- Found Firefox version 140.0.4
Processing label firefox_da.
-- Found Firefox version 140.0.4
Processing label firefox_intl.
-- Found Firefox version 140.0.4
Processing label firefoxdeveloperedition.
Processing label firefoxesr.
-- Found Firefox version 140.0.4
Processing label firefoxesr_intl.
-- Found Firefox version 140.0.4
Processing label firefoxpkg.
-- Found Firefox version 140.0.4
Processing label firefoxpkg_intl.
-- Found Firefox version 140.0.4
Processing label flexoptixapp.
Processing label flowjo.
[...]
Verifying: /Applications/Firefox.app
--- Latest version installed.
Verifying: /Applications/Firefox.app
/Applications/Firefox.app already verified.
/Applications/Firefox.app already linked to label firefoxesr_intl.
<b>Replace label firefoxesr_intl with firefoxpkg? [y/N] y
	Replacing.</b>
--- Latest version installed.
Verifying: /Applications/Firefox.app
/Applications/Firefox.app already verified.
/Applications/Firefox.app already linked to label firefoxpkg.
<b>Replace label firefoxpkg with firefoxpkg_intl? [y/N] n
	Skipping.</b>
[...]
<b>3 of the 18 found labels need updates.
Done.</b>


<b>Currently configured labels:</b>
    /Applications/Adobe Acrobat DC/Acrobat Distiller.app                      adobeacrobatprodc
    /Applications/Adobe Acrobat Reader.app                                    adobereaderdc
    /Applications/BBEdit.app                                                  bbeditpkg
    /Applications/Blender.app                                                 blender
    /Applications/Firefox.app                                                 firefoxpkg
    /Applications/Google Chrome.app                                           googlechromepkg
    /Applications/Microsoft Excel.app                                         microsoftexcel
    /Applications/Microsoft OneNote.app                                       microsoftonenote
    /Applications/Microsoft Outlook.app                                       microsoftoutlook
    /Applications/Microsoft PowerPoint.app                                    microsoftpowerpoint
    /Applications/Microsoft Word.app                                          microsoftword
    /Applications/OneDrive.app                                                microsoftonedrive
    /Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app       adobecreativeclouddesktop
    /Applications/VLC.app                                                     vlc
    /Library/Application Support/Dialog/Dialog.app                            dialog
    /Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app    microsoftautoupdate
    /Library/Internet Plug-Ins/JavaAppletPlugin.plugin                        jre8
    /usr/local/Installomator/Installomator.sh                                 installomator
    IgnoredLabels
        firefoxesr_intl,
        firefoxpkg_intl,
        googlechromeenterprise,
        microsoftonedrive-deferred,
        firefox_intl,
        microsoftonedrivesuprod,
        firefox_da,
        microsoftofficebusinesspro,
        microsoftoutlook-monthly,
        microsoftonedrivesuinsiders,
        googlechrome,
        microsoftonedrive-rollingout,
        firefox,
        microsoftonedrive-rollingoutdeferred,
        bbedit,
        firefoxesr
    
    RequiredLabels

Patchomator finished: 2025-06-30 00:00:00
</code></pre>    

### Install and update

<pre><code>% sudo /usr/local/Installomator/patchomator.sh --install

Patchomator starting: 2025-06-30 00:00:00
Checking for latest labels.
Package labels installed. Last updated 0 days ago.
Checking Installomator version.
<b>[ERROR]</b> Installomator was not found at /usr/local/Installomator/Installomator.sh 
Patchomator can still discover apps on the system and create a configuration for later use, but will not be able to install or update anything without Installomator. 		
<b>Download and install Installomator now?</b> [y/N] y
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
Processing label 1password7.
Processing label 1password8.
[...]
Processing label finaldraft13.
Processing label findanyfile.
Processing label firefox.
-- Found Firefox version 140.0.4
Processing label firefox_da.
-- Found Firefox version 140.0.4
Processing label firefox_intl.
-- Found Firefox version 140.0.4
Processing label firefoxdeveloperedition.
Processing label firefoxesr.
-- Found Firefox version 140.0.4
Processing label firefoxesr_intl.
-- Found Firefox version 140.0.4
Processing label firefoxpkg.
-- Found Firefox version 140.0.4
Processing label firefoxpkg_intl.
-- Found Firefox version 140.0.4
Processing label flexoptixapp.
Processing label flowjo.
[...]
Verifying: /Applications/Firefox.app
--- Latest version installed.
Verifying: /Applications/Firefox.app
/Applications/Firefox.app already verified.
/Applications/Firefox.app already linked to label firefoxesr_intl.
<b>Replace label firefoxesr_intl with firefoxpkg? [y/N] y
	Replacing.</b>
--- Latest version installed.
Verifying: /Applications/Firefox.app
/Applications/Firefox.app already verified.
/Applications/Firefox.app already linked to label firefoxpkg.
<b>Replace label firefoxpkg with firefoxpkg_intl? [y/N] n
	Skipping.</b>
[...]
<b>3 of the 18 found labels need updates.</b>
Passing 3 labels to Installomator: adobeacrobatprodc adobecreativeclouddesktop googlechromepkg
Performing installations.
Installing adobeacrobatprodc...
2025-06-30 00:00:00 : INFO  : adobeacrobatprodc : setting variable from argument  DEBUG="-1" IGNORE_APP_STORE_APPS="no" LOGGING="INFO" SYSTEMOWNER="0" NOTIFY_DIALOG="1" NOTIFY="success" INTERRUPT_DND="yes" LOGO="appstore" REOPEN="yes" BLOCKING_PROCESS_ACTION="tell_user" PROMPT_TIMEOUT="86400"
2025-06-30 00:00:00 : INFO  : adobeacrobatprodc : Total items in argumentsArray: 1
2025-06-30 00:00:00 : INFO  : adobeacrobatprodc : argumentsArray:  DEBUG="-1" IGNORE_APP_STORE_APPS="no" LOGGING="INFO" SYSTEMOWNER="0" NOTIFY_DIALOG="1" NOTIFY="success" INTERRUPT_DND="yes" LOGO="appstore" REOPEN="yes" BLOCKING_PROCESS_ACTION="tell_user" PROMPT_TIMEOUT="86400"
2025-06-30 00:00:00 : REQ   : adobeacrobatprodc : ################## Start Installomator v. 10.8, date 2025-03-28
2025-06-30 00:00:00 : INFO  : adobeacrobatprodc : ################## Version: 10.8
2025-06-30 00:00:00 : INFO  : adobeacrobatprodc : ################## Date: 2025-03-28
2025-06-30 00:00:00 : INFO  : adobeacrobatprodc : ################## adobeacrobatprodc
[...]
2025-06-30 00:00:00 : REQ   : adobeacrobatprodc : All done!
2025-06-30 00:00:00 : REQ   : adobeacrobatprodc : ################## End Installomator, exit code 0 
[...]
Patchomator finished: 2025-06-30 00:00:00
</code></pre>

## Help! It's not working!

Sorry about that. If you're willing and able to help test, please report any problems by [opening an issue](https://github.com/Mac-Nerd/patchomator/issues). And if you can see where I've messed something up, I'm open to pull requests.


