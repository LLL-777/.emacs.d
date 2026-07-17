;; -*- lexical-binding: t; -*-
(setq dired-omit-files
      (rx (or (seq bol (? ".") "#")
	      (seq bol ".")
	      (seq bol "." eol)
              (seq bol ".." eol)
              )))

(use-package nerd-icons
  :ensure t)

(use-package nerd-icons-dired
  :ensure t
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package dired
  :ensure nil
  :commands (dired dired-jump)
  :custom
  (dired-listing-switches "-alh --group-directories-first")
  (dired-recursive-copies 'always)
  (dired-recursive-deletes 'top)
  (delete-by-moving-to-trash t)
  (dired-dwim-target t)
  :bind
  (:map dired-mode-map
        ("RET" . dired-find-alternate-file)
        ("^"   . (lambda ()
                   (interactive)
                   (find-alternate-file ".."))))
  :config (add-hook 'dired-mode-hook #'dired-omit-mode))

(provide 'dired-config)
