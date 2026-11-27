;;; list-mode-demo.el --- Frame, window and buffer demo for list-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Daniel Nagy

;; Author: Daniel Nagy
;; URL: https://github.com/nagy/emacs-list-mode
;; Keywords: convenience
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

;; A table over live builtin objects.  `M-x list-demo' lists every
;; frame, a frame expands into its windows, and a window expands into
;; the buffer that it displays.  Each cell reads its value through
;; `map-elt', so no row type holds a copy of an object.  A frame, a
;; window and a buffer can die while the table still prints the row
;; that named them: such a row is stale.  The base dims a stale row
;; and refuses to expand it, `g' reads the tree again, and
;; `auto-revert-mode' does that for you.
;;
;; The demo needs `map-extras', which teaches the `map.el' protocol to
;; frames, windows and buffers; builtin `map.el' covers none of the
;; three.  The dependency stays optional and out of the package
;; headers, the way `list-mode-evil' keeps evil out: the mode and the
;; command load the library and report it when it is missing.
;;
;; Design notes for a change in this file:
;;
;; - Each level answers its own keys.  A frame names itself under
;;   `name', a window names its buffer under `buffer', and a buffer
;;   names itself under `name' again, so one `:key' per column of
;;   `list-mode-columns' cannot serve all three.  The row therefore
;;   computes its cells from `map-elt' calls of its own level, and the
;;   column properties stay with the header, the fit and the sort.
;; - A key must stay unique in the whole table.  A window that shows a
;;   buffer does not own it, and two windows may show one buffer, so a
;;   child key carries the key of its parent; see `list-demo--child-key'.
;; - The rows wrap live objects, and it is the cell that changes when a
;;   window shows another buffer.  `list-mode-set-rows' finds no change
;;   in a list of wrappers around the same objects, so a refresh drops
;;   the cached children and reprints through `list-mode-reprint', as a
;;   map table of live objects always does.
;; - `window-list' answers the windows of a frame because `map-extras'
;;   gives a frame no key for them; the buffer of a window is a
;;   `map-elt'.
;; - A live object can die, and the row around it stays.  A stale row
;;   answers `list-row-stale-p', so the base dims it and refuses to
;;   expand it.  Its cells print the object itself when it is gone,
;;   because `map-elt' signals on a killed window and a dead row must
;;   still reach the table; a refresh reads the tree again and drops
;;   the rows whose objects went away.
;; - The Kind cell prints the type of the object and the Mode cell a
;;   symbol name, so the column vector declares the face of each one.
;;   The demo paints nothing: the base reads the `:face' of a column
;;   and propertizes the text that it prints.

;;; Code:

(require 'list-mode)
(require 'list-mode-map)

(cl-defstruct (list-demo-row (:include list-map-tree-row)
                             (:constructor list-demo-row-create))
  "Row of the demo table.
`list-map-row-object' holds the live frame, window or buffer, and
`list-map-tree-row-child-maker' answers the next level.")

(defun list-demo--ensure-map-extras ()
  "Load `map-extras', or signal a `user-error' that names it."
  (unless (require 'map-extras nil t)
    (user-error "The list-mode demo needs the `map-extras' library"))
  t)

;;; Cells

(defun list-demo--live-p (object)
  "Return non-nil when OBJECT is a live frame, window or buffer."
  (pcase (type-of object)
    ('frame (frame-live-p object))
    ('window (window-live-p object))
    ('buffer (buffer-live-p object))
    (_ t)))

(defun list-demo--shown-buffer (object)
  "Return the buffer that the window OBJECT shows, or nil."
  (and (windowp object) (window-live-p object)
       (map-elt object 'buffer)))

(defun list-demo--name (object)
  "Return the text that names OBJECT.
A window names the live buffer that it shows, because the `map.el'
protocol gives a window no name of its own.  An object that went
away prints its representation, because its row still reaches the
table."
  (cond
   ((windowp object)
    (let ((buffer (list-demo--shown-buffer object)))
      (if (buffer-live-p buffer)
          (buffer-name buffer)
        (format "%s" object))))
   ((not (list-demo--live-p object))
    (format "%s" object))
   (t (or (map-elt object 'name)
          (format "%s" object)))))

(defun list-demo--kind (object)
  "Return the text of the kind of OBJECT."
  (symbol-name (type-of object)))

(defun list-demo--mode (object)
  "Return the major mode of OBJECT, or of the buffer that it shows."
  (let ((buffer (if (windowp object)
                    (list-demo--shown-buffer object)
                  object)))
    (if (and (buffer-live-p buffer) (map-elt buffer 'major-mode))
        (symbol-name (map-elt buffer 'major-mode))
      "")))

(defun list-demo--detail (object)
  "Return the detail text of OBJECT.
A frame reports its size and whether it is selected, a window its
start and point, and a buffer its size and point.  An object that
went away reports nothing."
  (if (not (list-demo--live-p object))
      ""
    (pcase (type-of object)
      ('frame (format "%sx%s%s"
                      (map-elt object 'width)
                      (map-elt object 'height)
                      (if (map-elt object 'selected) ", selected" "")))
      ('window (format "start %s, point %s"
                       (map-elt object 'start)
                       (map-elt object 'point)))
      ('buffer (format "%s bytes, point %s"
                       (map-elt object 'size)
                       (map-elt object 'point)))
      (_ ""))))

(cl-defmethod list-row-cells ((row list-demo-row) _columns)
  "Return the cells of the demo row ROW.
The row reads the keys of its own level, because a frame, a window
and a buffer share no key that would name them all."
  (let ((object (list-map-row-object row)))
    (vector (list-demo--name object)
            (list-demo--kind object)
            (list-demo--mode object)
            (list-demo--detail object))))

(cl-defmethod list-row-stale-p ((row list-demo-row))
  "Return non-nil when the object behind ROW is gone.
A frame, a window and the buffer of a window can all die while the
table still prints the row that named them."
  (not (list-demo--live-p (list-map-row-object row))))

;;; Children

(defun list-demo--child-key (row object)
  "Return the key of ROW for the child OBJECT.
The key of the parent stays in front, so two windows that show one
buffer still key their buffer rows apart."
  (append (list-row-key row)
          (list (type-of object) object)))

(defun list-demo--row (key object child-maker)
  "Return a demo row of KEY over OBJECT with CHILD-MAKER.
CHILD-MAKER answers the child rows of the row, or nil for a leaf."
  (list-demo-row-create :key key
                        :object object
                        :expandable (and child-maker t)
                        :child-maker child-maker))

(defun list-demo--window-rows (row)
  "Return one demo row per window of the frame of ROW."
  (mapcar (lambda (window)
            (list-demo--row (list-demo--child-key row window)
                            window
                            #'list-demo--buffer-rows))
          (window-list (list-map-row-object row) 'no-minibuf)))

(defun list-demo--buffer-rows (row)
  "Return one demo row for the buffer that the window of ROW shows."
  (let ((buffer (map-elt (list-map-row-object row) 'buffer)))
    (if (buffer-live-p buffer)
        (list (list-demo--row (list-demo--child-key row buffer)
                              buffer
                              nil))
      nil)))

(defun list-demo--top-rows ()
  "Return one demo row per live frame."
  (mapcar (lambda (frame)
            (list-demo--row (list 'frame frame)
                            frame
                            #'list-demo--window-rows))
          (frame-list)))

;;; Visiting

(cl-defmethod list-row-visit ((row list-demo-row))
  "Select the frame or window of ROW, or show its buffer."
  (let ((object (list-map-row-object row)))
    (pcase (type-of object)
      ('frame (select-frame object)
              (select-window (frame-selected-window object)))
      ('window (select-window object))
      ('buffer (pop-to-buffer object)))))

;;; The mode and the command

(defun list-demo--refresh ()
  "Rebuild the demo table from the live frames, windows and buffers."
  (let ((rows (list-demo--top-rows)))
    (if (equal rows list-mode-rows)
        ;; The wrappers compare `equal' while the objects under them
        ;; changed, so `list-mode-set-rows' would print nothing.  Drop
        ;; the cached children and print the rows again.
        (progn
          (mapc #'list-mode-forget-children list-mode-rows)
          (list-mode-reprint))
      (list-mode-set-rows rows))))

;;;###autoload
(define-derived-mode list-demo-mode list-mode "List-Demo"
  "Demo table of the live frames, their windows and their buffers.

The cells come from the `map.el' protocol, which `map-extras'
teaches to frames, windows and buffers.  A frame expands into its
windows, a window expands into the buffer that it displays, and
`g' reads the tree again.  A row whose frame, window or buffer went
away is stale: the table dims it and refuses to expand it, and it
never refreshes itself.  Turn on `auto-revert-mode' to let the table
follow the live windows."
  :interactive nil
  (list-demo--ensure-map-extras)
  (setq-local list-mode-columns
              [("Object" 24 t)
               ("Kind" 8 t :face font-lock-type-face)
               ("Mode" 16 t :face font-lock-function-name-face)
               ("Detail" 0 nil)])
  (setq-local list-mode-refresh-function #'list-demo--refresh)
  (list-mode-init))

;;;###autoload
(defun list-demo ()
  "Show a map-backed table of the frames, windows and buffers.
A frame expands into its windows, a window into the buffer that it
displays.  The table needs `map-extras' on the load path, because
builtin `map.el' covers no frame, window or buffer."
  (interactive)
  (list-demo--ensure-map-extras)
  (let ((buffer (get-buffer-create "*list-demo*")))
    (with-current-buffer buffer
      (list-demo-mode)
      (list-demo--refresh))
    (pop-to-buffer buffer)))

(provide 'list-mode-demo)
;;; list-mode-demo.el ends here
