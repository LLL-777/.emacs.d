;;; buffer-queue-view.el --- Clickable queue section -*- lexical-binding: t; -*-

(require 'buffer-queue-core)
(require 'buffer-queue-icons)

(defvar buffer-queue-view-refresh-hook nil
  "Display hosts subscribe here to redraw their own surface.")
(defvar buffer-queue-view--timer nil)
(defvar buffer-queue-view-mode nil)

(defun buffer-queue-view-current-id ()
  "Return the selected editing buffer, preserving it during minibuffer use."
  (let ((window (if (active-minibuffer-window)
                    (minibuffer-selected-window)
                  (selected-window))))
    (if (and (window-live-p window)
             (not (window-parameter window 'window-side)))
        (window-buffer window)
      (frame-parameter nil 'buffer-queue-selected-id))))

(defun buffer-queue-view--flush ()
  "Deliver one coalesced redraw request."
  (setq buffer-queue-view--timer nil)
  (when buffer-queue-view-mode
    (run-hooks 'buffer-queue-view-refresh-hook)))

(defun buffer-queue-view-invalidate ()
  "Schedule a redraw without doing layout in process filters or buffer hooks."
  (when (and buffer-queue-view-mode (not (timerp buffer-queue-view--timer)))
    (setq buffer-queue-view--timer (run-at-time buffer-queue-render-delay nil #'buffer-queue-view--flush))))

(defun buffer-queue-view--selection (&rest _)
  "Invalidate only when the actual selected editing buffer changes."
  (let ((id (buffer-queue-view-current-id)))
    (unless (eq id (frame-parameter nil 'buffer-queue-selected-id))
      (set-frame-parameter nil 'buffer-queue-selected-id id)
      (buffer-queue-view-invalidate))))

(defun buffer-queue-view--event-frame (event)
  "Use EVENT's frame without selecting the service side window."
  (let ((window (posn-window (event-start event))))
    (when (windowp window) (select-frame (window-frame window)))))

(defun buffer-queue-view--button (entry selected)
  "Render ENTRY with a SELECTED highlight and adapter-owned actions."
  (let* ((id (buffer-queue-entry-id entry))
         (map (make-sparse-keymap))
         (review (plist-get (buffer-queue-entry-state entry) :review))
         (padding (make-string buffer-queue-item-padding ?\s))
         (glyph (buffer-queue-icon (buffer-queue-entry-kind entry) selected))
         (text (progn
                 (when (eq review 'read)
                   (add-face-text-property 0 (length glyph) 'desktop-ui-read-face nil glyph))
                 (concat padding glyph padding))))
    (define-key map [mouse-1]
                (lambda (event) (interactive "e")
                  (buffer-queue-view--event-frame event)
                  (buffer-queue-activate id)))
    (define-key map [C-mouse-1]
                (lambda (event) (interactive "e")
                  (buffer-queue-view--event-frame event)
                  (buffer-queue-dismiss id)))
    ;; Suppress down-events so clicking never first selects the side window.
    (define-key map [down-mouse-1] #'ignore)
    (define-key map [C-down-mouse-1] #'ignore)
    (when selected
      (add-face-text-property 0 (length text) 'buffer-queue-selected-face t text))
    (propertize text 'keymap map 'mouse-face 'highlight
                'buffer-queue-id id
                'help-echo (format "%s%s\n左键：打开；Ctrl+左键：关闭"
                                   (or (buffer-queue-entry-help entry)
                                       (buffer-queue-entry-label entry))
                                   (pcase review
                                     ('unread "\n待查看修改")
                                     ('viewing "\n正在查看修改")
                                     ('read "\n已浏览")
                                     (_ ""))))))

(defun buffer-queue-view-select ()
  "Select an entry, including one hidden by the display's width limit."
  (interactive)
  (let* ((index 0)
         (choices (mapcar (lambda (entry)
                            (cons (format "%d  %s" (cl-incf index)
                                          (buffer-queue-entry-label entry))
                                  (buffer-queue-entry-id entry)))
                          (buffer-queue-entries))))
    (when choices
      (buffer-queue-activate
       (cdr (assoc (completing-read "Buffer 队列：" choices nil t) choices))))))

(defun buffer-queue-view--overflow (hidden width)
  "Make an overflow button for HIDDEN entries within WIDTH columns."
  (let ((map (make-sparse-keymap)))
    (define-key map [down-mouse-1] #'ignore)
    (define-key map [mouse-1]
                (lambda (event) (interactive "e")
                  (buffer-queue-view--event-frame event)
                  (buffer-queue-view-select)))
    (propertize (truncate-string-to-width (format "+%d " hidden) width)
                'keymap map 'mouse-face 'highlight
                'help-echo (format "%d 个入口未显示；点击选择完整队列" hidden))))

(defun buffer-queue-view--columns (text)
  "Measure TEXT conservatively in host columns, including icon font metrics."
  (max (string-width text)
       (if (display-graphic-p)
           (ceiling (string-pixel-width text) (frame-char-width))
         0)))

(defun buffer-queue-view-section (width)
  "Return (TEXT . SIGNATURE) fitting WIDTH columns for a display host.
Newest entries appear on the left.  Keep the current entry visible even when
overflowing, without reordering the registry.  SIGNATURE excludes closures."
  (let* ((entries (buffer-queue-entries))
         (selected (buffer-queue-view-current-id))
         (items (mapcar (lambda (entry)
                          (cons entry (buffer-queue-view--button
                                       entry (eq selected (buffer-queue-entry-id entry)))))
                        entries))
         (total (apply #'+ (mapcar (lambda (item) (buffer-queue-view--columns (cdr item))) items)))
         (budget (if (> total width)
                     (max 0 (- width (buffer-queue-view--columns (format "+%d " (length items)))))
                   width))
         visible used)
    (setq used 0)
    (dolist (item items)
      (when (<= (+ used (buffer-queue-view--columns (cdr item))) budget)
        (push item visible)
        (cl-incf used (buffer-queue-view--columns (cdr item)))))
    (setq visible (nreverse visible))
    (when-let* ((current (cl-find selected items
                                 :key (lambda (item) (buffer-queue-entry-id (car item)))
                                 :test #'eq))
                ((not (memq current visible)))
                ((<= (buffer-queue-view--columns (cdr current)) budget)))
      (while (> (+ used (buffer-queue-view--columns (cdr current))) budget)
        (cl-decf used (buffer-queue-view--columns (cdr (car (last visible)))))
        (setq visible (butlast visible)))
      (push current visible)
      (setq visible (cl-remove-if-not (lambda (item) (memq item visible)) items)))
    (let* ((hidden (- (length items) (length visible)))
           (text (concat (when (> hidden 0) (buffer-queue-view--overflow hidden width))
                         (mapconcat #'cdr visible "")))
           (signature (list selected buffer-queue-item-padding (desktop-ui-signature)
                            (mapcar (lambda (entry)
                                      (list (buffer-queue-entry-id entry)
                                            (buffer-queue-entry-kind entry)
                                            (buffer-queue-entry-label entry)
                                            (buffer-queue-entry-help entry)
                                            (buffer-queue-entry-state entry))) entries))))
      (cons text signature))))

(define-minor-mode buffer-queue-view-mode
  "Publish queue presentation changes to display hosts."
  :global t :group 'buffer-queue
  (if buffer-queue-view-mode
      (progn
        (add-hook 'buffer-queue-change-hook #'buffer-queue-view-invalidate)
        (add-hook 'desktop-ui-change-hook #'buffer-queue-view-invalidate)
        (add-hook 'buffer-queue-settings-change-hook #'buffer-queue-view-invalidate)
        (add-hook 'post-command-hook #'buffer-queue-view--selection)
        (add-hook 'window-selection-change-functions #'buffer-queue-view--selection)
        (add-hook 'window-buffer-change-functions #'buffer-queue-view--selection)
        (buffer-queue-view-invalidate))
    (remove-hook 'buffer-queue-change-hook #'buffer-queue-view-invalidate)
    (remove-hook 'desktop-ui-change-hook #'buffer-queue-view-invalidate)
    (remove-hook 'buffer-queue-settings-change-hook #'buffer-queue-view-invalidate)
    (remove-hook 'post-command-hook #'buffer-queue-view--selection)
    (remove-hook 'window-selection-change-functions #'buffer-queue-view--selection)
    (remove-hook 'window-buffer-change-functions #'buffer-queue-view--selection)
    (when (timerp buffer-queue-view--timer) (cancel-timer buffer-queue-view--timer))
    (setq buffer-queue-view--timer nil)
    (dolist (frame (frame-list))
      (set-frame-parameter frame 'buffer-queue-selected-id nil))))

(provide 'buffer-queue-view)
;;; buffer-queue-view.el ends here
