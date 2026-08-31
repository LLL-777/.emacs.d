;; -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)

(defun my/codex-buffer-in-directory-p (buffer directory)
  "Return non-nil when BUFFER visits a file below DIRECTORY."
  (when (and (buffer-live-p buffer)
             (stringp directory))
    (with-current-buffer buffer
      (when buffer-file-name
        (let ((file (expand-file-name buffer-file-name))
              (root (file-name-as-directory (expand-file-name directory))))
          (or (file-in-directory-p file root)
              (ignore-errors
                (file-in-directory-p (file-truename file)
                                     (file-truename root)))))))))

(defun my/codex-dirty-file-buffers (session)
  "Return modified file buffers below SESSION's working directory."
  (let ((directory (codex-ide-session-directory session)))
    (seq-sort-by
     (lambda (buffer)
       (or (buffer-file-name buffer) ""))
     #'string-lessp
     (seq-filter
      (lambda (buffer)
        (and (my/codex-buffer-in-directory-p buffer directory)
             (buffer-modified-p buffer)))
      (buffer-list)))))

(defun my/codex-assert-project-file-buffers-clean (session)
  "Block a Codex submission when SESSION has unsaved project file buffers."
  (when-let* ((buffers (my/codex-dirty-file-buffers session))
              (directory (codex-ide-session-directory session)))
    (user-error
     "Codex submission blocked; save or revert these buffers first: %s"
     (mapconcat
      (lambda (buffer)
        (file-relative-name (buffer-file-name buffer) directory))
      buffers
      ", "))))

(defun my/codex-guard-turn-start (original session &rest args)
  "Call ORIGINAL for SESSION after checking for unsaved project files."
  (my/codex-assert-project-file-buffers-clean session)
  (apply original session args))

(defun my/codex-guard-running-prompt (original &rest args)
  "Call ORIGINAL after checking the active Codex session for dirty files."
  (let ((session (codex-ide--session-for-current-project)))
    (my/codex-assert-project-file-buffers-clean session))
  (apply original args))

(use-package codex-ide
  :vc (:url "https://github.com/dgillis/emacs-codex-ide" :rev :newest)
  :bind ("C-c c" . codex-ide-menu)
  :config
  (setq codex-ide-enable-emacs-tool-bridge t
        ;; Individual file changes stay folded in the transcript.  The hook
        ;; below opens one combined review after the whole turn completes.
        codex-ide-diff-auto-display-policy 'never)
  (require 'codex-ide-diff-data)
  (require 'codex-ide-diff-view)
  (require 'codex-edit-visibility)
  (unless (advice-member-p #'my/codex-guard-turn-start
                           'codex-ide--send-turn-start)
    (advice-add 'codex-ide--send-turn-start
                :around
                #'my/codex-guard-turn-start))
  (unless (advice-member-p #'my/codex-guard-running-prompt
                           'codex-ide--steer-prompt)
    (advice-add 'codex-ide--steer-prompt
                :around
                #'my/codex-guard-running-prompt))
  (unless (advice-member-p #'my/codex-guard-running-prompt
                           'codex-ide--queue-prompt)
    (advice-add 'codex-ide--queue-prompt
                :around
                #'my/codex-guard-running-prompt))
  (my/codex-edit-visibility-install))

(provide 'codex-config)
