;;; buffer-queue-bar.el --- Independent Emacs buffer queue bar -*- lexical-binding: t; -*-

(require 'buffer-queue-view)
(require 'subr-x)
(defvar buffer-queue-bar-mode nil)
(defvar buffer-queue-bar--busy nil)
(defvar buffer-queue-bar--buffers (make-hash-table :test #'eq))
(defvar buffer-queue-bar-frame-predicate-functions nil
  "Predicates called with a frame before displaying its queue bar.
Every predicate must return non-nil to allow display.  After changing
this hook, call `buffer-queue-bar-refresh' to reconcile existing bars.")
(defface buffer-queue-bar-face '((t :inherit mode-line))
  "Queue bar face." :group 'buffer-queue)

(defun buffer-queue-bar--eligible-p (frame)
  "Accept splittable editor FRAMEs allowed by the display predicates."
  (and (frame-live-p frame) (not (frame-parameter frame 'parent-frame))
       (not (frame-parameter frame 'unsplittable))
       (not (eq (frame-parameter frame 'minibuffer) 'only))
       (not (frame-parameter frame 'tooltip))
       (run-hook-with-args-until-failure
        'buffer-queue-bar-frame-predicate-functions frame)))

(defun buffer-queue-bar--remove (frame buffer)
  "Remove only the queue's display resources for FRAME and BUFFER."
  (let ((buffer-queue-bar--busy t))
    (when (buffer-live-p buffer)
      (dolist (window (get-buffer-window-list buffer nil t))
        ;; A root window cannot be deleted.  Killing our buffer below lets
        ;; Emacs restore another buffer without deleting the application frame.
        (when (window-parent window) (delete-window window)))
      (kill-buffer buffer))
    (remhash frame buffer-queue-bar--buffers)))

(defun buffer-queue-bar--slot ()
  "Return the current frame's bottom slot zero."
  (cl-find-if (lambda (w) (and (eq (window-parameter w 'window-side) 'bottom)
                              (eql (window-parameter w 'window-slot) 0)))
              (window-list nil 'nomini)))

(defun buffer-queue-bar--buffer (frame)
  "Return a private display buffer for FRAME."
  (or (let ((b (gethash frame buffer-queue-bar--buffers))) (and (buffer-live-p b) b))
      (let ((b (generate-new-buffer " *Buffer Queue*")))
        (puthash frame b buffer-queue-bar--buffers)
        (with-current-buffer b
          (special-mode)
          (buffer-face-set 'buffer-queue-bar-face)
          (setq-local mode-line-format nil header-line-format nil tab-line-format nil
                      cursor-type nil truncate-lines t window-size-fixed 'height
                      display-line-numbers nil global-hl-line-mode nil
                      show-trailing-whitespace nil line-spacing 0))
        b)))

(defun buffer-queue-bar-ensure (frame)
  "Show the queue on FRAME without selecting windows or replacing popups."
  (when (and buffer-queue-bar-mode (buffer-queue-bar--eligible-p frame)
             (not buffer-queue-bar--busy))
    (with-selected-frame frame
      (let* ((buffer-queue-bar--busy t)
             (buffer (buffer-queue-bar--buffer frame))
             (slot (buffer-queue-bar--slot)))
        (when (or (not slot) (eq (window-buffer slot) buffer))
          (let* ((window-min-height 1) (window-safe-min-height 1)
                 (window (or (get-buffer-window buffer frame)
                             (display-buffer-in-side-window
                              buffer '((side . bottom) (slot . 0) (window-height . 1)
                                       (window-parameters . ((no-other-window . t)
                                                             (no-delete-other-windows . t)))))))
                 (width (window-body-width window))
                 (section (buffer-queue-view-section (max 0 (1- width))))
                 (text (car section))
                 (pixels (and (display-graphic-p frame)
                              (with-current-buffer buffer (string-pixel-width text))))
                 (signature (list width pixels (cdr section))))
            (set-window-dedicated-p window t)
            (set-window-fringes window 0 0)
            (set-window-margins window 0 0)
            (with-current-buffer buffer
              (unless (equal signature (bound-and-true-p buffer-queue-bar--signature))
                (let ((inhibit-read-only t))
                  (erase-buffer)
                  (unless (string-empty-p text)
                    (insert (propertize " " 'display
                                        (list 'space :align-to
                                              (list '- 'right
                                                    (if pixels (list pixels) (string-width text))))))
                    (insert text))
                  (setq-local buffer-queue-bar--signature signature)
                  (set-buffer-modified-p nil))))
            (let ((height (+ (max (frame-char-height frame)
                                 (cdr (window-text-pixel-size window nil nil nil nil)))
                             (window-bottom-divider-width window) 2)))
              (when (and (window-parent window)
                         (/= height (window-pixel-height window)))
                (window-preserve-size window nil nil)
                (window-resize window (- height (window-pixel-height window)) nil 'safe t)
                (window-preserve-size window nil t)))
            (set-window-start window 1)))))))

(defun buffer-queue-bar-refresh (&rest _)
  "Refresh eligible frames and remove bars from ineligible or dead frames."
  (when buffer-queue-bar-mode
    (maphash (lambda (frame buffer)
               (unless (buffer-queue-bar--eligible-p frame)
                 (buffer-queue-bar--remove frame buffer)))
             buffer-queue-bar--buffers)
    (dolist (frame (frame-list))
      (condition-case err (buffer-queue-bar-ensure frame)
        (error (message "Buffer queue layout: %s" (error-message-string err)))))))

(defun buffer-queue-bar--layout (&rest _)
  "Schedule a coalesced refresh."
  (unless buffer-queue-bar--busy (buffer-queue-view-invalidate)))

(defun buffer-queue-bar--yield (original buffer alist)
  "Release our slot before ORIGINAL displays another BUFFER using ALIST."
  (let ((buffer-queue-bar--busy t))
    (when (and buffer-queue-bar-mode
               (eq (or (alist-get 'side alist) 'bottom) 'bottom)
               (eql (or (alist-get 'slot alist) 0) 0))
      (when-let* ((ours (gethash (selected-frame) buffer-queue-bar--buffers))
                  ((not (eq (get-buffer buffer) ours)))
                  (w (get-buffer-window ours (selected-frame))))
        (when (window-parent w) (delete-window w))))
    (funcall original buffer alist)))

(define-minor-mode buffer-queue-bar-mode
  "Display an independent queue in ordinary Emacs and EXWM."
  :global t :group 'buffer-queue
  (if buffer-queue-bar-mode
      (progn
        (add-hook 'buffer-queue-view-refresh-hook #'buffer-queue-bar-refresh)
        (add-hook 'window-state-change-functions #'buffer-queue-bar--layout)
        (add-hook 'window-size-change-functions #'buffer-queue-bar--layout)
        (add-hook 'after-make-frame-functions #'buffer-queue-bar--layout)
        (unless (advice-member-p #'buffer-queue-bar--yield 'display-buffer-in-side-window)
          (advice-add 'display-buffer-in-side-window :around #'buffer-queue-bar--yield))
        (buffer-queue-bar-refresh))
    (remove-hook 'buffer-queue-view-refresh-hook #'buffer-queue-bar-refresh)
    (remove-hook 'window-state-change-functions #'buffer-queue-bar--layout)
    (remove-hook 'window-size-change-functions #'buffer-queue-bar--layout)
    (remove-hook 'after-make-frame-functions #'buffer-queue-bar--layout)
    (advice-remove 'display-buffer-in-side-window #'buffer-queue-bar--yield)
    (let ((buffer-queue-bar--busy t))
      (maphash (lambda (frame buffer)
                 (buffer-queue-bar--remove frame buffer))
               buffer-queue-bar--buffers)
      (clrhash buffer-queue-bar--buffers))))

(provide 'buffer-queue-bar)
;;; buffer-queue-bar.el ends here
