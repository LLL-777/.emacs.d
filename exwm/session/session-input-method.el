;;; session-input-method.el --- Input method for the EXWM session -*- lexical-binding: t; -*-

(setq default-input-method "chinese-py")

;; In the fallback input method, space confirms a candidate without inserting
;; an extra space.  Change only chinese-py's translation keymap.
(with-eval-after-load "PY"
  (let ((quail-current-package (assoc "chinese-py" quail-package-alist)))
    (define-key (quail-translation-keymap) (kbd "SPC")
                #'quail-select-current)))

(when (and (locate-library "pyim")
           (locate-library "pyim-basedict"))
  (condition-case err
      (progn
        (require 'pyim)
        (require 'pyim-basedict)
        ;; Keep learned words and frequencies across sessions.  Pyim saves
        ;; these caches when Emacs exits normally.
        (setq pyim-dcache-backend 'pyim-dhashcache
              pyim-dcache-directory (locate-user-emacs-file "pyim/dcache/"))
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
