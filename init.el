;; -*- lexical-binding: t; -*-

(add-to-list 'load-path (expand-file-name "custom" user-emacs-directory))
(setq custom-file (expand-file-name "custom/custom-settings.el"
                                    user-emacs-directory))

(require 'use-package)
(require 'base-config)
(require 'extensions-config)

(use-package nyan-mode
  :ensure t
  :init
  (nyan-mode)
  :config
  (nyan-start-animation)
  (nyan-toggle-wavy-trail))

;; Keep Customize-generated data out of the hand-maintained startup file.
(load custom-file 'noerror 'nomessage)
