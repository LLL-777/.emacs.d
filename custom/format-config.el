;; C/C++
(use-package clang-format
  :ensure t
  :bind (("s-F" . clang-format-region)))

;; Rust
(add-hook 'rust-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'rust-format-buffer nil t)))

;; Julia
(add-hook 'julia-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'eglot-format-buffer nil t)))

;; Common Lisp
(use-package aggressive-indent
  :ensure t
  :hook (lisp-mode . aggressive-indent-mode))

(provide 'format-config)
