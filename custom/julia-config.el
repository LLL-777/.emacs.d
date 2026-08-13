;; -*- lexical-binding: t; -*-

(defun my/julia-format-buffer-before-save ()
  "Format the current Julia buffer through Eglot before saving."
  (add-hook 'before-save-hook #'eglot-format-buffer nil t))

(use-package julia-mode
  :ensure t
  :mode "\\.jl\\'"
  :hook
  ((julia-mode . eglot-ensure)
   (julia-mode . julia-repl-mode)
   (julia-mode . my/julia-format-buffer-before-save)))

(use-package julia-repl
  :ensure t
  :after julia-mode
  :commands (julia-repl julia-repl-mode))

(with-eval-after-load 'eglot
  (add-to-list
   'eglot-server-programs
   '(julia-mode . ("julia"
                   "--startup-file=no"
                   "--history-file=no"
                   "-e"
                   "using LanguageServer; using SymbolServer;
                    server = LanguageServer.LanguageServerInstance(stdin, stdout);
                    server.runlinter = true;
                    LanguageServer.run(server)"))))

(provide 'julia-config)
