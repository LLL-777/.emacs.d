;;; exwm-bottom-bar-clock.el --- Minute clock component -*- lexical-binding: t; -*-

(require 'exwm-bottom-bar-common)
(defvar exwm-bottom-bar-clock--timer nil)
(defun exwm-bottom-bar-clock-text ()
  "Return local time with the complete date in its tooltip."
  (propertize (format-time-string "%H:%M")
              'help-echo (format-time-string "%Y-%m-%d %A %Z")))
(define-minor-mode exwm-bottom-bar-clock-mode
  "Refresh at minute boundaries without a per-second clock timer."
  :global t :group 'exwm-bottom-bar
  (when (timerp exwm-bottom-bar-clock--timer) (cancel-timer exwm-bottom-bar-clock--timer))
  (setq exwm-bottom-bar-clock--timer
        (when exwm-bottom-bar-clock-mode
          (run-at-time (- 60 (mod (float-time) 60)) 60 #'exwm-bottom-bar-notify))))
(provide 'exwm-bottom-bar-clock)
