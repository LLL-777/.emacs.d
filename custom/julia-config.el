(use-package julia-mode
  :ensure t
  :init (require 'julia-repl)
  :config
  (add-hook 'julia-mode-hook 'eglot-ensure)
  (add-hook 'julia-mode-hook 'julia-repl-mode))

(provide 'julia-config)
