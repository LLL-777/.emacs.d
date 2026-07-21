;; -*- lexical-binding: t; -*-

(use-package magit
  :ensure t
  :commands (magit-status)
  :bind
  ("C-c g" . magit-status))

(provide 'magit-config)
