;; -*- lexical-binding: t; -*-



(add-to-list 'load-path "~/.emacs.d/custom")

(require 'base-config)
(require 'extensions-config)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages
   '(dired-sidebar julia-repl treemacs-nerd-icons treemacs ace-window magit eglot lsp-ivy vterm projector treemacs-projectile ivy-hydra use-package-hydra company-box auctex clang-format+ dap-mode which-key rust-mode counsel ivy command-log-mode company use-package solarized-theme nyan-mode)))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
