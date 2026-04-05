(in-package #:area51)

(defun cmd-clean (args)
  "Clean the global package cache (~/.area51/)."
  (declare (ignore args))
  (let ((dir (namestring *area51-home*)))
    (if (probe-file dir)
        (progn
          (uiop:delete-directory-tree
           (pathname dir) :validate t :if-does-not-exist :ignore)
          (format t "Cleaned ~a~%" dir))
        (format t "Nothing to clean.~%"))))
