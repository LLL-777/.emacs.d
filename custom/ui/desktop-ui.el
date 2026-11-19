;;; desktop-ui.el --- Shared theme faces and semantic icons -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'diff-mode)
(defgroup desktop-ui nil "Shared presentation, independent of the window manager." :group 'faces)
(defvar desktop-ui-change-hook nil
  "Display subscribers invalidate cached rendering when shared settings change.")
(defvar desktop-ui--revision 0)

(defun desktop-ui-refresh (&rest _)
  "Invalidate font availability and notify active display subscribers.
Call after installing an icon font during an existing Emacs session."
  (interactive)
  (dolist (frame (frame-list)) (set-frame-parameter frame 'desktop-ui-font-cache nil))
  (cl-incf desktop-ui--revision)
  (run-hooks 'desktop-ui-change-hook))

(defun desktop-ui--set (symbol value)
  "Set shared SYMBOL to VALUE and notify displays when already loaded."
  (set-default symbol value)
  (when (featurep 'desktop-ui) (desktop-ui-refresh)))

(defcustom desktop-ui-icon-font "Symbols Nerd Font Mono"
  "Icon font family, or nil to inherit the default font.
If this family is unavailable, use the semantic text fallback."
  :type '(choice (const :tag "Default font" nil) string)
  :set #'desktop-ui--set :group 'desktop-ui)
(defcustom desktop-ui-icons
  '((codex-file . "\uf044") (file . "\uf016") (directory . "\uf07b")
    (terminal . "\uf120") (help . "\uf02d") (emoji . "\uf118")
    (codex-session . "\uf121") (codex-manager . "\uf0ae")
    (application . "\uf2d0") (buffer . "\uf15b") (diff . "\uf440")
    (warning . "\uf071") (message . "\uf05a") (codex-waiting . "\uf059")
    (codex-running . "\uf013") (drawer . "\uf1b3") (mihomo . "\uf1d8")
    (wireless . "\uf1eb") (wired . "\uf0e8") (network . "\uf1eb")
    (service . "\uf013"))
  "Semantic icon vocabulary shared by Emacs and optional desktop displays."
  :type '(alist :key-type symbol :value-type string)
  :set #'desktop-ui--set :group 'desktop-ui)
(defcustom desktop-ui-icon-fallbacks
  '((codex-file . "E") (file . "F") (directory . "D") (terminal . ">")
    (help . "?") (emoji . ":)") (codex-session . "C") (codex-manager . "L")
    (application . "A") (buffer . "B") (diff . "D") (warning . "!")
    (message . "i") (codex-waiting . "?") (codex-running . "*")
    (drawer . "#") (mihomo . "M") (wireless . "W") (wired . "N")
    (network . "N") (service . "S"))
  "Readable replacements for icons on terminals and without the icon font."
  :type '(alist :key-type symbol :value-type string)
  :set #'desktop-ui--set :group 'desktop-ui)

(defface desktop-ui-selected-face '((t :inherit highlight :weight bold :box t))
  "Selected object; inherit colors from the active Emacs theme." :group 'desktop-ui)
(defface desktop-ui-read-face '((t :inherit shadow))
  "Previously viewed content." :group 'desktop-ui)
(defface desktop-ui-added-face '((t :inherit diff-added :extend t))
  "Applied additions and replacement text." :group 'desktop-ui)
(defface desktop-ui-removed-face '((t :inherit diff-removed :extend t))
  "Deleted text, displayed without restoring it to the file." :group 'desktop-ui)

(defun desktop-ui-icon (kind &optional face)
  "Render semantic KIND with optional FACE on the selected frame.
Cache font availability per frame and font setting, never per buffer."
  (let* ((cache (frame-parameter nil 'desktop-ui-font-cache))
         (key (list desktop-ui-icon-font (frame-parameter nil 'font)
                    (display-graphic-p))))
    (unless (equal (car cache) key)
      (setq cache
            (cons key (and (display-graphic-p)
                           (or (null desktop-ui-icon-font)
                               (find-font (font-spec :family desktop-ui-icon-font))))))
      (set-frame-parameter nil 'desktop-ui-font-cache cache))
    (let* ((available (cdr cache))
           (glyph (or (alist-get kind (if available desktop-ui-icons
                                       desktop-ui-icon-fallbacks)) "?"))
           (attributes (append (when face (list :inherit face))
                               (when (and available desktop-ui-icon-font)
                                 (list :family desktop-ui-icon-font)))))
      (if attributes (propertize glyph 'face attributes) glyph))))

(defun desktop-ui-signature ()
  "Return shared settings affecting display contents, including direct setq edits."
  (list desktop-ui--revision desktop-ui-icon-font
        (copy-tree desktop-ui-icons) (copy-tree desktop-ui-icon-fallbacks)))

(add-hook 'enable-theme-functions #'desktop-ui-refresh)
(add-hook 'disable-theme-functions #'desktop-ui-refresh)
(add-hook 'after-setting-font-hook #'desktop-ui-refresh)

(provide 'desktop-ui)
