;; -*- lexical-binding: t; -*-

(setq org-startup-indented t
      org-hide-emphasis-markers t
      org-pretty-entities t
      org-ellipsis "…"
      org-startup-folded 'overview)

(with-eval-after-load 'org
  (require 'org-tempo)
  (require 'org-gpg-inline-image))

(with-eval-after-load 'company
  (add-hook 'org-mode-hook
            (lambda ()
              (setq-local company-backends '(company-capf)))))

(use-package org-modern
  :ensure t
  :hook (org-mode . org-modern-mode))

(use-package gnuplot
  :ensure t
  :defer t)

(with-eval-after-load 'org
  ;; 保留其他已启用的 Babel 语言，并加入直接执行 gnuplot 代码块的支持。
  (add-to-list 'org-babel-load-languages '(gnuplot . t))
  (org-babel-do-load-languages
   'org-babel-load-languages
   org-babel-load-languages))

;; (use-package org-fragtog
;;   :ensure t
;;   ;; :hook (org-mode . org-fragtog-mode)
;;   :config
;;   ;; Match XeLaTeX documents (notably Chinese ones using fontspec/ctex) and
;;   ;; inherit the active theme without relying on Org's fragile `auto' lookup.
;;   (setq org-preview-latex-default-process 'xelatex)
;;   (setq org-format-latex-options
;;         (plist-put
;;          (plist-put org-format-latex-options :scale 1.8)
;;          :foreground 'default)))

(provide 'org-mode-config)
