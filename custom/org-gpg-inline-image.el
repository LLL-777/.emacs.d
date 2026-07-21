;;; org-gpg-inline-image.el --- Inline base64 images in org.gpg -*- lexical-binding: t; -*-

(require 'org)
(require 'cl-lib)

(defgroup org-gpg-inline-image nil
  "Display base64 images inline in org-mode without writing to disk."
  :group 'org)

(defcustom org-gpg-image-max-width 200
  "Maximum width for displayed base64 images."
  :type 'integer
  :group 'org-gpg-inline-image)

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
        (if img
            (let ((ov (make-overlay (match-beginning 0) (match-end 0))))
              (overlay-put ov 'display img)
              (overlay-put ov 'org-gpg-inline-image t)
              (overlay-put ov 'evaporate t))
          (warn "Unrecognized image type: %s, skipping" type))))))

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
          (list type
                (buffer-substring-no-properties beg end)
                beg
                end))))))

(defun org-gpg--save-image-data (b64 type)
  "Save base64 B64 of TYPE to a user-specified file path.
Prompts interactively for the destination.  Validates that the directory
exists and is writable before writing.  Signals an error on failure."
  (let* ((data (base64-decode-string
                (replace-regexp-in-string "[ \t\n\r]" "" b64)))
         (ext (if type (symbol-name type) "bin"))
         (default-name (format "%s.%s" (format-time-string "%Y%m%d%H%M%S") ext))
         (save-path (read-file-name "Save image to: " nil default-name nil)))
    (when (or (not save-path) (string-empty-p save-path))
      (user-error "No valid file path specified"))
    (cond
     ((file-directory-p save-path)
      (user-error "%s is a directory, not a file path" save-path))
     ((not (file-writable-p save-path))
      (let ((dir (file-name-directory save-path)))
        (if (not (and dir (file-directory-p dir)))
            (user-error "Directory does not exist: %s" dir)
          (user-error "Cannot write to %s" save-path))))
     (t
      (let ((coding-system-for-write 'binary))
        (write-region data nil save-path nil 'silent))
      (message "Image saved to %s" save-path)))))

;;;###autoload
(defun org-gpg-save-image-from-block ()
  "Save the base64 image block at point to a file.
Prompts for a destination path and writes the decoded binary data.
If the path is invalid or the directory does not exist, signals an error."
  (interactive)
  (let ((info (org-gpg--b64-block-at-point)))
    (unless info
      (user-error "Not inside a B64 image block"))
    (org-gpg--save-image-data (nth 1 info) (nth 0 info))))

(defun org-gpg-show-image-at-point ()
  "Show only the base64 image block at point in a separate secure window.
Press \\[org-gpg-save-image-from-block] to save, or q to close."
  (interactive)
  (let ((info (org-gpg--b64-block-at-point)))
    (unless info
      (user-error "Not inside a B64 image block"))
    (let* ((type (nth 0 info))
           (b64  (nth 1 info))
           (data (base64-decode-string
                  (replace-regexp-in-string "[ \t\n\r]" "" b64)))
           (pixel-width (and (display-graphic-p) (window-pixel-width)))
           (maxw (if pixel-width
                     (min org-gpg-image-max-width pixel-width)
                   org-gpg-image-max-width))
           (img  (create-image data type t :max-width maxw))
           (buf  (get-buffer-create "*org-gpg-image*")))
      (with-current-buffer buf
        (setq buffer-read-only nil)
        (erase-buffer)
        (setq-local org-gpg--preview-b64 b64)
        (setq-local org-gpg--preview-type type)
        (insert "Press q to close, p to save the image to a file\n\n")
        (insert-image img)
        (special-mode)
        (local-set-key (kbd "q")
                       (lambda ()
                         (interactive)
                         (let ((win (get-buffer-window buf)))
                           (when win (quit-window t win)))))
        (local-set-key (kbd "p")
                       (lambda ()
                         (interactive)
                         (if (and (boundp 'org-gpg--preview-b64)
                                  org-gpg--preview-b64)
                             (org-gpg--save-image-data
                              org-gpg--preview-b64
                              org-gpg--preview-type)
                           (user-error "No image data available")))))
      (pop-to-buffer buf))))

(provide 'org-gpg-inline-image)
;;; org-gpg-inline-image.el ends here
