;;; exwm-bottom-bar-workspaces.el --- Workspace indicator adapter -*- lexical-binding: t; -*-

(require 'exwm-bottom-bar-common)
(defvar exwm-workspace--list)
(defvar exwm-workspace--current)
(defvar exwm--id-buffer-alist)
(declare-function exwm-workspace-switch "exwm-workspace" (frame-or-index &optional force))

(defcustom exwm-bottom-bar-workspaces-placeholder-buffers
  '("*scratch*" "*Messages*" "*Warnings*")
  "Placeholder buffers that do not make a workspace occupied."
  :type '(repeat string) :group 'exwm-bottom-bar)

(defun exwm-bottom-bar-workspaces-work-buffer-p (buffer)
  "Whether BUFFER is useful visible work rather than an internal surface."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer
         (or (derived-mode-p 'exwm-mode)
             (and (not (string-prefix-p " " (buffer-name)))
                  (not (member (buffer-name)
                               exwm-bottom-bar-workspaces-placeholder-buffers)))))))

(defun exwm-bottom-bar-workspaces-occupied-p (frame)
  "Whether FRAME contains a work buffer or any assigned EXWM application."
  (or (cl-some (lambda (pair)
                 (let ((buffer (cdr pair)))
                   (and (buffer-live-p buffer)
                        (eq frame (buffer-local-value 'exwm--frame buffer)))))
               (bound-and-true-p exwm--id-buffer-alist))
      (and (frame-live-p frame)
           (cl-some (lambda (window)
                      (and (not (window-minibuffer-p window))
                           (not (window-parameter window 'window-side))
                           (exwm-bottom-bar-workspaces-work-buffer-p
                            (window-buffer window))))
                    (window-list frame 'nomini)))))

(defun exwm-bottom-bar-workspaces-text ()
  "Build workspace buttons; selection and application occupancy are separate."
  (let ((index -1))
    (mapconcat
     (lambda (frame)
       (let* ((number (cl-incf index))
              (face (cond ((eq frame (bound-and-true-p exwm-workspace--current))
                           'exwm-bottom-bar-current-face)
                          ((exwm-bottom-bar-workspaces-occupied-p frame)
                           'exwm-bottom-bar-occupied-face)
                          (t 'shadow))))
         (exwm-bottom-bar-button
          (propertize (format "[%d]" number) 'face face)
          (format "工作区 %d：点击切换" number)
          (lambda () (when (frame-live-p frame) (exwm-workspace-switch frame))))))
     (bound-and-true-p exwm-workspace--list) "")))

(defun exwm-bottom-bar-workspaces--windows-changed (frame)
  "Report workspace window changes, excluding our child displays."
  (when (memq frame (bound-and-true-p exwm-workspace--list))
    (exwm-bottom-bar-notify)))

(defun exwm-bottom-bar-workspaces--killed ()
  "Schedule occupancy update after an EXWM buffer finishes closing."
  (when (derived-mode-p 'exwm-mode) (exwm-bottom-bar-notify)))

(define-minor-mode exwm-bottom-bar-workspaces-mode
  "Report workspace selection, creation, deletion and application changes."
  :global t :group 'exwm-bottom-bar
  (if exwm-bottom-bar-workspaces-mode
      (progn
        (add-hook 'kill-buffer-hook #'exwm-bottom-bar-workspaces--killed)
        (add-hook 'window-state-change-functions #'exwm-bottom-bar-workspaces--windows-changed)
        (unless (advice-member-p #'exwm-bottom-bar-notify 'exwm-workspace-move-window)
          (advice-add 'exwm-workspace-move-window :after #'exwm-bottom-bar-notify)))
    (remove-hook 'kill-buffer-hook #'exwm-bottom-bar-workspaces--killed)
    (remove-hook 'window-state-change-functions #'exwm-bottom-bar-workspaces--windows-changed)
    (advice-remove 'exwm-workspace-move-window #'exwm-bottom-bar-notify))
  (dolist (hook '(exwm-workspace-switch-hook exwm-workspace-list-change-hook
                  exwm-manage-finish-hook))
    (if exwm-bottom-bar-workspaces-mode
        (add-hook hook #'exwm-bottom-bar-notify)
      (remove-hook hook #'exwm-bottom-bar-notify))))

(provide 'exwm-bottom-bar-workspaces)
