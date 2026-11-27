;;; list-mode-demo-test.el --- ERT tests for the frames, windows and buffers demo -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Daniel Nagy

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public
;; License along with this program.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Tests for the demo table of frames, windows and buffers.  Every
;; test needs `map-extras' on the load path, because builtin `map.el'
;; covers none of the three objects, so the suite skips without it.
;;
;; The fixture is the running Emacs itself: the selected frame, the
;; selected window and a temporary buffer stand for the live objects
;; that the demo reads.

;;; Code:

(require 'ert)
(require 'cl-lib)

(require 'list-mode-test-helper)
(require 'list-mode-demo)

(defun list-mode-demo-test--row (object &optional child-maker)
  "Return a demo row over OBJECT with CHILD-MAKER."
  (list-demo--row (list (type-of object) object) object child-maker))

(defun list-mode-demo-test--cells (object &optional child-maker)
  "Return the demo cells of OBJECT with CHILD-MAKER."
  (list-row-cells (list-mode-demo-test--row object child-maker) nil))

;;; Cells

(ert-deftest list-mode-demo-row-reads-a-frame ()
  "A frame row names the frame and reports its size."
  (skip-unless (require 'map-extras nil t))
  (let ((cells (list-mode-demo-test--cells (selected-frame))))
    (should (stringp (aref cells 0)))
    (should (equal "frame" (aref cells 1)))
    (should (equal "" (aref cells 2)))
    (should (string-match-p "^[0-9]+x[0-9]+" (aref cells 3)))))

(ert-deftest list-mode-demo-row-reads-a-window ()
  "A window row names the buffer that the window shows."
  (skip-unless (require 'map-extras nil t))
  (let* ((window (selected-window))
         (buffer (window-buffer window))
         (cells (list-mode-demo-test--cells window)))
    (should (equal (buffer-name buffer) (aref cells 0)))
    (should (equal "window" (aref cells 1)))
    (should (equal (symbol-name
                    (buffer-local-value 'major-mode buffer))
                   (aref cells 2)))
    (should (string-match-p "^start " (aref cells 3)))))

(ert-deftest list-mode-demo-row-reads-a-buffer ()
  "A buffer row names the buffer and reports its mode and size."
  (skip-unless (require 'map-extras nil t))
  (with-temp-buffer
    (rename-buffer " *list-mode-demo-test*" t)
    (let ((cells (list-mode-demo-test--cells (current-buffer))))
      (should (equal (buffer-name) (aref cells 0)))
      (should (equal "buffer" (aref cells 1)))
      (should (equal "fundamental-mode" (aref cells 2)))
      (should (string-match-p "bytes" (aref cells 3))))))

;;; Faces

(ert-deftest list-mode-demo-declares-the-mode-face ()
  "Every demo row declares the face of its Mode cell."
  (skip-unless (require 'map-extras nil t))
  (should (equal '((2 . font-lock-function-name-face))
                 (list-row-cell-faces
                  (list-mode-demo-test--row (selected-frame))))))

(ert-deftest list-mode-demo-paints-the-mode-cell ()
  "The demo table prints the major mode in the function name face."
  (skip-unless (require 'map-extras nil t))
  (with-temp-buffer
    (list-demo-mode)
    (list-mode-set-rows
     (list (list-demo--row (list 'buffer (current-buffer))
                           (current-buffer) nil)))
    (goto-char (point-min))
    (should (search-forward "list-demo-mode" nil t))
    (should (eq 'font-lock-function-name-face
                (get-text-property (1- (point)) 'face)))))

;;; Children

(ert-deftest list-mode-demo-frame-expands-into-its-windows ()
  "A frame row answers one row per window of the frame."
  (skip-unless (require 'map-extras nil t))
  (let* ((frame (selected-frame))
         (row (list-mode-demo-test--row frame #'list-demo--window-rows))
         (children (list-row-children row)))
    (should (= (length children)
               (length (window-list frame 'no-minibuf))))
    (should (cl-every (lambda (child)
                        (windowp (list-map-row-object child)))
                      children))
    (should (= (length children)
               (length (delete-dups (mapcar #'list-row-key children)))))))

(ert-deftest list-mode-demo-window-expands-into-its-buffer ()
  "A window row answers one row for the buffer that it shows."
  (skip-unless (require 'map-extras nil t))
  (let* ((window (selected-window))
         (row (list-mode-demo-test--row window #'list-demo--buffer-rows))
         (children (list-row-children row)))
    (should (= 1 (length children)))
    (should (eq (window-buffer window)
                (list-map-row-object (car children))))
    (should-not (list-row-expandable-p (car children)))))

(ert-deftest list-mode-demo-keys-two-windows-apart-on-one-buffer ()
  "Two windows that show one buffer keep their buffer rows apart."
  (skip-unless (require 'map-extras nil t))
  (let* ((window (selected-window))
         (new (split-window window nil 'below))
         (frame-row (list-mode-demo-test--row (selected-frame)
                                              #'list-demo--window-rows)))
    (unwind-protect
        (let* ((window-rows (list-row-children frame-row))
               (window-keys (mapcar #'list-row-key window-rows))
               (buffer-keys (mapcar (lambda (window-row)
                                      (list-row-key
                                       (car (list-row-children window-row))))
                                    window-rows)))
          (should (= 2 (length window-rows)))
          (should (= 2 (length (delete-dups (copy-sequence window-keys)))))
          (should (= 2 (length (delete-dups (copy-sequence buffer-keys))))))
      (delete-window new))))

;;; The table

(ert-deftest list-mode-demo-prints-and-expands ()
  "The demo mode prints a frame and expands it into its windows."
  (skip-unless (require 'map-extras nil t))
  (with-temp-buffer
    (list-demo-mode)
    (list-mode-set-rows (list-demo--top-rows))
    (goto-char (point-min))
    (should (equal (length (frame-list))
                   (length (list-mode-visible-rows))))
    (should (equal "frame"
                   (aref (list-row-cells
                          (caar (list-mode-visible-rows)) nil)
                         1)))
    (list-mode-toggle-row)
    (should (= (length (list-mode-visible-rows))
               (+ (length (frame-list))
                  (length (window-list (selected-frame) 'no-minibuf)))))
    (should (equal '(0 1)
                   (delete-dups (list-mode-test--visible-depths))))))

(ert-deftest list-mode-demo-refresh-shows-a-new-window ()
  "A refresh reads the live windows under an expanded frame."
  (skip-unless (require 'map-extras nil t))
  (with-temp-buffer
    (list-demo-mode)
    (list-mode-set-rows (list-demo--top-rows))
    (goto-char (point-min))
    (list-mode-toggle-row)
    (let ((before (length (list-mode-visible-rows)))
          (new (split-window (selected-window) nil 'below)))
      (unwind-protect
          (progn
            (list-demo--refresh)
            (should (= (1+ before) (length (list-mode-visible-rows))))
            (should (list-row-expanded (caar (list-mode-visible-rows)))))
        (delete-window new)))))

;;; Visiting

(ert-deftest list-mode-demo-visits-what-a-row-stands-for ()
  "A row selects its frame or window, or shows its buffer."
  (skip-unless (require 'map-extras nil t))
  (let ((frame (selected-frame))
        (window (selected-window))
        (buffer (get-buffer-create " *list-mode-demo-visit*")))
    (unwind-protect
        (let (visited)
          (cl-letf (((symbol-function 'select-frame)
                     (lambda (object &rest _)
                       (push (cons 'frame object) visited)))
                    ((symbol-function 'select-window)
                     (lambda (object &rest _)
                       (push (cons 'window object) visited)))
                    ((symbol-function 'pop-to-buffer)
                     (lambda (object &rest _)
                       (push (cons 'buffer object) visited))))
            (list-row-visit (list-mode-demo-test--row frame))
            (list-row-visit (list-mode-demo-test--row window))
            (list-row-visit (list-mode-demo-test--row buffer)))
          (should (equal (list (cons 'buffer buffer)
                               (cons 'window (frame-selected-window frame))
                               (cons 'window window)
                               (cons 'frame frame))
                         visited)))
      (kill-buffer buffer))))

(provide 'list-mode-demo-test)
;;; list-mode-demo-test.el ends here
