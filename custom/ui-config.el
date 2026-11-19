;;; ui-config.el --- Load shared presentation settings -*- lexical-binding: t; -*-

;; Use M-x customize-group RET desktop-ui for shared faces and icon settings.
(add-to-list 'load-path
             (expand-file-name "ui" (file-name-directory (or load-file-name buffer-file-name))))
(require 'desktop-ui)

(provide 'ui-config)
