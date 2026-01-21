;; -*- lexical-binding: t; -*-

;; julia-config
(use-package julia-mode
  :ensure t
  :init (require 'julia-repl)
  :config
  (add-hook 'julia-mode-hook 'eglot-ensure)
  (add-hook 'julia-mode-hook 'julia-repl-mode))

(add-to-list 'eglot-server-programs
             '(julia-mode . ("julia" "-e using LanguageServer, LanguageServer.SymbolServer; runserver()")))

(add-hook 'julia-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'eglot-format-buffer nil t)))

(provide 'julia-config)
