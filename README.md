# Artix/Arch Linux Installer

arinstall is a Linux installer written in POSIX shell. It is capable of cross installing Artix (OpenRC) from the Arch live installation medium and vice versa. Bloated software is avoided wherever possible. BIOS/MBR, EFI/{PMBR,GPT}, LVM, LUKS disk encryption, and HiDPI are all supported.<br>

suckless.org's `dwm` and `dmenu` enable a keyboard-centric graphical interface. Scripts placed in `/usr/local/bin/` allow for the following:

* Trivally spawn virtual machines with a few keystrokes.
* Quickly lock screen, reboot, and toggle volume/brightness/networking etc.
* Manage passwords with `$HOME/.passwd/`, `xclip`, and the `genpasswd` script.
* Open files and HTTP links with the `st` terminal emulator.
* Locally manage YouTube subscriptions.
* Easily control clipboard (images included) with `copy`/`paste` aliases and `clipboard.sh`.

All of this has a consistent UI and can be done without touching a mouse.

<img width="1000" src="https://github.com/fkabell3/arinstall/blob/main/gui.png">

Nongraphical features include:

* NetworkManager ignores DHCP DNS and is forced to use 1.1.1.1/9.9.9.9 (for privacy reasons).
* Transparently drop privlidges when running `yay` or `makepkg` as root.
* `doas` instead of `sudo`, with a compatility shim installed.
* `/bin/sh` symlinks to `dash`.
* `booster` initramfs generator and `limine` bootloader.
* If using GPT, a unified kernel image is available (instead of bootloader).
* If using EFI, an EFI shell will be installed to the root of the ESP.

The installer tries to abstract the installation process in a meaningful way.

* Straightforward questions are asked at the beginning.
* Interactive questioning can be avoided and further customization can be achieved by editing variables at the start of the script.
* Partitions sizes and filesystems are adjusted with `vi`/`vim`.
* The script is capable of chrooting itself.

Installation Instructions:

* Download, burn, and boot into an [Artix](https://artixlinux.org/download.php) or [Arch](https://archlinux.org/download/) Linux installation enviroment.<br>
It doesn't really matter which one you choose but Arch makes connecting to WiFi easier.<br>
* Connect to network.<br>
Either plug in an Ethernet cable or for WiFi try:<br>
<details>
  <summary>Artix</summary>

`rfkill unblock wlan`<br>
`connmanctl`<br>
`connmanctl> scan wifi`<br>
`connmanctl> agent on`<br>
`connmanctl> services`<br>
`<ID>` is the second field of the line containing your SSID (string starting with `wifi_`)<br>
Note that tab completion is available<br>
`connmanctl> connect <ID>`<br>

</details>

<details>
  <summary>Arch</summary>
  
`iwctl -P '<PSK>' station <iface> connect '<SSID>'`

</details>

* `curl https://raw.githubusercontent.com/fkabell3/arinstall/main/install.sh > install.sh`<br>
You can not pipe `curl` directly into `sh` unless you use a BASHism.
* `vim install.sh || vi install.sh`<br>
(Optional) Edit variables directly inside the script to avoid interactive querying.
* `sh -e install.sh`
* When script is done, exit and reboot into the GUI.<br>
**If script fails for any reason after patitioning, `wipefs -af /dev/$disk` and reboot before trying again.**<br>
If script completes successfully and your computer will not boot, see TROUBLESHOOTING.md.<br>

Optional Postinstallation Instructions:<br>
(Spawn terminals with `Super`/`Enter`, spawn application launcher with `Super`/`P`. Read `man 1 dwm`.)
* Place a background in `/usr/local/share/backgrounds/`.<br>
If there is only one background, it is chosen by default. If there is more than one, edit `/etc/X11/xdm/Xsetup_0` to specify which one you want.<br>
* Populate `/var/vm/` with subdirectories which contain a file called `disk.qcow2` (`qemu-img create -f qcow2 /var/vm/<name>/disk.qcow2 <gibibytes>G`) and an .iso file. Then start a virtual machine.
* Enable the installed LibreWolf addons/theme by starting a browser and going to the `about:addons` URL.
* Place passwords in `$HOME/.passwd/`. You can create a new secure password by redirecting stdout from `genpasswd`.
* If on Aritx, launch `alsamixer` and raise `PCM` levels to unmute

Please send me the output of execution trace (`set -x`) if the script fails on your system.<br>
Your feedback is appreciated.<br>
Thanks!
