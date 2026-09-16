(in-package #:area51)

(defun cmd-test (args)
  "Run project tests"
  (declare (ignore args))
  (let* ((config (ensure-config))
         (name (config-value config :name)))
    (format t "Running tests for ~a...~%" name)
    (multiple-value-bind (out code)
        (run-command
         (lisp-eval-argv
          (format nil "(asdf:test-system ~s)" name))
         :directory (uiop:getcwd)
         :output :interactive)
      (declare (ignore out))
      (unless (zerop code)
        (format *error-output* "Tests failed~%")
        (uiop:quit 1)))))
