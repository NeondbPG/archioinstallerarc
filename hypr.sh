setup_ctl() {
  sudo timedatectl --no-ask-password set-timezone GMT+0
  sudo timedatectl --no-ask-password set-ntp 1

  sudo localectl --no-ask-password set-locale LANG="en_GB.UTF-8" LC_TIME="en_GB.UTF-8"
  sudo localectl --no-ask-password set-keymap uk
}

install_aur_helper() {
  sudo pacman -S --noconfirm --needed rustup

  rustup default stable

  git clone https://aur.archlinux.org/paru.git
  cd paru

  makepkg -si
}

install_hypr() {
  paru -S gdb ninja gcc cmake meson libxcb xcb-proto xcb-util xcb-util-keysyms libxfixes libx11 libxcomposite xorg-xinput libxrender pixman wayland-protocols cairo pango seatd libxkbcommon xcb-util-wm xorg-xwayland libinput libliftoff libdisplay-info cpio tomlplusplus hyprlang hyprcursor hyprwayland-scanner xcb-util-errors

  git clone --recursive https://github.com/hyprwm/Hyprland
  cd Hyprland

  make all && sudo make install
}

install_hypr
