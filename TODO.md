# To Do/Bugs
* Fix bug where calculating swap size fails if there is <1GB of RAM, line 114
* Document everything, patch the dwm, dmenu, etc man pages.
* Instead of patching everything locally, set up git server so patches will not break when suckless.org updates their programs.
* Port script to ARM (not sure how big of a task this is besides updating GPT codes).
* Let user choose AUR wrapper (yay/paru). 
* ~~Let user pick /usr/bin/cc~~ (Won't implement this since clang apparently depends on GCC, which defeats the purpose).

# Completed!
* Fix sound in Artix (add user to :audio), I am not sure if raising PCM levels is necessary (as stated in the readme)
