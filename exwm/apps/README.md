# EXWM application modules

This directory holds optional EXWM integrations for external applications.
Name each module `exwm-app-<program>.el`, provide the matching
`exwm-app-<program>` feature, and keep its commands and global key list in that
file. Application shortcuts use `Super+Space`, then `u`, then an application
letter and an action letter. Load each module optionally from `session.el` and
add its keys only when the feature loaded successfully. EXWM must still start
when an application module is absent.

## scrot

`exwm-app-scrot.el` uses these sequential keys:

- `Super+Space`, `u`, `s`, `s`: select a region and save it in
  `~/Pictures/Screenshots/`.
- `Super+Space`, `u`, `s`, `c`: select a region and copy the PNG image to the X
  clipboard. This command also requires `xclip`.

The existing terminal and EXWM control keys remain unchanged.
