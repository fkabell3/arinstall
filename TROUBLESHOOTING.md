# Computer won't boot with EFI (options B(GPT/Limine) & C(GPT/EFI stub))
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

# systemd prevents boot stating \`A start job is running for TPM2 ...'
Disable TPM in firmware settings.<br>
I don't think this is a problem with the script but rather a problem with my personal hardware. Just in case I'm wrong, I included it in this document.<br>
