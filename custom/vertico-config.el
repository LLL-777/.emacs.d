;; -*- lexical-binding: t; -*-

;; Enable Vertico.
(use-package vertico
  :ensure t
  :custom
  ;; (vertico-scroll-margin 0) ;; Different scroll margin
  ;; (vertico-count 20) ;; Show more candidates
  ;; (vertico-resize t) ;; Grow and shrink the Vertico minibuffer
  (vertico-cycle t) ;; Enable cycling for `vertico-next/previous'
  :init
  (vertico-mode))

;; Persist history over Emacs restarts. Vertico sorts by history position.
(use-package savehist
  :init
  (savehist-mode))

;; Emacs minibuffer configurations.
(use-package emacs
  :custom
  ;; Enable context menu. `vertico-multiform-mode' adds a menu in the minibuffer
  ;; to switch display modes.
  (context-menu-mode t)
  ;; Support opening new minibuffers from inside existing minibuffers.
  (enable-recursive-minibuffers t)
  ;; Hide commands in M-x which do not work in the current mode.  Vertico
  ;; commands are hidden in normal buffers. This setting is useful beyond
  ;; Vertico.
  (read-extended-command-predicate #'command-completion-default-include-p)
  ;; Do not allow the cursor in the minibuffer prompt
  (minibuffer-prompt-properties
   '(read-only t cursor-intangible t face minibuffer-prompt)))


;; Orderless: 模糊匹配风格
(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles basic partial-completion)))))

;; Consult: incremental narrowing and live previews.
(use-package consult
  :ensure t
  :init
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)
  :bind (("C-s" . consult-line)
         ("C-c s" . consult-ripgrep)
         ("C-c G" . consult-git-grep)
         ("C-x b" . consult-buffer)
         ("M-y" . consult-yank-pop)
         ([remap imenu] . consult-imenu)
         ([remap recentf-open-files] . consult-recent-file)))

;; Embark: “右键菜单”功能
(use-package embark
  :bind (("C-." . embark-act)         ;; 当前候选的动作
         ("C-;" . embark-dwim))       ;; 智能动作
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

;; 可选：在 minibuffer 下实时显示 Embark 的候选动作
(use-package embark-consult
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

(provide 'vertico-config)
