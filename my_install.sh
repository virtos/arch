echo Check connection:
ping archilinux.org
exit

timedatectl set-ntp true

# Partition the disk
echo Install on /dev/sda?
lsblk
exit


# Create a primary partition - entire disk
parted -s /dev/sda mklabel gpt
parted -s mkpart ESP fat32 1MiB 300MiB
parted -s name 1 efiboot
parted -s /dev/sda mkpart primary 300MiB 100%
parted -s name system
parted -s print

exit

# Create a LUKS volume & Open it
cryptsetup luksFormat --cipher aes-xts-plain64 --key-size 256 --hash sha256 --use-random /dev/sda2
cryptsetup luksOpen /dev/sda2 cryptroot

mkfs.fat   --label efiboot -F32 /dev/sda1
mkfs.btrfs --label archlinux /dev/mapper/cryptroot
mount -o noatime,commit=120,compress=zstd,discard,ssd,defaults /dev/mapper/cryptroot /mnt

read -p "Press any key if no errors"

btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@var
btrfs su cr /mnt/@opt
btrfs su cr /mnt/@tmp
btrfs su cr /mnt/@.snapshots
umount /mnt

read -p "Press any key if no errors"

mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@ /dev/mapper/cryptroot /mnt
mkdir /mnt/{boot,home,var,opt,tmp,.snapshots}
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@opt  /dev/mapper/cryptroot /mnt/opt
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@tmp  /dev/mapper/cryptroot /mnt/tmp
mount -o noatime,commit=120,compress=zstd,space_cache,subvol=@.snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o space_cache,subvol=@var /dev/mapper/cryptroot /mnt/var
# Mounting the boot partition at /boot folder
mount /dev/sda1 /mnt/boot

read -p "Press any key if no errors"


# Install Arch Linux with full encrypted btrfs subvolume inside luks
pacstrap /mnt base base-devel linux linux-firmware nano intel-ucode btrfs-progs grub --noconfirm
# Generate fstab
genfstab -U -p /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab

read -p "Press any key if fstab looks ok"

arch-chroot /mnt
# Setup system clock
ln -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc --utc
# Set the hostname
echo archlap > /etc/hostname

read -p "uncomment en_US.UTF-8 UTF-8 and other needed locales. Ready?"
nano /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 >> /etc/locale.conf
echo LANGUAGE=en_US >> /etc/locale.conf
echo LC_ALL=C >> /etc/locale.conf

read -p "Press any key if fstab looks ok"

touch /etc/hosts
echo '127.0.0.1	localhost'  >> /etc/hosts
echo '::1		localhost' >> /etc/hosts
echo '127.0.1.1	laparch.localdomain	laparch' >> /etc/hosts

# Create a new initramfs
sed -i 's/HOOKS=(base\ udev\ autodetect\ modconf\ block\ filesystems\ keyboard\ fsck)/HOOKS="base\ udev\ autodetect\ modconf\ block\ encrypt\ filesystems\ keyboard\ fsck"/' /etc/mkinitcpio.conf
cat /etc/mkinitcpio.conf
read -p "Check HOOKS before continue"
mkinitcpio -p linux

echo 'Set the root password'
passwd root

echo 'Install grub'
grub-install --target=x86_64-efi --efi-directory=/boot/efi --recheck

echo 'Configure LUKS kernel parameters'
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="cryptdevice=\/dev\/sda4:cryptroot\ root=\/dev\/mapper\/cryptroot\ rootflags=subvol=__active\/rootvol\ quiet"/' /etc/default/grub

echo 'Regenerate grub.cfg file:'
grub-mkconfig -o /boot/grub/grub.cfg
grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg
mkdir /boot/efi/EFI/BOOT
cp /boot/efi/EFI/arch/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

echo 'Allow users to run SUDO'
echo "%wheel ALL=(ALL) ALL" | (EDITOR="tee -a" visudo)

echo 'Create a user account'
useradd -m -G wheel eugene
passwd eugene

# Exit new system and go into the cd shell
exit

# Unmount all partitions
umount -R /mnt

# Reboot into the new system, don't forget to remove the usb
reboot