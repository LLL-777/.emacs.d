;;; exwm-bottom-bar.el --- Non-invasive EXWM bottom area host -*- lexical-binding: t; -*-

(require 'exwm-bottom-bar-workspaces)
(require 'exwm-bottom-bar-services)
(require 'exwm-bottom-bar-clock)
(defvar exwm-workspace--current)
(defvar exwm-systemtray-width)
(defvar exwm-systemtray-position)
(defvar exwm-bottom-bar-mode nil)
(defvar exwm-bottom-bar--frames (make-hash-table :test #'eq))
(defvar exwm-bottom-bar--timer nil)
(defvar exwm-bottom-bar--busy nil)
(defvar exwm-bottom-bar--last-error nil)

(defun exwm-bottom-bar--input-needs-space-p (left)
  "Whether input/candidates/message need the area starting at pixel LEFT.
Do not change the minibuffer's contents, keymaps, margins or resize policy."
  (or (active-minibuffer-window)
      (bound-and-true-p pyim-process--translating)
      (let ((message (current-message)))
        (and message
             (or (string-match-p "\n" message)
                 (> (string-pixel-width message) (max 0 (- left 16))))))))

(defun exwm-bottom-bar--new-frame (parent name)
  "Create an unfocusable child display of PARENT with private buffer NAME."
  (let* ((window-min-height 1) (window-safe-min-height 1)
         (buffer (generate-new-buffer name))
         (frame
          (make-frame
           (list (cons 'parent-frame parent) '(minibuffer . nil)
                 '(visibility . nil) '(min-height . 1) '(min-width . 1)
                 '(height . 1) '(width . 1) '(no-accept-focus . t) '(no-focus-on-map . t)
                 '(undecorated . t) '(skip-taskbar . t) '(no-other-frame . t)
                 '(desktop-dont-save . t) '(unsplittable . t) '(user-position . t)
                 '(menu-bar-lines . 0) '(tool-bar-lines . 0) '(tab-bar-lines . 0)
                 '(left-fringe . 0) '(right-fringe . 0)
                 '(internal-border-width . 0) '(child-frame-border-width . 0)
                 '(vertical-scroll-bars . nil) '(horizontal-scroll-bars . nil)
                 '(cursor-type . nil) '(accept-focus . nil)
                 (cons 'font (frame-parameter parent 'font))
                 (cons 'background-color (face-background 'default parent t))
                 (cons 'foreground-color (face-foreground 'default parent t))
                 (cons 'name name)))))
    (with-current-buffer buffer
      (special-mode)
      (setq-local mode-line-format nil header-line-format nil tab-line-format nil
                  display-line-numbers nil cursor-type nil truncate-lines t
                  global-hl-line-mode nil show-trailing-whitespace nil))
    (set-window-buffer (frame-root-window frame) buffer)
    (set-window-dedicated-p (frame-root-window frame) t)
    (cons frame buffer)))

(defun exwm-bottom-bar--record (parent)
  "Return display resources belonging to PARENT."
  (or (gethash parent exwm-bottom-bar--frames)
      (let ((record (list :bar (exwm-bottom-bar--new-frame parent " *EXWM bottom bar*")
                          :drawer (exwm-bottom-bar--new-frame parent " *EXWM service drawer*"))))
        (modify-frame-parameters
         (car (plist-get record :drawer))
         (list '(internal-border-width . 2)
               (cons 'background-color (face-background 'mode-line parent t))))
        (puthash parent record exwm-bottom-bar--frames)
        record)))

(defun exwm-bottom-bar--hide (record)
  "Hide every display in RECORD."
  (dolist (key '(:bar :drawer))
    (let ((frame (car (plist-get record key))))
      (when (frame-live-p frame) (make-frame-invisible frame)))))

(defun exwm-bottom-bar--destroy (record)
  "Delete RECORD's owned child frames and buffers."
  (dolist (key '(:bar :drawer))
    (let ((display (plist-get record key)))
      (when (frame-live-p (car display)) (delete-frame (car display) t))
      (when (buffer-live-p (cdr display)) (kill-buffer (cdr display))))))

(defun exwm-bottom-bar--text (display text width height x y)
  "Draw TEXT in DISPLAY at pixel geometry WIDTH HEIGHT X Y."
  (let ((frame (car display)) (buffer (cdr display)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer) (insert text) (set-buffer-modified-p nil)))
    (let ((frame-resize-pixelwise t) (window-resize-pixelwise t)
          (window-min-height 1) (window-safe-min-height 1))
      (unless (and (= width (frame-pixel-width frame)) (= height (frame-pixel-height frame)))
        (set-frame-size frame (max 1 width) (max 1 height) t)))
    (set-frame-position frame x y)
    (make-frame-visible frame)))

(defun exwm-bottom-bar-refresh (&rest _)
  "Render cached components only; never probe services or edit the echo area."
  (setq exwm-bottom-bar--timer nil)
  (when (and exwm-bottom-bar-mode (not exwm-bottom-bar--busy))
    (let ((exwm-bottom-bar--busy t))
      (condition-case err
          (let ((parent (bound-and-true-p exwm-workspace--current)))
            (maphash
             (lambda (frame record)
               (cond ((not (frame-live-p frame))
                      (exwm-bottom-bar--destroy record)
                      (remhash frame exwm-bottom-bar--frames))
                     ((not (eq parent frame)) (exwm-bottom-bar--hide record))))
             exwm-bottom-bar--frames)
            (when (and (frame-live-p parent) (display-graphic-p parent))
              (with-selected-frame parent
                (let* ((record (exwm-bottom-bar--record parent))
                       (mini (minibuffer-window parent))
                       (edges (window-pixel-edges mini))
                       (height (- (nth 3 edges) (nth 1 edges)))
                       (width (frame-pixel-width parent))
                       (workspaces (exwm-bottom-bar-workspaces-text))
                       (workspace-pixels (string-pixel-width workspaces))
                       (tray (if (eq (bound-and-true-p exwm-systemtray-position) 'bottom)
                                 (or (bound-and-true-p exwm-systemtray-width) 0) 0))
                       (left (max 0 (- (/ width 2) (/ workspace-pixels 2))))
                       (panel-width (max 1 (- width left tray 4)))
                       (right (concat (exwm-bottom-bar-services-entry-text)
                                      " " (exwm-bottom-bar-clock-text) " "))
                       (right-pixels (string-pixel-width right)))
                  (if (or (exwm-bottom-bar--input-needs-space-p left)
                          (> height (* 1.7 (frame-char-height parent)))
                          (< panel-width (+ workspace-pixels right-pixels 20)))
                      (exwm-bottom-bar--hide record)
                    (exwm-bottom-bar--text
                     (plist-get record :bar)
                     (concat workspaces
                             (propertize " " 'display
                                         (list 'space :align-to
                                               (list '- 'right (list right-pixels))))
                             right)
                     panel-width height left (nth 1 edges))
                    (if exwm-bottom-bar-services-open
                        (let* ((text (concat " " (exwm-bottom-bar-services-icons) " "))
                               (drawer-width (+ 4 (string-pixel-width text)))
                               (drawer-height (+ 4 (frame-char-height parent))))
                          (exwm-bottom-bar--text
                           (plist-get record :drawer) text drawer-width drawer-height
                           (max 0 (- width tray drawer-width 4))
                           (max 0 (- (nth 1 edges) drawer-height))))
                      (let ((drawer (car (plist-get record :drawer))))
                        (when (frame-live-p drawer) (make-frame-invisible drawer)))))))))
        (error
         (let ((text (error-message-string err)))
           (unless (equal text exwm-bottom-bar--last-error)
             (setq exwm-bottom-bar--last-error text)
             (message "EXWM bottom bar: %s" text))))))))

(defun exwm-bottom-bar-invalidate (&rest _)
  "Coalesce notifications, including echo messages and input transitions."
  (when (and exwm-bottom-bar-mode (not exwm-bottom-bar--busy)
             (not (timerp exwm-bottom-bar--timer)))
    (setq exwm-bottom-bar--timer (run-at-time 0 nil #'exwm-bottom-bar-refresh))))

(define-minor-mode exwm-bottom-bar-mode
  "Display workspaces, a service drawer and time beside the echo area."
  :global t :group 'exwm-bottom-bar
  (if exwm-bottom-bar-mode
      (progn
        (exwm-bottom-bar-workspaces-mode 1)
        (exwm-bottom-bar-services-mode 1)
        (exwm-bottom-bar-clock-mode 1)
        (dolist (hook '(exwm-bottom-bar-change-hook desktop-ui-change-hook post-command-hook
                        minibuffer-setup-hook minibuffer-exit-hook
                        window-size-change-functions after-make-frame-functions))
          (add-hook hook #'exwm-bottom-bar-invalidate))
        (unless (advice-member-p #'exwm-bottom-bar-invalidate 'message)
          (advice-add 'message :after #'exwm-bottom-bar-invalidate))
        (exwm-bottom-bar-refresh))
    (dolist (hook '(exwm-bottom-bar-change-hook desktop-ui-change-hook post-command-hook
                    minibuffer-setup-hook minibuffer-exit-hook
                    window-size-change-functions after-make-frame-functions))
      (remove-hook hook #'exwm-bottom-bar-invalidate))
    (advice-remove 'message #'exwm-bottom-bar-invalidate)
    (exwm-bottom-bar-clock-mode -1)
    (exwm-bottom-bar-services-mode -1)
    (exwm-bottom-bar-workspaces-mode -1)
    (when (timerp exwm-bottom-bar--timer) (cancel-timer exwm-bottom-bar--timer))
    (setq exwm-bottom-bar--timer nil)
    (maphash (lambda (_ record) (exwm-bottom-bar--destroy record)) exwm-bottom-bar--frames)
    (clrhash exwm-bottom-bar--frames)))

(provide 'exwm-bottom-bar)
