firefox)
	name="Firefox"
	type="dmg"
	downloadURL="https://download.mozilla.org/?product=firefox-latest&os=osx&lang=en-US"
	appNewVersion=$(curl -fs https://www.mozilla.org/en-US/firefox/releases/ | grep '<html' | grep -o -i -e "data-latest-firefox=\"[0-9.]*\"" | cut -d '"' -f2)
	expectedTeamID="43AQ936H96"
	blockingProcesses=( firefox )
	[ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/locale.ini' 2> /dev/null | cut -d'=' -f2)" != "" ] || [ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/update-settings.ini' 2> /dev/null | cut -d'-' -f3)" != "release" ] && disambiguation=false
	;;
firefox_da)
	name="Firefox"
	type="dmg"
	downloadURL="https://download.mozilla.org/?product=firefox-latest&amp;os=osx&amp;lang=da"
	appNewVersion=$(curl -fs https://www.mozilla.org/en-US/firefox/releases/ | grep '<html' | grep -o -i -e "data-latest-firefox=\"[0-9.]*\"" | cut -d '"' -f2)
	expectedTeamID="43AQ936H96"
	blockingProcesses=( firefox )
	[ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/locale.ini' 2> /dev/null | cut -d'=' -f2)" != "da" ] || [ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/update-settings.ini' 2> /dev/null | cut -d'-' -f3)" != "release" ] && disambiguation=false
	;;
firefox_intl)
	# This label will try to figure out the selected language of the user, 
	# and install corrosponding version of Firefox
	name="Firefox"
	type="dmg"
	userLanguage=$(runAsUser defaults read .GlobalPreferences AppleLocale)
	printlog "Found language $userLanguage to be used for Firefox."
	if ! curl -fs "https://ftp.mozilla.org/pub/firefox/releases/latest/README.txt" | grep -o "=$userLanguage"; then
		userLanguage=$(echo $userLanguage | cut -c 1-2)
		if ! curl -fs "https://ftp.mozilla.org/pub/firefox/releases/latest/README.txt" | grep "=$userLanguage"; then
			userLanguage="en_US"
		fi
	fi
	printlog "Using language $userLanguage for download."
	downloadURL="https://download.mozilla.org/?product=firefox-latest&amp;os=osx&amp;lang=$userLanguage"
	if ! curl -sfL --output /dev/null -r 0-0 "$downloadURL" ; then
		printlog "Download not found for that language. Using en-US"
		downloadURL="https://download.mozilla.org/?product=firefox-latest&os=osx&lang=en-US"
	fi
	appNewVersion=$(curl -fs https://www.mozilla.org/en-US/firefox/releases/ | grep '<html' | grep -o -i -e "data-latest-firefox=\"[0-9.]*\"" | cut -d '"' -f2)
	expectedTeamID="43AQ936H96"
	blockingProcesses=( firefox )
	[ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/locale.ini' 2> /dev/null | cut -d'=' -f2)" != "$userLanguage" ] || [ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/update-settings.ini' 2> /dev/null | cut -d'-' -f3)" != "release" ] && disambiguation=false
	;;
firefoxesr|\
firefoxesrpkg)
	name="Firefox"
	type="pkg"
	downloadURL="https://download.mozilla.org/?product=firefox-esr-pkg-latest-ssl&os=osx"
	appNewVersion=$(curl -fsIL "$downloadURL" | grep -i "^location" | awk '{print $2}' | sed -E 's/.*releases\/([0-9.]*)esr.*/\1/g')
	expectedTeamID="43AQ936H96"
	blockingProcesses=( firefox )
	 [ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/locale.ini' 2> /dev/null | cut -d'=' -f2)" != "" ] || [ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/update-settings.ini' 2> /dev/null | cut -d'-' -f3)" != "esr" ] && disambiguation=false
	;;
firefoxesr_intl)
	# This label will try to figure out the selected language of the user, 
	# and install corrosponding version of Firefox ESR
	name="Firefox"
	type="dmg"
	userLanguage=$(runAsUser defaults read .GlobalPreferences AppleLocale)
	printlog "Found language $userLanguage to be used for Firefox."
	if ! curl -fs "https://ftp.mozilla.org/pub/firefox/releases/latest-esr/README.txt" | grep -o "=$userLanguage"; then
		userLanguage=$(echo $userLanguage | cut -c 1-2)
		if ! curl -fs "https://ftp.mozilla.org/pub/firefox/releases/latest-esr/README.txt" | grep "=$userLanguage"; then
			userLanguage="en_US"
		fi
	fi
	printlog "Using language $userLanguage for download."
	downloadURL="https://download.mozilla.org/?product=firefox-esr-latest-ssl&os=osx&lang=$userLanguage"
	# https://download.mozilla.org/?product=firefox-esr-latest-ssl&os=osx&lang=en-US
	if ! curl -sfL --output /dev/null -r 0-0 "$downloadURL" ; then
		printlog "Download not found for that language. Using en-US"
		downloadURL="https://download.mozilla.org/?product=firefox-latest&os=osx&lang=en-US"
	fi
	appNewVersion=$(curl -fsIL "$downloadURL" | grep -i "^location" | awk '{print $2}' | sed -E 's/.*releases\/([0-9.]*)esr.*/\1/g')
	expectedTeamID="43AQ936H96"
	blockingProcesses=( firefox )
	[ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/locale.ini' 2> /dev/null | cut -d'=' -f2)" != "$userLanguage" ] || [ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/update-settings.ini' 2> /dev/null | cut -d'-' -f3)" != "esr" ] && disambiguation=false
	;;
firefoxpkg)
	name="Firefox"
	type="pkg"
	downloadURL="https://download.mozilla.org/?product=firefox-pkg-latest-ssl&os=osx&lang=en-US"
	expectedTeamID="43AQ936H96"
	blockingProcesses=( firefox )
	[ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/locale.ini' 2> /dev/null | cut -d'=' -f2)" != "" ] || [ "$(tail -1 '/Applications/Firefox.app/Contents/Resources/update-settings.ini' 2> /dev/null | cut -d'-' -f3)" != "release" ] && disambiguation=false
	;;
