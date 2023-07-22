#!/bin/sh -e

#disk=''			# Exclude /dev/ prefix
#disklabel=''			# MBR 	 || GPT, GPT depends on EFI
#bootloader=''			# Limine || EFIstub, EFIstub depends on GPT
#uselvm=''			# Boolean
vgname='vg'			# Volume group name
#useluks=''			# Boolean, LUKS depends on LVM
luksdmname='luks'		# LUKS device mapper name
#lukspasswd=''			# LUKS disk encryption password
excluded='BOOT ESP'		# Filesystem labels excluded from LUKS/LVM
#rootpasswd=''			# Root password
#username=''			# User created/added to :wheel
#usergecos='' 			# 5th field of passwd database
#userpasswd=''			# User password
#hostname=''			# Long hostname
#timezone=''			# As in /usr/share/zoneinfo/
local_pkgs='vim mupdf'		# Arbitrary pacman(8) packages
force_dns='1.1.1.1 9.9.9.9' 	# Comment out to use DHCP DNS
builddir='/var/builds'		# Location of system git/makepkg/yay builds
vmdir='/var/vm'			# Location of virtual machines for vm.sh
# rd.luks.name=$luksuuid=$luksdmname is managed by this script
kernelcmdline='root=LABEL=rootfs rw resume=LABEL=swap quiet bgrt_disable'
# Enabled system services
services='gpm NetworkManager xdm'
# Comment out this variable to disable LibreWolf browser installation
librewolf_addons='ublock-origin sponsorblock istilldontcareaboutcookies
clearurls darkreader complete-black-theme-for-firef'
# Note: Caps Lock and Escape are swapped
# This and the locale have not been tested when changed
keymap='/usr/share/kbd/keymaps/i386/qwerty/us.map'
# Variables that become lowercase
lowercasevars='disklabel bootloader'
# Variables that are sorted into 0 ([NnFf0]*) or 1 ([YyTt1]*)
booleanvars='uselvm useluks'
# Variables that persist when chrooting
chrootvars='disk diskp disklabel bootloader useluks uselvm luksdisk targetos
init rootpasswd username usergecos userpasswd hostname timezone'

error() {
	if [ X"$1" = X'invalidvar' ]; then
		printf '%s %s %s\n' 'Error:' "\$$2 is invalid:" "$3" >&2
	else
		printf '%s %s\n' 'Error:' "$1" >&2
	fi
}

die() {
	printf '%s %s\n' 'Fatal:' "$1" >&2
	exit 1
}

netcheck() {
	printf '%s' 'Checking network connection...'
	if ping -c 1 archlinux.org >/dev/null 2>&1; then
		printf '%s\n' ' ok'
	else
		printf '\n'
		if ping -c 1 1.1.1.1 >/dev/null 2>&1; then
			die 'DNS is potentially not working.'
		else
			die 'ping(8) failed.'
		fi
	fi
}

userquery() {
	eval [ -z "\$$1" ] || return 0
	if [ X"$1" = X'repeat' ]; then
		eval [ -z "\$$2" ] || return 0
		shift
		while true; do
			printf '%s' "$2"
			read REPLY
			[ -z "$REPLY" ] || break
		done
	else
		printf '%s' "$2"
		read REPLY
	fi
	if [ -n "$REPLY" ]; then
		eval "$1"=\'"$REPLY"\'
	elif [ -z "$REPLY" ] && [ -n "$default" ]; then
		eval "$1"=\'"$default"\'
	fi
}

lslabels() {
	regex="$(printf '%s' '\('
	for label in $excluded; do
		printf '%s' "^$label\|"
	done | sed 's/..$/\\)\n/')"

	case "$1" in
		included) # Included on LVM/LUKS
			grep -v "$regex"
		;;
		excluded) # Excluded from LVM/LUKS
			grep "$regex"
		;;
	esac < /tmp/disk
}

autosize() {
	case "$2" in
		total)
			base="$storage"
		;;
		free)
			base="$free"
			max="$storage"
		;;
	esac
	gibi=$((base / $3))
	min="$4"
	case "$5" in
		# Potential bug: NULL could use previous $max value
		NULL);;
		*)
			max="$5"
		;;
	esac
	if [ "$gibi" -lt "$min" ]; then
		gibi="$min"
	elif [ "$gibi" -gt "$max" ]; then
		gibi="$max"
	# elif $gibi is not a power of 2; then
	elif factor -h "$gibi" | \
		eval '! grep "^$gibi: 2\^[0-9]*$\|^$gibi:$" >/dev/null 2>&1'
		then
		x=1
		while [ "$x" -lt "$gibi" ]; do
			y="$x"
			x=$((x * 2))
		done
		gibi="$y"
	fi
	eval "$1size=$gibi"
	free=$((free - gibi))
}

autopart() {
	if [ X"$disklabel" = X'gpt' ]; then
		case "$1" in
			lvm) # Linux LVM
				printf '%s\n' \
					',,E6D6D379-F507-44C2-A23C-238F2A3DF928,;'
				return 0
			;;
			luks) # Linux LUKS
			      # (shows up as `unknown' in util-linux fdisk)
				printf '%s\n' \
					',,CA7D7CCB-63ED-4C53-861C-1742536059CC,;'
				return 0
			;;
		esac
		case "$3" in
			none|swap) # Linux swap
			code=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F
			;;
			/) # Linux root (x86-64)
			code=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
			;;
			/boot) # Linux extended boot
			code=BC13C2FF-59E6-4262-A352-B275FD6F7172
			;;
			/boot/efi)
				if [ X"$targetos" = X'artix' ]; then
					# EFI System
					code=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
				elif [ X"$targetos" = X'arch' ]; then
					# We don't want systemd-automount
					# from overriding the ESP to /efi
					# Linux filesystem
					code=0FC63DAF-8483-4772-8E79-3D69D8477DE4
				fi
			;;
			# Seperate /usr is not supported with booster initramfs
			/usr) # Linux /usr (x86-64)
			code=8484680C-9521-48C6-9C11-B0720656F69E
			;;
			/var) # Linux variable data
			code=4D21B016-B534-45C2-A9FB-5C16E091FD2D
			;;
			/var/tmp) # Linux temporary data
			code=7EC6F557-3BC5-4ACA-B293-16EF5DF639D1
			;; 
			/home) # Linux user's home
			code=773F91Ef-66D4-49B5-BD83-D683BF40AD16
			;;
			*) # Linux filesystem
			code=0FC63DAF-8483-4772-8E79-3D69D8477DE4
			;;
		esac
	elif [ X"$disklabel" = X'mbr' ]; then
		case "$1" in
			lvm) # Linux LVM
				printf '%s\n' ',,8e,-;'
				return 0
			;;
			luks) # Linux LUKS
			      # (shows up as `unknown' in util-linux fdisk)
				printf '%s\n' ',,e8,-;'
				return 0
			;;
		esac
		bootable='-'
		case "$3" in
			none|swap) # Linux swap / Solaris
				code=82
			;;
			/boot) # W95 FAT32 (LBA)
				code=0c
				bootable='*'
			;;
			/boot/efi) # EFI (FAT-12/16/32)
				code=ef
			;;
			*) # Linux
				code=83
			;;
		esac
		if [ "$partnum" -eq 4 ]; then
			printf '%s\n' ',,05,-;'	# Extended
			partnum=$((partnum + 1))
		fi
	fi
	size=$(($2 * sectorspergibi))
	printf '%s\n' ",$size,$code,$bootable;"
	partnum=$((partnum + 1))
	printf '%s' "partnum=$partnum" > /tmp/partnum
}

autolvm() {
	pvcreate -ffy "$1"
	vgcreate "$vgname" "$1"
	lslabels included | while read line; do
		set -- $line
		lvcreate -y -n "$1" -L "$2"g "$vgname"
	done
}

automkfs() {
	if [ X"$1" = X'lvm' ]; then
		onlvm=1
		shift
	else
		onlvm=0
		if [ X"$disklabel" = X'mbr' ] && [ "$partnum" -eq 4 ]; then
			partnum=$((partnum + 1))
		fi
	fi
	case "$4" in
		vfat)
			mkfs="mkdosfs -n $1 -F 32"
		;;
		swap)
			mkfs="mkswap -L $1"
		;;
		ext4)
			mkfs="mkfs.ext4 -L $1"
		;;
	esac
	if [ "$onlvm" -eq 0 ]; then
		eval "$mkfs /dev/$diskp$partnum"
	elif [ "$onlvm" -eq 1 ]; then
		eval "$mkfs /dev/$vgname/$1"
	fi
	[ -d /mnt"$3" ] || mkdir -p /mnt"$3"
	case "$4" in
		swap)
			swapon LABEL="$1"
		;;
		*)
			mount LABEL="$1" /mnt"$3"
		;;
	esac
	[ "$onlvm" -eq 0 ] && partnum=$((partnum + 1))
	# If this process is running in a subshell, then
	# we need to "export" $partnum up to its parent
	printf '%s' "partnum=$partnum" > /tmp/partnum
}

chrootvars() {
	for var in $chrootvars; do
		printf '%s ' "$var=\"$(eval printf '%s' "\"\$$var\"")\""
	done
}

if [ -d /sys/firmware/efi/efivars ]; then
       	bootmode=efi
else
	bootmode=bios
fi

_disklabel="$disklabel"
_bootloader="$bootloader"
for var in $lowercasevars; do
	eval "$var"="$(eval printf '%s' "\$$var" | awk '{print tolower($0)}')"
done
for boolean in $booleanvars; do
	case "$(eval printf '%s' "\$$boolean")" in
		[NnFf0]*)
			eval $boolean=0
		;;
		[YyTt1]*)
			eval $boolean=1
		;;
		*)
			eval $boolean=
		;;
	esac
done

[ X"$(whoami)" != X'root' ] && die 'Must be superuser.'

if [ -n "$1" ] && [ X"$1" != X'chroot' ]; then
########
printf '%s\n' "Syntax error: Usage: $0"
#^^^^^^^
elif [ -z "$1" ]; then
########
if which basestrap >/dev/null 2>&1; then
	sourceos=artix
	init=openrc
	bootstrap=basestrap
	editor=vi
	keyring=artix-keyring
elif which pacstrap >/dev/null 2>&1; then
	sourceos=arch
	init=systemd
	bootstrap=pacstrap
	editor=vim
	keyring=archlinux-keyring
else
	die 'Neither pacstrap(8) nor basestrap(8) found.'
fi

netcheck

if ! which git >/dev/null 2>&1; then
	printf '%s\n' 'git(1) not found, installing...'
	x=1
	while [ "$x" -le 3 ]; do
		# pacman(8) either does or does not work the first time...
		# We want to preserve pacman's exit code while
		# being tolerent to failures because of set -e
		{ pacman --noconfirm -Sy git && var="$?"; } || var="$?"
		if [ "$var" -ne 0 ]; then
			pkill gpg-agent || true
			rm -rf /etc/pacman.d/gnupg/*
			pacman-key --init
			pacman-key --populate
		else
			break
		fi
		x=$((x + 1))
	done
fi

if [ X"$(basename "$PWD")" = X'arinstall' ]; then
	gitdir="$PWD"
elif [ -d "$PWD"/arinstall ]; then
	gitdir="$PWD"/arinstall
else
	git clone --depth 1 \
		https://github.com/fkabell3/arinstall || \
		die "git clone failed."
	gitdir="$PWD"/arinstall
fi
clear

[ X"$(set -o | awk '$1 ~ /errexit/ { print $2 }')" = X'on' ] && \
	printf '%s\n\n' 'Script exits on any failures.'

potentialdisk="$(lsblk -o NAME,RM,TYPE -e 7,254 | \
	awk '$2 ~ /0/ && $3 !~ /part/ { print $1}')"
if [ "$(printf '%s ' "$potentialdisk" | wc -w)" -eq 1 ]; then
	default="$potentialdisk"
	_default=" [$default]"
fi

[ -z "$disk" ] && lsblk -e 7 -o NAME,RM,SIZE,TYPE | \
	awk '$2 ~ /0/ && $4 !~ /lvm|crypt|part/ { print $1, $3 }'
while true; do
	userquery disk "Input target disk to install Linux$_default: "
	if ! [ -e /dev/"$disk" ]; then
		error invalidvar disk "\`/dev/$disk' does not exist"
		disk=
	elif ! [ -b /dev/"$disk" ]; then
		error invalidvar disk "\`/dev/$disk' is not block special"
		disk=
	elif [ "$(stat -c %T /dev/"$disk")" -ne 0 ]; then
		error invalidvar disk \
			"\`/dev/$disk' might be a partition (minor != 0)"
		disk=
	else
		break
	fi
done
# Linux kernel inserts `p' between the whole block device name and the 
# partition number if the whole block device name ends with a digit
case "$disk" in
	*[0-9])
		diskp="$disk"p
	;;
	*)
		diskp="$disk"
	;;
esac

if [ X"$bootmode" = X'bios' ]; then
	if [ -n "$disklabel" ] && [ X"$disklabel" != X'mbr' ]; then
		error invalidvar disklabel "using BIOS, correcting \`$_disklabel'->MBR"
	fi
	disklabel=mbr
	if [ -n "$bootloader" ] && [ X"$bootloader" != X'limine' ]; then
		error invalidvar bootloader "using BIOS/MBR, correcting \`_$bootloader'->Limine"
	fi
	bootloader=limine
elif [ X"$bootmode" = X'efi' ]; then
	if [ -n "$disklabel" ] && { [ X"$disklabel" != X'mbr' ] && [ X"$disklabel" != X'gpt' ]; }; then
		die '$disklabel must be MBR or GPT'
	fi
	if [ -n "$bootloader" ] && { [ X"$bootloader" != X'limine' ] && [ X"$bootloader" != X'efistub' ]; }; then
		die '$bootloader must be Limine or EFIstub'
	fi
	if [ X"$disklabel" = X'mbr' ] && [ X"$bootloader" = X'efistub' ]; then
		die 'MBR can not be used with EFI stub'
	fi
fi

if [ X"$bootmode" = X'efi' ] && { [ -z "$disklabel" ] || [ -z "$bootloader" ]; }; then
	printf '%s\n' 'You are using EFI. Select a configuration:'
	printf '\t%s\n' \
		'A) GPT  & EFI stub with UKI' \
		'B) GPT  & Limine bootloader' \
		'C) PMBR & Limine bootloader'
	userquery eficonf 'Your choice [A/b/c]: '
	case "$eficonf" in
		[Cc]*)
			disklabel=mbr
			bootloader=limine
		;;
		[Bb]*)
			disklabel=gpt
			bootloader=limine
		;;
		*)
			disklabel=gpt
			bootloader=efistub
		;;
	esac
fi

if [ -z "$uselvm" ] || [ -z "$useluks" ]; then
	printf '%s\n' "Select a configuration for /dev/$disk:"
	printf '\t%s\n' \
		'A)    LVM & LUKS disk encryption' \
		'B)    LVM & no   disk encryption' \
		'C) no LVM & no   disk encryption'
	userquery diskconf 'Your choice [A/b/c]: '
	case "$diskconf" in
		[Cc]*)
			uselvm=0
			useluks=0
		;;
		[Bb]*)
			uselvm=1
			useluks=0
		;;
		*)
			uselvm=1
			useluks=1
		;;
	esac
fi
if [ "$useluks" -eq 1 ] && [ -z "$lukspasswd" ]; then
	default=
	userquery repeat lukspasswd 'Input disk encrytion password: '
fi

# Cross installation is not implemented yet.
printf '%s\n' 'Select init and its corresponding operating system:'
printf '\t%s\n' \
	'A) OpenRC  & Artix Linux' \
	'B) systemd & Arch  Linux'
if [ X"$sourceos" = X'artix' ]; then
	userquery osconf 'Your choice [A/b]: '
	case "$osconf" in
		[Bb]*)
			init='systemd'
			targetos='arch'
		;;
		*)
			init='openrc'
			targetos='artix'
		;;	
	esac
elif [ X"$sourceos" = X'arch' ]; then
	userquery osconf 'Your choice [a/B]: '
	case "$osconf" in
		[Aa]*)
			init='openrc'
			targetos='artix'
		;;	
		*)
			init='systemd'
			targetos='arch'
		;;
	esac
fi

# Repeat only if there is no default
default=
userquery repeat rootpasswd 'Input root password: '
default=
userquery repeat username 'Input username (added to :wheel): '
default='Linux User,,,'
_default=" [$default]"
userquery usergecos "Input user GECOS field$_default: "
default=
userquery repeat userpasswd 'Input user password: '
while true; do
	default='UTC'
	_default=" [$default]"
	userquery timezone \
		"Input timezone (as in /usr/share/zoneinfo/)$_default: "
	if [ -f "/usr/share/zoneinfo/$timezone" ]; then
		break
	elif [ -d "/usr/share/zoneinfo/$timezone" ]; then
		error invalidvar timezone \
			"/usr/share/zoneinfo/$timezone is a timezone subdirectory - listing contents"
		ls /usr/share/zoneinfo/"$timezone"
		timezone=
	else
		error invalidvar timezone \
			"/usr/share/zoneinfo/$timezone - no such file or directory"
		timezone=
	fi
done
default='localhost.localdomain'
_default=" [$default]"
userquery hostname "Input hostname$_default: "

if [ X"$sourceos" = X'arch' ] && [ X"$targetos" = X'artix' ]; then
	cat "$gitdir"/pacman/base.conf "$gitdir"/pacman/artix.conf > /etc/pacman.conf
	curl https://gitea.artixlinux.org/packages/artix-mirrorlist/raw/branch/master/trunk/mirrorlist -o /etc/pacman.d/mirrorlist
	pacman --noconfirm -Scc
	pacman --noconfirm -Syy
	pacman --noconfirm -S artix-keyring
	pacman-key --populate artix
elif [ X"$sourceos" = X'artix' ] && [ X"$targetos" = X'arch' ]; then
	cat "$gitdir"/pacman/base.conf "$gitdir"/pacman/arch.conf > /etc/pacman.conf
	curl https://archlinux.org/mirrorlist/all/https/ -o /etc/pacman.d/mirrorlist
	pacman --noconfirm -Scc
	pacman --noconfirm -Syy
	pacman --noconfirm -S archlinux-keyring
	pacman-key --populate archlinux
else
	sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 8/' /etc/pacman.conf
	pacman -Sy --noconfirm "$keyring"
fi
	

# Gibibytes of storage available on $drive
# minus 1 gibi for metadata
storage=$(($(grep "$disk$" /proc/partitions | \
	awk '{print $3}') / 1024 / 1024 - 1))
free="$storage"
# Gibibytes of memory available on system
ram=$(($(grep MemTotal: /proc/meminfo | \
	grep -o '[0-9]*') / 1024 / 1024))

# The whole autosize section needs to be reworked for better numbers
# Could not find swap algorithm which took both RAM and storage as input
# <max> can be NULL (only with `free')
# autosize() <label>   <total|free>  <denominator>     <min>  <max>
autosize     rootfs    free          4                 16     32
autosize     BOOT      total         1024              1      2
autosize     var       total         32                4      32
autosize     home      free          1                 1      NULL
autosize     swap      total         "$ram"            1      16
if [ X"$bootmode" = X'efi' ]; then
autosize     ESP       total         1024              1      2
   _ESP="ESP      $ESPsize      /boot/efi  vfat  rw,noexec,nosuid,nodev 0 2"
fi

# For (P)MBR, the boot partition & ESP should be on a
# primary partition so put it/them within the first three
cat <<- EOF > /tmp/disk
rootfs   $rootfssize   /          ext4  rw,nodev               0 1
BOOT     $BOOTsize     /boot      vfat  rw,noexec,nosuid,nodev 0 2
$_ESP
var      $varsize      /var       ext4  rw,noexec,nosuid,nodev 0 2
home     $homesize     /home      ext4  rw,nosuid,nodev        0 2
swap     $swapsize     none       swap  sw                     0 0
EOF
true > /tmp/disk.rej > /tmp/disk.swap

[ X"$bootmode" = X'efi' ] && string=' ESP,'
_break=0
regex='^[a-zA-Z]* *[0-9]* *[/a-z]* *\(ext4\|vfat\|swap\) *[a-z,]* *[0-1] *[0-2]'
while true; do
	printf '%s\n' "# disk: $disk, storage: $storage, memory: $ram" '#' \
		> /tmp/disk.swap
	column --table --table-columns \
		'# <label>,<size>,<mount>,<fs>,<options>,<dump>,<pass>' \
		< /tmp/disk >> /tmp/disk.swap
	free="$storage"
	for number in $(awk '{ print $2 }' /tmp/disk); do
		free=$((free - number))
	done
	printf '%s\n' "# Free: $free" >> /tmp/disk.swap
	cp /tmp/disk.swap /tmp/disk.bak
	clear
	cat /tmp/disk.swap
	# Fix me, $swapsize should always be >= 1
	[ "$(awk '/^swap/ { print $2 }' /tmp/disk.swap)" -eq 0 ] && \
		printf '\n%s\n' \
		'Bug: allocate at least 1 gibibyte to swap! Sorry!'
	[ "$free" -lt 0 ] && printf '\n%s\n' \
		'Warning: more storage allocated than available, this will break script!'
	if [ -s /tmp/disk.rej ]; then
		printf '\n%s\n%s\n' 'Warning: the regular expression:' "$regex"
		printf '%s' 'did not match line'
		[ "$(wc -l < /tmp/disk.rej)" -gt 1 ] && printf '%s' 's'
		printf '%s\n' ':'
		cat /tmp/disk.rej
	fi
	printf '\n%s' 'Are these values ok? [y/N]: '
	read REPLY
	case "$REPLY" in
		[Yy]*)
			_break=1
		;;
		*)
			sed -i -f - /tmp/disk.swap <<- EOF
			1i \\
			# Limitations: \\
			# Do not change the labels of or delete rootfs, BOOT,$string or swap \\
			# Put rootfs on the top of the partition/filesystem list \\
			# /usr/bin must be on the rootfs due to booster initramfs \\
			# Only ext4/vfat filesystems are supported \\
			# \\
			# Note: \\
			# /var/vm holds virtual machines, /var/builds holds yay/makepkg/git builds \\
			#
			EOF
			cat /tmp/disk.swap > /tmp/disk.edit
			if [ -s /tmp/disk.rej ]; then
				printf '\n%s\n' '# Rejects:' >> /tmp/disk.edit
				while read line; do
					printf '%s\n' "#$line"
				done < /tmp/disk.rej >> /tmp/disk.edit
				true > /tmp/disk.rej
			fi
			$editor /tmp/disk.edit
			cp /tmp/disk.edit /tmp/disk.swap
		;;
	esac
	grep -o "$regex" /tmp/disk.swap > /tmp/disk
	grep -v "\(^$\|^#\|$regex\)" /tmp/disk.swap > /tmp/disk.rej || true
	[ "$_break" -eq 1 ] && break
done

printf '%s\n' \
	'From this point on, if the script fails (eg. curl(1) hangs), reboot before trying again.' \
	'Press ENTER to wipe partition table and install Linux, CTRL/C to abort.'
read REPLY

sectorsize="$(cat /sys/block/"$disk"/queue/hw_sector_size)"
sectorspergibi=$((1073741824 / sectorsize))

if ! wipefs -a /dev/"$disk"; then
	# This condition seems to be met when LVMs
	# without LUKS are already on the system.
	wipefs -af /dev/"$disk"
	clear
	die "$disk is in use but has been wiped anyways. Reboot and run script again."
fi

partnum=1
if [ "$uselvm" -eq 0 ]; then
	while read line; do
		eval "autopart $line"
	done < /tmp/disk | sfdisk -X "$disklabel" /dev/"$disk"

	partnum=1
	while read line; do
		eval "automkfs $line"
	done < /tmp/disk
elif [ "$uselvm" -eq 1 ]; then
	lslabels excluded | while read line; do
		eval "autopart $line"
	done | sfdisk -X "$disklabel" /dev/"$disk"
	. /tmp/partnum

	if [ "$useluks" -eq 0 ]; then
		autopart lvm | sfdisk -X "$disklabel" -a /dev/"$disk"
		autolvm /dev/"$diskp$partnum"
	elif [ "$useluks" -eq 1 ]; then
		autopart luks | sfdisk -X "$disklabel" -a /dev/"$disk"
		luksdisk="/dev/$diskp$partnum"
		printf '%s\n' "Encrypting /dev/$diskp$partnum..."
		printf '%s' "$lukspasswd" | cryptsetup -q --key-file - \
			luksFormat /dev/"$diskp$partnum"
		printf '%s' "$lukspasswd" | cryptsetup --key-file - \
			open /dev/"$diskp$partnum" "$luksdmname"
		autolvm /dev/mapper/"$luksdmname"
	fi

	partnum=1
	# rootfs must get mounted first
	lslabels included | while read line; do
		eval "automkfs lvm $line"
	done 
	. /tmp/partnum
	lslabels excluded | while read line; do
		eval "automkfs $line"
	done 
fi

system_pkgs='base linux linux-firmware booster opendoas git'
network_pkgs="networkmanager openresolv"
doc_pkgs='man-db man-pages'
gui_pkgs="alsa-utils gnu-free-fonts picom scrot xclip xclip xdotool xorg-server
xorg-xdm xorg-xhost xorg-xinit xorg-xrandr xorg-xsetroot xwallpaper imlib2
libx11 libxft libxinerama"
console_pkgs="terminus-font gpm"
vm_pkgs='qemu-system-x86 qemu-ui-gtk bridge-utils'
# Install base-devel dependencies except sudo
# (we use doas & doas-sudo-shim instead)
devel_pkgs="$(pacman -Si base-devel | \
	grep 'Depends On' | cut -d : -f 2 | sed 's/sudo//')"
[ -n "$librewolf_addons" ] && browser_pkgs='unzip'
[ X"$bootmode" = X'efi' ] && efi_pkgs='efibootmgr'
case "$bootloader" in
	# Artix repos have neither Limine or sbctl in repos
	# We get Limine from git and sbctl from AUR
	limine)
		[ X"$targetos" = X'arch' ] && bootloader_pkgs='limine'
	;;
	efistub)
		[ X"$targetos" = X'arch' ] && bootloader_pkgs='sbctl'
	;;
esac
[ "$uselvm" -eq 1 ] && lvm_pkgs='lvm2'
case "$(lscpu | awk '/^Vendor ID:/ { print $NF }')" in
	*Intel*)
		microcode_pkgs=intel-ucode
	;;
	*AMD*)
		microcode_pkgs=amd-ucode
	;;
esac
case "$init" in
	systemd)
		init_pkgs=
	;;
	openrc)
		init_pkgs='openrc elogind-openrc'
	;;
esac
# Xorg log complained about these three not being installed on
# Framework/Librem 14, spikes CPU if (one or all?) not installed
video_drivers_pkgs='xf86-video-fbdev xf86-video-intel xf86-video-vesa'
[ X"$targetos" = X'artix' ] && service_pkgs="gpm-$init networkmanager-$init xdm-$init"
$bootstrap /mnt $system_pkgs $network_pkgs $doc_pkgs $gui_pkgs $console_pkgs \
	$vm_pkgs $devel_pkgs $browser_pkgs $efi_pkgs $bootloader_pkgs \
	$lvm_pkgs $microcode_pkgs $video_drivers_pkgs $init_pkgs $service_pkgs \
	$local_pkgs || \
	die "$bootstrap(8) failed with exit $?." \
		'Reboot and try script again. Sorry!'

cp "$gitdir/usr.local.bin/"* /mnt/usr/local/bin
[ X"$targetos" = X'artix' ] && \
	sed -i 's/nmtui/doas nmtui/' /mnt/usr/local/bin/dmenu_launcher
mkdir /mnt/etc/skel/.sfeed
if [ -n "$librewolf_addons" ]; then
	mkdir -p /mnt/etc/skel/.librewolf/defaultp.default/extensions
	cp -r "$gitdir"/etc/skel/dotlibrewolf/* /mnt/etc/skel/.librewolf
fi
# Copy non-browser/bashrc files into /mnt/etc
for file in $(find "$gitdir"/etc/ -type f | \
	grep -v '\(librewolf\|bashrc\)' | grep -o '/etc/.*' | tr '\n' ' '); do 
	newfile="$(printf '%s' "$file" | sed 's/\/dot/\/./')"
	cp "$gitdir$file" /mnt"$newfile"
done
if [ X"$bootloader" = X'efistub' ]; then
	mkdir /mnt/usr/local/share/bitmap
	cp "$gitdir"/linux.bmp /mnt/usr/local/share/bitmap/linux.bmp
fi
chmod 0400 /mnt/etc/doas.conf
if [ X"$targetos" = X'arch' ]; then
	rm /mnt/etc/bash.bash_logout
	cp "$gitdir"/etc/bashrc /mnt/etc/bash.bashrc
	sed -i '1 s/.*/# \/etc\/bash.bashrc/' /mnt/etc/bash.bashrc
elif [ X"$targetos" = X'artix' ]; then
	rm -rf /mnt/etc/bash/*
	cp "$gitdir"/etc/bashrc /mnt/etc/bash/bashrc
	sed -i '1 s/.*/# \/etc\/bash\/bashrc/' /mnt/etc/bash/bashrc
	sed -i '13d' /mnt/etc/bash/bashrc
	sed -i 's/ SYSTEMD_PAGER//' /mnt/etc/bash/bashrc
fi
builddir=/mnt"$builddir"
mkdir -p /mnt"$vmdir" "$builddir" \
	/mnt/usr/local/share/backgrounds /mnt/etc/skel/.sfeed
cp "$gitdir"/etc/skel/dotsfeed/sfeedrc /mnt/etc/skel/.sfeed/sfeedrc
rm /mnt/etc/skel/.bash*
for srcdir in dwm dmenu st tabbed slock; do
	git -C "$builddir" clone --depth 1 https://git.suckless.org/"$srcdir"
	cp "$gitdir"/patches/"$srcdir"-arinstall.diff "$builddir/$srcdir"
done
git -C "$builddir" clone --depth 1 https://github.com/dudik/herbe
cp "$gitdir"/patches/herbe-arinstall.diff "$builddir"/herbe
git -C "$builddir" clone --depth 1 git://git.codemadness.org/sfeed
cp "$gitdir"/patches/sfeed-arinstall.diff "$builddir"/sfeed
git -C "$builddir" clone --depth 1 https://aur.archlinux.org/yay-bin.git
awk '{print "LABEL="$1, $3, $4, $5, $6, $7}' /tmp/disk | \
	column --table --table-columns \
	'# <filesystem>,<mount>,<type>,<options>,<dump>,<pass>' > /mnt/etc/fstab

cp "$0" /mnt
chmod 740 /mnt/"$(basename $0)"
printf '\n%s\n' 'Chrooting into /mnt...'
eval "$sourceos"-chroot /mnt /bin/sh -c \'$(chrootvars) /"$(basename "$0")" chroot\'
#^^^^^^^
elif [ X"$1" = X'chroot' ]; then
########
printf '%s\n' 'Chroot entered successfully!'
chmod 640 "$(basename $0)"

netcheck

if [ -n "$force_dns" ]; then
	dnsconf='/etc/NetworkManager/conf.d/dns-servers.conf'
	printf '%s\n%s' '[global-dns-domain-*]' 'servers=' > "$dnsconf"
	for nameserver in $force_dns; do
		printf '%s' "$nameserver,"
	done | sed 's/.$/\n/' >> "$dnsconf"
fi

horizontal="$(cut -d , -f 1 \
	"$(find /sys -name virtual_size 2>/dev/null | head -n 1)")"
vertical="$(cut -d , -f 2 \
	"$(find /sys -name virtual_size 2>/dev/null | head -n 1)")"
pixels=$((horizontal * vertical))

if [ -n "$librewolf_addons" ]; then
	librewolf='librewolf-bin'
	librewolfpath='/etc/skel/.librewolf'
	chmod -R 700 "$librewolfpath"
	chmod 755 "$librewolfpath"/defaultp.default/extensions
	chmod 600 "$librewolfpath"/defaultp.default/user.js
	# Calculate LibreWolf's about:config layout.css.devPixelsPerPx value
	# 1680 x 1050 = 1764000, the base resolution which gets 1 as its value
	perpx="$(awk "BEGIN { print sqrt( $pixels / 1764000)}")"
	printf '%s\n' \
		"user_pref(\"layout.css.devPixelsPerPx\", \"$perpx\");" \
		>> /etc/skel/.librewolf/defaultp.default/user.js

	chmod 644 "$librewolfpath"/profiles.ini
	cd "$librewolfpath"/defaultp.default/extensions
	printf '%s\n' 'Downloading LibreWolf extensions...'
	for addon in $librewolf_addons; do
		curl -o "$addon" "$(curl \
			"https://addons.mozilla.org/en-US/firefox/addon/$addon/" | \
			grep -o \
			'https://addons.mozilla.org/firefox/downloads/file/[^"]*')"
		newxpiname="$(unzip -p "$addon" manifest.json | \
			grep '"id"' | cut -d \" -f 4)"
		mv "$addon" "$newxpiname".xpi
	done
fi

sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 4/' /etc/pacman.conf

ln -s /usr/share/zoneinfo/"$timezone" /etc/localtime

[ -z "$hostname" ] && hostname='localhost.localdomain'
printf '%s\n' "$hostname" > /etc/hostname
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
locale-gen

printf '%s\n' 'LANG=en_US.UTF-8' > /etc/locale.conf
gzip -d "$keymap".gz
sed -i 's/1 = Escape/1 = Caps_Lock/' "$keymap"
sed -i 's/58 = Caps_Lock/58 = Escape/' "$keymap"
gzip "$keymap"
printf '%s\n' "KEYMAP=$(basename "$keymap" | cut -d '.' -f 1)" \
	'FONT=ter-932n' > /etc/vconsole.conf

rm /etc/xdg/picom.conf

printf '%s\n' root:"$rootpasswd" | chpasswd
cat <<- EOF > /root/.bashrc
# /root/.bashrc

# Sometimes --reset-env is required, sometimes its absence is required
alias yay='setpriv --reuid=bin --regid=bin --clear-groups --reset-env yay'
alias makepkg='setpriv --reuid=bin --regid=bin --clear-groups makepkg'
EOF

# Build stuff as bin user, see /etc/doas.conf
# and /var/builds/.config/yay/config.json
usermod -c 'system build user' -d "$builddir" bin

chown -R root:bin "$builddir"
find "$builddir" -perm 644 -execdir chmod 664 {} +
find "$builddir" -perm 755 -execdir chmod 775 {} +

# Create a user for vm.sh to run QEMU
useradd -c 'vm.sh user' -d "$vmdir" -p '!*' -r -s /usr/bin/nologin vm
# If user backed up virtual machines, give correct perms for vm.sh
chown -R root:vm "$vmdir"
find "$vmdir" -type d -execdir chmod 770 {} + || chmod -R 770 "$vmdir"
find "$vmdir" -type f -name '*.iso' -execdir chmod 440 {} +
find "$vmdir" -type f \( -name drive -o -name drive2 \) \
	-execdir chmod 660 {} +

for skeletons in documents downloads images .passwords; do
	mkdir /etc/skel/"$skeletons"
done

if [ X"$targetos" = X"artix" ]; then
	useradd -c "$usergecos" -G wheel,vm,network,power -m "$username"
	sed -i -f - /etc/doas.conf <<- EOF
6i \\
permit nopass  :network	as root cmd nmcli \\
permit nopass  :network	as root cmd nmtui \\
permit nopass  :power	as root cmd openrc-shutdown \\
permit nopass  :power	as root cmd loginctl args suspend \\
permit nopass  :power	as root cmd loginctl args hibernate
	EOF
elif [ X"$targetos" = X"arch" ]; then
	useradd -c "$usergecos" -G wheel,vm -m "$username"
fi
printf '%s\n' "$username:$userpasswd" | chpasswd
[ -n "$librewolf_addons" ] && sed -i \
	"s/\/\/user_pref(\"browser.download.dir\", \"\/home\/NAME\/downloads\");/user_pref(\"browser.download.dir\", \"\/home\/$username\/downloads\");/" \
	/home/$username/.librewolf/defaultp.default/user.js

pwck -s
grpck -s

# Accounts already locked
getent shadow bin vm

# Create temp sudo link to prevent asking for root password
# since doas-sudo-shim has not been installed yet
ln -s /usr/bin/doas /usr/local/bin/sudo
cd "$builddir"/yay-bin && \
	setpriv --reuid=bin --regid=bin --clear-groups makepkg --noconfirm -ci
rm /usr/local/bin/sudo
# doas.conf only works when full pacman path is set with yay --save
# also doas.conf must have full pacman path or else permission denied
setpriv --reuid=bin --regid=bin --clear-groups --reset-env \
	yay --save --pacman /usr/bin/pacman
setpriv --reuid=bin --regid=bin --clear-groups --reset-env \
	yay --removemake --noconfirm -S \
	dashbinsh devour $librewolf otf-san-francisco-mono \
	doas-sudo-shim xbanish
setpriv --reuid=bin --regid=bin --clear-groups \
	yay --removemake --noconfirm -S keynav

# Calculate how large the XDM login box is
if [ "$pixels" -gt 3200000 ]; then
	dpi=96
	increment=2048
	x=$((pixels - 3200000))
	y=$increment
	while [ "$x" -gt "$y" ]; do
		dpi=$((dpi + 1))
		x=$((x - y))
		y=$((y + increment))
	done
	sed -i "2a ! Dots per inch for the login box (higher=bigger)\nXft.dpi: $dpi\n" \
		/etc/X11/xdm/Xresources
fi

for srcdir in dwm dmenu st tabbed slock sfeed herbe; do
	cd "$builddir/$srcdir"
	patch -p 1 < "$builddir/$srcdir/$srcdir-arinstall.diff"
done
# Calculate how big some suckless.org programs will be
# bc(1) is not available
fontsize="$(awk "BEGIN { print sqrt( $pixels / 7168)}" | \
	LC_ALL=C xargs /usr/bin/printf '%.*f\n' 0)"
sed -i "s/monospace:size=10/SF Mono:size=$fontsize/g" \
	"$builddir/dwm/config.def.h"
sed -i "s/monospace:size=10/SF Mono:size=$fontsize/" \
	"$builddir/dmenu/config.def.h"
sed -i "s/Liberation Mono:pixelsize=12/SF Mono:pixelsize=$fontsize/" \
	"$builddir/st/config.def.h"
sed -i "s/monospace:size=9/SF Mono:size=$((fontsize * 3/4))/" \
	"$builddir/tabbed/config.def.h"
sed -i "s/monospace:size=10/SF Mono:size=$fontsize/" \
	"$builddir/herbe/config.def.h"
for srcdir in dwm dmenu st tabbed slock sfeed herbe; do
	cd "$builddir/$srcdir"
	make
	make install
done

ESPnum="$(findmnt /boot/efi -o SOURCE | tail -n 1 | sed "s/\/dev\/$diskp//")"

if [ X"$bootmode" = X'efi' ]; then
	curl -Lo /boot/efi/shellx64.efi \
		'https://github.com/tianocore/edk2/raw/UDK2018/ShellBinPkg/UefiShell/X64/Shell.efi'
	efibootmgr -c -d /dev/"$disk" -p "$ESPnum" \
		-l '\shellx64.efi' -L 'EFI Shell'
fi

if [ "$useluks" -eq 1 ]; then
	luksuuid="$(blkid "$luksdisk" | \
		grep -o ' UUID="[a-zA-Z0-9-]*' | sed 's/ UUID="//')"
	kernelcmdline="rd.luks.name=$luksuuid=$luksdmname $kernelcmdline"
fi

case "$(lscpu | awk '/^Vendor ID:/ { print $NF }')" in
	*Intel*)
		microcodeargs='-i /boot/intel-ucode.img'
	        microcodeinitrd='MODULE_PATH=boot:///intel-ucode.img'
	;;
	*AMD*)
		microcodeargs='-a /boot/amd-ucode.img'
	        microcodeinitrd='MODULE_PATH=boot:///amd-ucode.img'
	;;
esac
if [ "$uselvm" -eq 1 ]; then
	# I think `uname -r' is unreliable,
	# displays nonchroot kernel instead
	kver="$(find /usr/lib/modules/*/vmlinuz | \
		cut -d / -f 5 | sort -u | tail -n 1)"
	printf '%s\n' 'enable_lvm: true' >> /etc/booster.yaml
	booster build -f --kernel-version "$kver" /boot/booster-linux.img
fi
[ X"$bootmode" = X'efi' ] && mkdir -p /boot/efi/EFI/linux/
if [ X"$bootloader" = X'limine' ]; then
	mkdir /etc/pacman.d/hooks
	if [ X"$targetos" = X'artix' ]; then
		limineprefix='/usr/local/share/limine'
		cd "$builddir"
		git clone --depth 1 --branch=v5.x-branch-binary \
			https://github.com/limine-bootloader/limine.git
		cd limine
		make
		make install
	# Artix does not have Limine in repos so no need for hook
	elif [ X"$targetos" = X'arch' ]; then
		limineprefix='/usr/share/limine'
		cat <<- EOF > /etc/pacman.d/hooks/bootloader.hook
		[Trigger]
		Type = Package
		Operation = Upgrade
		Target = limine
		
		[Action]
		EOF
		if [ X"$bootmode" = X'bios' ]; then
			cat <<- EOF >> /etc/pacman.d/hooks/bootloader.hook
			Description = Installing Limine bootloader to /dev/$disk...
			When = PostTransaction
			Exec = /bin/sh -c "limine bios-install /dev/$disk; cp /usr/share/limine/limine-bios.sys /boot/limine-bios.sys"
			EOF
		elif [ X"$bootmode" = X'efi' ]; then
			cat <<- EOF >> /etc/pacman.d/hooks/bootloader.hook
			Description = Installing Limine bootloader to the ESP...
			When = PostTransaction
			Exec = /usr/bin/cp /usr/share/limine/BOOTX64.EFI /boot/efi/EFI/linux/BOOTX64.EFI
			EOF
		fi
	fi
	if [ X"$bootmode" = X'bios' ]; then
		cp "$limineprefix"/limine-bios.sys /boot
		limine bios-install /dev/"$disk"
	elif [ X"$bootmode" = X'efi' ]; then
		cp "$limineprefix"/BOOTX64.EFI /boot/efi/EFI/linux/BOOTX64.EFI
		efibootmgr -c -d /dev/"$disk" -p "$ESPnum" \
			-l '\EFI\linux\BOOTX64.EFI'
	fi
	# These numbers are guesses
	if [ "$pixels" -lt 1000000 ]; then
	        scale='TERM_FONT_SCALE=1x1'
	elif [ "$pixels" -lt 4000000 ]; then
	        scale='TERM_FONT_SCALE=2x2'
	elif [ "$pixels" -lt 8000000 ]; then
	        scale='TERM_FONT_SCALE=3x3'
	elif [ "$pixels" -lt 10000000 ]; then
	        scale='TERM_FONT_SCALE=4x4'
	else
	        scale='TERM_FONT_SCALE=5x5'
	fi
	cat <<- EOF > /boot/limine.cfg
	:Linux
	        PROTOCOL=linux
	        $scale
	        $microcodeinitrd
	        MODULE_PATH=boot:///booster-linux.img
	        KERNEL_PATH=boot:///vmlinuz-linux
	        CMDLINE=$kernelcmdline
	EOF
elif [ X"$bootloader" = X'efistub' ]; then
	mkdir /etc/kernel || true
	printf '%s\n' "$kernelcmdline" > /etc/kernel/cmdline
	# TODO: Get rid of `printf '%d\n' 1'
	[ X"$targetos" = X'artix' ] && printf '%d\n' 1 | setpriv --reuid=bin \
		--regid=bin --clear-groups --reset-env yay --removemake \
			--noconfirm -S sbctl-git efistub-standalone
	sbctl bundle -s $microcodeargs -f /boot/booster-linux.img \
		-l /usr/local/share/bitmap/linux.bmp -p /boot/efi \
		/boot/efi/EFI/linux/linux.efi
	efibootmgr -c -d /dev/"$disk" -p "$ESPnum" -l '\EFI\linux\linux.efi'
fi

set -- $services
case "$init" in
	systemd)
		systemctl enable "$@"
	;;
	openrc)
		for service in "$@"; do
			rc-update add "$service"
		done
	;;
esac

clear
printf '%s\n' 'Linux installation script completed.' \
	'If your computer does not boot see TROUBLESHOOTING.md.' \
	'<https://github.com/fkabell3/arinstall/blob/main/TROUBLESHOOTING.md>' \
	'Now reboot and God bless!'
exit 0
#^^^^^^^
fi
