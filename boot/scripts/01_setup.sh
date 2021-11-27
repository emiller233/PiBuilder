#!/usr/bin/env bash

# should not run as root
[ "$EUID" -eq 0 ] && echo "This script should NOT be run using sudo" && exit -1

# the name of this script is
SCRIPT=$(basename "$0")

if [ $# -eq 1 ] ; then

   HOSTNAME="$1"
   read -s -p "New password for $USER@$HOSTNAME: " NEW_PASSWORD
   echo ""
   read -s -p "Re-enter new password: " CHK_PASSWORD
   echo ""
   if [ ! "$NEW_PASSWORD" = "$CHK_PASSWORD" ] ; then
      echo "Passwords do not match!"
      exit -1
   fi

else

   echo "Usage: $SCRIPT machinename {password}"
   echo "       (will prompt for password if omitted)"
   exit -1

fi

# declare path to support directory and import common functions
SUPPORT="/boot/scripts/support"
. "$SUPPORT/pibuilder/functions.sh"

# import user options and run the script prolog - if they exist
run_pibuilder_prolog

# copy etc
echo "Taking a baseline copy of /etc"
sudo cp -a /etc /etc-baseline

echo "Initialising empty user directories for SSH and GnuPG"
[ ! -d "$HOME/.gnupg" ] && mkdir -p "$HOME/.gnupg"
[ ! -d "$HOME/.ssh" ] && mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.gnupg" "$HOME/.ssh"

if is_running_raspbian buster ; then
   echo "Adding Debian Buster Backports support (for libseccomp2)"
   sudo apt-key adv \
      --keyserver hkps://keyserver.ubuntu.com:443 \
      --recv-keys 04EE7237B7D453EC 648ACFD622F3D138
   TARGET="/etc/apt/sources.list.d/debian-backports.list"
   if SOURCE="$(supporting_file "$TARGET")" ; then
      cat "$SOURCE" | sudo tee -a "$TARGET" >/dev/null
   fi
fi

echo "Running sudo apt update"
sudo apt update

echo "Running sudo apt full-upgrade -y"
sudo apt full-upgrade -y
sudo apt autoremove -y

# apply any preset for /etc/ssh
if SOURCE="$(supporting_file "/etc/ssh/etc-ssh-backup.tar.gz")" ; then

   # yes! replace /etc/ssh
   echo "Replacing /etc/ssh with $SOURCE"
   sudo mv /etc/ssh /etc/ssh.old
   sudo mkdir /etc/ssh
   sudo chown root:root /etc/ssh
   sudo chmod 755 /etc/ssh
   sudo tar --same-owner -xzf "$SOURCE" -C /etc/ssh

else

   # no! alert
   echo "$SOURCE not found - /etc/ssh is as set by Raspbian"
   
fi

# remove all ssh presets from boot volume
echo "Removing all /etc/ssh presets"
sudo rm -rf $SUPPORT/etc/ssh

# change the login password
echo "Setting the user password"
echo -e "$NEW_PASSWORD\n$NEW_PASSWORD" | sudo passwd $USER

# make the VNC password the same
TARGET="/etc/vnc/config.d/common.custom"
if SOURCE="$(supporting_file "$TARGET")" ; then
   echo "Setting up VNC (even though it is not activated)"
   sudo cp "$SOURCE" "$TARGET"
   echo -e "$NEW_PASSWORD\n$NEW_PASSWORD" | sudo vncpasswd -file "$TARGET"
   sudo chown root:root "$TARGET"
   sudo chmod 644 "$TARGET"
fi

if try_patch "/etc/locale.gen" "setting locales (ignore errors)" ; then
   sudo locale-gen
   # this produces an error - but it seems to work anyway (after reboot)
   sudo update-locale LANG=en_US.UTF-8
fi

# run the script epilog if it exists (best to run before rasp-config)
run_pibuilder_epilog

# boot to console (no desktop GUI)
# hints from https://discord.com/channels/638610460567928832/638610461109256194/792694778613202966
echo "Setting boot behaviour to console (no GUI)"
sudo raspi-config nonint do_boot_behaviour B1

echo "Setting WiFi country code to $LOCALCC"
sudo raspi-config nonint do_wifi_country "$LOCALCC"

echo "Setting time-zone to $LOCALTZ"
sudo raspi-config nonint do_change_timezone "$LOCALTZ"

# set the host name (produces errors)
echo "Setting machine name to $HOSTNAME"
sudo raspi-config nonint do_hostname "$HOSTNAME"

echo "Remember to do ssh-keygen -R raspberrypi.local then re-connect"
echo "to this machine under the name $HOSTNAME."
echo "$SCRIPT complete - rebooting..."
sudo reboot
