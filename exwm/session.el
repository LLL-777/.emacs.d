;;; session.el --- EXWM session entry point -*- lexical-binding: t; -*-

;; Normal startup activates package.el packages before --load runs this file.
;; Keep package activation and shared configuration in the normal init sequence.
(dolist (library '("xelb" "exwm"))
  (unless (locate-library library)
    (error "EXWM session requires %s on the normal Emacs load-path" library)))

;; Daemon startup has no X connection yet.  Preserve the former --xrm
;; setting before the first client frame opens that connection; child X
;; applications still use the EXWM XIM server through XMODIFIERS.
(when (daemonp)
  (require 'term/common-win)
  (setq x-command-line-resources
        (concat x-command-line-resources "\nemacs.useXIM: false\n")))

(require 'cl-lib)
(require 'exwm)
(require 'exwm-input)
(require 'exwm-workspace)
(require 'exwm-xim)

(let ((directory (file-name-directory (or load-file-name buffer-file-name))))
  ;; Register only explicit module directories; do not recursively load files.
  (dolist (module '("session" "services" "apps" "bottom-bar"))
    (let ((path (expand-file-name module directory)))
      (when (file-directory-p path) (add-to-list 'load-path path)))))

(require 'session-compat)
(require 'session-input-method)
(require 'session-input)
(require 'session-commands)
(require 'session-buffers)
(my/exwm-buffers-mode 1)

;; Application modules are optional; keep EXWM usable without this directory.
(require 'exwm-app-scrot nil t)

;; Optional service platform: register adapters after EXWM is ready.  Daemons
;; remain manually started; a platform failure must not abort the desktop.
(add-hook 'exwm-init-hook
          (lambda ()
            (condition-case err
                (when (require 'exwm-service-session nil t)
                  (exwm-service-session-initialize))
              (error (message "EXWM services unavailable: %s"
                              (error-message-string err))))))

;; Desktop display is optional and independent of service observation.
(add-hook 'exwm-init-hook
          (lambda ()
            (condition-case err
                (when (require 'exwm-bottom-bar nil t) (exwm-bottom-bar-mode 1))
              (error (message "EXWM bottom bar unavailable: %s"
                              (error-message-string err))))))

(setq exwm-workspace-number 4
      ;; Every X application uses the shared input policy by default.
      exwm-manage-configurations
      '((t char-mode nil))
      exwm-input-global-keys
      `((,(kbd "C-\\") . toggle-input-method)
        (,(kbd "<f12>") . my/exwm-open-emergency-terminal)
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
(my/exwm-input-enable)
(exwm-xim-mode 1)
(require (quote exwm-systemtray))
(exwm-systemtray-mode 1)

;; The desktop clock is owned by exwm-bottom-bar-clock.
(display-time-mode -1)
(display-battery-mode 1)

(add-hook 'exwm-init-hook
          (lambda ()
            (when-let* ((program (executable-find "nm-applet")))
              (let ((process (start-process "nm-applet" nil program)))
                (set-process-query-on-exit-flag process nil))))
          t)

(require 'session-touchpad)

;; Daemon startup starts this default server before a client creates the
;; first X frame.  Keep ordinary graphical startup usable as a fallback.
(require 'server)
(setq server-name "server")
(add-hook 'exwm-init-hook
          (lambda ()
            (unless (process-live-p server-process)
              (condition-case err
                  (server-start)
                (error (message "EXWM server unavailable: %s"
                                (error-message-string err)))))
            ;; Give the bridge an absolute socket path even if its subprocess
            ;; lacks XDG_RUNTIME_DIR; derive the path from this Emacs.
            (when (and (process-live-p server-process)
                       (boundp 'codex-ide-emacs-bridge-server-name))
              (setq codex-ide-emacs-bridge-server-name
                    (expand-file-name server-name server-socket-dir))))
          t)

(exwm-wm-mode 1)

;;; session.el ends here
