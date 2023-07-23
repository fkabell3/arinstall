# Computer won't boot with EFI (options B(GPT/Limine) & A(GPT/EFI stub))
If you use EFI, efibootmgr(8) may silently fail depending on your motherboard's firmware. If that is the case, your computer will not boot and you must launch an EFI shell to resolve the situation.<br>
Here are two ways to launch an EFI shell:<br>
        1) Reboot into the Arch live installation .iso, and then select `UEFI Shell` in GRUB menu (easiest)<br>
        2) Use the computer's firmware file manager to launch `\shellx64.efi` (this script places it there)<br>
Once the EFI shell has been launched, find out which filesystem is your disk's ESP:<br>
        `Shell> map`<br>
You are looking for `FS<num>:` containing `\ESP\Linux\` and `\shellx64.efi`. Search with:<br>
        `Shell> ls FS<num>:`<br>
Once you have found it (it is probably `FS1:` or `FS0:`), "enter" the file system:<br>
        `Shell> FS<num>:`<br>
If you use the Limine bootloader, add that to the boot order:<br>
	        `Shell> bcfg boot add 0x0 \EFI\Linux\BOOTX64.EFI "Linux"`<br>
Else if you used the EFI boot stub, add that to the boot order instead:<br>
	        `Shell> bcfg boot add 0x0 \EFI\Linux\linux.efi "Linux"`<br>
Now optionally add the EFI shell to the boot order.<br>
        `Shell> bcfg boot add 0x1 \shellx64.efi "EFI Shell"`<br>
Reboot:<br>
        `Shell> reset`<br>
Now your computer should boot normally if it didn't before.<br>

# Filesystem mounting fails before pacstrap/basestrap
Make sure you do not have duplicate filesystem labels on disk. For instance, if `/dev/vg/rootfs` has `LABEL=rootfs`, make sure another filesystem such as on `nvme0n1p1` does not have the same `LABEL=rootfs` (check with `blkid`). I ran into this error when testing a new version of the script on a computer formatted with a very old version. The solution was to `wipefs -af /dev/$diskp<num>` on the affected partitions.

# Sound doesn't work on Artix
I am still looking into this but I think this is multi level issue. I think on everyone's machine, `pipewire` needs configuration (see this [Reddit comment](https://www.reddit.com/r/artixlinux/comments/s3p380/comment/htl6cvr/?context=3).). On my machine, `aplayer -l` shows no available soundcards, but `cat /proc/asound/cards` shows one. Again, I think these are two seperate issues. Will update this document when I have get this figured out.

# systemd prevents boot stating \`A start job is running for TPM2 ...'
Disable TPM in firmware settings.<br>
I think this problem is related to faulty hardware.
