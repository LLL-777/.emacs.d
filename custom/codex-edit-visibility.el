;; -*- lexical-binding: t; -*-

;;; Commentary:

;; Present Codex file edits as a visible, sequential workflow.  Each target
;; file gets its own tab, completed hunks pulse in place, and the turn ends on
;; a dedicated combined-diff tab.  All writes remain owned by Codex; this
;; module only keeps clean Emacs buffers synchronized with the files on disk.

;;; Code:

(require 'cl-lib)
(require 'pulse)
(require 'seq)
(require 'subr-x)
(require 'tab-bar)

(defgroup my/codex-edit-visibility nil
  "Visible presentation of Codex file edits."
  :group 'codex-ide)

(defcustom my/codex-edit-presentation-interval 0.8
  "Seconds to show each completed file before advancing the queue."
  :type 'number
  :group 'my/codex-edit-visibility)

(defface my/codex-edit-pulse-face
  '((t :inherit highlight :extend t))
  "Face used to pulse lines changed by Codex."
  :group 'my/codex-edit-visibility)

(defconst my/codex-edit-visibility-prompt
  "
- Visible file editing is mandatory.  Edit files sequentially, one file per patch.
- Before changing or creating a file, call emacs_show_file_buffer with its absolute path and the first planned edit line.
- Wait for that call to succeed before writing.  If it reports an unsaved-buffer conflict, do not edit the file.
- After each file write, allow Emacs to refresh and pulse the changed lines before proceeding to the next file.
- Do not combine multiple files in one apply_patch call unless a tool unavoidably changes them together."
  "Instructions appended to the Codex session baseline prompt.")

(defvar my/codex-edit--tabs (make-hash-table :test #'equal)
  "Map absolute file names to their Codex editing tab names.")

(defvar my/codex-edit--session-items (make-hash-table :test #'eq)
  "Map Codex sessions to per-file-change state tables.")

(defvar my/codex-edit--presentation-queue nil
  "FIFO queue of zero-argument presentation functions.")

(defvar my/codex-edit--presentation-timer nil
  "Timer currently advancing `my/codex-edit--presentation-queue'.")

(defvar my/codex-edit--overview-tab nil
  "Name of the combined-diff tab for the current Codex turn.")

(defun my/codex-edit--tab-names ()
  "Return names of tabs on the selected frame."
  (delq nil (mapcar (lambda (tab) (alist-get 'name tab))
                    (tab-bar-tabs))))

(defun my/codex-edit--unique-tab-name (base)
  "Return a tab name based on BASE that is unused on the selected frame."
  (let ((names (my/codex-edit--tab-names))
        (candidate base)
        (index 2))
    (while (member candidate names)
      (setq candidate (format "%s <%d>" base index)
            index (1+ index)))
    candidate))

(defun my/codex-edit--live-tab-p (name)
  "Return non-nil when a tab named NAME exists on the selected frame."
  (and (stringp name)
       (member name (my/codex-edit--tab-names))))

(defun my/codex-edit--goto (line column)
  "Move point to one-based LINE and COLUMN, then center it visibly."
  (widen)
  (goto-char (point-min))
  (when (and (integerp line) (> line 0))
    (forward-line (1- line)))
  (when (and (integerp column) (> column 0))
    (move-to-column (1- column)))
  (set-window-point (selected-window) (point))
  (recenter))

(defun my/codex-edit-show-file (path &optional line column)
  "Show PATH in its selected Codex tab at LINE and COLUMN.

Create the visiting buffer and tab when needed.  Refuse to proceed when the
buffer contains unsaved user edits, since refreshing it after an external
Codex write would otherwise discard those edits."
  (let* ((file (expand-file-name path))
         (buffer (find-file-noselect file))
         (known-tab (gethash file my/codex-edit--tabs)))
    (when (buffer-modified-p buffer)
      (user-error "Codex edit blocked; buffer has unsaved changes: %s" file))
    (tab-bar-mode 1)
    (if (my/codex-edit--live-tab-p known-tab)
        (tab-bar-switch-to-tab known-tab)
      (let ((tab-name
             (my/codex-edit--unique-tab-name
              (format "Codex: %s" (file-name-nondirectory file)))))
        (tab-bar-new-tab)
        (delete-other-windows)
        (switch-to-buffer buffer)
        (tab-bar-rename-tab tab-name)
        (puthash file tab-name my/codex-edit--tabs)))
    (unless (eq (current-buffer) buffer)
      (switch-to-buffer buffer))
    (delete-other-windows)
    (my/codex-edit--goto line column)
    buffer))

(defun my/codex-edit--bridge-show-file-buffer (params)
  "Display the file described by MCP bridge PARAMS in a selected tab."
  (let ((path (alist-get 'path params))
        (line (alist-get 'line params))
        (column (alist-get 'column params)))
    (unless (and (stringp path) (not (string-empty-p path)))
      (error "Missing file path"))
    (let ((buffer (my/codex-edit-show-file path line column)))
      (codex-ide-mcp-bridge--file-buffer-response
       buffer
       `((window-id . ,(format "%s" (selected-window)))
         (tab . ,(gethash (expand-file-name path)
                          my/codex-edit--tabs)))))))

(defun my/codex-edit--session-item-table (session)
  "Return the file-change state table for SESSION, creating it if needed."
  (or (gethash session my/codex-edit--session-items)
      (let ((table (make-hash-table :test #'equal)))
        (puthash session table my/codex-edit--session-items)
        table)))

(defun my/codex-edit--item-state (session item-id)
  "Return SESSION state for file-change ITEM-ID."
  (gethash item-id (my/codex-edit--session-item-table session)))

(defun my/codex-edit--put-item-state (session item-id state)
  "Store STATE for SESSION file-change ITEM-ID."
  (puthash item-id state (my/codex-edit--session-item-table session)))

(defun my/codex-edit--reset-turn (session)
  "Reset transient edit presentation state for SESSION's new turn."
  (remhash session my/codex-edit--session-items)
  (clrhash my/codex-edit--tabs)
  (setq my/codex-edit--overview-tab nil))

(defun my/codex-edit--strip-diff-path (path)
  "Return a project-relative path from a unified-diff PATH."
  (when (stringp path)
    (setq path (car (split-string path "\t")))
    (setq path (string-trim path))
    (unless (string= path "/dev/null")
      (if (string-match-p (rx string-start (or "a/" "b/")) path)
          (substring path 2)
        path))))

(defun my/codex-edit--diff-paths (diff)
  "Return file paths mentioned by unified DIFF."
  (let (paths)
    (when (stringp diff)
      (dolist (line (split-string diff "\n"))
        (when (string-match (rx line-start "+++" (+ space) (group (+ nonl)))
                            line)
          (when-let* ((path (my/codex-edit--strip-diff-path
                             (match-string 1 line))))
            (push path paths)))
        (when (and (string-match (rx line-start "---" (+ space) (group (+ nonl)))
                                 line)
                   (string-match-p (rx "+++" (+ space) "/dev/null") diff))
          (when-let* ((path (my/codex-edit--strip-diff-path
                             (match-string 1 line))))
            (push path paths)))))
    (delete-dups (nreverse paths))))

(defun my/codex-edit--item-paths (item diff)
  "Return paths described by file-change ITEM and normalized DIFF."
  (let (paths)
    (dolist (change (or (alist-get 'changes item) '()))
      (let ((path (alist-get 'path change)))
        (when (and (stringp path) (not (string= path "patch")))
          (push path paths))))
    (nconc (nreverse paths) (my/codex-edit--diff-paths diff))))

(defun my/codex-edit--absolute-paths (paths directory)
  "Resolve PATHS against DIRECTORY and discard pseudo paths."
  (delete-dups
   (delq nil
         (mapcar
          (lambda (path)
            (when (and (stringp path)
                       (not (member path '("patch" "/dev/null"))))
              (expand-file-name path directory)))
          paths))))

(defun my/codex-edit--diff-ranges (diff directory)
  "Return an alist mapping DIFF files to changed new-line ranges.

Each range is a cons cell (START . END), using one-based inclusive lines.
Deletion-only hunks point at the closest surviving line."
  (let (result current-path old-path)
    (dolist (line (split-string (or diff "") "\n"))
      (cond
       ((string-match (rx line-start "---" (+ space) (group (+ nonl))) line)
        (setq old-path (my/codex-edit--strip-diff-path (match-string 1 line))))
       ((string-match (rx line-start "+++" (+ space) (group (+ nonl))) line)
        (setq current-path
              (or (my/codex-edit--strip-diff-path (match-string 1 line))
                  old-path)))
       ((and current-path
             (string-match
              (rx line-start "@@" (+ space)
                  "-" (+ digit) (? "," (+ digit)) (+ space)
                  "+" (group (+ digit)) (? "," (group (+ digit))) (+ space)
                  "@@")
              line))
        (let* ((start (string-to-number (match-string 1 line)))
               (count (if (match-string 2 line)
                          (string-to-number (match-string 2 line))
                        1))
               (end (+ start (max 1 count) -1))
               (file (expand-file-name current-path directory))
               (entry (assoc file result)))
          (if entry
              (setcdr entry (append (cdr entry) (list (cons start end))))
            (push (list file (cons start end)) result))))))
    (nreverse result)))

(defun my/codex-edit--line-region (start end)
  "Return buffer positions covering inclusive line range START through END."
  (save-excursion
    (goto-char (point-min))
    (forward-line (max 0 (1- start)))
    (let ((beg (point)))
      (forward-line (max 1 (1+ (- end start))))
      (cons beg (max beg (point))))))

(defun my/codex-edit--refresh-and-pulse (path ranges)
  "Refresh PATH, select its tab, and pulse changed line RANGES."
  (let ((buffer (find-buffer-visiting path)))
    (when (and buffer (buffer-modified-p buffer))
      (message "Codex refresh blocked; buffer has unsaved changes: %s" path)
      (user-error "Unsaved buffer conflict: %s" path))
    (if (file-exists-p path)
        (progn
          (setq buffer (or buffer (find-file-noselect path)))
          (with-current-buffer buffer
            ;; Codex writes the disk file externally; reverting makes the
            ;; visible buffer clean without pretending Emacs performed a save.
            (revert-buffer :ignore-auto :noconfirm :preserve-modes))
          (my/codex-edit-show-file
           path
           (or (caar ranges) 1)
           1)
          (dolist (range (or ranges '((1 . 1))))
            (pcase-let ((`(,beg . ,end)
                         (my/codex-edit--line-region (car range) (cdr range))))
              (pulse-momentary-highlight-region
               beg end 'my/codex-edit-pulse-face))))
      ;; Keep the pre-delete contents visible and read-only; the final diff tab
      ;; is the authoritative presentation of what was removed.
      (when buffer
        (my/codex-edit-show-file path (or (caar ranges) 1) 1)
        (message "Codex deleted file: %s" path)))))

(defun my/codex-edit--run-next-presentation ()
  "Run the next queued presentation action."
  (setq my/codex-edit--presentation-timer nil)
  (when-let* ((action (pop my/codex-edit--presentation-queue)))
    (condition-case err
        (funcall action)
      (error (message "Codex edit presentation failed: %s"
                      (error-message-string err))))
    (when my/codex-edit--presentation-queue
      (setq my/codex-edit--presentation-timer
            (run-at-time my/codex-edit-presentation-interval nil
                         #'my/codex-edit--run-next-presentation)))))

(defun my/codex-edit--enqueue-presentation (action)
  "Append zero-argument ACTION to the presentation queue."
  (setq my/codex-edit--presentation-queue
        (append my/codex-edit--presentation-queue (list action)))
  (unless (timerp my/codex-edit--presentation-timer)
    (setq my/codex-edit--presentation-timer
          (run-at-time 0 nil #'my/codex-edit--run-next-presentation))))

(defun my/codex-edit--begin-file-change (session item)
  "Record and visibly prepare a file-change ITEM for SESSION."
  (let* ((item-id (alist-get 'id item))
         (directory (codex-ide-session-directory session))
         (diff (codex-ide--file-change-diff-text item))
         (paths (my/codex-edit--absolute-paths
                 (my/codex-edit--item-paths item diff)
                 directory)))
    (when item-id
      (my/codex-edit--put-item-state
       session item-id (list :paths paths :diff (or diff ""))))
    ;; This is a fallback for edits that did not make the mandatory MCP call.
    ;; Window changes are deferred out of the process filter.
    (dolist (path paths)
      (run-at-time 0 nil
                   (lambda (file)
                     (condition-case err
                         (my/codex-edit-show-file file 1 1)
                       (error (message "Codex edit display failed: %s"
                                       (error-message-string err)))))
                   path))))

(defun my/codex-edit--append-file-change-delta (session item-id delta)
  "Append file-change DELTA to SESSION's ITEM-ID state."
  (when (and item-id (stringp delta))
    (let ((state (or (my/codex-edit--item-state session item-id) '())))
      (setq state
            (plist-put state :diff
                       (concat (or (plist-get state :diff) "") delta)))
      (my/codex-edit--put-item-state session item-id state))))

(defun my/codex-edit--complete-file-change (session item)
  "Queue refresh and pulse actions for completed file-change ITEM."
  (let* ((item-id (alist-get 'id item))
         (state (and item-id (my/codex-edit--item-state session item-id)))
         (directory (codex-ide-session-directory session))
         (item-diff (codex-ide--file-change-diff-text item))
         (diff (if (and (stringp item-diff)
                        (not (string-empty-p item-diff)))
                   item-diff
                 (or (plist-get state :diff) "")))
         (paths (delete-dups
                 (append (plist-get state :paths)
                         (my/codex-edit--absolute-paths
                          (my/codex-edit--item-paths item diff)
                          directory))))
         (ranges (my/codex-edit--diff-ranges diff directory)))
    (dolist (path paths)
      (let ((file path)
            (file-ranges (cdr (assoc path ranges))))
        (my/codex-edit--enqueue-presentation
         (lambda ()
           (my/codex-edit--refresh-and-pulse file file-ranges)))))))

(defun my/codex-edit--notification-advice (original session message)
  "Track file changes around ORIGINAL handling of SESSION MESSAGE."
  (let* ((method (alist-get 'method message))
         (params (alist-get 'params message))
         (item (alist-get 'item params)))
    (when (equal method "turn/started")
      (my/codex-edit--reset-turn session))
    (when (and (equal method "item/started")
               (equal (alist-get 'type item) "fileChange"))
      (my/codex-edit--begin-file-change session item))
    (when (equal method "item/fileChange/outputDelta")
      (my/codex-edit--append-file-change-delta
       session
       (alist-get 'itemId params)
       (alist-get 'delta params)))
    (prog1 (funcall original session message)
      (when (and (equal method "item/completed")
                 (equal (alist-get 'type item) "fileChange"))
        (my/codex-edit--complete-file-change session item)))))

(defun my/codex-edit--show-overview (session turn-id)
  "Create and select a combined Diff tab for SESSION and TURN-ID."
  (when-let* ((diff-text
               (condition-case nil
                   (codex-ide-diff-data-combined-turn-diff-text session turn-id)
                 (user-error nil)))
              ((not (string-empty-p diff-text))))
    (tab-bar-mode 1)
    (if (my/codex-edit--live-tab-p my/codex-edit--overview-tab)
        (tab-bar-switch-to-tab my/codex-edit--overview-tab)
      (tab-bar-new-tab)
      (setq my/codex-edit--overview-tab
            (my/codex-edit--unique-tab-name "Codex Diff")))
    (delete-other-windows)
    (tab-bar-rename-tab my/codex-edit--overview-tab)
    (let ((buffer
           (codex-ide-diff-open-buffer
            diff-text
            (codex-ide-diff-combined-buffer-name-for-session
             (codex-ide-session-buffer session))
            (codex-ide-session-directory session)
            :select t)))
      (switch-to-buffer buffer)
      (delete-other-windows)
      (goto-char (point-min)))))

(defun my/codex-edit-handle-session-event (event session payload)
  "Handle Codex EVENT for SESSION using event PAYLOAD."
  (when (eq event 'turn-completed)
    (when-let* ((turn-id (plist-get payload :turn-id)))
      ;; Enqueuing makes the overview run strictly after all file pulses.
      (my/codex-edit--enqueue-presentation
       (lambda ()
         (my/codex-edit--show-overview session turn-id))))))

(defun my/codex-edit-visibility-install ()
  "Install the Codex visible-editing workflow."
  (unless (advice-member-p #'my/codex-edit--bridge-show-file-buffer
                           'codex-ide-mcp-bridge--tool-call--show_file_buffer)
    (advice-add 'codex-ide-mcp-bridge--tool-call--show_file_buffer
                :override #'my/codex-edit--bridge-show-file-buffer))
  (unless (advice-member-p #'my/codex-edit--notification-advice
                           'codex-ide--handle-notification)
    (advice-add 'codex-ide--handle-notification
                :around #'my/codex-edit--notification-advice))
  (add-hook 'codex-ide-session-event-hook
            #'my/codex-edit-handle-session-event)
  (unless (string-match-p
           (regexp-quote "Visible file editing is mandatory")
           (or codex-ide-session-baseline-prompt ""))
    (setq codex-ide-session-baseline-prompt
          (concat (string-trim-right
                   (or codex-ide-session-baseline-prompt ""))
                  "\n"
                  my/codex-edit-visibility-prompt))))

(provide 'codex-edit-visibility)

;;; codex-edit-visibility.el ends here
