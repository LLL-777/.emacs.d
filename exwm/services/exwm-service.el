;; -*- lexical-binding: t; -*-
;;; exwm-service.el --- EXWM service protocol and dispatcher

;;; Commentary:
;; Protocol version 1 is documented in services/README.md.  This library has
;; no EXWM, privilege, process or init-system dependency.  Adapters implement
;; asynchronous handlers; views consume snapshots and change notifications.

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)

(defgroup exwm-service nil "EXWM services." :group 'external)
(defcustom exwm-service-timeout 20
  "Default operation timeout in seconds, excluding queue and user input waits."
  :type 'number)
(defvar exwm-service-change-hook nil
  "Functions called with service ID and a copied state snapshot.")
(defvar exwm-service--registry (make-hash-table :test #'eq))
(defvar exwm-service--sequence 0)

(cl-defstruct (exwm-service-entry (:constructor exwm-service--entry))
  id name backend key handlers actions state active queue cleanup)
(cl-defstruct (exwm-service-request (:constructor exwm-service--request))
  id service operation arguments callback timer cancel done)

(defun exwm-service--safe (function &rest arguments)
  "Call FUNCTION with ARGUMENTS, isolating callback failures."
  (condition-case err (apply function arguments)
    (error (message "EXWM service callback: %s" (error-message-string err)))))

(defun exwm-service-get (id)
  "Return registered service ID, or signal an error."
  (or (gethash id exwm-service--registry)
      (user-error "Unknown service: %s" id)))

(defun exwm-service-ids ()
  "Return registered service identifiers in stable order."
  (sort (hash-table-keys exwm-service--registry)
        (lambda (a b) (string-lessp (symbol-name a) (symbol-name b)))))

(defun exwm-service-snapshot (id)
  "Return an independent copy of service ID's last observed state."
  (copy-tree (exwm-service-entry-state (exwm-service-get id))))

(defun exwm-service-publish (id state)
  "Validate and publish STATE for ID.  STATE is a complete snapshot."
  (unless (and (proper-list-p state)
               (memq (plist-get state :lifecycle)
                    '(unknown unavailable stopped starting running stopping failed))
               (memq (plist-get state :health) '(unknown healthy degraded unhealthy))
               (memq (plist-get state :ownership) '(none managed external))
               (or (null (plist-get state :summary))
                   (stringp (plist-get state :summary))))
    (error "Invalid service snapshot: %S" state))
  (let ((entry (exwm-service-get id)))
    (setf (exwm-service-entry-state entry)
          (plist-put (copy-tree state) :updated-at (float-time)))
    (dolist (listener exwm-service-change-hook)
      (exwm-service--safe listener id (exwm-service-snapshot id)))))

(cl-defun exwm-service-register (&key (version 1) id name backend key handlers
                                     actions subscribe)
  "Register a protocol VERSION service and return ID.
HANDLERS maps operation symbols to (REQUEST DONE) functions.  DONE accepts a
result plist.  A handler returns nil or a cancellation function.  ACTIONS maps
menu labels to operation symbols.  SUBSCRIBE takes ID and returns cleanup."
  (unless (and (eql version 1) id (symbolp id) (stringp name)
               backend (symbolp backend) (listp handlers)
               (or (null key) (and (stringp key) (string-match-p "\\`[a-z]\\'" key)
                                   (not (member key '("l" "s")))))
               (cl-every (lambda (pair)
                           (and (symbolp (car pair)) (functionp (cdr pair))))
                         handlers)
               (assq 'status handlers)
               (cl-every (lambda (pair) (assq (cdr pair) handlers)) actions))
    (error "Invalid service descriptor: %s" id))
  (when (gethash id exwm-service--registry)
    (error "Service already registered: %s" id))
  (when (and key (cl-some (lambda (other)
                            (equal key (exwm-service-entry-key (exwm-service-get other))))
                          (exwm-service-ids)))
    (error "Service key already registered: %s" key))
  (let ((entry (exwm-service--entry
                :id id :name name :backend backend :key key :handlers handlers
                :actions actions :state '(:lifecycle unknown :health unknown
                                         :ownership none :summary "Not queried"))))
    (puthash id entry exwm-service--registry)
    (condition-case err
        (when subscribe
          (setf (exwm-service-entry-cleanup entry) (funcall subscribe id)))
      (error (remhash id exwm-service--registry) (signal (car err) (cdr err))))
    (exwm-service-publish id (exwm-service-entry-state entry)))
  id)

(defun exwm-service-delete (id)
  "Unregister ID without deleting files or stopping a running service.
Refuse pending work or a managed service that is not known to be stopped."
  (interactive (list (exwm-service-read)))
  (let* ((entry (exwm-service-get id)) (state (exwm-service-snapshot id)))
    (when (or (exwm-service-entry-active entry) (exwm-service-entry-queue entry)
              (and (eq (plist-get state :ownership) 'managed)
                   (not (memq (plist-get state :lifecycle) '(stopped failed)))))
      (user-error "Stop the managed service and finish pending work first"))
    (when (exwm-service-entry-cleanup entry)
      (funcall (exwm-service-entry-cleanup entry)))
    (remhash id exwm-service--registry)
    (dolist (listener exwm-service-change-hook)
      (exwm-service--safe listener id nil))))

(defun exwm-service--finish (entry request result)
  "Complete REQUEST once and advance ENTRY's queue."
  (unless (exwm-service-request-done request)
    (setf (exwm-service-request-done request) t)
    (when (timerp (exwm-service-request-timer request))
      (cancel-timer (exwm-service-request-timer request)))
    (unless (and (proper-list-p result)
                 (memq (plist-get result :outcome)
                       '(success error cancelled timeout unsupported)))
      (setq result '(:outcome error :message "Invalid adapter result")))
    (when-let* ((state (plist-get result :state)))
      (condition-case err
          (exwm-service-publish (exwm-service-entry-id entry) state)
        (error (setq result (list :outcome 'error
                                  :message (error-message-string err))))))
    (when (eq request (exwm-service-entry-active entry))
      (setf (exwm-service-entry-active entry) nil))
    (when (exwm-service-request-callback request)
      (exwm-service--safe (exwm-service-request-callback request)
                          (append (list :request-id (exwm-service-request-id request)
                                        :service (exwm-service-entry-id entry))
                                  result)))
    ;; Defer to avoid recursive completion of synchronous adapters.
    (run-at-time 0 nil #'exwm-service--advance entry)))

(defun exwm-service--abort (entry request outcome)
  "Cancel active REQUEST in ENTRY, returning OUTCOME."
  (unless (exwm-service-request-done request)
    ;; Mark first: cancellation may trigger a late process sentinel.
    (setf (exwm-service-request-done request) t)
    (when (exwm-service-request-cancel request)
      (exwm-service--safe (exwm-service-request-cancel request)))
    (setf (exwm-service-request-done request) nil)
    (exwm-service--finish entry request
                          (list :outcome outcome :message (symbol-name outcome)))))

(defun exwm-service-cancel (request)
  "Cancel queued or active REQUEST.  Return no false success on cancellation."
  (let ((entry (exwm-service-get (exwm-service-request-service request))))
    (setf (exwm-service-entry-queue entry)
          (delq request (exwm-service-entry-queue entry)))
    (exwm-service--abort entry request 'cancelled)))

(defun exwm-service-read-input (request reader &rest arguments)
  "Call READER with ARGUMENTS without charging REQUEST for user input time.
Resume the remaining timeout on return or quit.  Nested input waits are safe;
an operation cancelled while reading must not acquire another timeout."
  (when (exwm-service-request-done request)
    (user-error "Service request has already finished"))
  (let* ((timer (exwm-service-request-timer request))
         (remaining (when (timerp timer)
                      (max 0.001 (- (float-time (timer--time timer)) (float-time))))))
    (when remaining
      (cancel-timer timer)
      (setf (exwm-service-request-timer request) nil))
    (unwind-protect
        (apply reader arguments)
      (when (and remaining (not (exwm-service-request-done request)))
        (setf (exwm-service-request-timer request)
              (run-at-time remaining nil #'exwm-service--abort
                           (exwm-service-get (exwm-service-request-service request))
                           request 'timeout))))))

(defun exwm-service--advance (entry)
  "Start ENTRY's next queued request, if still registered and idle."
  (when (and (eq entry (gethash (exwm-service-entry-id entry) exwm-service--registry))
             (not (exwm-service-entry-active entry))
             (exwm-service-entry-queue entry))
    (let* ((request (pop (exwm-service-entry-queue entry)))
           (handler (alist-get (exwm-service-request-operation request)
                               (exwm-service-entry-handlers entry)))
           (done (lambda (result) (exwm-service--finish entry request result))))
      (setf (exwm-service-entry-active entry) request
            (exwm-service-request-timer request)
            (run-at-time exwm-service-timeout nil #'exwm-service--abort
                         entry request 'timeout))
      (condition-case err
          (if handler
              (setf (exwm-service-request-cancel request)
                    (funcall handler request done))
            (funcall done '(:outcome unsupported :message "Operation unsupported")))
        (quit (funcall done '(:outcome cancelled)))
        (error (funcall done (list :outcome 'error
                                   :message (error-message-string err))))))))

(defun exwm-service-call (id operation &optional arguments callback)
  "Queue OPERATION for ID with ARGUMENTS and CALLBACK; return request handle."
  (let* ((entry (exwm-service-get id))
         (request (exwm-service--request
                   :id (cl-incf exwm-service--sequence) :service id
                   :operation operation :arguments arguments :callback callback)))
    (setf (exwm-service-entry-queue entry)
          (nconc (exwm-service-entry-queue entry) (list request)))
    (exwm-service--advance entry)
    request))

(defun exwm-service-global-keys ()
  "Build EXWM bindings from registered service descriptors."
  (append
   `((,(kbd "s-SPC s l") . exwm-service-list-services)
     (,(kbd "s-SPC s s") . exwm-service-status)
     (,(kbd "s-SPC s SPC") . exwm-service-menu))
   (cl-loop for id in (exwm-service-ids)
            for entry = (exwm-service-get id)
            when (exwm-service-entry-key entry)
            append
            (cl-loop for (suffix . op) in '(("m" . menu) ("i" . status)
                                            ("u" . start) ("d" . stop)
                                            ("r" . restart) ("l" . logs))
                     when (or (eq op 'menu) (assq op (exwm-service-entry-handlers entry)))
                     collect
                     (let ((service id) (operation op))
                       (cons (kbd (format "s-SPC s %s %s" (exwm-service-entry-key entry) suffix))
                             (lambda () (interactive)
                               (if (eq operation 'menu) (exwm-service-menu service)
                                 (exwm-service-call service operation nil #'exwm-service--report)))))))))

(defun exwm-service-read ()
  "Read a registered service ID with completion."
  (intern (completing-read "Service: " (mapcar #'symbol-name (exwm-service-ids))
                          nil t)))

(defun exwm-service--report (result)
  "Report operation RESULT in the echo area."
  (message "%s: %s%s" (plist-get result :service) (plist-get result :outcome)
           (if-let* ((text (plist-get result :message))) (concat " — " text) "")))

(defun exwm-service-start (id)
  "Start service ID."
  (interactive (list (exwm-service-read)))
  (exwm-service-call id 'start nil #'exwm-service--report))
(defun exwm-service-stop (id)
  "Stop service ID using its registered backend."
  (interactive (list (exwm-service-read)))
  (exwm-service-call id 'stop nil #'exwm-service--report))
(defun exwm-service-restart (id)
  "Restart service ID using its registered backend."
  (interactive (list (exwm-service-read)))
  (exwm-service-call id 'restart nil #'exwm-service--report))
(defun exwm-service-status (id)
  "Refresh service ID's actual state."
  (interactive (list (exwm-service-read)))
  (exwm-service-call id 'status nil #'exwm-service--report))

(defun exwm-service-menu (&optional id)
  "Select an operation supported by service ID."
  (interactive)
  (let* ((id (or id (exwm-service-read))) (entry (exwm-service-get id))
         (choices (append
                   (cl-loop for op in '(status start stop restart logs)
                            when (assq op (exwm-service-entry-handlers entry))
                            collect (cons (symbol-name op) op))
                   (exwm-service-entry-actions entry)))
         (choice (completing-read (format "%s: " id) choices nil t)))
    (exwm-service-call id (cdr (assoc choice choices)) nil #'exwm-service--report)))

(defun exwm-service-refresh ()
  "Refresh idle services without accumulating background requests."
  (interactive)
  (dolist (id (exwm-service-ids))
    (let ((entry (exwm-service-get id)))
      (unless (or (exwm-service-entry-active entry) (exwm-service-entry-queue entry))
        (exwm-service-call id 'status)))))

(defun exwm-service--list-update (&rest _ignored)
  "Update the service list from cached snapshots."
  (when-let* ((buffer (get-buffer "*EXWM Services*")))
    (with-current-buffer buffer
      (setq tabulated-list-entries
            (mapcar
             (lambda (id)
               (let* ((entry (exwm-service-get id)) (state (exwm-service-snapshot id)))
                 (list id (vector (exwm-service-entry-name entry)
                                  (symbol-name (exwm-service-entry-backend entry))
                                  (symbol-name (plist-get state :lifecycle))
                                  (symbol-name (plist-get state :health))
                                  (symbol-name (plist-get state :ownership))
                                  (or (plist-get state :summary) "")))))
             (exwm-service-ids)))
      (tabulated-list-print t))))

(defvar-keymap exwm-service-list-mode-map
  :parent tabulated-list-mode-map
  "g" #'exwm-service-refresh
  "RET" (lambda () (interactive) (exwm-service-menu (tabulated-list-get-id)))
  "s" (lambda () (interactive) (exwm-service-start (or (tabulated-list-get-id)
                                                      (exwm-service-read))))
  "d" (lambda () (interactive) (exwm-service-stop (or (tabulated-list-get-id)
                                                     (exwm-service-read)))))
(define-derived-mode exwm-service-list-mode tabulated-list-mode "Services"
  "Services: RET menu, g refresh, s start, d stop."
  (setq tabulated-list-format [("Service" 16 t) ("Backend" 10 t)
                               ("State" 12 t) ("Health" 10 t)
                               ("Owner" 10 t) ("Details" 0 t)])
  (tabulated-list-init-header))

(defun exwm-service-list-services ()
  "Display all registered services and refresh their state asynchronously."
  (interactive)
  (with-current-buffer (get-buffer-create "*EXWM Services*")
    (exwm-service-list-mode)
    (exwm-service--list-update)
    (pop-to-buffer (current-buffer)))
  (exwm-service-refresh))

(add-hook 'exwm-service-change-hook #'exwm-service--list-update)
(provide 'exwm-service)
;;; exwm-service.el ends here
