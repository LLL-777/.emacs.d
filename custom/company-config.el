;; -*- lexical-binding: t; -*-

(use-package company
  :hook (prog-mode . company-mode)
  :custom
  (company-minimum-prefix-length 2)
  (company-tooltip-align-annotations t)
  (company-idle-delay 0.25)
  (company-show-numbers t)
  (company-selection-wrap-around t)
  (company-transformers '(company-sort-by-occurrence)))

(defun my/company-sync-box ()
  "Keep Company Box in sync with Company in the current buffer."
  (cond
   ((bound-and-true-p company-mode)
    (company-box-mode 1))
   ((bound-and-true-p company-box-mode)
    (company-box-mode -1))))

(use-package company-box
  :commands company-box-mode
  :hook (company-mode . my/company-sync-box)
  :custom
  (company-box-scrollbar nil))

(provide 'company-config)
