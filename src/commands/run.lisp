(in-package #:area51)

(defun cmd-run (args)
  "Run the project"
  (declare (ignore args))
  (let* ((config (ensure-config))
         (name (config-value config :name))
         (entry (or (config-value config :entry-point) "main")))
    (run-command
     (lisp-eval-command
      (uiop:getcwd)
      (format nil "(asdf:load-system ~s :verbose nil)" name)
      (format nil "(funcall (find-symbol ~s ~s))"
              (string-upcase entry) (string-upcase name)))
     :output :interactive)))
