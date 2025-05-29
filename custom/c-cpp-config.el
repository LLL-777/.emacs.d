(require 'eglot)
(add-hook 'c-mode-hook 'eglot-ensure)
(add-hook 'c++-mode-hook 'eglot-ensure)

(add-to-list 'eglot-server-programs
	     '((c++-mode c-mode) . ("clangd")))

(use-package cmake-mode
  :ensure t
  :init (cmake-mode))

(use-package clang-format
  :ensure t
  :bind (("s-F" . clang-format-region)))

(provide 'c-cpp-config)
