;; -*- lexical-binding: t; -*-

(use-package sly
  :ensure t
  :commands (sly sly-connect)
  :init
  (setq inferior-lisp-program "sbcl"))

(use-package aggressive-indent
  :ensure t
  :hook (lisp-mode . aggressive-indent-mode))

(provide 'common-lisp-config)
