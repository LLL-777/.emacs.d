# EXWM session

This is an opt-in X11 session. Snap Emacs loads the usual `early-init.el` and
`init.el`, then the EXWM-only `session.el`. EXWM and XELB come from Ubuntu's
system packages. GNOME and GDM remain available as a fallback.

`session.el` is the entry point and owns EXWM configuration. It loads
`session-input-method.el` for Chinese input, `session-commands.el` for launch
commands, and `session-touchpad.el` for gesture hooks before enabling EXWM.
The terminal package remains loaded only when its command is used.

## Start from a TTY

1. Save your work and log out of GNOME.
2. Press `Ctrl+Alt+F3` and log in at the text prompt.
3. Run:

   ```sh
   startx /bin/sh "$HOME/.emacs.d/exwm/xinitrc" -- :1
   ```

This starts `/snap/bin/emacs` with the full Emacs configuration in a separate
X11 session. The usual `C-c c` Codex binding is available in this main Emacs.
The `:1` display avoids colliding with a display already used by GDM. Startup
output is saved to `~/.local/state/exwm/startup.log` for troubleshooting.
The session sets `Xft.dpi` to 192 for readable fonts on the 3072x1920 panel;
this applies only to EXWM's X11 display and takes effect after restarting it.

## Basic keys

EXWM commands use `Super+Space` as a prefix: release those keys, then press
the second key. Firefox starts in line mode: `C-x b` switches buffers, and
`C-n`, `C-p`, `C-f`, `C-b`, `C-a`, and `C-e` act as navigation keys in Firefox.
Other X applications start in char mode and keep their native shortcuts.

- `Super+Space`, then `t`: open a new `vterm` buffer inside the EXWM host Emacs.
- `F12` or `Super+Space`, then `Shift+t`: open an independent X terminal
  for recovery when Emacs or `vterm` needs repair.
- `Super+Space`, then `d`: enter a command to launch without blocking Emacs.
- `Super+Space`, then `e`: open a new Eat buffer inside the EXWM host Emacs.
- `Super+Space`, then `n`: open another configured Snap Emacs process.
- `Super+Space`, then `b`: switch buffers from any X application, even in char mode.
- `Super+Space`, then `w`: switch workspace.
- `Super+Space`, then `0`–`9`: switch to or create a workspace.
- `Super+Space`, then `u s s`: select a region and save it in
  `~/Pictures/Screenshots/` with scrot.
- `Super+Space`, then `u s c`: select a region and copy it to the X clipboard
  with scrot and xclip.
- `Super+Space`, then `k`: toggle the current X app between char and line mode.
- `Super+Space`, then `r`: reset the current X app to line mode.
- In Firefox, use `Super+Space`, then `k` for native browser shortcuts such as
  `C-n` and `C-f`; press it again to return to Emacs-style navigation.
- `C-x C-c` in the EXWM host Emacs: end the EXWM session.

External application integrations live in `apps/`. These modules are optional;
see `apps/README.md` for the module naming and key conventions.

`vterm` requires the Emacs `vterm` package and its loadable module in addition
to the system `libvterm` library. On Ubuntu, `elpa-vterm` supplies those files.

## Touch Bar keys

EXWM handles the volume, mute, display brightness, keyboard backlight, and
previous/play-pause/next media keys globally, including while an X application
has focus. Volume uses the existing `wpctl` command. Display brightness targets
`gmux_backlight` in five-percent steps, and keyboard backlight targets
`:white:kbd_backlight` in ten-percent steps. Emacs reads the current brightness
from sysfs and asks `systemd-logind` to set the new value over D-Bus. This does
not require `brightnessctl` or membership in the `video` and `input` groups.

Media keys call MPRIS through Emacs's built-in D-Bus support; the active media
player must expose an MPRIS service. No `playerctl` installation is needed.
PipeWire and WirePlumber must remain installed and running for volume control,
including if GNOME is removed later.

## Chinese input

The EXWM host uses `pyim` with `pyim-basedict` for word candidates when both
packages are installed. It falls back to Emacs's built-in `chinese-py` if they
are unavailable. Press `C-\` to toggle Chinese input in Emacs and in X apps
using EXWM's XIM server. In both Emacs and X apps, candidates appear in the
EXWM host's bottom minibuffer, with Solarized colors for the selected word.
Chinese input uses half-width English punctuation by default; run
`pyim-punctuation-toggle` to change that for the current buffer.

The XIM environment is set only by `exwm/xinitrc`. Restart the EXWM session,
then launch Firefox again to let it connect to the new input method server.
Apps without XIM support may not accept this input method. An Emacs process
opened with `Super+Space e` still defaults to `chinese-py`.

After EXWM exits, the TTY login remains available. Use the GDM login screen
to return to GNOME. No default login session is changed by these files.
