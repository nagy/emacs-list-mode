;;; list-mode-test-helper.el --- Fixtures of the list-mode suites -*- lexical-binding: t; -*-

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

;; The row type, the mode and the helpers that the list-mode suites
;; share.  This file carries no `-test.el' suffix, so the
;; `test/*-test.el' glob of the flake loads it only through the
;; `require' of a suite.
;;
;; A fixture row holds a name, a size and a note, so one column
;; format serves every test: a text column, a numeric column that
;; sorts as text, and a flexible last column.  A row answers :pending
;; for its child rows when the test marks it slow, which is how the
;; asynchronous expansion path gets a test without a process.

;;; Code:

(require 'list-mode)

(cl-defstruct (list-mode-test-row (:include list-row)
                                  (:constructor list-mode-test-row-create))
  "Row of the fixture table.
NAME is the first cell, SIZE the second and NOTE the third.  KIDS
holds the child rows that `list-row-children' answers, and SLOW
makes that answer :pending."
  name
  size
  note
  kids
  slow)

(cl-defmethod list-row-cells ((row list-mode-test-row) _columns)
  "Return the cells of the fixture row ROW."
  (vector (or (list-mode-test-row-name row) "")
          (number-to-string (or (list-mode-test-row-size row) 0))
          (or (list-mode-test-row-note row) "")))

(cl-defmethod list-row-children ((row list-mode-test-row))
  "Return the child rows that the fixture row ROW holds."
  (if (list-mode-test-row-slow row)
      :pending
    (list-mode-test-row-kids row)))

(defvar list-mode-test-visited nil
  "Keys that the fixture visit method recorded, newest first.")

(cl-defmethod list-row-visit ((row list-mode-test-row))
  "Record the key of ROW as visited."
  (push (list-row-key row) list-mode-test-visited))

(cl-defstruct (list-mode-test-tiny-row (:include list-row))
  "Row of the fixture table that defines a single cell."
  label)

(cl-defmethod list-row-cells ((row list-mode-test-tiny-row) _columns)
  "Return the one cell of the tiny row ROW."
  (vector (or (list-mode-test-tiny-row-label row) "")))

(defun list-mode-test-row (key name &rest properties)
  "Return a fixture row of KEY and NAME.
PROPERTIES is a plist of :size, :note, :kids and :slow.  The row is
expandable when it holds child rows or a slow fetch."
  (let* ((slow (plist-get properties :slow))
         (kids (plist-get properties :kids))
         (row (list-mode-test-row-create
               :key key
               :name name
               :size (plist-get properties :size)
               :note (plist-get properties :note)
               :kids kids
               :slow slow)))
    (setf (list-row-expandable row) (and (or kids slow) t))
    row))

(defvar list-mode-test-sort nil
  "Sort state that `list-mode-test-mode' installs.
Bind the variable around the mode call to start a sorted table.")

(define-derived-mode list-mode-test-mode list-mode "List-Test"
  "Fixture mode of the list-mode suites.
The three columns are a text column that sorts, a second text
column that sorts and a flexible last column without a sorter."
  :interactive nil
  (setq-local list-mode-columns
              [("Name" 12 t)
               ("Size" 6 t)
               ("Note" 0 nil)])
  (setq-local list-mode-default-sort-key list-mode-test-sort)
  (list-mode-init))

(defmacro list-mode-test--with-table (rows &rest body)
  "Print ROWS in a fresh fixture table and run BODY.
Point starts on the first line of the table."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (list-mode-test-mode)
     (list-mode-set-rows ,rows)
     (goto-char (point-min))
     ,@body))

(defun list-mode-test--goto-row (key)
  "Move point to the first line of the row of KEY.
Return non-nil when the function found the row."
  (goto-char (point-min))
  (let ((found nil))
    (while (and (not found) (not (eobp)))
      (if (equal key (list-mode-key-at-point))
          (setq found t)
        (forward-line 1)))
    found))

(defun list-mode-test--visible-keys ()
  "Return the keys of the printed rows, in display order."
  (mapcar (lambda (pair) (list-row-key (car pair)))
          (list-mode-visible-rows)))

(defun list-mode-test--visible-depths ()
  "Return the depths of the printed rows, in display order."
  (mapcar #'cdr (list-mode-visible-rows)))

(defun list-mode-test--mark-rows (first last)
  "Activate a region that covers the rows of keys FIRST through LAST.
The region ends at the beginning of the line of LAST, and the row of
LAST joins the answer."
  (setq-local transient-mark-mode t)
  (list-mode-test--goto-row first)
  (beginning-of-line)
  (push-mark (point) t t)
  (list-mode-test--goto-row last)
  (beginning-of-line))

(defun list-mode-test--line ()
  "Return the text of the current line without its properties."
  (buffer-substring-no-properties (line-beginning-position)
                                  (line-end-position)))

(provide 'list-mode-test-helper)
;;; list-mode-test-helper.el ends here
