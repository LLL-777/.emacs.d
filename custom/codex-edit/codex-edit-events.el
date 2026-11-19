;;; codex-edit-events.el --- Codex file events and presentation protocol -*- lexical-binding: t; -*-

;; This is the sole upstream Codex integration boundary.  Presentation providers
;; neither advise each other nor inspect the event source's internal state.
(require 'cl-lib)
(require 'subr-x)

(defgroup codex-edit nil "Codex file change integration." :group 'tools)
(defvar codex-ide-session-baseline-prompt "")
(defvar codex-ide-session-event-hook nil)
(declare-function codex-ide-session-directory "codex-ide" (session))
(declare-function codex-ide--file-change-diff-text "codex-ide" (item))
(declare-function codex-ide-mcp-bridge--file-buffer-response "codex-ide-mcp-bridge" (buffer &optional extra))

(defvar codex-edit--backends nil)
(defvar codex-edit--items (make-hash-table :test #'eq))
(defvar codex-edit--tasks nil)
(defvar codex-edit--timer nil)
(defvar codex-edit--delivering nil)
(defvar codex-edit-events-mode nil)

(defun codex-edit-backend ()
  "Return the active provider's name, or nil."
  (caar codex-edit--backends))

(defun codex-edit--call (operation &rest args)
  "Call the active provider's OPERATION with ARGS, if implemented."
  (when-let* ((function (plist-get (cdar codex-edit--backends) operation)))
    (apply function args)))

(defun codex-edit--cancel ()
  "Cancel queued delivery before switching providers or stopping the source."
  (when (timerp codex-edit--timer) (cancel-timer codex-edit--timer))
  (setq codex-edit--timer nil codex-edit--tasks nil)
  (codex-edit--call :cancel))

(defun codex-edit--without-prompt (prompt)
  "Remove only our managed instruction blocks from PROMPT."
  (let ((start-marker "<codex-edit-visibility>")
        (end-marker "</codex-edit-visibility>"))
    (while-let ((start (string-match (regexp-quote start-marker) prompt))
                (end (string-match (regexp-quote end-marker) prompt start)))
      (setq prompt (concat (substring prompt 0 start)
                           (substring prompt (+ end (length end-marker))))))
    (string-trim-right prompt)))

(defun codex-edit-update-prompt ()
  "Apply the active provider's instructions without altering other text."
  (setq codex-ide-session-baseline-prompt
        (concat (codex-edit--without-prompt codex-ide-session-baseline-prompt)
                (or (plist-get (cdar codex-edit--backends) :prompt) ""))))

(defun codex-edit-register-backend (name properties &optional fallback)
  "Register presentation provider NAME with PROPERTIES.
Required :prepare accepts (PATH LINE COLUMN) and returns a buffer.
Required :refresh accepts (PATH RANGES). Optional :preview accepts a slice
response, :start accepts SESSION, :complete accepts (SESSION TURN-ID), and
:cancel accepts no arguments; :ready-at returns a presentation deadline.
:response is extra MCP response metadata,
:prompt is managed instruction text, and :interval is a scheduling delay
or a symbol naming its setting. FALLBACK providers run only without overrides.
Repeated registration replaces NAME without accumulating handlers."
  (unless (and (symbolp name) (functionp (plist-get properties :prepare))
               (functionp (plist-get properties :refresh)))
    (error "Codex provider requires a name, :prepare and :refresh"))
  (let* ((entry (cons name properties))
         (others (assq-delete-all name (copy-sequence codex-edit--backends)))
         (backends (if fallback (append others (list entry)) (cons entry others))))
    (unless (equal (car backends) (car codex-edit--backends))
      (codex-edit--cancel))
    (setq codex-edit--backends backends))
  (codex-edit-update-prompt))

(defun codex-edit-unregister-backend (name)
  "Remove NAME and restore the remaining provider without pending UI actions."
  (when (assq name codex-edit--backends)
    (when (eq name (codex-edit-backend)) (codex-edit--cancel))
    (setq codex-edit--backends (assq-delete-all name codex-edit--backends))
    (codex-edit-update-prompt)))

(defun codex-edit-prepare-file (path &optional line column)
  "Prepare PATH through the selected provider; refuse unsaved buffer conflicts."
  (unless (and (stringp path) (not (string-empty-p path)))
    (error "Missing file path"))
  (setq path (expand-file-name path))
  (when-let* ((buffer (find-buffer-visiting path))
              ((buffer-modified-p buffer)))
    (user-error "Codex edit blocked; buffer has unsaved changes: %s" path))
  (unless (codex-edit-backend) (user-error "No Codex file presentation provider"))
  (codex-edit--call :prepare path line column))

(defun codex-edit-refresh-file (path ranges)
  "Deliver completed changes for PATH and inclusive line RANGES."
  (codex-edit--call :refresh path ranges))

(defun codex-edit--bridge (params)
  "Adapt upstream MCP PARAMS to the public file preparation request."
  (let ((buffer (codex-edit-prepare-file
                 (alist-get 'path params) (alist-get 'line params)
                 (alist-get 'column params))))
    (codex-ide-mcp-bridge--file-buffer-response
     buffer (let ((response (plist-get (cdar codex-edit--backends) :response)))
              (if (functionp response) (funcall response buffer) response)))))

(defun codex-edit--preview (original params)
  "Publish a successful slice response after ORIGINAL validates PARAMS."
  (let ((result (funcall original params)))
    (codex-edit--call :preview result)
    result))

(defun codex-edit--run-next ()
  "Deliver the next event outside process filters and honor provider delays."
  (setq codex-edit--timer nil)
  (let ((ready (codex-edit--call :ready-at)))
    (if (and ready (> ready (float-time)))
        (setq codex-edit--timer
              (run-at-time (- ready (float-time)) nil #'codex-edit--run-next))
      (codex-edit--deliver-next))))

(defun codex-edit--deliver-next ()
  "Deliver a ready task and schedule the remaining work."
  (when-let* ((task (pop codex-edit--tasks)))
    (let* ((codex-edit--delivering t)
           (result (condition-case err (apply (car task) (cdr task))
                     (error (message "Codex file event: %s" (error-message-string err)) nil))))
      (when codex-edit--tasks
        (let* ((setting (plist-get (cdar codex-edit--backends) :interval))
               (interval (if (symbolp setting) (and setting (symbol-value setting)) setting))
               (delay (if (eq (car-safe result) :delay) (cdr result) 0)))
          (setq codex-edit--timer
                (run-at-time (max (or interval 0) delay) nil #'codex-edit--run-next)))))))

(defun codex-edit--enqueue (function &rest args)
  "Queue FUNCTION with ARGS for serial, cancellable delivery."
  (setq codex-edit--tasks (nconc codex-edit--tasks (list (cons function args))))
  (unless (or codex-edit--delivering (timerp codex-edit--timer))
    (setq codex-edit--timer (run-at-time 0 nil #'codex-edit--run-next))))

(defun codex-edit--strip-diff-path (path)
  "Return a project-relative path from a unified-diff PATH."
  (when (stringp path)
    (setq path (car (split-string path "\t")))
    (setq path (string-trim path))
    (unless (string= path "/dev/null")
      (if (string-match-p (rx string-start (or "a/" "b/")) path)
          (substring path 2)
        path))))

(defun codex-edit--diff-paths (diff)
  "Return file paths mentioned by unified DIFF."
  (let (paths)
    (when (stringp diff)
      (dolist (line (split-string diff "\n"))
        (when (string-match (rx line-start "+++" (+ space) (group (+ nonl)))
                            line)
          (when-let* ((path (codex-edit--strip-diff-path
                             (match-string 1 line))))
            (push path paths)))
        (when (and (string-match (rx line-start "---" (+ space) (group (+ nonl)))
                                 line)
                   (string-match-p (rx "+++" (+ space) "/dev/null") diff))
          (when-let* ((path (codex-edit--strip-diff-path
                             (match-string 1 line))))
            (push path paths)))))
    (delete-dups (nreverse paths))))

(defun codex-edit--item-paths (item diff)
  "Return paths described by file-change ITEM and normalized DIFF."
  (let (paths)
    (dolist (change (or (alist-get 'changes item) '()))
      (let ((path (alist-get 'path change)))
        (when (and (stringp path) (not (string= path "patch")))
          (push path paths))))
    (nconc (nreverse paths) (codex-edit--diff-paths diff))))

(defun codex-edit--absolute-paths (paths directory)
  "Resolve PATHS against DIRECTORY and discard pseudo paths."
  (delete-dups
   (delq nil
         (mapcar
          (lambda (path)
            (when (and (stringp path)
                       (not (member path '("patch" "/dev/null"))))
              (expand-file-name path directory)))
          paths))))

(defun codex-edit--diff-ranges (diff directory)
  "Return an alist mapping DIFF files to exact added new-line ranges.

Each range is a one-based inclusive (START . END) pair.  A deletion-only hunk
uses its closest surviving line so the completed deletion remains visible."
  (let (result current-path old-path in-hunk new-line run-start
               hunk-anchor hunk-added hunk-deleted)
    (cl-labels
        ((record-range
          (start end)
          (when current-path
            (let* ((file (expand-file-name current-path directory))
                   (entry (assoc file result))
                   (range (cons (max 1 start) (max 1 end))))
              (if entry
                  (setcdr entry (append (cdr entry) (list range)))
                (push (list file range) result)))))
         (finish-run
          ()
          (when run-start
            (record-range run-start (1- new-line))
            (setq run-start nil)))
         (finish-hunk
          ()
          (finish-run)
          (when (and in-hunk hunk-deleted (not hunk-added))
            (record-range hunk-anchor hunk-anchor))
          (setq in-hunk nil)))
      (dolist (line (split-string (or diff "") "\n"))
        (cond
         ((string-match (rx line-start "---" (+ space) (group (+ nonl))) line)
          (finish-hunk)
          (setq old-path
                (codex-edit--strip-diff-path (match-string 1 line))))
         ((string-match (rx line-start "+++" (+ space) (group (+ nonl))) line)
          (finish-hunk)
          (setq current-path
                (or (codex-edit--strip-diff-path (match-string 1 line))
                    old-path)))
         ((and current-path
               (string-match
                (rx line-start "@@" (+ space)
                    "-" (+ digit) (? "," (+ digit)) (+ space)
                    "+" (group (+ digit)) (? "," (+ digit)) (+ space)
                    "@@")
                line))
          (finish-hunk)
          (setq in-hunk t
                new-line (string-to-number (match-string 1 line))
                hunk-anchor (max 1 new-line)
                hunk-added nil
                hunk-deleted nil
                run-start nil))
         ((and in-hunk (string-prefix-p "+" line))
          (unless run-start
            (setq run-start new-line))
          (setq hunk-added t
                new-line (1+ new-line)))
         ((and in-hunk (string-prefix-p "-" line))
          (finish-run)
          (setq hunk-deleted t))
         ((and in-hunk (string-prefix-p " " line))
          (finish-run)
          (setq new-line (1+ new-line)))
         ((and in-hunk (not (string-prefix-p "\\" line)))
          (finish-hunk))))
      (finish-hunk))
    (nreverse result)))


(defun codex-edit--state (session item-id)
  "Return state for SESSION's ITEM-ID."
  (when-let* ((table (gethash session codex-edit--items)))
    (gethash item-id table)))

(defun codex-edit--put-state (session item-id state)
  "Save STATE for SESSION's ITEM-ID."
  (unless (gethash session codex-edit--items)
    (puthash session (make-hash-table :test #'equal) codex-edit--items))
  (puthash item-id state (gethash session codex-edit--items)))

(defun codex-edit--begin (session item)
  "Translate an upstream started ITEM into preparation requests."
  (let* ((diff (codex-ide--file-change-diff-text item))
         (paths (codex-edit--absolute-paths
                 (codex-edit--item-paths item diff) (codex-ide-session-directory session))))
    (when-let* ((id (alist-get 'id item)))
      (codex-edit--put-state session id (list :paths paths :diff (or diff ""))))
    ;; Mandatory MCP preparation remains the reliable pre-write snapshot.
    ;; Started notifications are a best-effort fallback outside process filters.
    (dolist (path paths)
      (codex-edit--enqueue #'codex-edit-prepare-file path 1 1))))

(defun codex-edit--complete (session item)
  "Normalize a completed upstream ITEM and release its accumulated delta."
  (let* ((id (alist-get 'id item))
         (state (and id (codex-edit--state session id)))
         (directory (codex-ide-session-directory session))
         (item-diff (codex-ide--file-change-diff-text item))
         (diff (if (and (stringp item-diff) (not (string-empty-p item-diff)))
                   item-diff (or (plist-get state :diff) "")))
         (paths (delete-dups
                 (append (plist-get state :paths)
                         (codex-edit--absolute-paths (codex-edit--item-paths item diff) directory))))
         (ranges (codex-edit--diff-ranges diff directory)))
    (dolist (path paths)
      (codex-edit--enqueue #'codex-edit-refresh-file path (cdr (assoc path ranges))))
    (when-let* ((table (gethash session codex-edit--items))) (remhash id table))))

(defun codex-edit--notification (original session message)
  "Translate upstream notifications while preserving ORIGINAL's result."
  (let* ((method (alist-get 'method message))
         (params (alist-get 'params message))
         (item (alist-get 'item params)))
    (pcase method
      ("turn/started"
       (remhash session codex-edit--items)
       (codex-edit--call :start session))
      ("item/started"
       (when (equal (alist-get 'type item) "fileChange") (codex-edit--begin session item)))
      ("item/fileChange/outputDelta"
       (when-let* ((id (alist-get 'itemId params)) (delta (alist-get 'delta params))
                   ((stringp delta)))
         (let ((state (codex-edit--state session id)))
           (codex-edit--put-state
            session id (plist-put state :diff (concat (plist-get state :diff) delta)))))))
    (prog1 (funcall original session message)
      (when (and (equal method "item/completed")
                 (equal (alist-get 'type item) "fileChange"))
        (codex-edit--complete session item)))))

(defun codex-edit--session-event (event session payload)
  "Translate upstream turn completion and session teardown."
  (pcase event
    ('turn-completed
     (when-let* ((id (plist-get payload :turn-id)))
       (codex-edit--enqueue #'codex-edit--call :complete session id))
     (remhash session codex-edit--items))
    ((or 'destroyed 'reset 'thread-deleted) (remhash session codex-edit--items))))

(define-minor-mode codex-edit-events-mode
  "Connect upstream Codex notifications and MCP requests to the event protocol."
  :global t :group 'codex-edit
  (let ((bindings '((codex-ide-mcp-bridge--tool-call--show_file_buffer :override codex-edit--bridge)
                    (codex-ide--handle-notification :around codex-edit--notification)
                    (codex-ide-mcp-bridge--tool-call--get_buffer_slice :around codex-edit--preview))))
    (if codex-edit-events-mode
        (progn
          (dolist (binding bindings)
            (unless (advice-member-p (nth 2 binding) (car binding))
              (advice-add (car binding) (nth 1 binding) (nth 2 binding))))
          (add-hook 'codex-ide-session-event-hook #'codex-edit--session-event)
          (codex-edit-update-prompt))
      (dolist (binding bindings) (advice-remove (car binding) (nth 2 binding)))
      (remove-hook 'codex-ide-session-event-hook #'codex-edit--session-event)
      (codex-edit--cancel)
      (clrhash codex-edit--items)
      (setq codex-ide-session-baseline-prompt
            (codex-edit--without-prompt codex-ide-session-baseline-prompt)))))

(provide 'codex-edit-events)
