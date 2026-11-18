;;; exwm-bottom-bar-services.el --- Service drawer presentation -*- lexical-binding: t; -*-

(require 'exwm-bottom-bar-common)
(require 'exwm-service)
(defvar exwm-bottom-bar-services-open nil)
(defvar exwm-bottom-bar-services--exit nil)
(defvar exwm-workspace--current)

(defun exwm-bottom-bar-services-face (state)
  "Derive status color from STATE; stopped optional services are not errors."
  (cond ((or (eq (plist-get state :lifecycle) 'failed)
             (eq (plist-get state :health) 'unhealthy)) 'error)
        ((eq (plist-get state :health) 'degraded) 'warning)
        ((eq (plist-get state :lifecycle) 'running) 'success)
        (t 'shadow)))

(defun exwm-bottom-bar-services-close ()
  "Close the drawer and remove its temporary keymap."
  (interactive)
  (setq exwm-bottom-bar-services-open nil)
  (when exwm-bottom-bar-services--exit
    (let ((exit exwm-bottom-bar-services--exit))
      (setq exwm-bottom-bar-services--exit nil)
      (funcall exit)))
  (exwm-bottom-bar-notify))

(defun exwm-bottom-bar-services-toggle ()
  "Toggle service icons above the bottom bar."
  (interactive)
  (if exwm-bottom-bar-services-open
      (exwm-bottom-bar-services-close)
    (setq exwm-bottom-bar-services-open t)
    (let ((map (make-sparse-keymap)))
      (define-key map [escape] #'exwm-bottom-bar-services-close)
      (define-key map (kbd "ESC") #'exwm-bottom-bar-services-close)
      (define-key map (kbd "C-g") #'exwm-bottom-bar-services-close)
      (setq exwm-bottom-bar-services--exit
            (set-transient-map map
                               (lambda () exwm-bottom-bar-services-open)
                               (lambda ()
                                 (setq exwm-bottom-bar-services-open nil
                                       exwm-bottom-bar-services--exit nil)
                                 (exwm-bottom-bar-notify)))))
    (exwm-bottom-bar-notify)))

(defun exwm-bottom-bar-services-entry-text ()
  "Render the single drawer icon, with cached aggregate status in its tooltip."
  (let* ((ids (exwm-service-ids))
         (states (mapcar #'exwm-service-snapshot ids))
         (face (cond ((cl-some (lambda (s) (eq (exwm-bottom-bar-services-face s) 'error)) states) 'error)
                     ((cl-some (lambda (s) (eq (exwm-bottom-bar-services-face s) 'warning)) states) 'warning)
                     ((cl-some (lambda (s) (eq (plist-get s :lifecycle) 'running)) states) 'success)
                     (t 'shadow)))
         (text (concat " " (exwm-bottom-bar-icon 'drawer face) " ")))
    (when exwm-bottom-bar-services-open
      (add-face-text-property 0 (length text) 'highlight t text))
    (exwm-bottom-bar-button
     text
     (concat "服务抽屉：点击展开／收起\n"
             (mapconcat (lambda (id)
                          (format "%s：%s" (exwm-service-entry-name (exwm-service-get id))
                                  (plist-get (exwm-service-snapshot id) :summary))) ids "\n"))
     #'exwm-bottom-bar-services-toggle)))

(defun exwm-bottom-bar-services-icons ()
  "Render registered services only as icons; hover reveals full status."
  (mapconcat
   (lambda (id)
     (let* ((state (exwm-service-snapshot id))
            (kind (if (eq id 'network)
                      (pcase (plist-get state :connection)
                        ('wired 'wired) ('wireless 'wireless)
                        ('virtual 'service) (_ 'network))
                    id)))
       (exwm-bottom-bar-button
        (concat " " (exwm-bottom-bar-icon kind (exwm-bottom-bar-services-face state)) " ")
        (format "%s\n%s\n点击打开操作菜单"
                (exwm-service-entry-name (exwm-service-get id)) (plist-get state :summary))
        (lambda ()
          (exwm-bottom-bar-services-close)
          (when (frame-live-p (bound-and-true-p exwm-workspace--current))
            (select-frame-set-input-focus exwm-workspace--current))
          (exwm-service-menu id)))))
   (exwm-service-ids) ""))

(define-minor-mode exwm-bottom-bar-services-mode
  "Subscribe to service snapshots; this view never probes services."
  :global t :group 'exwm-bottom-bar
  (if exwm-bottom-bar-services-mode
      (add-hook 'exwm-service-change-hook #'exwm-bottom-bar-notify)
    (remove-hook 'exwm-service-change-hook #'exwm-bottom-bar-notify)
    (exwm-bottom-bar-services-close)))

(provide 'exwm-bottom-bar-services)
