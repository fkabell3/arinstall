#!/bin/sh

batterypath=$(find /sys/class/power_supply/BAT* | head -n 1)

while true; do
	nmcli con show --active | grep vpn >/dev/null 2>&1
	if [ "$?" = 0 ]; then
		vpn='[VPN] '
	else
		vpn=''
	fi
	if [ -n "$batterypath" ]; then
		case "$(cat "$batterypath"/status)" in
			Charging)
				charge='+ '
			;;
			Discharging)
				charge='- '
			;;
			*)
				charge=' '
			;;
		esac
		battery="$(cat $batterypath/capacity)%"
	fi
	date=$(date '+%a %R')
	xsetroot -name "$vpn$battery$charge$date"
	sleep 1
done
