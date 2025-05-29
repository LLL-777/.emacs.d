;;; move-text.el --- Move current line or region up/down with auto-linebreak -*- lexical-binding: t; -*-



(defun move-text-pulse-line ()
  "Visual feedback for moved line/region."
  (when (fboundp 'pulse-momentary-highlight-one-line)
    (pulse-momentary-highlight-one-line (point))))
;; //移动选中的行。
(defun move-text-internal (arg)
   (cond
    ((and mark-active transient-mark-mode)
     (if (> (point) (mark))
            (exchange-point-and-mark))
     (let ((column (current-column))
              (text (delete-and-extract-region (point) (mark))))
       (forward-line arg)
       (move-to-column column t)
       (set-mark (point))
       (insert text)
       (exchange-point-and-mark)
       (setq deactivate-mark nil)
       (move-text-pulse-line)))
    (t
     (beginning-of-line)
     (when (or (> arg 0) (not (bobp)))
       (forward-line)
       (when (or (< arg 0) (not (eobp)))
            (transpose-lines arg))
       (forward-line -1)
       (move-text-pulse-line)))))
(defun move-text-down (arg)
   "Move region (transient-mark-mode active) or current line
  arg lines down."
   (interactive "*p")
   (move-text-internal arg))
(defun move-text-up (arg)
   "Move region (transient-mark-mode active) or current line
  arg lines up."
   (interactive "*p")
   (move-text-internal (- arg)))
(global-set-key (kbd "C-s-n") #'move-text-down)
(global-set-key (kbd "C-s-p") #'move-text-up)

;; //~


;; (defun move-text-internal (arg)
;;   "Move current line or region up/down by ARG lines."
;;   (cond
;;    ;; Region is active
;;    ((and mark-active transient-mark-mode)
;;     (let* ((column (current-column))
;;            (text (delete-and-extract-region (region-beginning) (region-end)))
;;            (target-point (save-excursion
;;                            (goto-char (region-beginning))
;;                            (forward-line arg)
;;                            (point))))
;;       ;; Insert newline if necessary to avoid merging
;;       (save-excursion
;;         (goto-char target-point)
;;         (unless (looking-at "^")
;;           (insert "\n")))
;;       (goto-char target-point)
;;       (insert text)
;;       ;; Restore region
;;       (set-mark (point))
;;       (forward-char (- (length text)))
;;       (setq deactivate-mark nil)
;;       (move-text-pulse-line)))

;;    ;; No region, operate on current line
;;    (t
;;     (let ((col (current-column)))
;;       (beginning-of-line)
;;       (let ((start (point)))
;;         (forward-line 1)
;;         (let ((line-text (delete-and-extract-region start (point))))
;;           (forward-line (1- arg))
;;           ;; Insert newline if needed
;;           (unless (looking-at "^")
;;             (insert "\n"))
;;           (insert line-text)
;;           (forward-line -1)
;;           (move-to-column col)
;;           (move-text-pulse-line)))))))

;; (defun move-text-up (arg)
;;   "Move region (or current line) up by ARG lines."
;;   (interactive "p")
;;   (move-text-internal (- arg)))

;; (defun move-text-down (arg)
;;   "Move region (or current line) down by ARG lines."
;;   (interactive "p")
;;   (move-text-internal arg))

;; ;; Suggested keybindings
;; (global-set-key (kbd "C-s-n") #'move-text-down)
;; (global-set-key (kbd "C-s-p") #'move-text-up)

(provide 'move-text)
