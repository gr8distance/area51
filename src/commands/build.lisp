(in-package #:area51)

(defun parse-build-verbose (args)
  "Check if --verbose flag is present in args"
  (member "--verbose" args :test #'string=))

(defun cmd-build (args)
  "Build the project into a standalone binary"
  (let* ((verbose (parse-build-verbose args))
         (config (ensure-config))
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
            (format nil "(asdf:load-system ~s :verbose ~a)" name (if verbose "t" "nil"))
            (lisp-save-image-form bin-path entry package))
           :output (if verbose :interactive :string))
        (declare (ignore out))
        (if (zerop code)
            (format t "Built: bin/~a~%" name)
            (progn
              (format *error-output* "Build failed~%")
              (uiop:quit 1)))))))
