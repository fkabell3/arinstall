#!/bin/sh

# Unfortunately doesn't read from rc or profile
EDITOR=/usr/bin/vi

die() {
	rm "$raw" "$parsed"
	exit "$1"
}

raw="$(mktemp)"
parsed="$(mktemp)"

# Change :+-]*' | sort
#     to :+-\&]*' | sort
# in order to allow query strings in the URL
grep -Eo '/[^ ]*|(http|https)://[a-zA-Z0-9./?=_%:+-]*[.][a-z]*[/]?[a-zA-Z0-9./?=_%:+-\&]*' | \
	sort -u > "$raw"

while read line; do
	if [ -f "$line" ] || printf '%s' "$line" | grep 'http'; then
		printf '%s\n' "$line" >> "$parsed"
	fi
done < "$raw"

selection="$(dmenu -l 5 -w "$WINDOWID" < "$parsed")"

case "$selection" in
	'')
		die 1
	;;
	http*)
		eval "$BROWSER $selection"
	;;
	*)
		[ -f "$selection" ] && eval st -e "$EDITOR" "$selection"
	;;
esac

die 0
