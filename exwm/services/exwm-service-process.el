;;; exwm-service-process.el --- Owned user processes -*- lexical-binding: t; -*-

(require 'exwm-service)

(cl-defstruct (exwm-service-process (:constructor exwm-service-process-create))
  id command probe log process stopping failed)

(defun exwm-service-process--ready-p (observation)
  "Whether probe OBSERVATION reports readiness."
  (or (eq observation t) (and (listp observation) (plist-get observation :ready))))

(defun exwm-service-process--present-p (observation)
  "Whether OBSERVATION detects an existing endpoint, even if unhealthy."
  (or (exwm-service-process--ready-p observation)
      (and (listp observation) (plist-get observation :present))))

(defun exwm-service-process--state (backend lifecycle health summary &optional external)
  "Construct BACKEND's snapshot from LIFECYCLE, HEALTH and SUMMARY."
  (list :lifecycle lifecycle :health health :summary summary
        :ownership (cond ((process-live-p (exwm-service-process-process backend))
                          'managed) (external 'external) (t 'none))))

(defun exwm-service-process--publish (backend lifecycle health summary)
  "Publish BACKEND's state if it remains registered."
  (when (gethash (exwm-service-process-id backend) exwm-service--registry)
    (exwm-service-publish
     (exwm-service-process-id backend)
     (exwm-service-process--state backend lifecycle health summary))))

(defun exwm-service-process-status (backend done)
  "Probe BACKEND asynchronously and call DONE with an actual snapshot."
  (funcall
   (exwm-service-process-probe backend)
   (lambda (ready)
     (let* ((present (exwm-service-process--present-p ready))
            (problem (and (listp ready) (plist-get ready :message)))
            (ready (exwm-service-process--ready-p ready))
            (live (process-live-p (exwm-service-process-process backend)))
            (state
             (exwm-service-process--state
              backend
              (cond (live 'running) (present 'running)
                    ((exwm-service-process-failed backend) 'failed) (t 'stopped))
              (cond (ready 'healthy) ((or live present) 'unhealthy) (t 'unknown))
              (cond (ready (if live "Ready" "External instance"))
                    (problem problem)
                    (live "Process alive; readiness probe failed")
                    (t (or (exwm-service-process-failed backend) "Not running")))
              (and present (not live)))))
       (funcall done (list :outcome 'success :state state
                           :message (plist-get state :summary)))))))

(defun exwm-service-process-start (backend done)
  "Start BACKEND only if no instance answers its probe; call DONE when ready."
  (let (cancel-probe retry finished)
    (cl-labels
        ((finish (result)
           (unless finished (setq finished t) (funcall done result)))
         (check ()
           (unless finished
             (setq cancel-probe
                   (funcall
                    (exwm-service-process-probe backend)
                    (lambda (ready)
                      (unless finished
                        (cond
                         ((not (process-live-p (exwm-service-process-process backend)))
                          (finish (list :outcome 'error :message "Process exited before ready")))
                         ((exwm-service-process--ready-p ready)
                          (finish
                           (list :outcome 'success :message "Ready"
                                 :state (exwm-service-process--state
                                         backend 'running 'healthy "Ready"))))
                         (t (setq retry (run-at-time 0.4 nil #'check))))))))))
         (launch ()
           (let* ((command (funcall (exwm-service-process-command backend)))
                  (default-directory (expand-file-name "~/"))
                  (process-connection-type nil)
                  (proc
                   (make-process
                    :name (format "exwm-service-%s" (exwm-service-process-id backend))
                    :buffer (get-buffer-create (exwm-service-process-log backend))
                    :command command :noquery nil :connection-type 'pipe
                    :sentinel
                    (lambda (process _event)
                      (when (and (eq process (exwm-service-process-process backend))
                                 (memq (process-status process) '(exit signal)))
                        (let ((expected (exwm-service-process-stopping backend)))
                          (setf (exwm-service-process-failed backend)
                                (unless expected
                                  (format "Exited (%s)" (process-exit-status process))))
                          (exwm-service-process--publish
                           backend (if expected 'stopped 'failed) 'unknown
                           (if expected "Stopped" (exwm-service-process-failed backend)))))))))
             (setf (exwm-service-process-process backend) proc
                   (exwm-service-process-stopping backend) nil
                   (exwm-service-process-failed backend) nil)
             (exwm-service-process--publish backend 'starting 'unknown "Waiting for readiness")
             (check))))
      (setq cancel-probe
            (funcall
             (exwm-service-process-probe backend)
             (lambda (ready)
               (unless finished
                 (condition-case err
                     (cond
                      ((exwm-service-process--ready-p ready)
                       (finish
                        (list :outcome 'success :message "Already running"
                              :state (exwm-service-process--state
                                      backend 'running 'healthy "Already running" t))))
                      ((exwm-service-process--present-p ready)
                       (finish
                        (list :outcome 'error :message (or (plist-get ready :message)
                                                          "An existing endpoint is not ready")
                              :state (exwm-service-process--state
                                      backend 'running 'unhealthy "Existing endpoint not ready" t))))
                      ((process-live-p (exwm-service-process-process backend)) (check))
                      (t (launch)))
                   (error (finish (list :outcome 'error
                                         :message (error-message-string err)))))))))
      (lambda ()
        (setq finished t)
        (when cancel-probe (funcall cancel-probe))
        (when (timerp retry) (cancel-timer retry))
        ;; A timeout does not silently terminate a possibly useful service.
        ;; Retain ownership and display that readiness was not established.
        (when (process-live-p (exwm-service-process-process backend))
          (exwm-service-process--publish backend 'running 'unhealthy
                                         "Start cancelled or timed out; process still managed"))))))

(defun exwm-service-process-stop (backend done)
  "Gracefully terminate only BACKEND's owned process, then call DONE."
  (let ((proc (exwm-service-process-process backend)) timer finished)
    (if (not (process-live-p proc))
        (exwm-service-process-status
         backend
         (lambda (result)
           (if (eq (plist-get (plist-get result :state) :ownership) 'external)
               (funcall done '(:outcome error :message "External process: stop it in its original owner"))
             (funcall done result))))
      (setf (exwm-service-process-stopping backend) t)
      (exwm-service-process--publish backend 'stopping 'unknown "Stopping")
      (signal-process proc 'SIGTERM)
      (setq timer
            (run-at-time
             0.1 0.1
             (lambda ()
               (when (and (not finished) (not (process-live-p proc)))
                 (setq finished t)
                 (cancel-timer timer)
                 (setf (exwm-service-process-failed backend) nil)
                 (funcall done
                          (list :outcome 'success :message "Stopped"
                                :state (exwm-service-process--state
                                        backend 'stopped 'unknown "Stopped")))))))
      (lambda ()
        (setq finished t)
        (when (timerp timer) (cancel-timer timer))
        (exwm-service-process--publish
         backend (if (process-live-p proc) 'running 'stopped) 'unknown
         "Stop cancelled or timed out; query status")))))

(defun exwm-service-process-restart (backend done)
  "Stop then start BACKEND, preserving cancellation across both stages."
  (let (cancel next-timer cancelled)
    (setq cancel
          (exwm-service-process-stop
           backend
           (lambda (result)
             (unless cancelled
               (if (eq (plist-get result :outcome) 'success)
                   ;; Defer: stop can complete synchronously.
                   (setq next-timer
                         (run-at-time
                          0 nil (lambda ()
                                  (unless cancelled
                                    (setq cancel (exwm-service-process-start backend done))))))
                 (funcall done result))))))
    (lambda ()
      (setq cancelled t)
      (when (timerp next-timer) (cancel-timer next-timer))
      (when cancel (funcall cancel)))))

(defun exwm-service-process-handlers (backend)
  "Return standard protocol handlers for process BACKEND."
  (list
   (cons 'status (lambda (_request done) (exwm-service-process-status backend done)))
   (cons 'start (lambda (_request done) (exwm-service-process-start backend done)))
   (cons 'stop (lambda (_request done) (exwm-service-process-stop backend done)))
   (cons 'restart (lambda (_request done) (exwm-service-process-restart backend done)))
   (cons 'logs (lambda (_request done)
                 (pop-to-buffer (get-buffer-create (exwm-service-process-log backend)))
                 (funcall done '(:outcome success)) nil))))

(provide 'exwm-service-process)
;;; exwm-service-process.el ends here
