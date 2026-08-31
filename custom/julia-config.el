;; -*- lexical-binding: t; -*-

(defun my/julia-format-buffer-before-save ()
  "Format the current Julia buffer through Eglot before saving."
  (add-hook 'before-save-hook #'eglot-format-buffer nil t))

(defun my/julia-eglot-ensure ()
  "Initialize Julia-specific Eglot support, then ensure a server is running."
  ;; Register the project-aware server before `eglot-ensure' selects a contact.
  (eglot-jl-init)
  (eglot-ensure))

(use-package julia-mode
  :ensure t
  :mode "\\.jl\\'"
  :hook
  ((julia-mode . my/julia-eglot-ensure)
   (julia-mode . julia-repl-mode)
   (julia-mode . my/julia-format-buffer-before-save)))

(use-package julia-repl
  :ensure t
  :after julia-mode
  :commands (julia-repl julia-repl-mode))

(use-package eglot-jl
  :ensure t
  :commands eglot-jl-init)

(provide 'julia-config)
