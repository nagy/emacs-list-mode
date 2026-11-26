;;; list-mode-evil.el --- Evil bindings for list-mode tables -*- lexical-binding: t; -*-

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

;; Optional evil layer for `list-mode'.  The package does not depend
;; on evil, so a user without it installs nothing.  The entry library
;; loads this file once evil loads, and enables `list-mode-evil-mode'
;; in every list table while the option `list-mode-evil-auto-enable'
;; holds, which is the default.  A user who wants the bindings without
;; that wait loads the file and turns the mode on:
;;
;;   (require 'list-mode-evil)
;;   (list-mode-evil-mode 1)
;;
;; The load that the entry library starts runs inside
;; `evil-after-load-hook', which evil calls before it provides its
;; feature, so this file requires evil only when its functions are
;; absent.
;;
;; Evil state maps take precedence over a major mode map, so a command
;; key reaches a list buffer only through a state binding.
;; `list-mode-evil-mode' is a buffer-local minor mode, and
;; `evil-define-minor-mode-key' puts its map ahead of the state maps
;; while the mode variable holds a value.  The evil motions stay
;; untouched: `j', `k', `gg', `G', `C-d', `C-u', `/', `n' and `N'
;; keep their meaning.
;;
;;   TAB      expand or collapse the row at point
;;   RET      visit the row at point
;;   zo       expand the row at point
;;   zc       collapse the row at point
;;   za       expand or collapse the row at point
;;   zR       expand every row that the table shows
;;   zM       collapse every row that the table shows
;;   S        sort by the column at point
;;   <mouse-2> visit the row under the mouse
;;
;; Design notes for a change in this file:
;;
;; - `evil-define-key' is a macro, so the table goes through the
;;   function `evil-define-minor-mode-key' instead.  A string key is
;;   parsed with `key-parse' first, because `define-key' reads "TAB" as
;;   four characters.  A remap entry stays a `[remap COMMAND]' vector:
;;   `key-parse' would turn the vector into literal characters.
;; - TAB is C-i, the jump of the evil jump list, in the normal state.
;;   A list table expands a row instead, which is the whole point of
;;   the mode.
;; - Turning the minor mode off needs no key removal: Emacs activates
;;   the map of `evil-define-minor-mode-key' only while the mode
;;   variable holds a value.

;;; Code:

(declare-function evil-define-minor-mode-key "evil" (state mode key def))

;; Evil defines `evil-define-minor-mode-key' before it provides its
;; feature, and `evil-after-load-hook' runs between the two, so a plain
;; `require' of evil recurses at that moment.  Load evil only when its
;; functions are absent.
(unless (fboundp 'evil-define-minor-mode-key)
  (require 'evil))

(require 'list-mode)

(defvar list-mode-evil-keys
  '(([remap evil-ret] . list-mode-visit-row)
    ([remap evil-change-whole-line] . list-mode-sort)
    ("TAB" . list-mode-toggle-row)
    ("zo" . list-mode-expand-row)
    ("zc" . list-mode-collapse-row)
    ("za" . list-mode-toggle-row)
    ("zR" . list-mode-expand-all)
    ("zM" . list-mode-collapse-all)
    ("<mouse-2>" . list-mode-mouse-visit))
  "Keys that `list-mode-evil-mode' binds in the normal state.
A key is a key string or a `[remap COMMAND]' vector, and the value
is the command to run.")

(defun list-mode-evil--key (key)
  "Return KEY as a key sequence for `define-key'."
  (if (stringp key) (key-parse key) key))

(defun list-mode-evil--install ()
  "Bind `list-mode-evil-keys' for the current buffer."
  (dolist (pair list-mode-evil-keys)
    (evil-define-minor-mode-key 'normal 'list-mode-evil-mode
                                (list-mode-evil--key (car pair))
                                (cdr pair))))

(defun list-mode-evil--auto-enable ()
  "Enable `list-mode-evil-mode' in a list table when the option allows."
  (when list-mode-evil-auto-enable
    (list-mode-evil-mode 1)))

;;;###autoload
(define-minor-mode list-mode-evil-mode
  "Evil bindings for the list table of the current buffer.
The mode binds the commands of `list-mode' in the normal evil
state, and the keys of the major mode reach every other state."
  :lighter nil
  :group 'list
  (when list-mode-evil-mode
    (list-mode-evil--install)))

(provide 'list-mode-evil)
;;; list-mode-evil.el ends here
