#!/usr/bin/env bash
# Preview or install a readable Solarized Dark Linux virtual console.
set -euo pipefail

font=/usr/share/consolefonts/Lat15-TerminusBold32x16.psf.gz
config=/etc/default/console-setup
backup=/etc/default/console-setup.before-solarized-dark
palette_file=/etc/console-setup/vtrgb.solarized-dark

palette() {
  cat <<'COLORS'
#002b36
#dc322f
#859900
#b58900
#268bd2
#d33682
#2aa198
#839496
#073642
#cb4b16
#586e75
#657b83
#93a1a1
#6c71c4
#eee8d5
#fdf6e3
COLORS
}

usage() {
  echo "Usage: sudo bash $0 preview [/dev/tty4] | install | restore" >&2
  exit 2
}

(( EUID == 0 )) || { echo 'Run this script with sudo.' >&2; exit 1; }
[[ -f $font ]] || { echo "Missing console font: $font" >&2; exit 1; }

case ${1:-} in
  preview)
    console=${2:-/dev/tty4}
    [[ $console =~ ^/dev/tty[1-6]$ && -c $console ]] || usage
    setfont -C "$console" "$font"
    palette | setvtrgb -C "$console" -
    printf '\033[0;37;40m\033[2J\033[H%s\n%s\n' \
      'Solarized Dark / TerminusBold 16x32' \
      'Press Enter for a login prompt; switch back to EXWM when done.' \
      > "$console"
    echo "Preview ready on $console. Switch there with Ctrl+Alt+F${console##*tty}."
    ;;
  install)
    for key in CODESET FONTFACE FONTSIZE; do
      grep -q "^${key}=" "$config" || { echo "Missing $key in $config" >&2; exit 1; }
    done
    [[ -e $backup ]] || cp -p "$config" "$backup"
    sed -i \
      -e 's/^CODESET=.*/CODESET="Lat15"/' \
      -e 's/^FONTFACE=.*/FONTFACE="TerminusBold"/' \
      -e 's/^FONTSIZE=.*/FONTSIZE="16x32"/' \
      "$config"
    palette > "$palette_file"
    chmod 644 "$palette_file"
    update-alternatives --install /etc/vtrgb vtrgb "$palette_file" 60
    update-alternatives --set vtrgb "$palette_file"
    setupcon --save-only
    echo 'Installed. Console font and colors will be applied at the next boot.'
    ;;
  restore)
    [[ -f $backup ]] || { echo "Missing backup: $backup" >&2; exit 1; }
    cp -p "$backup" "$config"
    update-alternatives --set vtrgb /etc/console-setup/vtrgb
    setupcon --save-only
    echo 'Previous console setup restored; reboot to apply it.'
    ;;
  *) usage ;;
esac
