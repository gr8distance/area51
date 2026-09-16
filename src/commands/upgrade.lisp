(in-package #:area51)

(defparameter *repo-url* "https://github.com/gr8distance/area51.git")

(defun cmd-upgrade (args)
  "Upgrade area51 itself to the latest version."
  (declare (ignore args))
  (let* ((build-dir (merge-pathnames "area51-update/" (uiop:temporary-directory)))
         (bin-path (uiop:argv0)))
    (format t "Updating area51...~%")
    (when (probe-file build-dir)
      (uiop:delete-directory-tree build-dir :validate t :if-does-not-exist :ignore))
    (run-command! (list "git" "clone" "--depth" "1" "--" *repo-url*
                        (namestring build-dir)))
    (format t "Building...~%")
    (run-command! (list "sbcl" "--noinform" "--non-interactive" "--load" "build.lisp")
                  :directory build-dir)
    (uiop:copy-file (merge-pathnames "bin/area51" build-dir) bin-path)
    (uiop:delete-directory-tree build-dir :validate t :if-does-not-exist :ignore)
    (format t "Updated. Run 'area51 -v' to verify.~%")))
