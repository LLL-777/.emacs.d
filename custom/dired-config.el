;; -*- lexical-binding: t; -*-

(defun my/dired-setup ()
  "Use a compact listing while keeping file details one key away."
  (dired-hide-details-mode 1)
  (dired-omit-mode 1)
  (display-line-numbers-mode -1))

(use-package dired
  :ensure nil
  :demand t
  :custom
  (dired-listing-switches "-alh")
  (dired-recursive-copies 'always)
  (dired-recursive-deletes 'top)
  (delete-by-moving-to-trash t)
  (dired-dwim-target t)
  (dired-kill-when-opening-new-dired-buffer t)
  :hook (dired-mode . my/dired-setup)
  :config
  (require 'dired-x)
  ;; Show dotfiles; omit only backup and generated files by default.
  (setq dired-omit-extensions '("~" ".elc" ".pyc")))

(use-package nerd-icons-dired
  :ensure t
  :hook (dired-mode . nerd-icons-dired-mode))

(provide 'dired-config)
