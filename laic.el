;;; laic --- Render LateX in comments -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2024 Oscar Civit Flores
;; Author: Oscar Civit Flores
;; Keywords: LaTeX
;; Package-Version: ???????????
;; URL: https://github.com/esquellington/LatexInComments'
;; Version: 0.1
;; Package-Requires: ((emacs "27"))
;;
;;; Commentary:
;;
;; The package offers a few interactive functions to show and hide
;; math blocks in comments:
;; - `laic-create-overlay-from-comment-inside-or-forward' Create overlay for current or next visible latex block in a comment.
;; - `laic-create-overlays-from-comment-inside-or-forward' Create overlays for all latex blocks in the current comment.
;; - `laic-remove-overlays' Remove all laic overlays from the current buffer, but keep cached images on disk.
;; - `laic-remove-overlays-and-files' Remove all laic overlays from the current buffer and delete cached images from disk.
;;
;; Temporary files are stored in the customizable `laic-output-dir'
;; relative to current file path.
;;
;; Images are generated on first "create" operation, and cached for
;; fast show/hide.  They are only deleted when a buffer is closed or
;; when *laic-remove-overlays-and-files* is explicitly called.
;;
;; Installation: Add (require 'laic) to your (programming) mode hook,
;; and defile keybindings to call interactive functions.
;; For example:
;; (add-hook 'prog-mode-hook
;;  (function
;;   (lambda ()
;;    (require 'laic)
;;    ;; Create overlay for current or next visible latex block in a comment.
;;    (local-set-key (kbd "C-c C-x C-l") 'laic-create-overlay-from-comment-inside-or-forward)
;;    ;; Create overlays for all latex blocks in the current or next comment.
;;    (local-set-key (kbd "C-c C-x C-o") 'laic-create-overlays-from-comment-inside-or-forward)
;;    ;; Remove all laic overlays
;;    (local-set-key (kbd "C-c C-x o") 'laic-remove-overlays)
;;    ;; Remove all laic overlays and delete cache
;;    (local-set-key (kbd "C-c C-x r") 'laic-remove-overlays-and-files)
;;
;;; License:
;;
;; This file is not a part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Code:

;;--------------------------------
;; Customization
;;--------------------------------

(defgroup laic nil
  "Render LaTeX blocks in comments."
  :group 'tex)

(defcustom laic-output-dir "laic-tmp"
  "Default tmp output directory, relative to current file."
  :group 'laic
  :type 'directory)

(defcustom laic-command-dvipng "dvipng"
  "Command for dvipng."
  :group 'laic
  :type 'file)

(defcustom laic-block-delimiter-pairs (list (list "\\(" "\\)")
                                            (list "\\[" "\\]")
                                            (list "\\begin{equation*}" "\\end{equation*}")
                                            (list "\\begin{equation}" "\\end{equation}")
                                            (list "\\begin{align}" "\\end{align}")
                                            (list "\\begin{align*}" "\\end{align*}"))
  "List of delimiter pairs."
  :group 'laic
  :type 'list)

(defcustom laic-extra-packages ""
  "List of extra package names, separated by commas.
Packages amsmath,amsfonts are included by default.  NOTE: Adding
extra packages may significantly slow preview generation down."
  :group 'laic
  :type 'string)

(defcustom laic-user-preamble ""
  "User-defined preamble, arbitrary LaTeX block.
Can be used to define custom math operators, etc..."
  :group 'laic
  :type 'string)

(defcustom laic-dpi 200
  "Custom DPI for LaTeX images, independent of font size."
  :group 'laic
  :type 'number)

;;------------------------------------------------------------------------------------------------
;; Internal implementation
;; IMPORTANT: No function moves the point (all use save-excursion when required)
;;------------------------------------------------------------------------------------------------

;; Compute DPI for LaTeX images.
;;
;; This would be the proper way, but requires finding physical screen
;; size in inches, on the XPS13 it's 170dpi
;; (/ (sqrt (+ (* (display-pixel-width) (display-pixel-width))
;;             (* (display-pixel-height) (display-pixel-height))))
;;     13.0)) ;TODO (physical-screen-diagonal-size-in-inches)))
;;
;; TODO For now we just customize it explicitly, could select
;; customized or automatic, see beardbolt.el for defaults that can be
;; overriden in customization
(defun laic-get-image-dpi()
  "Return image DPI."
  laic-dpi)

;; Return comment foreground color (defined by theme)
;; NOTE: Builtin (foreground-color-at-point) returns inconsistent
;; results, and often returns regular code face color instead of
;; comment face color, so we just read the :foreground attribute of
;; the comment face directly, regardless of point
(defun laic-get-image-foreground-color()
  "Return image foreground color that matches comment face."
  (face-attribute 'font-lock-comment-face :foreground nil 'default))
(defun laic-get-image-background-color()
  "Return image background color that matches comment face."
  (face-attribute 'font-lock-comment-face :background nil 'default))

(defun laic-convert-color-to-dvipng-arg( color )
  "Convert Emacs COLOR string \"#RRGGBB\" to dvipng argument string."
  (let (rsub gsub bsub rnum gnum bnum)
       (setq rsub (substring color 1 3)) ;get RR
       (setq gsub (substring color 3 5)) ;get GG
       (setq bsub (substring color 5 7)) ;get BB
       (setq rnum (string-to-number rsub 16)) ;base 16
       (setq gnum (string-to-number gsub 16)) ;base 16
       (setq bnum (string-to-number bsub 16)) ;base 16
       ;; output "rgb r g b" with r,g,b \in [0..1]
       (format "rgb %f %f %f" (/ rnum 255.0) (/ gnum 255.0) (/ bnum 255.0))))

(defun laic-convert-color-to-html-arg( color )
  "Convert Emacs COLOR string \"#RRGGBB\" to HTML argument string RRGGBB."
  (substring color 1 7))

;;--------------------------------
;; OS-specific
;;--------------------------------

(defun laic-OS-dir ( path )
  "OS-specific file-name-as-directory to convert PATH with \ to / if necessary."
  (cond ((eq system-type 'windows-nt)
         (subst-char-in-string ?/ ?\\ (file-name-as-directory path)))
        (t ;;else 'gnu/linux, 'darwin, etc...
         (file-name-as-directory path))))

(defvar laic-OS-null-sink
  (cond ((eq system-type 'windows-nt)
         " > NUL 2> laic_errors.txt")
        (t ;;else 'gnu/linux, 'darwin, etc...
         (concat " > /dev/null 2> laic_errors.txt" )))
  "OS-specific commandline args to redirect output to null sink.")

(defvar laic-OS-commandline-separator
  (cond ((eq system-type 'windows-nt)
         "&")
        (t ;;else 'gnu/linux, 'darwin, etc...
         ";"))
  "OS-specific commandline separator string, to concatenate commands."
)

;;--------------------------------
;; buffer-local vars
;;--------------------------------

(defvar-local laic--list-images
  ()
  "Buffer-local list of images to reuse and files to be deleted later.")

(defvar-local laic--list-overlays
  ()
  "Buffer-local list of laic-created overlays.")

;;--------------------------------
;; LaTeX + Image processing
;;--------------------------------

(defun laic-create-image-from-latex ( code dpi bgcolor fgcolor )
  "Create an image from latex string with given dpi and bg/fg colors and return it."

  ;; Create output dir if required
  (when (not (file-directory-p laic-output-dir))
    (make-directory laic-output-dir))

  ;; Try to create image
  (let (tmpfilename tmpfilename_tex tmpfilename_dvi tmpfilename_png
        prefix packages fullcode
        img
        ;;start_time
        ;;current_time
        )

    ;; PROFILE \[ \alpha = \beta \]
    ;; (setq start_time (float-time))

    ;; Create unique temporary filename using hash
    (setq tmpfilename (secure-hash 'md5 (format "%s-%d-%s-%s" code dpi bgcolor fgcolor)))

    (setq tmpfilename_tex (expand-file-name (concat (laic-OS-dir laic-output-dir) tmpfilename ".tex")))
    (setq tmpfilename_dvi (expand-file-name (concat (laic-OS-dir laic-output-dir) tmpfilename ".dvi")))
    (setq tmpfilename_png (expand-file-name (concat (laic-OS-dir laic-output-dir) tmpfilename ".png")))

    ;; Compose latex code into temporary file
    (setq prefix "\\documentclass{article}\n\\pagestyle{empty}\n") ;minimal docuument class 10% faster, but limited
    (setq packages "\\usepackage{amsmath,amsfonts}\n") ;amsfonts adds \( \approx 0 \)  overhead, so add it
    (setq packages (concat packages "\\usepackage{" laic-extra-packages "}\n")) ;works even if empty
    (setq fullcode (concat
                    prefix
                    packages
                    laic-user-preamble
                    ;; IF "xcolor" package is included we must set explicit background + text color (BUT no need for "color" package)
                    (when (string-match-p "xcolor" packages) ;nil if no match
                      (concat "\\pagecolor[HTML]{" (laic-convert-color-to-html-arg bgcolor) "}"
                              "\\color[HTML]{" (laic-convert-color-to-html-arg fgcolor) "}"))
                    "\\begin{document}\n"
                    code
                    "\n\\end{document}\n"))
    (write-region fullcode nil tmpfilename_tex)

    ;; PROFILE \[ \alpha = \beta \]
    ;;(setq current_time (float-time))
    ;;(message "PROF/SOURCE %f" (- current_time start_time))
    ;;(setq start_time current_time)

    ;; Run latex on tmp file and then run dvipng to generate trimmed image for
    ;; the latex block with desired fg/bg colours
    ;;
    ;; NOTE:
    ;; - latex reads .tex and outputs .dvi/.log/.aux files in working dir, so we must cd into it
    ;; - dvipng
    ;;   -bg \"rgb 0.13 0.13 0.13\" using double quotes is required for Windows (Linux also supports single quotes '..')
    ;;   -bg Transparent works, but Emacs seems to ignore transparency
    ;;   NOTE: explicit fg/bg only set when "xcolor" package is NOT included, but is neccessary for "color" packate
    ;;
    ;; TODO:
    ;; - Retrieve DPI programmatically and pass as -D argument
    (shell-command (concat "cd " (laic-OS-dir laic-output-dir)
                           ;; LaTeX: .tex -> .dvi
                           " " laic-OS-commandline-separator " latex --interaction=batchmode " tmpfilename_tex laic-OS-null-sink
                           ;; dvipng: .dvi -> .png
                           " " laic-OS-commandline-separator " " laic-command-dvipng
                           " -D " (number-to-string dpi) ;DPI
                           ;; IF "xcolor" package is not included, we must set explicit background/foreground colors, but no need for "color"
                           (when (not (string-match-p "xcolor" packages)) ;nil if match
                             (concat " -bg \"" (laic-convert-color-to-dvipng-arg bgcolor) "\""   ;background color
                                     " -fg \"" (laic-convert-color-to-dvipng-arg fgcolor) "\"")) ;foreground color
                           " -T tight" ;avoid whitespace -> equivalent to "convert -trim", but MUCH faster
                           " -q" ;quiet
                           " " tmpfilename_dvi ;input
                           " -o " tmpfilename_png ;output
                           laic-OS-null-sink)
                   nil nil)

    ;; PROFILE \[ \alpha = \beta \]
    ;;(setq current_time (float-time))
    ;;(message "PROF/COMMAND %f" (- current_time start_time))
    ;;(setq start_time current_time)

    ;; Coloured text tests with "color" or "xcolor" packages
    ;; - "color" does not show orange, "xcolor" does
    ;; \[ \pi \alpha \neq \beta \]
    ;; \[ \textcolor{red}{\alpha} \beta \]
    ;; \[ \textcolor{orange}{\alpha} {\color{green}\beta} \gamma \]
    ;; laic-user-preamble
    ;; \[ \textcolor{orange}{\trace(A)} \neq \det(B) \neq \textcolor{pink}{\adjugate(A)} \]

    ;; Create image object from filename
    (setq img (create-image tmpfilename_png))

    ;; Cleanup temp files
    (delete-file tmpfilename_tex)
    (delete-file tmpfilename_dvi)
    (delete-file (expand-file-name (concat (laic-OS-dir laic-output-dir) tmpfilename ".aux")))
    (delete-file (expand-file-name (concat (laic-OS-dir laic-output-dir) tmpfilename ".log")))

    ;; TODO delete laic_errors.txt IFF no errors (file is empty)
    ;; TODO maybe laic-cleanup hook called after mode end that deletes all temp files
    ;;(delete-file (expand-file-name (concat (laic-OS-dir laic-output-dir) "laic_errors.txt")))

    ;; Save (png img) for future deletion and reuse, as file must exist while overlay is visible
    (push (list tmpfilename_png img) laic--list-images)

    ;; PROFILE \[ \alpha = \beta \]
    ;;(setq current_time (float-time))
    ;;(message "PROF/FINISH %f" (- current_time start_time))
    ;;(setq start_time current_time)

    ;; Return image
    img))

(defun laic-find-image-from-latex ( code dpi bgcolor fgcolor )
  "Find an image from latex string with given dpi and bg/fg colors and return it."
  (let (tmpfilename tmpfilename_png found)

    ;; Create unique temporary filename using hash
    (setq tmpfilename (secure-hash 'md5 (format "%s-%d-%s-%s" code dpi bgcolor fgcolor)))
    (setq tmpfilename_png (expand-file-name (concat (laic-OS-dir laic-output-dir) tmpfilename ".png")))

    ;; Find cached image with same name (see http://xahlee.info/emacs/emacs/elisp_sequence_find.html)
    (setq found (seq-find
                 (lambda (x) (string-equal (nth 0 x) tmpfilename_png))
                 laic--list-images))

    ;; Return img if found
    (when found
      (message "tmpfilename_png %s exists, using cached IMG!" tmpfilename_png)
      (nth 1 found))))

;;    ;; TEMP OLD WAY: find in filesystem, not in laic--list-images
;;    (when (file-exists-p tmpfilename_png)
;;      (message "tmpfilename_png %s exists, using cached PNG!" tmpfilename_png)
;;      ;; Create image object from filename
;;      (setq img (create-image tmpfilename_png))
;;      img)))

(defun laic-create-overlay-from-block ( begin end dpi bgcolor fgcolor )
  "Create latex overlay from BEGIN..END region with DPI, BGCOLOR,
FGCOLOR and return it."
  (let (latexblock latexblocknormalized ov img)
    (setq latexblock (buffer-substring-no-properties begin end))

    ;; remove potential single-line 'comment-start' substring from latex block
    (setq latexblocknormalized (string-replace comment-start "" latexblock))

    ;; Find cached img, or create from scratch
    (setq img (laic-find-image-from-latex latexblocknormalized dpi bgcolor fgcolor))
    (when (not img)
      (setq img (laic-create-image-from-latex latexblocknormalized dpi bgcolor fgcolor)))

    (setq ov (make-overlay begin end))
    (overlay-put ov 'display img) ;sets image to be displayed in overlay
    ;;(message "LCOFLB be = %d %d = %s" begin end (buffer-substring-no-properties begin end))
    (push ov laic--list-overlays)
    ov))

;;--------------------------------
;; LaTeX block searches
;; NOTE: Do not consider whether point or blocks are inside comments
;;--------------------------------

(defun laic-search-forward-block-begin ()
  "Search forward closest latex block begin, return point at beginning."
  (let (best b ld d)
    (setq best (point-max)) ;init to end of buffer
    (setq ld laic-block-delimiter-pairs)
    ;; search for all delimiters
    (while ld
      (setq d (pop ld))
      (save-excursion
        (setq b (search-forward (nth 0 d) best t))) ;find begin delimiter, if closer than best
      (when (and b (< b best))
        (setq best (match-beginning 0)))) ;point at beginning of match
    ;; return closest delimiter
    (cond ((and best (< best (point-max)))
           best)
          (t
           nil))))

(defun laic-search-forward-block-end ()
  "Search forward closest latex block end, return point at end."
  (let (best e ld d)
    (setq best (point-max)) ;init to end of buffer
    (setq ld laic-block-delimiter-pairs)
    ;; search for all delimiters
    (while ld
      (setq d (pop ld))
      (save-excursion
        (setq e (search-forward (nth 1 d) best t))) ;find end delimiter, if closer than best
      (when (and e (< e best))
        (setq best (match-end 0)))) ;point at end of match
    ;; return closest delimiter
    (cond ((and best (< best (point-max)))
           best)
          (t
           nil))))

(defun laic-search-backward-block-begin ()
  "Search forward closest latex block begin, return point at begin."
  (let (best e ld d)
    (setq best (point-min)) ;init to begin of buffer
    (setq ld laic-block-delimiter-pairs)
    ;; search for all delimiters
    (while ld
      (setq d (pop ld))
      (save-excursion
        (setq e (search-backward (nth 0 d) best t))) ;find begin delimiter, if closer than best
      (when (and e (> e best))
        (setq best (match-beginning 0)))) ;point at begin of match
    ;; return closest delimiter
    (cond ((and best (> best (point-min)))
           best)
          (t
           nil))))

(defun laic-search-backward-block-end ()
  "Search forward closest latex block end, return point at end."
  (let (best e ld d)
    (setq best (point-min)) ;init to begin of buffer
    (setq ld laic-block-delimiter-pairs)
    ;; search for all delimiters
    (while ld
      (setq d (pop ld))
      (save-excursion
        (setq e (search-backward (nth 1 d) best t))) ;find end delimiter, if closer than best
      (when (and e (> e best))
        (setq best (match-end 0)))) ;point at end of match
    ;; return closest delimiter
    (cond ((and best (> best (point-min)))
           best)
          (t
           nil))))

(defun laic-search-forward-block ()
  "Find matching begin/end latex block forward."
  (save-excursion
    (let (begin end)
      (setq begin (laic-search-forward-block-begin))
      (when begin
        (goto-char begin)) ;move point to begin
      (setq end (laic-search-forward-block-end))
      (cond ((or (eq begin nil) (eq end nil))
             ;;(message "laic-search-forward-block() no LaTeX block found!")
             nil) ;returns nil
            (t
             (list begin end) )))))

;;--------------------------------
;; Comment helpers
;;--------------------------------

;; NOTE: comment-beginning returns nil if point not inside comment,
;; which seems to work, as opposed to (comment-only-p begin end),
;; which returns inconsistent results.
(defun laic-is-point-in-comment-p()
  "Return non-nil if point is in comment, nil otherwise."
  (save-excursion ;reverts comment-beginning moving point
    (comment-normalize-vars)
    (not (eq (comment-beginning) nil))))

(defun laic-find-comment-or-buffer-end()
  "Return point at end of current comment or at end of buffer."
  (interactive)
  (save-excursion
    (while (and (< (point) (point-max)) (laic-is-point-in-comment-p))
      (forward-line))
    (point)))

;;--------------------------------
;; Region functionality
;;--------------------------------

(defun laic-gather-blocks( begin end )
  "Gather all latex blocks inside BEGIN/END points, return as list of pairs."
  (save-excursion
    (let (lb be)
      (setq lb ()) ;empty
      (goto-char begin)
      (setq be (laic-search-forward-block)) ;first block
      (while (and be (<= (nth 1 be) end)) ;non-empty and be.end < end
        (push be lb) ;save block
        (goto-char (nth 1 be)) ;skip block
        (setq be (laic-search-forward-block))) ;next block
      (reverse lb) )))

(defun laic-gather-blocks-in-comments( begin end )
  "Gather all latex blocks inside BEGIN/END points, return as list of pairs."
  (save-excursion
    (let (lb be)
      (setq lb ()) ;empty
      (goto-char begin)
      (setq be (laic-search-forward-block)) ;1st block
      (while (and be (<= (nth 1 be) end)) ;non-empty and be.end < end
        (let ((b (nth 0 be))
              (e (nth 1 be)))
          ;;DEBUG (message "be = %d %d = %s" b e (buffer-substring-no-properties b e))
          (goto-char b) ;move to block begin
          ;;(when (comment-only-p b e) ;block is inside comment
          (when (laic-is-point-in-comment-p) ;block in comment
            ;;DEBUG (message "COMMENT in %d %d" b e)
            (push be lb)) ;save block
          (goto-char e) ;skip to block end
          (setq be (laic-search-forward-block)))) ;next block
      (reverse lb))))

(defun laic-create-overlays-from-blocks( listblocks )
  "Create overlays eack block in the LISTBLOCKS."
  (save-excursion
    (let (lb be)
      (setq lb listblocks)
      (while lb
        (setq be (pop lb))
        (goto-char (nth 0 be)) ;move to begin
        (laic-create-overlay-from-block (nth 0 be) (nth 1 be) ;begin/end
                                        (laic-get-image-dpi) ;dpi
                                        (laic-get-image-background-color) (laic-get-image-foreground-color)) )))) ;bg/fg colors

;;----------------------------------------------------------------
;; Main interactive functionality
;;
;; These functions may move point to their "intuitive" position,
;; if any overlays are created
;;----------------------------------------------------------------

(defun laic-create-overlay-from-latex-inside ()
  "If point is in a latex block in a comment, create overlay and move point to end."
  (interactive)
  (when (laic-is-point-in-comment-p)
    (let (pt beginpt endpt)
      (setq pt (point)) ;get current point
      (setq beginpt (laic-search-backward-block-begin)) ;find prev begin wrt point
      (when beginpt ;valid begin
        (goto-char beginpt) ;move to prev begin
        (setq endpt (laic-search-forward-block-end)) ;find next end
        (goto-char pt)) ;restore point
      ;; Create overlay if valid begin/end block found around point
      (when (and beginpt endpt (< pt endpt)) ;non-nil begin and end + end after current
        (laic-create-overlay-from-block beginpt endpt
                                        (laic-get-image-dpi)
                                        (laic-get-image-background-color) (laic-get-image-foreground-color))
        (goto-char endpt) ;move to block end
        t)))) ;return true if succeeded

(defun laic-create-overlay-from-latex-forward ()
  "Find next visible latex block in comment, create overlay and move point to end."
  (interactive)
  (let (be blockisincomment)
    (setq be (laic-search-forward-block))
    (when (and be ;;found block
               (pos-visible-in-window-p (nth 0 be) (selected-window))) ;;block is visible
      (save-excursion
        (goto-char (nth 0 be)) ;;move to block begin
        (setq blockisincomment (laic-is-point-in-comment-p)))
      (when blockisincomment ;;block is in comment
        (add-hook 'kill-buffer-hook #'laic-remove-overlays-and-files nil t) ;cleanup on kill buffer, local
        (add-hook 'kill-emacs-hook #'laic-remove-overlays-and-files nil t) ;cleanup on kill emacs, local
        (laic-create-overlay-from-block (nth 0 be) (nth 1 be) ;begin/end
                                        (laic-get-image-dpi) ;dpi
                                        (laic-get-image-background-color) (laic-get-image-foreground-color)) ;bg/fg colors
        (goto-char (nth 1 be)) ;;move to block end
        t)))) ;return true if succeeded

;;;###autoload
(defun laic-create-overlay-from-comment-inside-or-forward ()
  "Create overlay from current or next visible latex block and move point to end."
  (interactive)
  (when (not (laic-create-overlay-from-latex-inside))
    (laic-create-overlay-from-latex-forward)))

(defun laic-create-overlays-from-comment-inside()
  "Create overlays for all blocks in current comment, keep point unchanged."
  (interactive)
  (when (laic-is-point-in-comment-p) ;we're inside a comment
    (add-hook 'kill-buffer-hook #'laic-remove-overlays-and-files nil t) ;cleanup on kill buffer, local
    (add-hook 'kill-emacs-hook #'laic-remove-overlays-and-files nil t) ;cleanup on kill emacs, local
    (save-excursion
      (let (bc ec)
        (setq bc (comment-search-backward nil t)) ;comment begin, moves point to begin
        (setq ec (laic-find-comment-or-buffer-end)) ;comment end, from previously moved point at begin
        (cond ((and bc ec)
               (laic-create-overlays-from-blocks (laic-gather-blocks bc ec))
               t) ;;return true
              (t
               (error "ERROR: laic-create-overlays-from-blocks could not find comment begin/end")
               nil)))))) ;;return nil

(defun laic-create-overlays-from-comment-forward()
  "Create overlays for all blocks in next visible comment, keep point unchanced."
  (interactive)
  (let (be blockisincomment)
    (setq be (laic-search-forward-block)) ;;fwd block
    (when (and be ;;found block
               (pos-visible-in-window-p (nth 0 be) (selected-window))) ;;block is visible
      (save-excursion
        (goto-char (nth 0 be)) ;;move to block begin
        (setq blockisincomment (laic-is-point-in-comment-p)))
      (when blockisincomment ;;block is in comment
        (save-excursion
          (goto-char (nth 0 be)) ;;move to block begin
          (let (bc ec)
            (setq bc (comment-search-backward nil t)) ;find comment begin from block begin, moves point to comment begin
            (setq ec (laic-find-comment-or-buffer-end)) ;comment end, from previously moved point at begin
            (cond ((and bc ec)
                   (laic-create-overlays-from-blocks (laic-gather-blocks bc ec))
                   t) ;;return true
                  (t
                   (error "ERROR: laic-create-overlays-from-blocks could not find comment begin/end")
                   nil)))))))) ;;return nil

;;;###autoload
(defun laic-create-overlays-from-comment-inside-or-forward ()
  "Create overlays for all blocks in current comment or next visible one."
  (interactive)
;;  (message "LAIC took %f seconds"
;;           (benchmark-elapse ;IMPORTANT (require 'benchmark)
  (when (not (laic-create-overlays-from-comment-inside))
    (laic-create-overlays-from-comment-forward)))

;; TODO COULD remove-overlays in BEGIN END region too, in a given
;; comment for example, useful to toggle
(defun laic-remove-overlays ()
  "Remove all laic overlays."
  (interactive)
  (while laic--list-overlays
    (delete-overlay (pop laic--list-overlays))))

;;;###autoload
(defun laic-remove-overlays-and-files ()
  "Remove all laic overlays and delete all temporary files."
  (interactive)
  (laic-remove-overlays)
  (while laic--list-images
    (let (imagedata)
      (setq imagedata (pop laic--list-images))
      ;;(message "DELETING %s IMG" (nth 0 imagedata))
      (delete-file (nth 0 imagedata))))
  ;;ensure img cache is cleared or they are not regen after remove+regen
  (clear-image-cache))

;;----------------------------------------------------------------
;; Buffer/Region interactive functionality
;;----------------------------------------------------------------

;;;###autoload
(defun laic-create-overlays-from-buffer()
  "Create overlays for all latex blocks in the buffer."
  (interactive)
  (laic-create-overlays-from-blocks (laic-gather-blocks (point-min) (point-max))))
;;;###autoload
(defun laic-create-overlays-from-region()
  "Create overlays for all latex blocks in the region."
  (interactive)
  (laic-create-overlays-from-blocks (laic-gather-blocks (region-beginning) (region-end))))

;;;###autoload
(defun laic-create-overlays-from-buffer-comments()
  "Create overlays for all latex blocks in the buffer comments."
  (interactive)
  (laic-create-overlays-from-blocks (laic-gather-blocks-in-comments (point-min) (point-max))))
;;;###autoload
(defun laic-create-overlays-from-region-comments()
  "Create overlays for all latex blocks in active region comments."
  (interactive)
  (laic-create-overlays-from-blocks (laic-gather-blocks-in-comments (region-beginning) (region-end))))

;;--------------------------------
;; Package setup
;;--------------------------------
(provide 'laic)
;;; laic.el ends here

;;--------------------------------
;; Suggested Keybindings
;;--------------------------------
;; (local-set-key (kbd "C-c l") 'laic-create-overlay-from-latex-inside-or-forward)
;; (local-set-key (kbd "C-c c") 'laic-create-overlays-from-comment-inside)
;; (local-set-key (kbd "C-c r") 'laic-remove-overlays)
;;
;; (global-set-key (kbd "C-c L") 'laic-create-overlays-from-buffer)
;; (global-set-key (kbd "C-c R") 'laic-create-overlays-from-region)
;; (global-set-key (kbd "C-c C") 'laic-create-overlays-from-region-comments)
;; (global-set-key (kbd "C-c B") 'laic-create-overlays-from-buffer-comments)

;;----------------------------------------------------------------
;; Tests
;;
;; REQUIRES physics package (apt-get install texlive-science), see
;; https://ctan.org/pkg/physics and PDF manual linked there
;;----------------------------------------------------------------

;;---- Simple blocks
;; IMPORTANT: Comment prefix does not matter here

;; Del operator
;; \[ \nabla = ( \frac{\partial}{\partial x}, \frac{\partial}{\partial y}, \frac{\partial}{\partial z} ) \]
;; Gradient
;; \[ \nabla f = ( \frac{\partial f}{\partial x}, \frac{\partial f}{\partial y}, \frac{\partial f}{\partial z} ) \]
;; Laplacian (Del squared)
;; \[ \Delta f = \nabla^2 f = \nabla \cdot \nabla f\]
;; Divergence
;; \[ \text{div} \vec f = \nabla \cdot \vec f \]
;; Curl
;; \[ \text{curl} \vec f = \nabla \times \vec f\]

;;---- Equation environments
;; IMPORTANT: Comment prefix
;; \begin{equation}
;; e^{i\pi} = -1
;; \end{equation}

;; List tests
;;(setq ll ())
;;(setq aa '(1 2))
;;(setq bb (list 3 4))
;;(setq cc (list 4 5))
;;(push aa ll)
;;(push bb ll)
;;(push cc ll)
;;(reverse ll)
