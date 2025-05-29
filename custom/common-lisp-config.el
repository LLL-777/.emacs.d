

;; common-lisp-config

(setq inferior-lisp-program "sbcl")
(use-package sly
  :ensure t
  :init (setq inferior-lisp-program "sbcl"))

(use-package aggressive-indent
  :ensure t
  :hook (lisp-mode . aggressive-indent-mode))

(provide 'common-lisp-config)
