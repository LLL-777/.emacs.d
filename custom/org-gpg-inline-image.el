;;; org-gpg-inline-image.el --- Inline base64 images in org.gpg -*- lexical-binding: t; -*-

(require 'org)
(require 'cl-lib)

(defcustom org-gpg-image-max-width 200
  "Maximum width for displayed base64 images."
  :type 'integer)

(defgroup org-gpg-inline-image nil
  "Display base64 images inline in org-mode without writing to disk."
  :group 'org)

(defface org-gpg-inline-image-face
  '((t :inherit default))
  "Face used for inline base64 images.")

(defun org-gpg--decode-base64-image (b64 type)
  "Decode B64 string of TYPE into an image object (memory only)."
  (let* ((data (base64-decode-string
                (replace-regexp-in-string "[ \t\n\r]" "" b64)))
         (img (create-image data type t)))
    img))

(defun org-gpg--clear-inline-images ()
  "Remove all org-gpg image overlays."
  (remove-overlays (point-min) (point-max) 'org-gpg-inline-image t))

(defun org-gpg-inline-b64-images ()
  "Display all base64 images in current org buffer."
  (interactive)
  (org-gpg--clear-inline-images)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward
            "^#\\+BEGIN_B64_IMAGE[ \t]+\\([a-zA-Z0-9]+\\)\n\\([[:ascii:]\n\r]+?\\)\n#\\+END_B64_IMAGE"
            nil t)
      (let* ((type (intern (downcase (match-string 1))))
             (b64  (match-string 2))
             (img  (org-gpg--decode-base64-image b64 type)))
        (when img
          (let ((ov (make-overlay (match-beginning 0) (match-end 0))))
            (overlay-put ov 'display img)
            (overlay-put ov 'org-gpg-inline-image t)
            (overlay-put ov 'evaporate t)))))))

(defun org-gpg-clear-inline-images ()
  "Clear inline base64 images."
  (interactive)
  (org-gpg--clear-inline-images))


(defun org-gpg--b64-block-at-point ()
  "Return (TYPE B64 BEG END) if point is inside a B64 image block."
  (save-excursion
    (let (type beg end)
      (when (re-search-backward "^#\\+BEGIN_B64_IMAGE[ \t]+\\([a-zA-Z0-9]+\\)" nil t)
        (setq type (intern (downcase (match-string 1))))
        (setq beg (match-end 0))
        (when (re-search-forward "^#\\+END_B64_IMAGE" nil t)
          (setq end (match-beginning 0))
          (when (and (> (point) (point-min))
                     (< (point) (point-max)))
            (list type
                  (buffer-substring-no-properties beg end)
                  beg
                  end)))))))


;; (defun org-gpg-show-image-at-point ()
;;   "Show only the base64 image block at point in a separate secure window."
;;   (interactive)
;;   (let ((info (org-gpg--b64-block-at-point)))
;;     (unless info
;;       (user-error "Not inside a B64 image block"))
;;     (let* ((type (nth 0 info))
;;            (b64  (nth 1 info))
;; 	    ;; (img  (org-gpg--decode-base64-image b64 type))

;; 	   ((data (base64-decode-string
;;               (replace-regexp-in-string "[ \t\n\r]" "" b64)))
;;        (maxw (min org-gpg-image-max-width
;;                   (window-pixel-width)))
;;        (img  (create-image data type t :max-width maxw)))
	   
;;            (buf  (get-buffer-create "*org-gpg-image*")))
;;       (with-current-buffer buf
;;         (setq buffer-read-only nil)
;;         (erase-buffer)
;;         (insert-image img)
;;         (insert "\n\nPress q to close.")
;;         (special-mode)
;;         (local-set-key (kbd "q")
;;                        (lambda ()
;;                          (interactive)
;;                          (kill-buffer)
;;                          (delete-window))))
;;       (pop-to-buffer buf))))

(defun org-gpg-show-image-at-point ()
  "Show only the base64 image block at point in a separate secure window."
  (interactive)
  (let ((info (org-gpg--b64-block-at-point)))
    (unless info
      (user-error "Not inside a B64 image block"))
    (let* ((type (nth 0 info))
           (b64  (nth 1 info))
           (data (base64-decode-string
                  (replace-regexp-in-string "[ \t\n\r]" "" b64)))
           (maxw (min org-gpg-image-max-width
                      (window-pixel-width)))
           (img  (create-image data type t :max-width maxw))
           (buf  (get-buffer-create "*org-gpg-image*")))
      (with-current-buffer buf
        (setq buffer-read-only nil)
        (erase-buffer)
        (insert "Press q to close\n\n")
        (insert-image img)
        (special-mode)
        (local-set-key
         (kbd "q")
         (lambda ()
           (interactive)
           (kill-buffer)
           (delete-window))))
      (pop-to-buffer buf))))

(provide 'org-gpg-inline-image)
;;; org-gpg-inline-image.el ends here
