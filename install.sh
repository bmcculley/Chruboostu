# fw_type will always be developer for Mario.
# Alex and ZGB need the developer BIOS installed though.
fw_type="`crossystem mainfw_type`"
if [ ! "$fw_type" = "developer" ]
  then
    echo -e "\nYou're Chromebook is not running a developer BIOS!"
    echo -e "You need to run:"
    echo -e ""
    echo -e "sudo chromeos-firmwareupdate --mode=todev"
    echo -e ""
    echo -e "and then re-run this script."
    exit 
fi

powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]
then
  echo -e "Stopping powerd to keep display from timing out..."
  initctl stop powerd
fi

setterm -blank 0

if [ "$3" != "" ]; then
  target_disk=$3
  echo "Got ${target_disk} as target drive"
  echo ""
  echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
  echo ""
  read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

  ext_size="`blockdev --getsz ${target_disk}`"
  aroot_size=$((ext_size - 65600 - 33))
  parted --script ${target_disk} "mktable gpt"
  cgpt create ${target_disk} 
  cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
  cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
  sync
  blockdev --rereadpt ${target_disk}
  partprobe ${target_disk}
  crossystem dev_boot_usb=1
else
  target_disk="`rootdev -d -s`"
  # Do partitioning (if we haven't already)
  ckern_size="`cgpt show -i 6 -n -s -q ${target_disk}`"
  croot_size="`cgpt show -i 7 -n -s -q ${target_disk}`"
  state_size="`cgpt show -i 1 -n -s -q ${target_disk}`"

  max_ubuntu_size=$((999))
  rec_ubuntu_size=$(($max_ubuntu_size - 1))
  # If KERN-C and ROOT-C are one, we partition, otherwise assume they're what they need to be...
  if [ "$ckern_size" =  "1" -o "$croot_size" = "1" ]
  then
    while :
    do
      read -p "Enter the size in gigabytes you want to reserve for Ubuntu. Acceptable range is 5 to $max_ubuntu_size although 10 is the recommended maximum: " ubuntu_size
      if [ ! $ubuntu_size -ne 0 2>/dev/null ]
      then
        echo -e "\n\nNumbers only please...\n\n"
        continue
      fi
      if [ $ubuntu_size -lt 5 -o $ubuntu_size -gt $max_ubuntu_size ]
      then
        echo -e "\n\nThat number is out of range. Enter a number 5 through $max_ubuntu_size\n\n"
        continue
      fi
      break
    done
    # We've got our size in GB for ROOT-C so do the math...

    #calculate sector size for rootc
    rootc_size=$(($ubuntu_size*1024*1024*2))

    #kernc is always 16mb
    kernc_size=32768

    #new stateful size with rootc and kernc subtracted from original
    stateful_size=$(($state_size - $rootc_size - $kernc_size))

    #start stateful at the same spot it currently starts at
    stateful_start="`cgpt show -i 1 -n -b -q ${target_disk}`"

    #start kernc at stateful start plus stateful size
    kernc_start=$(($stateful_start + $stateful_size))

    #start rootc at kernc start plus kernc size
    rootc_start=$(($kernc_start + $kernc_size))

    #Do the real work

    echo -e "\n\nModifying partition table to make room for Ubuntu." 
    echo -e "Your Chromebook will reboot, wipe your data and then"
    echo -e "you should re-run this script..."
    umount -f /mnt/stateful_partition

    # stateful first
    cgpt add -i 1 -b $stateful_start -s $stateful_size -l STATE ${target_disk}

    # now kernc
    cgpt add -i 6 -b $kernc_start -s $kernc_size -l KERN-C ${target_disk}

    # finally rootc
    cgpt add -i 7 -b $rootc_start -s $rootc_size -l ROOT-C ${target_disk}
    read -p "Partitioning complete, do you want to reboot? Type y or n: " rebootDecision
    if [ "$rebootDecision" = "y" ]; then
        reboot
        exit
    else
      exit
    fi
  fi
fi

# hwid lets us know if this is a Mario (Cr-48), Alex (Samsung Series 5), ZGB (Acer), etc
hwid="`crossystem hwid`"

chromebook_arch="`uname -m`"

ubuntu_metapackage=${1:-default}

latest_ubuntu=`wget --quiet -O - http://changelogs.ubuntu.com/meta-release | grep "^Version: " | tail -1 | sed -r 's/^Version: ([^ ]+)( LTS)?$/\1/'`
ubuntu_version=${2:-$latest_ubuntu}

if [ "$ubuntu_version" = "lts" ]
then
  ubuntu_version=`wget --quiet -O - http://changelogs.ubuntu.com/meta-release | grep "^Version:" | grep "LTS" | tail -1 | sed -r 's/^Version: ([^ ]+)( LTS)?$/\1/'`
elif [ "$ubuntu_version" = "latest" ]
then
  ubuntu_version=$latest_ubuntu
fi

if [ "$chromebook_arch" = "x86_64" ]
then
  ubuntu_arch="amd64"
  if [ "$ubuntu_metapackage" = "default" ]
  then
    ubuntu_metapackage="ubuntu-desktop"
  fi
elif [ "$chromebook_arch" = "i686" ]
then
  ubuntu_arch="i386"
  if [ "$ubuntu_metapackage" = "default" ]
  then
    ubuntu_metapackage="ubuntu-desktop"
  fi
elif [ "$chromebook_arch" = "armv7l" ]
then
  ubuntu_arch="armhf"
  if [ "$ubuntu_metapackage" = "default" ]
  then
    ubuntu_metapackage="xubuntu-desktop"
  fi
else
  echo -e "Error: This script doesn't know how to install ChrUbuntu on $chromebook_arch"
  exit
fi

echo -e "\nChrome device model is: $hwid\n"

echo -e "Installing Ubuntu ${ubuntu_version} with metapackage ${ubuntu_metapackage}\n"

echo -e "Kernel Arch is: $chromebook_arch  Installing Ubuntu Arch: $ubuntu_arch\n"

read -p "Press [Enter] to continue..."

if [ ! -d /mnt/stateful_partition/ubuntu ]
then
  mkdir /mnt/stateful_partition/ubuntu
fi

cd /mnt/stateful_partition/ubuntu

if [[ "${target_disk}" =~ "mmcblk" ]]
then
  target_rootfs="${target_disk}p7"
  target_kern="${target_disk}p6"
else
  target_rootfs="${target_disk}7"
  target_kern="${target_disk}6"
fi

echo "Target Kernel Partition: $target_kern  Target Root FS: ${target_rootfs}"

if mount|grep ${target_rootfs}
then
  echo "Refusing to continue since ${target_rootfs} is formatted and mounted. Try rebooting"
  exit 
fi

mkfs.ext4 ${target_rootfs}

if [ ! -d /tmp/urfs ]
then
  mkdir /tmp/urfs
fi
mount -t ext4 ${target_rootfs} /tmp/urfs

tar_file="http://cdimage.ubuntu.com/ubuntu-core/releases/$ubuntu_version/release/ubuntu-core-$ubuntu_version-core-$ubuntu_arch.tar.gz"
if [ $ubuntu_version = "dev" ]
then
  ubuntu_animal=`wget --quiet -O - http://changelogs.ubuntu.com/meta-release-development | grep "^Dist: " | tail -1 | sed -r 's/^Dist: (.*)$/\1/'`
  tar_file="http://cdimage.ubuntu.com/ubuntu-core/daily/current/$ubuntu_animal-core-$ubuntu_arch.tar.gz"
fi
wget -O - $tar_file | tar xzvvp -C /tmp/urfs/

mount -o bind /proc /tmp/urfs/proc
mount -o bind /dev /tmp/urfs/dev
mount -o bind /dev/pts /tmp/urfs/dev/pts
mount -o bind /sys /tmp/urfs/sys

if [ -f /usr/bin/old_bins/cgpt ]
then
  cp /usr/bin/old_bins/cgpt /tmp/urfs/usr/bin/
else
  cp /usr/bin/cgpt /tmp/urfs/usr/bin/
fi


read -p "Enter desired hostname : " hostname
chmod a+rx /tmp/urfs/usr/bin/cgpt
cp /etc/resolv.conf /tmp/urfs/etc/
echo $hostname > /tmp/urfs/etc/hostname
#echo -e "127.0.0.1       localhost"
echo -e "\n127.0.0.1     localhost
         \n127.0.0.1     ${hostname}" >> /tmp/urfs/etc/hosts
# The following lines are desirable for IPv6 capable hosts
#::1     localhost ip6-localhost ip6-loopback
#fe00::0 ip6-localnet
#ff00::0 ip6-mcastprefix
#ff02::1 ip6-allnodes
#ff02::2 ip6-allrouters" > /tmp/urfs/etc/hosts


read -p "Do you want to install chrome? Type y or n :" installChrome
if [ "$installChrome" = "y" ]; then
      cr_install="wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
      add-apt-repository \"deb http://dl.google.com/linux/chrome/deb/ stable main\"
      apt-get update
      apt-get -y install google-chrome-stable"
      if [ $ubuntu_arch = 'armhf' ]
      then
        cr_install='apt-get -y install chromium-browser'
      fi
    else
      cr_install="apt-get -y update"
  fi

add_apt_repository_package='software-properties-common'
ubuntu_major_version=${ubuntu_version:0:2}
ubuntu_minor_version=${ubuntu_version:3:2}
if [ $ubuntu_major_version -le 12 ] && [ $ubuntu_minor_version -lt 10 ]
then
  add_apt_repository_package='python-software-properties'
fi

# Let's make a cron job to trim our ssd daily
# mkdir /tmp/urfs/etc/cron.daily/
trim_install="cd 
cd /etc/cron.daily/
wget https://dl.dropboxusercontent.com/s/oq52f80tgqldlbx/trim.cron
chmod +x trim.cron
sudo mv trim.cron trim
"
# echo -e "#!/bin/sh
#         LOG=/var/log/trim.log
#         echo \"*** $(date -R) ***\" >> $LOG
#         fstrim -v / >> $LOG
#         fstrim -v /home >> $LOG" >> /tmp/urfs/cron.daily/trim
# chmod +x /tmp/urfs/cron.daily/trim


# Choose username and password
read -p "Enter username : " username

read -p "Do you want to install steam? Type y or n :" installSteam
if [ "$installSteam" = "y" ]; then
    steam_install="wget http://media.steampowered.com/client/installer/steam.deb
                     apt-get -y install gdebi-core
                     gdebi steam.deb
                     rm steam.deb"
    else
      steam_install="apt-get -y update"
  fi

read -p "Do you want to install virtualmin? Type y or n :" installVmin
if [ "$installVmin" = "y" ]; then
    vmin_install="wget http://software.virtualmin.com/gpl/scripts/install.sh
                    chmod +x install.sh
                    ./install.sh
                    rm install.sh"
    else
      vmin_install="apt-get -y update"
  fi

if [ "$installVmin" != "y" ]; then
  read -p "Do you want to install webmin? Type y or n :" installWebmin
  if [ "$installWebmin" = "y" ]; then
      webmin_install="add-apt-repository \"deb http://download.webmin.com/download/repository sarge contrib\"
                       add-apt-repository \"deb http://webmin.mirror.somersettechsolutions.co.uk/repository sarge contrib\"
                       wget http://www.webmin.com/jcameron-key.asc
                       apt-key add jcameron-key.asc
                       rm jcameron-key.asc
                       apt-get -y update
                       apt-get -y install webmin"
      else
        webmin_install="apt-get update"
    fi
fi

read -p "Do you want to install utorrent server? Type y or n :" installUtorrent
if [ "$installUtorrent" = "y" ]; then
    utorrent_install="apt-get -y install libssl0.9.8:i386
                        wget http://download.utorrent.com/linux/utorrent-server-3.0-25053.tar.gz
                        cp utorrent-server-3.0-25053.tar.gz /opt/
                        cd /opt/
                        tar -xvf utorrent-server-3.0-25053.tar.gz
                        rm -rf utorrent-server-3.0-25053.tar.gz
                        chmod 777 -R utorrent-server-v3_0/
                        ln -s /opt/utorrent-server-v3_0/utserver /usr/bin/utserver"
    else
      utorrent_install="apt-get -y update"
  fi

read -p "Do you want to install plex media server? Type y or n :" installPlex
if [ "$installPlex" = "y" ]; then
    plex_install="add-apt-repository \"deb http://plex.r.worldssl.net/PlexMediaServer/ubuntu-repo lucid main\"
    apt-get -y install plex-archive-keyring
    wget http://plexapp.com/plex_pub_key.pub
    apt-key -y add plex_pub_key.pub
    rm plex_pub_key.pub
    apt-get -y update
    apt-get --force-yes install plexmediaserver"
    else
      plex_install="apt-get -y update"
  fi

read -p "Do you want to install mysql-server? Type y or n :" installMysql
if [ "$installMysql" = "y" ]; then
    mysql_install="apt-get -y install mysql-server"
    else
    mysql_install="apt-get -y update"
  fi

read -p "Do you want to install Chef Server (12.04 only)?, WARNING: Do not press y if you are chose a version newer than 12.04, it might install but no promises! Type y or n :" installChef
if [ "$installChef" = "y" ]; then
    chef_install="wget https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chef-server_11.0.8-1.ubuntu.12.04_amd64.deb
                    dpkg -i chef-server_11.0.8-1.ubuntu.12.04_amd64.deb
                    chef-server-ctl reconfigure"
    else
    chef_install="apt-get -y update"
  fi

read -p "Install OpenSSH Server? Type y or n :" installSSH
if [ "$installSSH" = "y" ]; then
    ssh_install="apt-get -y install ssh"
    else
    ssh_install="apt-get -y update"
  fi

read -p "Do you want to update intel graphics driver for ubuntu ${ubuntu_version:0:5}? Type y or n :" installIntel
if [ "$installIntel" = "y" ]; then
    intel_install="add-apt-repository \"deb https://download.01.org/gfx/ubuntu/${ubuntu_version:0:5}/main Ubuntu ${ubuntu_version:0:5}\"
                    apt-get -y update
                    apt-get -y install intel-linux-graphics-installer"
    else
      intel_install="apt-get -y update"
  fi
  


echo -e "useradd -m ${username} -s /bin/bash
passwd ${username}
apt-get -y update
apt-get -y dist-upgrade
apt-get -y install ubuntu-minimal
apt-get -y install wget
apt-get -y install $add_apt_repository_package
add-apt-repository main
add-apt-repository universe
add-apt-repository restricted
add-apt-repository multiverse
apt-get -y update
apt-get -y install $ubuntu_metapackage
apt-get -y install build-essential
apt-get -y install apt-transport-https
apt-get -y install mesa-utils
apt-get -y install localepurge
if [ -f /usr/lib/lightdm/lightdm-set-defaults ]
then
  /usr/lib/lightdm/lightdm-set-defaults --autologin ${username}
fi
adduser ${username} adm
adduser ${username} sudo
$trim_install
$mysql_install
$ssh_install
$chef_install
$vmin_install
$webmin_install
$utorrent_install
$steam_install
$plex_install
$cr_install
$intel_install
" > /tmp/urfs/install-ubuntu.sh

chmod a+x /tmp/urfs/install-ubuntu.sh
chroot /tmp/urfs /bin/bash -c /install-ubuntu.sh
rm /tmp/urfs/install-ubuntu.sh

KERN_VER=`uname -r`
mkdir -p /tmp/urfs/lib/modules/$KERN_VER/
cp -ar /lib/modules/$KERN_VER/* /tmp/urfs/lib/modules/$KERN_VER/
if [ ! -d /tmp/urfs/lib/firmware/ ]
then
  mkdir /tmp/urfs/lib/firmware/
fi
cp -ar /lib/firmware/* /tmp/urfs/lib/firmware/

echo "console=tty1 debug verbose root=${target_rootfs} rootwait rw lsm.module_locking=0 disablevmx=off" > kernel-config
vbutil_arch="x86"
if [ $ubuntu_arch = "armhf" ]
then
  vbutil_arch="arm"
fi

current_rootfs="`rootdev -s`"
current_kernfs_num=$((${current_rootfs: -1:1}-1))
current_kernfs=${current_rootfs: 0:-1}$current_kernfs_num

vbutil_kernel --repack ${target_kern} \
    --oldblob $current_kernfs \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --version 1 \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --config kernel-config \
    --arch $vbutil_arch

#Set Ubuntu kernel partition as top priority for next boot (and next boot only)
cgpt add -i 6 -P 5 -T 1 ${target_disk}

echo -e "

Installation seems to be complete. If ChrUbuntu fails when you reboot,
power off your Chrome OS device and then turn it back on. You'll be back
in Chrome OS. If you're happy with ChrUbuntu when you reboot be sure to run:

sudo cgpt add -i 6 -P 5 -S 1 ${target_disk}

To make it the default boot option. The ChrUbuntu login is:

Username:  ${username}
Password:  Whatever you put your password as ;)

We're now ready to start ChrUbuntu!
"

read -p "Press [Enter] to reboot..."

reboot
