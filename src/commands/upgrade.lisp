(in-package #:area51)

(defparameter *repo-url* "https://github.com/gr8distance/area51.git")

(defun cmd-upgrade (args)
  "Upgrade area51 itself to the latest version."
  (declare (ignore args))
  (let* ((build-dir (format nil "~aarea51-update/"
                            (uiop:temporary-directory)))
         (bin-path (uiop:argv0)))
    (format t "Updating area51...~%")
    ;; Clone latest
    (run-command! (format nil "rm -rf ~a" build-dir))
    (run-command! (format nil "git clone --depth 1 ~a ~a" *repo-url* build-dir))
    ;; Build
    (format t "Building...~%")
    (run-command!
     (format nil "cd ~a && sbcl --noinform --non-interactive --load build.lisp"
             build-dir))
    ;; Replace binary
    (let ((new-bin (format nil "~abin/area51" build-dir)))
      (run-command! (format nil "cp ~a ~a" new-bin bin-path)))
    ;; Cleanup
    (run-command! (format nil "rm -rf ~a" build-dir))
    ;; Show new version
    (format t "Updated. Run 'area51 -v' to verify.~%")))
