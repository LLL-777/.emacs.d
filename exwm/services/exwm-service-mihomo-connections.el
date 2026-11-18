;;; exwm-service-mihomo-connections.el --- Live Mihomo connections -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)
(require 'json)
(require 'seq)
(require 'url-util)
(declare-function exwm-service-mihomo--http "exwm-service-mihomo")

(defvar-local exwm-service-mihomo-connections--timer nil)
(defvar-local exwm-service-mihomo-connections--generation 0)
(defvar-local exwm-service-mihomo-connections--requests nil)
(defvar-local exwm-service-mihomo-connections--records nil)
(defvar-local exwm-service-mihomo-connections--samples nil)
(defvar-local exwm-service-mihomo-connections--rates nil)
(defvar-local exwm-service-mihomo-connections--proxies nil)
(defvar-local exwm-service-mihomo-connections--proxy-time 0)
(defvar-local exwm-service-mihomo-connections--updated nil)
(defvar-local exwm-service-mihomo-connections--error nil)

(defun exwm-service-mihomo-connections--field (key object)
  "Return string KEY's value in the API alist OBJECT."
  (alist-get key object nil nil #'equal))

(defun exwm-service-mihomo-connections--text (value)
  "Format VALUE as a single display line."
  (if (or (null value) (equal value "")) "—"
    (replace-regexp-in-string "[\n\r\t]" " " (format "%s" value))))

(defun exwm-service-mihomo-connections--endpoint (host port)
  "Format HOST and PORT, including brackets for IPv6."
  (let ((host (exwm-service-mihomo-connections--text host)))
    (when (string-match-p ":" host) (setq host (concat "[" host "]")))
    (if (or (null port) (equal port "")) host (format "%s:%s" host port))))

(defun exwm-service-mihomo-connections--bytes (number &optional rate)
  "Format NUMBER bytes, or bytes per second when RATE is non-nil."
  (let* ((units ["B" "KiB" "MiB" "GiB" "TiB"])
         (value (and (numberp number) (max 0 (float number))))
         (index 0))
    (when value
      (while (and (>= value 1024) (< index 4))
        (setq value (/ value 1024) index (1+ index))))
    (propertize (if (null value) "—"
                  (format (if (= index 0) "%.0f %s%s" "%.1f %s%s")
                          value (aref units index) (if rate "/s" "")))
                'exwm-service-number (or number -1))))

(defun exwm-service-mihomo-connections--number-less (column a b)
  "Compare table entries A and B numerically in COLUMN."
  (< (get-text-property 0 'exwm-service-number (aref (cadr a) column))
     (get-text-property 0 'exwm-service-number (aref (cadr b) column))))

(defun exwm-service-mihomo-connections--route (connection)
  "Return (ROUTE PROTOCOL NODE CHAIN) for CONNECTION's recorded chain.
Look up the actual chain names, never a group's current selection."
  (let* ((chain (reverse (copy-sequence
                         (exwm-service-mihomo-connections--field "chains" connection))))
         protocols nodes direct unknown)
    (dolist (name chain)
      (let* ((info (cdr (assoc name exwm-service-mihomo-connections--proxies)))
             (type (exwm-service-mihomo-connections--field "type" info))
             (kind (downcase (or type ""))))
        (cond ((or (equal (upcase name) "DIRECT") (equal kind "direct"))
               (setq direct t))
              ((member kind '("selector" "urltest" "fallback" "loadbalance" "relay")))
              (t (push name nodes)
                 (if (string-empty-p kind) (setq unknown t)
                   (push type protocols))))))
    (list (cond (nodes "代理") (direct "直连") (t "未知"))
          (cond (nodes (string-join (append (delete-dups (nreverse protocols))
                                           (when unknown '("未知"))) " → "))
                (direct "DIRECT") (t "未知"))
          (if nodes (string-join (nreverse nodes) " → ") (if direct "DIRECT" "—"))
          (if chain (string-join chain " → ") "—"))))

(defun exwm-service-mihomo-connections--row (id connection)
  "Build a table entry for live CONNECTION with ID."
  (let* ((meta (exwm-service-mihomo-connections--field "metadata" connection))
         (process (exwm-service-mihomo-connections--field "process" meta))
         (path (exwm-service-mihomo-connections--field "processPath" meta))
         (host (exwm-service-mihomo-connections--field "host" meta))
         (route (exwm-service-mihomo-connections--route connection))
         (rates (gethash id exwm-service-mihomo-connections--rates)))
    (list id
          (vector
           (exwm-service-mihomo-connections--text
            (cond ((and (stringp process) (not (string-empty-p process))) process)
                  ((and (stringp path) (not (string-empty-p path))) (file-name-nondirectory path))
                  (t (exwm-service-mihomo-connections--endpoint
                      (exwm-service-mihomo-connections--field "sourceIP" meta)
                      (exwm-service-mihomo-connections--field "sourcePort" meta)))))
           (exwm-service-mihomo-connections--endpoint
            (if (and (stringp host) (not (string-empty-p host))) host
              (exwm-service-mihomo-connections--field "destinationIP" meta))
            (exwm-service-mihomo-connections--field "destinationPort" meta))
           (upcase (exwm-service-mihomo-connections--text
                    (exwm-service-mihomo-connections--field "network" meta)))
           (nth 0 route) (nth 1 route) (nth 2 route)
           (exwm-service-mihomo-connections--bytes (car rates) t)
           (exwm-service-mihomo-connections--bytes (cdr rates) t)
           (exwm-service-mihomo-connections--bytes
            (exwm-service-mihomo-connections--field "upload" connection))
           (exwm-service-mihomo-connections--bytes
            (exwm-service-mihomo-connections--field "download" connection))
           (exwm-service-mihomo-connections--text
            (exwm-service-mihomo-connections--field "rule" connection))))))

(defun exwm-service-mihomo-connections--header ()
  "Update refresh status without altering the selected window."
  (setq header-line-format
        (format " 活跃连接 %d  %s  | g 刷新  RET 详情  d 关闭连接  q 退出"
                (hash-table-count exwm-service-mihomo-connections--records)
                (cond (exwm-service-mihomo-connections--error
                       (concat "刷新失败：" exwm-service-mihomo-connections--error))
                      (exwm-service-mihomo-connections--updated
                       (concat "更新 " (format-time-string "%H:%M:%S"
                                                           exwm-service-mihomo-connections--updated)))
                      (t "正在读取…")))))

(defun exwm-service-mihomo-connections--render ()
  "Render the latest live records, preserving point by connection ID."
  (setq tabulated-list-entries nil)
  (maphash (lambda (id connection)
             (push (exwm-service-mihomo-connections--row id connection) tabulated-list-entries))
           exwm-service-mihomo-connections--records)
  (tabulated-list-print t)
  (exwm-service-mihomo-connections--header))

(defun exwm-service-mihomo-connections--apply (data now)
  "Replace live records from DATA, calculating rates at timestamp NOW."
  (unless (assoc "connections" data) (error "Invalid connections response"))
  (let ((records (make-hash-table :test #'equal))
        (samples (make-hash-table :test #'equal))
        (rates (make-hash-table :test #'equal)))
    (dolist (connection (exwm-service-mihomo-connections--field "connections" data))
      (when-let* ((id (exwm-service-mihomo-connections--field "id" connection)))
        (let* ((up (or (exwm-service-mihomo-connections--field "upload" connection) 0))
               (down (or (exwm-service-mihomo-connections--field "download" connection) 0))
               (previous (gethash id exwm-service-mihomo-connections--samples))
               (elapsed (and previous (- now (nth 2 previous)))))
          (puthash id connection records)
          (puthash id (list up down now) samples)
          (when (and elapsed (> elapsed 0))
            (puthash id (cons (when (>= up (car previous)) (/ (- up (car previous)) (float elapsed)))
                              (when (>= down (cadr previous)) (/ (- down (cadr previous)) (float elapsed))))
                     rates)))))
    ;; Replacing all three maps also discards closed connections and their samples.
    (setq exwm-service-mihomo-connections--records records
          exwm-service-mihomo-connections--samples samples
          exwm-service-mihomo-connections--rates rates
          exwm-service-mihomo-connections--updated (seconds-to-time now))
    (exwm-service-mihomo-connections--render)))

(defun exwm-service-mihomo-connections--cancel-path (path)
  "Invalidate and cancel the outstanding request for PATH."
  (when-let* ((entry (gethash path exwm-service-mihomo-connections--requests)))
    (remhash path exwm-service-mihomo-connections--requests)
    (when (cdr entry) (funcall (cdr entry)))))

(defun exwm-service-mihomo-connections--request (method path callback)
  "Run a non-overlapping request and deliver CALLBACK only to the current view."
  (unless (gethash path exwm-service-mihomo-connections--requests)
    (let ((buffer (current-buffer))
          (generation exwm-service-mihomo-connections--generation)
          (entry (cons t nil)))
      (puthash path entry exwm-service-mihomo-connections--requests)
      (condition-case err
          (setcdr entry
                  (exwm-service-mihomo--http
                   method path
                   (lambda (result)
                     (when (buffer-live-p buffer)
                       (with-current-buffer buffer
                         (when (and (= generation exwm-service-mihomo-connections--generation)
                                    (eq entry (gethash path exwm-service-mihomo-connections--requests)))
                           (remhash path exwm-service-mihomo-connections--requests)
                           (setq exwm-service-mihomo-connections--error nil)
                           (condition-case err
                               (if (eq (plist-get result :outcome) 'success)
                                   (funcall callback (plist-get result :data))
                                 (setq exwm-service-mihomo-connections--error
                                       (or (plist-get result :message) "控制接口请求失败")))
                             (error (setq exwm-service-mihomo-connections--error
                                          (error-message-string err))))
                           (exwm-service-mihomo-connections--header)))))))
        (error (remhash path exwm-service-mihomo-connections--requests)
               (setq exwm-service-mihomo-connections--error (error-message-string err))
               (exwm-service-mihomo-connections--header))))))

(defun exwm-service-mihomo-connections-refresh (&optional force-proxies)
  "Refresh live connections; with FORCE-PROXIES also refresh node types."
  (interactive (list t))
  (when (or force-proxies (> (- (float-time) exwm-service-mihomo-connections--proxy-time) 30))
    (setq exwm-service-mihomo-connections--proxy-time (float-time))
    (exwm-service-mihomo-connections--request
     "GET" "/proxies"
     (lambda (data)
       (setq exwm-service-mihomo-connections--proxies
             (exwm-service-mihomo-connections--field "proxies" data))
       (exwm-service-mihomo-connections--render))))
  (exwm-service-mihomo-connections--request
   "GET" "/connections"
   (lambda (data) (exwm-service-mihomo-connections--apply data (float-time)))))

(defun exwm-service-mihomo-connections--stop ()
  "Stop all refresh work and invalidate late callbacks."
  (cl-incf exwm-service-mihomo-connections--generation)
  (when exwm-service-mihomo-connections--timer
    (cancel-timer exwm-service-mihomo-connections--timer)
    (setq exwm-service-mihomo-connections--timer nil))
  (let (cancel)
    (when exwm-service-mihomo-connections--requests
      (maphash (lambda (_path entry) (when (cdr entry) (push (cdr entry) cancel)))
               exwm-service-mihomo-connections--requests)
      (clrhash exwm-service-mihomo-connections--requests))
    (dolist (function cancel) (funcall function))))

(defun exwm-service-mihomo-connections--tick (buffer)
  "Refresh visible BUFFER, otherwise release its timer and HTTP requests."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (if (get-buffer-window buffer t)
          (exwm-service-mihomo-connections-refresh)
        (exwm-service-mihomo-connections--stop)))))

(defun exwm-service-mihomo-connections--visibility (&rest _)
  "Start or stop polling when the connection view becomes visible or hidden."
  (when-let* ((buffer (get-buffer "*Mihomo Connections*")))
    (with-current-buffer buffer
      (when (derived-mode-p 'exwm-service-mihomo-connections-mode)
        (if (get-buffer-window buffer t)
            (unless exwm-service-mihomo-connections--timer
              (clrhash exwm-service-mihomo-connections--samples)
              (setq exwm-service-mihomo-connections--timer
                    (run-at-time 0 1 #'exwm-service-mihomo-connections--tick buffer)))
          (when exwm-service-mihomo-connections--timer
            (exwm-service-mihomo-connections--stop)))))))

(defun exwm-service-mihomo-connections--current ()
  "Return the current live connection, or report that it has gone away."
  (or (gethash (tabulated-list-get-id) exwm-service-mihomo-connections--records)
      (user-error "当前没有可操作的活跃连接")))

(defun exwm-service-mihomo-connections-detail (&optional raw)
  "Show the current connection details, or its diagnostic JSON with RAW."
  (interactive)
  (let* ((connection (exwm-service-mihomo-connections--current))
         (meta (exwm-service-mihomo-connections--field "metadata" connection))
         (route (exwm-service-mihomo-connections--route connection))
         (row (cadr (exwm-service-mihomo-connections--row "" connection)))
         (buffer (get-buffer-create "*Mihomo Connection Details*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if raw
            (progn (insert (json-encode connection)) (json-pretty-print-buffer))
          (insert "Mihomo 连接详情（打开时的快照）\n\n")
          (cl-mapc (lambda (label value) (insert (format "%s：%s\n" label value)))
                   '("程序/来源" "访问目标" "传输类型" "分流" "代理协议" "实际节点")
                   (seq-take (append row nil) 6))
          (dolist (item `(("来源地址" . ,(exwm-service-mihomo-connections--endpoint
                                         (exwm-service-mihomo-connections--field "sourceIP" meta)
                                         (exwm-service-mihomo-connections--field "sourcePort" meta)))
                          ("目标 IP" . ,(exwm-service-mihomo-connections--field "destinationIP" meta))
                          ("入站类型" . ,(exwm-service-mihomo-connections--field "type" meta))
                          ("进程路径" . ,(exwm-service-mihomo-connections--field "processPath" meta))
                          ("代理链" . ,(nth 3 route))
                          ("匹配规则" . ,(exwm-service-mihomo-connections--field "rule" connection))
                          ("规则内容" . ,(exwm-service-mihomo-connections--field "rulePayload" connection))
                          ("累计上传" . ,(aref row 8)) ("累计下载" . ,(aref row 9))
                          ("建立时间" . ,(exwm-service-mihomo-connections--field "start" connection))
                          ("连接 ID" . ,(exwm-service-mihomo-connections--field "id" connection))))
            (insert (format "%s：%s\n" (car item) (exwm-service-mihomo-connections--text (cdr item))))))
        (goto-char (point-min)) (special-mode)))
    (pop-to-buffer buffer)))

(defun exwm-service-mihomo-connections-close ()
  "Confirm and close the selected Mihomo connection."
  (interactive)
  (let* ((connection (exwm-service-mihomo-connections--current))
         (id (exwm-service-mihomo-connections--field "id" connection)))
    (when (yes-or-no-p "关闭当前连接？")
      (exwm-service-mihomo-connections--request
       "DELETE" (concat "/connections/" (url-hexify-string id))
       (lambda (_data)
         (exwm-service-mihomo-connections--cancel-path "/connections")
         (remhash id exwm-service-mihomo-connections--records)
         (remhash id exwm-service-mihomo-connections--samples)
         (remhash id exwm-service-mihomo-connections--rates)
         (exwm-service-mihomo-connections--render)
         (exwm-service-mihomo-connections-refresh))))))

(defun exwm-service-mihomo-connections-quit ()
  "Stop refreshing this connection view and quit its window."
  (interactive)
  (exwm-service-mihomo-connections--stop)
  (quit-window))

(defvar-keymap exwm-service-mihomo-connections-mode-map
  :parent tabulated-list-mode-map
  "g" #'exwm-service-mihomo-connections-refresh
  "RET" #'exwm-service-mihomo-connections-detail
  "j" (lambda () (interactive) (exwm-service-mihomo-connections-detail t))
  "d" #'exwm-service-mihomo-connections-close
  "q" #'exwm-service-mihomo-connections-quit)

(define-derived-mode exwm-service-mihomo-connections-mode tabulated-list-mode "Mihomo 连接"
  "Live Mihomo connections: g refresh, RET details, j JSON, d close, q quit."
  (setq tabulated-list-format
        (vconcat '(("程序/来源" 18 t) ("访问目标" 32 t) ("传输" 5 t)
                   ("分流" 6 t) ("代理协议" 14 t) ("实际节点" 24 t))
                 (cl-loop for (label . index) in '(("上传速度" . 6) ("下载速度" . 7)
                                                  ("累计上传" . 8) ("累计下载" . 9))
                          collect (list label 12 (apply-partially
                                                 #'exwm-service-mihomo-connections--number-less index)))
                 '(("匹配规则" 18 t)))
        tabulated-list-padding 1
        tabulated-list-sort-key '("访问目标" . nil)
        truncate-lines t)
  (dolist (variable '(exwm-service-mihomo-connections--requests
                      exwm-service-mihomo-connections--records
                      exwm-service-mihomo-connections--samples
                      exwm-service-mihomo-connections--rates))
    (set variable (make-hash-table :test #'equal)))
  (add-hook 'kill-buffer-hook #'exwm-service-mihomo-connections--stop nil t)
  (add-hook 'change-major-mode-hook #'exwm-service-mihomo-connections--stop nil t)
  (tabulated-list-init-header)
  (exwm-service-mihomo-connections--header))

(defun exwm-service-mihomo-connections-open ()
  "Display the live connection view and start polling while it is visible."
  (interactive)
  (let ((buffer (get-buffer-create "*Mihomo Connections*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'exwm-service-mihomo-connections-mode)
        (exwm-service-mihomo-connections-mode)))
    (add-hook 'window-buffer-change-functions #'exwm-service-mihomo-connections--visibility)
    (pop-to-buffer buffer)
    (exwm-service-mihomo-connections--visibility)))

(provide 'exwm-service-mihomo-connections)
;;; exwm-service-mihomo-connections.el ends here
