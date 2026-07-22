;; -*- lexical-binding: t; -*-

(add-hook 'c-mode-hook #'eglot-ensure)
(add-hook 'c++-mode-hook #'eglot-ensure)

(use-package cmake-mode
  :ensure t
  :mode
  ("CMakeLists\\.txt\\'"
   "\\.cmake\\'")
  :hook (cmake-mode . eglot-ensure))

;; (use-package clang-format
;;   :ensure t
;;   :bind (("s-F" . clang-format-region)))

(provide 'c-cpp-config)
