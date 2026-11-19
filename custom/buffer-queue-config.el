;;; buffer-queue-config.el --- Load the buffer queue module -*- lexical-binding: t; -*-

;; Keep user configuration here; implementation and its documentation live
;; together in buffer-queue/.  Resolve relative to this file, not the cwd.
(add-to-list 'load-path
             (expand-file-name "buffer-queue"
                               (file-name-directory
                                (or load-file-name buffer-file-name))))
(require 'buffer-queue-runtime)

(provide 'buffer-queue-config)
;;; buffer-queue-config.el ends here
