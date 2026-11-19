;;; codex-edit-config.el --- Load Codex file event support -*- lexical-binding: t; -*-

(add-to-list 'load-path
             (expand-file-name "codex-edit"
                               (file-name-directory (or load-file-name buffer-file-name))))
(require 'codex-edit-events)

(provide 'codex-edit-config)
