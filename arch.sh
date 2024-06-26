#!/usr/bin/env bash

select_menu() {
    ESC=$(printf "\033")
    cursor_blink_on()  { printf "$ESC[?25h"; }
    cursor_blink_off() { printf "$ESC[?25l"; }
    cursor_to()        { printf "$ESC[$1;${2:-1}H"; }
    print_option()     { printf "$2   $1 "; }
    print_selected()   { printf "$2  $ESC[7m $1 $ESC[27m"; }
    get_cursor_row()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
    get_cursor_col()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${COL#*[}; }
    key_input()         {
                        local key
                        IFS= read -rsn1 key 2>/dev/null >&2
                        if [[ $key = ""      ]]; then echo enter; fi;
                        if [[ $key = $'\x20' ]]; then echo space; fi;
                        if [[ $key = "k" ]]; then echo up; fi;
                        if [[ $key = "j" ]]; then echo down; fi;
                        if [[ $key = "h" ]]; then echo left; fi;
                        if [[ $key = "l" ]]; then echo right; fi;
                        if [[ $key = "a" ]]; then echo all; fi;
                        if [[ $key = "n" ]]; then echo none; fi;
                        if [[ $key = $'\x1b' ]]; then
                            read -rsn2 key
                            if [[ $key = [A || $key = k ]]; then echo up;    fi;
                            if [[ $key = [B || $key = j ]]; then echo down;  fi;
                            if [[ $key = [C || $key = l ]]; then echo right;  fi;
                            if [[ $key = [D || $key = h ]]; then echo left;  fi;
                        fi 
    }
    print_options_multicol() {
        local curr_col=$1
        local curr_row=$2
        local curr_idx=0

        local idx=0
        local row=0
        local col=0
        
        curr_idx=$(( $curr_col + $curr_row * $colmax ))
        
        for option in "${options[@]}"; do

            row=$(( $idx/$colmax ))
            col=$(( $idx - $row * $colmax ))

            cursor_to $(( $startrow + $row + 1)) $(( $offset * $col + 1))
            if [ $idx -eq $curr_idx ]; then
                print_selected "$option"
            else
                print_option "$option"
            fi
            ((idx++))
        done
    }

    for opt; do printf "\n"; done

    local return_value=$1
    local lastrow=`get_cursor_row`
    local lastcol=`get_cursor_col`
    local startrow=$(($lastrow - $#))
    local startcol=1
    local lines=$( tput lines )
    local cols=$( tput cols ) 
    local colmax=$2
    local offset=$(( $cols / $colmax ))

    local size=$4
    shift $(( $# > 4? 4 : $# ))

    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    local active_row=0
    local active_col=0
    while true; do
        print_options_multicol $active_col $active_row 

        case `key_input` in
            enter)  break;;
            up)     ((active_row--));
                    if [ $active_row -lt 0 ]; then active_row=0; fi;;
            down)   ((active_row++));
                    max_rows=$(( (${#options[@]} + $colmax - 1) / $colmax ))
                    if [ $active_row -ge $max_rows ]; then active_row=$(( max_rows - 1 )); fi;;
            left)   ((active_col--));
                    if [ $active_col -lt 0 ]; then active_col=0; fi;;
            right)  ((active_col++));
                    if [ $active_col -ge $colmax ]; then active_col=$(( $colmax - 1 )); fi;;
        esac

        selected_index=$(( $active_col + $active_row * $colmax ))

        if [ $selected_index -ge ${#options[@]} ]; then
            last_valid_index=$(( ${#options[@]} - 1 ))
            active_col=$(( $last_valid_index % $colmax ))
            active_row=$(( $last_valid_index / $colmax ))
        fi
    done

    local initial_row=$(get_cursor_row)
    local initial_col=$(get_cursor_col)

    cursor_to $initial_row $initial_col
    printf "\n"
    cursor_blink_on

    return $(( $active_col + $active_row * $colmax ))
}

confirm_option() {
    read -r -p "${1}" response
    case "${response}" in
        [yY][eE][sS]|[yY]|'' )
            true
            ;;
        *)
            false
            ;;
    esac
}

if [[ ! -d "/sys/firmware/efi" ]]; then
    echo "This script does not support BIOS systems."
    exit 1
fi

diskpart() {
    local options=($(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2"|"$3}'))

    while true; do
        echo "
Please choose the disk where your operating system is going to be installed on (root partition):"

        select_menu $? 1 "${options[@]}"
        disk=${options[$?]%|*}

        confirm_option "
You have selected (${disk}) for the installation. Proceed? [Y/n] " && break
    done
}

ssd() {
    local options=("Yes" "No")

    while true; do
        echo "
Is the installation disk (${disk}) an SSD?"

        select_menu $? 1 "${options[@]}"
        ssd=${options[$?]}

        confirm_option "
You have selected ${ssd}. Proceed? [Y/n] " && break
    done
}

filesystem() {
    local options=("BTRFS" "EXT4" "BTRFS LUKS" "EXT4 LUKS")

    while true; do
        echo "
What filesystem do you want to use?"

        select_menu $? 1 "${options[@]}"
        filesystem=${options[$?]}

        confirm_option "
You have selected ${filesystem}. Proceed? [Y/n] " && break
    done

    if [[ "${filesystem}" =~ ("BTRFS LUKS"|"EXT4 LUKS") ]]; then
        echo "
Please Enter Your LUKS Encryption Key: "
        read -s encryption_key

        while [[ -z ${encryption_key} ]]; do
            echo "
You did not enter a valid LUKS Encryption Key. Please try again: "
            read -s encryption_key
        done
    fi
}

timezone() {
    while true; do
        echo "Please enter a timezone (eg. Europe/Zurich)"
        read timezone

        if [ -f "/usr/share/zoneinfo/${timezone}" ]; then
            break
        fi
    done
}

keymap() {
    local options=("by" "ca" "cf" "cz" "de" "dk" "es" "et" "fa" "fi" "fr" "gr" "hu" "it" "lt" "lv" "mk" "nl" "no" "pl" "ro" "ru" "sg" "ua" "uk" "us")

    while true; do
        echo "Please select your keyboard layout:"

        select_menu $? 4 "${options[@]}"
        keymap=${options[$?]}

        confirm_option "
You have selected the '${keymap}' keyboard layout. Proceed? [Y/n] " && break
    done
}

other_info() {
    echo "Please enter a hostname:"
    read hostname
    while [[ -z "${hostname}" ]]; do
        echo "You did not enter a hostname. Please try again:"
        read hostname
    done

    echo "Please enter a Root Password:"
    read -s rootpass
    while [[ -z "${rootpass}" ]]; do
        echo "You did not enter a root password. Please try again:"
        read -s rootpass
    done

    echo "Please enter a username:"
    read username
    while [[ -z "${username}" ]]; do
        echo "You did not enter a username. Please try again:"
        read username
    done

    echo "Please enter your user's password:"
    read -s userpass
    while [[ -z "${userpass}" ]]; do
        echo "You did not enter a user password. Please try again:"
        read -s userpass
    done
}

diskpart
ssd
filesystem
timezone
keymap
other_info

while true; do 
  confirm_option "Are you certain you wish to proceed with the installation? this process cannot be undone. [Y/n]: " && break

  exit 1
done

format_disk() {
    dd if=/dev/urandom of=${disk} status=progress bs=4096

    sgdisk --clear \
        --new=1:0:+512MiB --typecode=1:ef00 --change-name=1:EFI \
        --new=2:0:0 --typecode=2:8304 --change-name=2:root \
    "${disk}"

    sort_partitions
    set_mount_options

    case "${filesystem}" in
        "BTRFS"|"EXT4")
            case "${filesystem}" in
                "BTRFS")
                    setup_btrfs "${partition2}"
                    ;;
                "EXT4")
                    setup_ext4 "${partition2}"
                    ;;
            esac
            ;;
        "BTRFS LUKS"|"EXT4 LUKS")
            echo -n "${encryption_key}" | cryptsetup luksFormat --perf-no_read_workqueue --perf-no_write_workqueue --type luks2 --cipher aes-xts-plain64 --hash sha512 --iter-time 2000 --key-size 512 --pbkdf argon2id --use-urandom --verify-passphrase "${partition2}" -
            echo -n "${encryption_key}" | cryptsetup luksOpen "${partition2}" systemRoot -

            case "${filesystem}" in
                "BTRFS LUKS")
                    setup_btrfs "/dev/mapper/systemRoot"
                    ;;
                "EXT4 LUKS")
                    setup_ext4 "/dev/mapper/systemRoot"
                    ;;
            esac
            ;;
    esac

    setup_swap
    format_efi_partition
}

sort_partitions() {
    local partition_prefix=""
    if [[ "${disk}" =~ "nvme" ]]; then
        partition_prefix="p"
    fi

    partition1="${disk}${partition_prefix}1"
    partition2="${disk}${partition_prefix}2"
}

set_mount_options() {
    local mount_options_base="rw,x-mount.mkdir,compress=zstd,space_cache=v2,noatime,nodiratime,autodefrag"
    mount_options="${mount_options_base}${ssd:+,ssd}"
}

create_subvolumes() {
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@swap
}

mount_subvolumes() {
    mount -t btrfs -o "${mount_options},subvol=@" LABEL=systemRoot /mnt
    mount -t btrfs -o "${mount_options},subvol=@home" LABEL=systemRoot /mnt/home
    mount -t btrfs -o "${mount_options},subvol=@var" LABEL=systemRoot /mnt/var
    mount -t btrfs -o "${mount_options},subvol=@snapshots" LABEL=systemRoot /mnt/.snapshots
}

setup_btrfs() {
    local partition="${1:-$partition2}"

    mkfs.btrfs -L systemRoot "${partition}"
    mount -t btrfs LABEL=systemRoot /mnt

    create_subvolumes
    umount -R /mnt

    mount_subvolumes
}

setup_ext4() {
    local partition="${1:-$partition2}"

    mkfs.ext4 -L systemRoot "${partition}"
    mount -t ext4 LABEL=systemRoot /mnt
}

setup_swap() {
    if [[ "${filesystem}" =~ ("BTRFS"|"BTRFS LUKS") ]]; then
        local mount_options_base_swap="rw,x-mount.mkdir,compress=no,space_cache=v2"
        mount_options_swap="${mount_options_base_swap}${ssd:+,ssd}"

        mount -t btrfs -o ${mount_options_swap},subvol=@swap LABEL=systemRoot /mnt/swap

        btrfs filesystem mkswapfile --size 10g --uuid clear /mnt/swap/swapfile

        swapon /mnt/swap/swapfile
    elif [[ "${filesystem}" =~ ("EXT4"|"EXT4 LUKS") ]]; then
        mkdir /mnt/swap
        mkswap -U clear --size 10G --file /mnt/swap/swapfile

        swapon /mnt/swap/swapfile
    fi
}

format_efi_partition() {
    mkfs.fat -F32 -n EFI "${partition1}"
    mkdir -p /mnt/efi
    mount LABEL=EFI /mnt/efi
}

pre_install() {
    pacman -S --noconfirm archlinux-keyring
    pacman -S --noconfirm --needed reflector rsync terminus-font
    setfont ter-v22b

    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

    reflector --download-timeout 15 -a 48 -f 15 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
    mkdir /mnt &> /dev/null
}

initial_setup() {
    cpu_type=$(lscpu)
    if grep -E "GenuineIntel" <<< "${cpu_type}"; then
        microcode="intel-ucode"
    elif grep -E "AuthenticAMD" <<< "${cpu_type}"; then
        microcode="amd-ucode"
    fi

    pacstrap -K /mnt base linux-hardened linux-firmware linux-headers ${microcode} dosfstools efibootmgr archlinux-keyring base-devel btrfs-progs nano sudo zsh git pacman-contrib tlp

    cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
    sed -i "/\[multilib\]/,/Include/"'s/^#//' /mnt/etc/pacman.conf
    sed -i 's/#UseSyslog/UseSyslog/' /mnt/etc/pacman.conf
    sed -i 's/#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf
    sed -i 's/#TotalDownload/TotalDownload/' /mnt/etc/pacman.conf
    sed -i 's/#CheckSpace/CheckSpace/' /mnt/etc/pacman.conf

    genfstab -L -p /mnt >> /mnt/etc/fstab

    sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab
}

pre_install
format_disk
initial_setup

cat <<REALEND > /mnt/chroot.sh
chroot_initial_setup() {
    sed -i 's/^#en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen

    echo "KEYMAP=${keymap}" > /etc/vconsole.conf

    ln -sf /usr/share/zoneinfo/"${timezone}" /etc/localtime
    hwclock --systohc

    echo ${hostname} > /etc/hostname
    cat <<EOF > /etc/hosts
127.0.0.1    localhost
::1            localhost
127.0.1.1    ${hostname}.localdomain    ${hostname}
EOF
}

chroot_user_setup() {
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

    useradd -m -G wheel -s /bin/zsh ${username}
    echo "${username}:${userpass//\"/\\\"}" | chpasswd

    echo "root:${rootpass//\"/\\\"}" | chpasswd
}

chroot_network_setup() {
    pacman -Sy --noconfirm --needed
    pacman -S --noconfirm --needed networkmanager dnsmasq

    systemctl enable NetworkManager

    cat <<EOF > /etc/NetworkManager/conf.d/wifi_rand_mac.conf
[device-mac-randomization]
wifi.scan-rand-mac-address=yes

[connection-mac-randomization]
ethernet.cloned-mac-address=random
wifi.cloned-mac-address=stable
EOF
}

chroot_mkinitcpio_setup() {
    case "${filesystem}" in
    "BTRFS LUKS")
        sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole sd-encrypt block filesystems btrfs)/' /etc/mkinitcpio.conf
        ;;
    "BTRFS")
        sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems btrfs)/' /etc/mkinitcpio.conf
        ;;
    "EXT4 LUKS")
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole sd-encrypt block filesystems fsck)/' /etc/mkinitcpio.conf
        ;;
    "EXT4")
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)/' /etc/mkinitcpio.conf
        ;;
    esac
}

chroot_other_setup() {
    systemctl enable paccache.timer
    systemctl enable fstrim.timer
    systemctl enable tlp.service

    cat <<EOF > /etc/tlp.conf
TLP_DEFAULT_MODE=BAT
TLP_PERSISTENT_DEFAULT=1

RUNTIME_PM_ON_AC=auto
USB_AUTOSUSPEND=0
EOF
   sed -i 's/^#MAKEFLAGS/MAKEFLAGS="-j$(getconf _NPROCESSORS_ONLN) --quiet"/' /etc/makepkg.conf

    pacman -S --needed --noconfirm \
        libva-intel-driver \
        libvdpau-va-gl \
        lib32-vulkan-intel \
        vulkan-intel \
        libva-intel-driver \
        libva-utils \
        lib32-mesa
}

chroot_boot_setup() {
    mkdir -p /efi/EFI/Linux

    sed -i 's/^#ALL_config="\/etc\/mkinitcpio.conf"/ALL_config="\/etc\/mkinitcpio.conf"/' /etc/mkinitcpio.d/linux-hardened.preset
    sed -i 's/^default_image="\/boot\/initramfs-linux-hardened.img"/#default_image="\/boot\/initramfs-linux-hardened.img"/' /etc/mkinitcpio.d/linux-hardened.preset
    sed -i 's/^#default_uki="\/efi\/EFI\/Linux\/arch-linux-hardened.efi"/default_uki="\/efi\/EFI\/Linux\/arch-linux-hardened.efi"/' /etc/mkinitcpio.d/linux-hardened.preset
    sed -i 's/^#default_options="--splash \/usr\/share\/systemd\/bootctl\/splash-arch.bmp"/default_options="--splash \/usr\/share\/systemd\/bootctl\/splash-arch.bmp"/' /etc/mkinitcpio.d/linux-hardened.preset
    sed -i 's/^fallback_image="\/boot\/initramfs-linux-hardened-fallback.img"/#fallback_image="\/boot\/initramfs-linux-hardened-fallback.img"/' /etc/mkinitcpio.d/linux-hardened.preset
    sed -i 's/^#fallback_uki="\/efi\/EFI\/Linux\/arch-linux-hardened-fallback.efi"/fallback_uki="\/efi\/EFI\/Linux\/arch-linux-hardened-fallback.efi"/' /etc/mkinitcpio.d/linux-hardened.preset

    echo "rd.luks.name=$(blkid -s UUID -o value ${partition2})=systemRoot root=/dev/mapper/systemRoot rootfstype=btrfs rootflags=subvol=@ quiet rw" > /etc/kernel/cmdline

    mkinitcpio -P
}

chroot_initial_setup
chroot_user_setup
chroot_network_setup
chroot_mkinitcpio_setup
chroot_other_setup
chroot_boot_setup

REALEND

arch-chroot /mnt sh chroot.sh

rm /mnt/chroot.sh
