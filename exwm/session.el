;;; session.el --- EXWM session entry point -*- lexical-binding: t; -*-

;; Snap Emacs does not include the EXWM and XELB packages installed by APT.
(unless (locate-library "exwm")
  (dolist (package '("xelb" "exwm"))
    (let ((directory
           (car (last (file-expand-wildcards
                       (format "/usr/share/emacs/site-lisp/elpa/%s-*"
                               package))))))
      (unless directory
        (error "System package %s is unavailable" package))
      (add-to-list 'load-path directory))))

(require 'cl-lib)
(require 'exwm)
(require 'exwm-input)
(require 'exwm-workspace)
(require 'exwm-xim)

(add-to-list 'load-path (file-name-directory (or load-file-name buffer-file-name)))

(setq inhibit-startup-screen t)

(require 'session-input-method)
(require 'session-commands)

;; Application modules are optional; keep EXWM usable without this directory.
(let ((apps-directory
       (expand-file-name "apps" (file-name-directory
                                  (or load-file-name buffer-file-name)))))
  (when (file-directory-p apps-directory)
    (add-to-list 'load-path apps-directory)))
(require 'exwm-app-scrot nil t)

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(setq exwm-workspace-number 4
      ;; Firefox uses Emacs keys; other X applications keep their native keys.
      exwm-manage-configurations
      '(((and exwm-class-name
              (string-match-p "firefox" (downcase exwm-class-name)))
         char-mode nil
         simulation-keys (([?\C-n] . [down])
                          ([?\C-p] . [up])
                          ([?\C-f] . [right])
                          ([?\C-b] . [left])
                          ([?\C-a] . [home])
                          ([?\C-e] . [end])))
        (t char-mode t))
      exwm-input-global-keys
      `((,(kbd "<f12>") . my/exwm-open-emergency-terminal)
        (,(kbd "<XF86AudioRaiseVolume>") . my/exwm-volume-up)
        (,(kbd "<XF86AudioLowerVolume>") . my/exwm-volume-down)
        (,(kbd "<XF86AudioMute>") . my/exwm-volume-mute)
        (,(kbd "<XF86MonBrightnessUp>") . my/exwm-screen-brightness-up)
        (,(kbd "<XF86MonBrightnessDown>") . my/exwm-screen-brightness-down)
        (,(kbd "<XF86KbdBrightnessUp>") . my/exwm-keyboard-brightness-up)
        (,(kbd "<XF86KbdBrightnessDown>") . my/exwm-keyboard-brightness-down)
        (,(kbd "<XF86AudioPrev>") . my/exwm-media-previous)
        (,(kbd "<XF86AudioPlay>") . my/exwm-media-play-pause)
        (,(kbd "<XF86AudioNext>") . my/exwm-media-next)
        (,(kbd "s-SPC t") . my/exwm-open-terminal)
        (,(kbd "s-SPC T") . my/exwm-open-emergency-terminal)
        (,(kbd "s-SPC d") . my/exwm-launch)
        (,(kbd "s-SPC e") . my/exwm-open-eat)
        (,(kbd "s-SPC n") . my/exwm-open-full-emacs)
        (,(kbd "s-SPC b") . exwm-workspace-switch-to-buffer)
        (,(kbd "s-SPC r") . exwm-reset)
        (,(kbd "s-SPC w") . exwm-workspace-switch)
        (,(kbd "s-SPC m") . exwm-workspace-move-window)
        (,(kbd "s-SPC k") . exwm-input-toggle-keyboard)
        ,@(when (featurep 'exwm-app-scrot)
            exwm-app-scrot-global-keys)
        ,@(mapcar (lambda (index)
                    `(,(kbd (format "s-SPC %d" index)) .
                      (lambda ()
                        (interactive)
                        (exwm-workspace-switch-create ,index))))
                  (number-sequence 0 9))))

(add-hook 'exwm-update-class-hook
          (lambda ()
            (exwm-workspace-rename-buffer exwm-class-name)))

(keymap-unset exwm-mode-map "C-c C-m")
(cl-pushnew ?\C-\\ exwm-input-prefix-keys)
(exwm-xim-mode 1)
(require (quote exwm-systemtray))
(exwm-systemtray-mode 1)

(display-time-mode 1)
(display-battery-mode 1)

(add-hook 'exwm-init-hook
          (lambda ()
            (let ((process (start-process "nm-applet" nil "nm-applet")))
              (set-process-query-on-exit-flag process nil)))
          t)

(require 'session-touchpad)

(exwm-enable)

;;; session.el ends here
