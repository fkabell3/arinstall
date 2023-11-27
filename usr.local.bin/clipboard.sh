#!/bin/sh

usage() {
	printf '%s\n' \
		"Syntax error: Usage: $(basename "$0") {copy [file] | paste}"
	exit 1
}

superclip() {
	xclip -selection clipboard -display "$DISPLAY" $@
}

# Guess the Xorg display (for running as root)
if [ -z "$DISPLAY" ]; then
	DISPLAY="$(who | grep -o '(:[0-9]*)' | grep -o ':[0-9]*')"
	if [ -z "$DISPLAY" ]; then
		DISPLAY=":0"
	fi
fi

if [ X"$1" = X'copy' ]; then
	if [ -f "$2" ]; then
		if [ -z "$3" ]; then
			case "$(file "$2" | awk -F "$2:" '{ print $2 }')" in
				# This list is not exhaustive
				# `xclip -t TARGETS' will show you
				# a (still not complete) list
				*ASCII*)
					target='text/plain'
				;;
				*PNG*)
					target='image/png'
				;;
				*JPEG*)
					target='image/jpeg'
				;;
				*PC\ bitmap*)
					target='image/bmp'
				;;
				*)
					superclip "$2"
					exit 0
				;;
			esac
			superclip -target "$target" "$2"
		else
			usage
		fi
	elif [ -z "$2" ]; then
		# Read from stdin
		# If interactive, CNTL/D to stop
		superclip -in
	else
		usage
	fi
elif [ X"$1" = X'paste' ]; then
	if [ -z "$2" ]; then
		superclip -out
	else
		usage
	fi
else
	usage
fi
