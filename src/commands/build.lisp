(in-package #:area51)

(defun cmd-build (args)
  "Build the project into a standalone binary"
  (declare (ignore args))
  (let* ((config (ensure-config))
         (name (config-value config :name))
         (entry (string-upcase (or (config-value config :entry-point) "main")))
         (package (string-upcase name)))
    (ensure-directories-exist
     (merge-pathnames "bin/" (uiop:getcwd)))
    (format t "Building ~a...~%" name)
    (let ((bin-path (namestring (merge-pathnames
                                (format nil "bin/~a" name)
                                (uiop:getcwd)))))
      (multiple-value-bind (out code)
          (run-command
           (lisp-eval-command
            (uiop:getcwd)
            (format nil "(asdf:load-system ~s :verbose nil)" name)
            (lisp-save-image-form bin-path entry package)))
        (declare (ignore out))
        (if (zerop code)
            (format t "Built: bin/~a~%" name)
            (progn
              (format *error-output* "Build failed~%")
              (uiop:quit 1)))))))
