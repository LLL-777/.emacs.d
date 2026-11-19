;;; codex-edit-visibility.el --- Compatibility entry for Codex presentation -*- lexical-binding: t; -*-

;; Existing codex-config loading remains valid. Event integration and the
;; optional legacy tab renderer now have separate implementations.
(require 'codex-edit-config)
(require 'codex-edit-tabs)

(provide 'codex-edit-visibility)
;;; codex-edit-visibility.el ends here
