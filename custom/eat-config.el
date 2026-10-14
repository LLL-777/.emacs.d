;; -*- lexical-binding: t; -*-

(use-package eat
  :commands (eat eat-other-window eat-project)
  :custom
  ;; Match the -256color check in ~/.bashrc so Bash enables its color prompt.
  (eat-term-name "eat-256color")
  :config
  ;; Solarized Dark's 16 ANSI colors for programs running inside Eat.
  (let ((palette '("#073642" "#dc322f" "#859900" "#b58900"
                   "#268bd2" "#d33682" "#2aa198" "#eee8d5"
                   "#002b36" "#cb4b16" "#586e75" "#657b83"
                   "#839496" "#6c71c4" "#93a1a1" "#fdf6e3")))
    (cl-loop for color in palette
             for index from 0
             do (set-face-attribute (intern (format "eat-term-color-%d" index))
                                    nil :foreground color :background color))
    ;; Keep dark ANSI backgrounds, but make dark foreground text readable.
    (set-face-attribute 'eat-term-color-0 nil :foreground "#586e75")
    (set-face-attribute 'eat-term-color-8 nil :foreground "#657b83")))

(provide 'eat-config)
