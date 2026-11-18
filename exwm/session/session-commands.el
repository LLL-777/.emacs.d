;;; session-commands.el --- Commands for the EXWM session -*- lexical-binding: t; -*-

(require 'dbus)
(require 'seq)

(defun my/exwm-launch (command)
  "Run COMMAND without blocking EXWM."
  (interactive (list (read-shell-command "$ ")))
  (start-process-shell-command command nil command))

(defun my/exwm-open-terminal ()
  "Open a new vterm buffer in the EXWM host Emacs."
  (interactive)
  (unless (require 'vterm nil t)
    (user-error "Emacs vterm package is unavailable on the normal load-path"))
  (vterm t))

(defun my/exwm-open-eat ()
  "Open a new Eat buffer in the EXWM host Emacs."
  (interactive)
  (unless (require 'eat nil t)
    (user-error "Emacs Eat package is unavailable"))
  (eat nil t))

(defun my/exwm-open-emergency-terminal ()
  "Open an independent X terminal if Emacs needs repair."
  (interactive)
  (let ((terminal (or (executable-find "xterm")
                      (executable-find "x-terminal-emulator"))))
    (unless terminal
      (user-error "No emergency X terminal is available"))
    (start-process "exwm-terminal" nil terminal)))

(defun my/exwm-open-full-emacs ()
  "Open the usual configured Emacs as a separate X window."
  (interactive)
  (start-process "emacs-full" nil
                 (expand-file-name invocation-name invocation-directory)
                 "--eval" "(setq default-input-method \"chinese-py\")"))

(defun my/exwm--run-control (program &rest arguments)
  "Run PROGRAM with ARGUMENTS for a hardware control key."
  (unless (executable-find program)
    (user-error "%s is unavailable" program))
  (make-process
   :name (format "exwm-%s" program)
   :buffer nil
   :command (cons program arguments)
   :noquery t
   :sentinel (lambda (process _event)
               (when (and (memq (process-status process) '(exit signal))
                          (not (zerop (process-exit-status process))))
                 (message "%s failed (status %d)"
                          program (process-exit-status process))))))

(defun my/exwm-volume-up ()
  "Raise each output channel by five percentage points, up to 100%."
  (interactive)
  (unless (executable-find "pactl")
    (user-error "pactl is unavailable"))
  (with-temp-buffer
    (unless (eq 0 (process-file "pactl" nil t nil
                               "get-sink-volume" "@DEFAULT_SINK@"))
      (user-error "Cannot read output volume: %s" (buffer-string)))
    (goto-char (point-min))
    (let (volumes)
      ;; PulseAudio uses 65536 for 100%; 3277 is approximately 5%.
      ;; Read raw channel values to avoid locale-dependent percent rounding.
      (while (re-search-forward "\\b\\([0-9]+\\)[ \t]+/" nil t)
        (push (number-to-string
               (min 65536 (+ 3277 (string-to-number (match-string 1)))))
              volumes))
      (unless volumes
        (user-error "Cannot parse output volume: %s" (buffer-string)))
      (apply #'my/exwm--run-control "pactl" "set-sink-volume"
             "@DEFAULT_SINK@" (nreverse volumes)))))

(defun my/exwm-volume-down ()
  "Lower the default output volume by five percent."
  (interactive)
  (my/exwm--run-control "pactl" "set-sink-volume" "@DEFAULT_SINK@" "-5%"))

(defun my/exwm-volume-mute ()
  "Toggle mute on the default audio output."
  (interactive)
  (my/exwm--run-control "pactl" "set-sink-mute" "@DEFAULT_SINK@" "toggle"))

(defun my/exwm--brightness-value (path)
  "Read a numeric backlight value from PATH."
  (with-temp-buffer
    (insert-file-contents-literally path)
    (string-to-number (buffer-string))))

(defun my/exwm--adjust-brightness (subsystem device change-percent)
  "Change DEVICE in SUBSYSTEM by CHANGE-PERCENT via logind."
  (let* ((base (format "/sys/class/%s/%s/" subsystem device))
         (current (my/exwm--brightness-value (concat base "brightness")))
         (maximum (my/exwm--brightness-value (concat base "max_brightness")))
         (step (max 1 (round (* maximum (/ (abs change-percent) 100.0)))))
         (minimum (if (string= subsystem "backlight") 1 0))
         (target (max minimum
                      (min maximum
                           (+ current (if (> change-percent 0) step (- step))))))
         (session-id (getenv "XDG_SESSION_ID")))
    (unless session-id
      (user-error "No login session ID is available for brightness control"))
    (unless (= target current)
      (condition-case err
          (let ((session-path
                 (dbus-call-method
                  :system "org.freedesktop.login1"
                  "/org/freedesktop/login1"
                  "org.freedesktop.login1.Manager" "GetSession"
                  :timeout 2000 session-id)))
            (dbus-call-method
             :system "org.freedesktop.login1" session-path
             "org.freedesktop.login1.Session" "SetBrightness"
             :timeout 2000 subsystem device :uint32 target))
        (dbus-error
         (user-error "Brightness control failed: %s"
                     (error-message-string err)))))))

(defun my/exwm-screen-brightness-up ()
  "Raise the display backlight by five percent."
  (interactive)
  (my/exwm--adjust-brightness "backlight" "gmux_backlight" 5))

(defun my/exwm-screen-brightness-down ()
  "Lower the display backlight by five percent."
  (interactive)
  (my/exwm--adjust-brightness "backlight" "gmux_backlight" -5))

(defun my/exwm-keyboard-brightness-up ()
  "Raise the keyboard backlight by ten percent."
  (interactive)
  (my/exwm--adjust-brightness "leds" ":white:kbd_backlight" 10))

(defun my/exwm-keyboard-brightness-down ()
  "Lower the keyboard backlight by ten percent."
  (interactive)
  (my/exwm--adjust-brightness "leds" ":white:kbd_backlight" -10))

(defun my/exwm--media-player ()
  "Find an MPRIS player, preferring one that is playing."
  (let* ((players (seq-filter
                   (lambda (name)
                     (string-prefix-p "org.mpris.MediaPlayer2." name))
                   (dbus-list-names :session)))
         (playing (seq-find
                   (lambda (name)
                     (condition-case nil
                         (equal "Playing"
                                (dbus-get-property
                                 :session name "/org/mpris/MediaPlayer2"
                                 "org.mpris.MediaPlayer2.Player"
                                 "PlaybackStatus"))
                       (dbus-error nil)))
                   players)))
    (or playing (car players)
        (user-error "No MPRIS media player is running"))))

(defun my/exwm--media-command (method)
  "Call MPRIS player METHOD without blocking Emacs."
  (dbus-call-method-asynchronously
   :session (my/exwm--media-player) "/org/mpris/MediaPlayer2"
   "org.mpris.MediaPlayer2.Player" method nil))

(defun my/exwm-media-previous ()
  "Play the previous track."
  (interactive)
  (my/exwm--media-command "Previous"))

(defun my/exwm-media-play-pause ()
  "Toggle media playback."
  (interactive)
  (my/exwm--media-command "PlayPause"))

(defun my/exwm-media-next ()
  "Play the next track."
  (interactive)
  (my/exwm--media-command "Next"))

(provide 'session-commands)
;;; session-commands.el ends here
