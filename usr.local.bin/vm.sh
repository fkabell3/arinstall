#!/bin/sh

user=vm
gid="$(id -g "$user")"
dir="$(getent passwd "$user" | awk -F : '{ print $6 }')"

# Resources allocated to guest
mebis=8192
vcpu=8

# Guess the Xorg display (not necessary if
# running from the graphical user with doas)
if [ -z "$DISPLAY" ]; then
	DISPLAY="$(who | grep -o '(:[0-9]*)' | grep -o ':[0-9]*')"
	if [ -z "$DISPLAY" ]; then
		DISPLAY=":0"
	fi
	export DISPLAY
fi

# Guess the exit interface (default route with lowest metric)
iface="$(awk '$2 == 00000000 { print $7, $1 }' /proc/net/route | sort | \
	awk 'NR == 1 { print $2 }')"

usage() {
	printf '%s' "Syntax error: Usage: $(basename "$0" 2>/dev/null) "
	subdirs="$(find /var/vm/* -exec sh -c '[ -f "$0"/*.iso ] || \
		[ -f "$0"/disk.qcow2 ] || [ -f "$0"/disk2.qcow2 ]' '{}' \
		\; -print | sed 's/\/var\/vm\///g')"
	if [ "$(printf '%s' "$subdirs" | wc -w)" -eq 1 ]; then
		printf '%s' "$subdirs"
	elif [ "$(printf '%s' "$subdirs" | wc -w)" -ge 2 ]; then
		printf '%s' '{'
		for vmdir in $subdirs; do
			printf '%s' "$vmdir | "
		done | sed 's/...$/}/'
	fi
	printf '%s\n' ' [delay]'
	delayexit 255
}

privdrop() {
	if [ X"$1" = X'qemu' ]; then
		# QEMU needs to escalate privs for bridge helper
		# to create tun device and needs to keep $DISPLAY
		shift
		setpriv --reuid="$user" --regid="$gid" --clear-groups "$@"
	else
		setpriv --reuid="$user" --regid="$gid" --clear-groups \
			--reset-env --no-new-privs "$@"
	fi
}

ckperm() {
	file="$1"
	case "$file" in
		""|*iso)
			write=0
			existseverity=warning
			permseverity=warning
			status=252
		;;
		*disk.qcow2)
			write=1
			existseverity=fatal
			permseverity=fatal
			status=253
		;;
		*disk2.qcow2)
			write=1
			existseverity=info
			permseverity=warning
			status=254
		;;
	esac
	if [ -f "$file" ]; then
		if [ "$write" -eq 1 ]; then
			if ! privdrop [ -r "$file" ] && ! privdrop [ -w "$file" ]; then
				log "$permseverity" \
					"User $user can't read or write to $file."
				lsperm "$file"
				if [ X"$permseverity" = X'fatal' ]; then
					delayexit "$status"
				else
					return "$status"
				fi
			elif ! privdrop [ -w "$file" ]; then
				log "$permseverity" \
					"User $user can't write to $file."
				lsperm "$file"
				if [ X"$permseverity" = X'fatal' ]; then
					delayexit "$status"
				else
					return "$status"
				fi
			fi
		fi
		if ! privdrop [ -r "$file" ]; then
			log "$permseverity" "User $user can't read $file."
			lsperm "$file"
			if [ X"$permseverity" = X'fatal' ]; then
				delayexit "$status"
			else
				return "$status"
			fi
		fi
	else
		[ X"$existseverity" = X'info' ] || \
			if [ -z "$file" ]; then
				log "$existseverity" "No .iso file exist."
			else
				log "$existseverity" "File $file does not exist."
			fi
			if [ X"$existseverity" = X'fatal' ]; then
				delayexit "$status"
			else
				return "$status"
			fi
	fi
}

lsperm() {
	printf '\t%s' '>> '
	ls -l "$1" | cut -d ' ' -f 1,3,4
}

log() {
	case "$1" in
		info)
			printf '%s\n' "$2"
		;;
		warning)
			printf '%s %s\n' 'Warning:' "$2" >&2
		;;
		fatal)
			printf '%s %s\n' 'Fatal:' "$2" >&2
		;;
	esac
}

# Let the user hit Enter key before exiting so user has
# a chance to read log message(s) before terminal closes
# (for use with dmenu(1) graphical program)
delay="$2"
delayexit() {
	if [ X"$delay" = X'delay' ]; then
		read REPLY
	fi
	exit "$1"
}

if [ X"$(whoami)" != X'root' ]; then
	log fatal 'Must be superuser.'
	delayexit 254
fi

rm -rf "$dir"/.cache

if [ -d "$dir" ]; then
	if [ "$(find "$dir" -type d | wc -l)" -gt 1 ]; then
		if [ -n "$1" ]; then
			if [ X"$1" = X'delay' ]; then
				usage
			elif [ -d "$dir/$1" ]; then
				vm="$dir/$1"
			elif [ -f "$dir/$1" ]; then
				log fatal \
					"$dir/$1 should be a subdirectory, not a file."
				delayexit 239
			else
				usage
			fi
		else
			usage
		fi
	else
		log fatal "$dir/ has no subdirectories."
		delayexit 238
	fi
elif [ -f "$dir" ]; then
	log fatal "$dir should be a directory, not a file."
	delayexit 237
else
	log fatal "$dir/ directory does not exist."
	delayexit 236
fi

disk="$vm/disk.qcow2"
disk2="$vm/disk2.qcow2"
iso="$(find "$vm" -type f -name *.iso | head -n 1)"

ckperm "$disk"
if ckperm "$disk2"; then
	_drive="-drive"
	disk2="file="$disk2""
else
	disk2=
fi
if ckperm "$iso"; then
	_cdrom="-cdrom"
else
	iso=
fi

log info "Initializing $1 virtual machine..."

log info "Configuring network"
# Disable VPN here
brctl addbr virbr0
ip addr flush dev virbr0
ip addr add 10.0.0.1/30 dev virbr0
ip -6 addr add fe80::1/64 dev virbr0
ip link set virbr0 up
if [ X"$(sysctl net.ipv4.ip_forward)" = X'net.ipv4.ip_forward = 0' ]; then
	sysctl net.ipv4.ip_forward=1 >/dev/null 2>&1
	routing4=wasoff
fi
if [ X"$(sysctl net.ipv6.conf.all.forwarding)" = \
	X'net.ipv6.conf.all.forwarding = 0' ]; then
	sysctl net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1
	routing6=wasoff
fi
if [ -z "$iface" ]; then
	log warning "No exit interface detected."
else
	iptables -t nat -A POSTROUTING -o "$iface" -j MASQUERADE
fi

privdrop qemu devour qemu-system-x86_64 \
	-enable-kvm \
	-display gtk,zoom-to-fit=on,show-menubar=off \
	-m "$mebis" \
	-smp "$vcpu" \
	-nic bridge,br=virbr0 \
	-drive file="$disk" \
	"$_drive" "$disk2" \
	"$_cdrom" "$iso" \
	>/dev/null 2>&1

status="$?"

case "$status" in
	0) # This condition does not guarantee success
		log info "Virtual machine shutdown!"
	;;
	139)
		log fatal "Virtual Machine GUI failed!"
	;;
	*)
		log fatal "Virtual machine failed!"
	;;
esac

log info "Undoing network config changes"
# Re-enable VPN here
ip link set virbr0 down
brctl delbr virbr0
[ X"$routing4" = X'wasoff' ] && sysctl net.ipv4.ip_forward=0 >/dev/null 2>&1
[ X"$routing6" = X'wasoff' ] && sysctl net.ipv6.conf.all.forwarding=0 \
	>/dev/null 2>&1

if [ "$status" -eq 139 ]; then
	if [ -z "$DISPLAY" ]; then
		log info '$DISPLAY is not set.'
	else
		log info 'Likely either $DISPLAY is incorrectly set or'
		log info 'root is denied by X access control (xhost(1)).'
	fi
fi

delayexit "$status"
