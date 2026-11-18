;;; session-input-method.el --- Input method for the EXWM session -*- lexical-binding: t; -*-

(require 'subr-x)

(setq default-input-method "chinese-py")

;; APT's Emacs packages are outside the Snap Emacs load path.
(dolist (package '("async" "xr" "pyim" "pyim-basedict"))
  (unless (locate-library package)
    (when-let* ((directory
                 (car (last (file-expand-wildcards
                             (format "/usr/share/emacs/site-lisp/elpa/%s-[0-9]*"
                                     package))))))
      (add-to-list 'load-path directory))))

(when (and (locate-library "pyim")
           (locate-library "pyim-basedict"))
  (condition-case err
      (progn
        (require 'pyim)
        (require 'pyim-basedict)
        (pyim-basedict-enable)
        ;; Use EXWM's bottom minibuffer for candidates in Emacs and X apps.
        (setq pyim-page-tooltip 'minibuffer)
        (setq-default pyim-punctuation-translate-p '(no yes auto))
        (set-face-attribute 'pyim-page nil
                            :background "#002b36" :foreground "#839496")
        (set-face-attribute 'pyim-page-selection nil
                            :background "#b58900" :foreground "#002b36")
        (setq default-input-method "pyim"))
    (error
     (message "EXWM pyim unavailable, keeping chinese-py: %s"
              (error-message-string err)))))

(provide 'session-input-method)
;;; session-input-method.el ends here
