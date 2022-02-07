#!/bin/zsh

isPKG="$(pkgutil --pkgs | grep -c firefox)" # 1 or 0
isRelease="$(tail -1 /Applications/Firefox.app/Contents/Resources/update-settings.ini | grep -c release)" # 1 or 0
localeINI="/Applications/Firefox.app/Contents/Resources/locale.ini"
localeVAL="$([ -f $localeINI ] && tail -1 $localeINI | cut -d'=' -f2 || echo "en-US")"

installedFF=$(printf "%i-%i-%s" "$isPKG" "$isRelease" "$localeVAL")

echo "$installedFF"


case $installedFF in 

"1-0-en-US")
	FFLabel="firefox"
    ;;
"1-0-da")
	FFLabel="firefox_da"
   ;;
"0-1-en-US")
	FFLabel="firefoxesr"
    ;;
"1-1-en-US")
	FFLabel="firefoxpkg"
    ;;

*)    
	[[ $isRelease -eq 0 ]] && FFLabel="firefoxesr_intl" || FFLabel="firefox_intl"
	;;
esac

echo "$FFLabel"
