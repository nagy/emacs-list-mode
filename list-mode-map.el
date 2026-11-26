;;; list-mode-map.el --- Map-backed rows for list-mode tables -*- lexical-binding: t; -*-

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

;; Rows whose cells come from the `map.el' protocol.  A table over a
;; list of alists, plists or hash tables needs no row type of its own:
;;
;;   (setq-local list-mode-columns
;;               [("Name" 12 t :key name)
;;                ("Size" 6 t :key size)])
;;   (list-mode-init)
;;   (list-mode-set-rows
;;    (mapcar (lambda (alist)
;;              (list-map-row-create :key (map-elt alist 'name)
;;                                   :object alist))
;;            alists))
;;
;; The same row wraps a builtin object once `map-extras' teaches it
;; the protocol, so a window table needs no new row type either:
;;
;;   (setq-local list-mode-columns
;;               [("Buffer" 20 t :key buffer
;;                 :formatter (lambda (buffer) (buffer-name buffer)))
;;                ("Start" 8 t :key start)])
;;   (list-mode-set-rows
;;    (mapcar (lambda (window)
;;              (list-map-row-create :key window :object window))
;;            (window-list)))
;;
;; Design notes for a change in this file:
;;
;; - The row is a wrapper, not the object itself.  `list-row' holds
;;   the key and the expansion state, and the renderer writes both, so
;;   a raw window has no room for them.  A list of the same windows
;;   would also compare `equal' to itself, so `list-mode-set-rows'
;;   would print nothing after a change that the objects carried.
;; - The `:key' and `:formatter' of a column live in the plist of the
;;   column, the one in `list-mode-columns', and not in a second
;;   vector beside it: the fit, the header and the sort key all
;;   address that one vector by name, and `:pad-right' shows that a
;;   column property may be read outside the printer.
;; - The adapter is text-out.  `list-mode--cell-text' measures a cell
;;   for the fit and for the `t' sorter and answers an empty string
;;   for anything but a string or a `(TEXT . PROPERTIES)' cons, and
;;   the fit skips the flexible column, so a raw buffer or a plist in
;;   a cell would size its column to the header and print past it.
;;   The formatter therefore runs before a cell reaches the base, and
;;   the first cell stays a string for the indentation.
;; - The adapter tests no `mapp' and asks only `map-elt'.  A window
;;   without `map-extras' signals `cl-no-applicable-method' from
;;   `map-elt' itself, a string answers `mapp' without holding a
;;   symbol key, and a keymap answers `map-elt' while it reads as a
;;   plist to `map-contains-key', so the lookup is the only honest
;;   test.  A sentinel as the default of `map-elt' therefore tells an
;;   absent key from a held nil; a cell gated on `map-contains-key'
;;   prints empty for a keymap binding and for a transformed key.
;; - A live object changes under its row while two wrappers around the
;;   same object compare `equal', so a table of live objects refreshes
;;   through `list-mode-reprint', and not through
;;   `list-mode-set-rows', which would find no change.
;; - A plain map row is a leaf.  A table that expands derives from
;;   `list-map-tree-row' and answers the child rows of a row from its
;;   maker, so the adapter still holds no notion of a level.
;; - A tree row keys its children, and a key must stay unique in the
;;   whole table.  Two children of one parent therefore need distinct
;;   keys even when they wrap the same object, as two windows that
;;   show one buffer do; build the child key from the parent key.

;;; Code:

(require 'map)
(require 'list-mode)

(cl-defstruct (list-map-row (:include list-row)
                            (:constructor list-map-row-create))
  "Row whose cells come from a map.
OBJECT is the map that answers `map-elt' for the key of a column,
such as an alist, a plist, a hash table, or a builtin object that
`map-extras' covers."
  object)

(cl-defstruct (list-map-tree-row (:include list-map-row)
                                 (:constructor list-map-tree-row-create))
  "Map row that expands into the rows of a maker.
CHILD-MAKER is a function of the row that answers its child rows as
`list-row-children' documents, or nil for a row without child rows.
Set `:expandable' for a row whose maker answers child rows."
  child-maker)

(defconst list-map-row--missing (list :missing)
  "Value that stands for a key that the map of a row does not hold.
A list of its own serves as the default of `map-elt', so a held nil
stays distinct from an absent key.")

(defun list-map-row-elt (row key)
  "Return the value that ROW holds for KEY.
The answer comes through `map-elt', so every object that the
`map.el' protocol covers works.  A predicate sorter of a column
reads the values that it compares through this function."
  (declare (side-effect-free t))
  (map-elt (list-map-row-object row) key))

(defun list-map-row-cell-text (value)
  "Return VALUE as the text of a cell.
An absent value answers an empty string, a string answers itself, a
number answers its decimal text, and anything else answers the
`format' of `%s'.  A value that must print as a cons of text and
button properties takes a `:formatter' of its column."
  (cond
   ((null value) "")
   ((stringp value) value)
   ((numberp value) (number-to-string value))
   (t (format "%s" value))))

(defun list-map-row--cell (row column)
  "Return the cell of ROW for COLUMN.
A column without a `:key' answers an empty string, and so does a key
that the map of the row does not hold.  The value of a key that the
map holds passes through the `:formatter' of the column, or through
`list-map-row-cell-text'."
  (let* ((properties (nthcdr 3 column))
         (key (plist-get properties :key))
         (value (and key
                     (map-elt (list-map-row-object row) key
                              list-map-row--missing))))
    (if (or (not key) (eq value list-map-row--missing))
        ""
      (funcall (or (plist-get properties :formatter)
                   #'list-map-row-cell-text)
               value))))

(cl-defmethod list-row-cells ((row list-map-row) columns)
  "Return one cell of ROW for each of COLUMNS.
Each column reads its `:key' from the map of the row, so the row
type stays the same for every table that the adapter serves."
  (let ((cells (make-vector (length columns) "")))
    (dotimes (index (length columns))
      (aset cells index
            (list-map-row--cell row (aref columns index))))
    cells))

(cl-defmethod list-row-children ((row list-map-tree-row))
  "Return the child rows that the maker of ROW answers.
The base caches the answer on the row, so a maker runs once per
print of an expanded row, and a nil answer demotes the row."
  (when-let* ((maker (list-map-tree-row-child-maker row)))
    (funcall maker row)))

(provide 'list-mode-map)
;;; list-mode-map.el ends here
