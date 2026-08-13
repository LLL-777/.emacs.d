;; -*- lexical-binding: t; -*-

;; Keep startup allocation cheap, then restore conservative GC settings once
;; Emacs is ready for interactive use.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6
      package-enable-at-startup t
      package-quickstart t)

(defun my/restore-gc-after-startup ()
  "Restore GC settings suitable for normal interactive use."
  (setq gc-cons-threshold (* 32 1024 1024)
        gc-cons-percentage 0.1))

(add-hook 'emacs-startup-hook #'my/restore-gc-after-startup)
