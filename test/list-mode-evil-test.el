;;; list-mode-evil-test.el --- ERT tests for the evil layer -*- lexical-binding: t; -*-

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

;; Tests for the optional evil layer: the setup on `evil-after-load-hook',
;; the auto-enable hook, the key table and the evil motions that the layer
;; leaves alone.  The suite needs evil on the load path, and the flake
;; supplies it.

;;; Code:

(require 'ert)

(require 'list-mode-evil)

(require 'list-mode-test-helper)

(defun list-mode-evil-test--binding (key)
  "Return the command that KEY runs in the current list buffer."
  (key-binding (kbd key)))

(ert-deftest list-mode-evil-auto-enable-turns-the-layer-on ()
  "A fixture buffer takes the evil layer from `list-mode-hook'."
  (with-temp-buffer
    (list-mode-test-mode)
    (should list-mode-evil-mode)))

(ert-deftest list-mode-evil-auto-enable-nil-keeps-the-layer-off ()
  "The option keeps the hook from enabling the layer."
  (let ((list-mode-evil-auto-enable nil))
    (with-temp-buffer
      (list-mode-test-mode)
      (should-not list-mode-evil-mode)
      (list-mode-evil-mode 1)
      (should list-mode-evil-mode))))

(ert-deftest list-mode-evil-setup-awaits-evil ()
  "The entry library puts the setup on `evil-after-load-hook'."
  (should (memq 'list-mode-evil-auto-setup evil-after-load-hook)))

(ert-deftest list-mode-evil-auto-setup-reaches-an-open-table ()
  "A setup enables the layer in a list table that is already open."
  (let ((list-mode-evil-auto-enable nil))
    (with-temp-buffer
      (list-mode-test-mode)
      (should-not list-mode-evil-mode)
      (let ((list-mode-evil-auto-enable t))
        (list-mode-evil-auto-setup))
      (should list-mode-evil-mode))))

(ert-deftest list-mode-evil-binds-the-table-commands ()
  "The normal state reaches the commands of the base mode."
  (with-temp-buffer
    (list-mode-test-mode)
    (evil-normal-state)
    (should (eq 'list-mode-toggle-row
                (list-mode-evil-test--binding "TAB")))
    (should (eq 'list-mode-visit-row
                (list-mode-evil-test--binding "RET")))
    (should (eq 'list-mode-sort
                (list-mode-evil-test--binding "S")))
    (should (eq 'list-mode-expand-row
                (list-mode-evil-test--binding "zo")))
    (should (eq 'list-mode-collapse-row
                (list-mode-evil-test--binding "zc")))
    (should (eq 'list-mode-toggle-row
                (list-mode-evil-test--binding "za")))
    (should (eq 'list-mode-expand-all
                (list-mode-evil-test--binding "zR")))
    (should (eq 'list-mode-collapse-all
                (list-mode-evil-test--binding "zM")))))

(ert-deftest list-mode-evil-leaves-the-motions-alone ()
  "The layer binds no evil motion."
  (with-temp-buffer
    (list-mode-test-mode)
    (evil-normal-state)
    (should (eq 'evil-next-line
                (list-mode-evil-test--binding "j")))
    (should (eq 'evil-previous-line
                (list-mode-evil-test--binding "k")))
    (should (eq 'evil-goto-line
                (list-mode-evil-test--binding "G")))))

(ert-deftest list-mode-evil-visual-selection-answers-region-rows ()
  "A visual line range reaches the region reader of the base mode.
The range starts at the row at point, not at the top of the table."
  (let ((b (list-mode-test-row "b" "beta"))
        (c (list-mode-test-row "c" "gamma")))
    (with-temp-buffer
      (list-mode-test-mode)
      (evil-local-mode 1)
      (evil-normal-state)
      (list-mode-set-rows (list (list-mode-test-row "a" "alpha") b c))
      (list-mode-test--goto-row "b")
      (evil-visual-line)
      (call-interactively 'evil-next-line)
      (should (equal (list b c) (list-mode-region-rows))))))

(ert-deftest list-mode-evil-expanded-range-reaches-the-line-below ()
  "A linewise range ends on the line below, so a command excludes the newline.
The expanded range of a linewise selection ends at the beginning of the
line below the selection, which names a row of its own, so a command of
the layer carries `:exclude-newline', and the newline of the last
selected row then names that row alone."
  (let ((a (list-mode-test-row "a" "alpha"))
        (b (list-mode-test-row "b" "beta"))
        (c (list-mode-test-row "c" "gamma")))
    (with-temp-buffer
      (list-mode-test-mode)
      (evil-local-mode 1)
      (evil-normal-state)
      (list-mode-set-rows (list a b c))
      (setq-local transient-mark-mode t)
      (goto-char (point-min))
      (push-mark (point) t t)
      (goto-char (line-beginning-position 3))
      (should (equal (list a b c) (list-mode-region-rows)))
      (goto-char (1- (line-beginning-position)))
      (should (equal (list a b) (list-mode-region-rows))))))

(ert-deftest list-mode-evil-tab-expands-the-row-at-point ()
  "The bound key runs the expansion of the base mode."
  (let ((row (list-mode-test-row
              "a" "alpha"
              :kids (list (list-mode-test-row "a1" "one")))))
    (with-temp-buffer
      (list-mode-test-mode)
      (list-mode-set-rows (list row))
      (evil-normal-state)
      (goto-char (point-min))
      (call-interactively (list-mode-evil-test--binding "TAB"))
      (should (list-row-expanded row))
      (should (equal '("a" "a1") (list-mode-test--visible-keys))))))

(ert-deftest list-mode-evil-mode-off-restores-the-state-keys ()
  "Turning the layer off gives the normal state its own keys back."
  (with-temp-buffer
    (list-mode-test-mode)
    (evil-normal-state)
    (list-mode-evil-mode -1)
    (should (eq 'evil-jump-forward
                (list-mode-evil-test--binding "TAB")))))

(provide 'list-mode-evil-test)
;;; list-mode-evil-test.el ends here
