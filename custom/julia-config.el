;; -*- lexical-binding: t; -*-


;; julia-config
(use-package julia-mode
  :ensure t
  :after julia-repl
  :config
  (add-hook 'julia-mode-hook 'eglot-ensure)
  (add-hook 'julia-mode-hook 'julia-repl-mode))

(use-package julia-repl
  :ensure t
  :config
  (julia-repl-set-terminal-backend 'mistty))

(add-to-list 'eglot-server-programs
              '(julia-mode . ("julia"
 			     "--startup-file=no"
 			     "--history-file=no"
 			     "-e"
 			     "using LanguageServer; using SymbolServer;
                              server = LanguageServer.LanguageServerInstance(stdin, stdout);
                              server.runlinter = true; 
                              LanguageServer.run(server)")))

(add-hook 'julia-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'eglot-format-buffer nil t)))

(provide 'julia-config)
