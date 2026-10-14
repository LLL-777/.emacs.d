;; -*- lexical-binding: t; -*-
;;; exwm-app-scrot.el --- scrot commands for EXWM

(defgroup exwm-app-scrot nil
  "Screenshot commands for an EXWM session."
  :group 'exwm)

(defcustom exwm-app-scrot-directory "~/Pictures/Screenshots/"
  "Directory where scrot saves screenshots."
  :type 'directory
  :group 'exwm-app-scrot)

(defun exwm-app-scrot--require-program (program)
  "Return the executable path for PROGRAM, or report that it is missing."
  (or (executable-find program)
      (user-error "%s is unavailable" program)))

(defun exwm-app-scrot--start (command success-message)
  "Run COMMAND asynchronously and report SUCCESS-MESSAGE when it succeeds."
  (make-process
   :name "exwm-scrot"
   :buffer nil
   :command command
   :noquery t
   :sentinel
   (lambda (process _event)
     (when (memq (process-status process) '(exit signal))
       (if (zerop (process-exit-status process))
           (message "%s" success-message)
         (message "Screenshot failed or was canceled (status %d)"
                  (process-exit-status process)))))))

(defun exwm-app-scrot-save ()
  "Select a screen region and save it under `exwm-app-scrot-directory'."
  (interactive)
  (let* ((scrot (exwm-app-scrot--require-program "scrot"))
         (directory (file-name-as-directory
                     (expand-file-name exwm-app-scrot-directory)))
         (file (expand-file-name
                (format-time-string "screenshot-%Y%m%d-%H%M%S-%3N.png")
                directory)))
    (make-directory directory t)
    (exwm-app-scrot--start (list scrot "-s" file)
                           (format "Screenshot saved to %s" file))))

(defun exwm-app-scrot-copy ()
  "Select a screen region and copy its PNG image to the X clipboard."
  (interactive)
  (let* ((scrot (exwm-app-scrot--require-program "scrot"))
         (xclip (exwm-app-scrot--require-program "xclip"))
         (output (generate-new-buffer " *exwm-scrot-png*")))
    (with-current-buffer output
      (set-buffer-multibyte nil))
    (make-process
     :name "exwm-scrot-copy"
     :buffer output
     :command (list scrot "-s" "-")
     :connection-type 'pipe
     :coding 'binary
     :noquery t
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (unwind-protect
             (if (zerop (process-exit-status process))
                 (let ((clipboard
                        (make-process
                         :name "exwm-scrot-clipboard"
                         :buffer nil
                         :command (list xclip "-quiet" "-selection"
                                        "clipboard" "-target" "image/png")
                         :connection-type 'pipe
                         :coding 'binary
                         :noquery t)))
                   (with-current-buffer output
                     (process-send-region clipboard (point-min) (point-max)))
                   (process-send-eof clipboard)
                   (message "Screenshot copied to clipboard"))
               (message "Screenshot failed or was canceled (status %d)"
                        (process-exit-status process)))
           (kill-buffer output)))))))

(defconst exwm-app-scrot-global-keys
  `((,(kbd "s-SPC u s s") . exwm-app-scrot-save)
    (,(kbd "s-SPC u s c") . exwm-app-scrot-copy))
  "EXWM global keys supplied by the scrot application module.")

(provide 'exwm-app-scrot)
;;; exwm-app-scrot.el ends here
