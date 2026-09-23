;; -*- lexical-binding: t; -*-

(defun my/c-cpp-eglot-ensure ()
  "Start Eglot only for C and C++, excluding derived languages like MQL5."
  (when (memq major-mode '(c-mode c++-mode))
    (eglot-ensure)))

;; Remove the old unguarded hooks as well when reloading this configuration.
(remove-hook 'c-mode-hook #'eglot-ensure)
(remove-hook 'c++-mode-hook #'eglot-ensure)
(add-hook 'c-mode-hook #'my/c-cpp-eglot-ensure)
(add-hook 'c++-mode-hook #'my/c-cpp-eglot-ensure)

;; MQL5 associations and editing rules live in mql5-config.el.
(setq auto-mode-alist
      (delete '("\\.mq5\\'" . c++-mode)
              (delete '("\\.mqh\\'" . c++-mode) auto-mode-alist)))

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
