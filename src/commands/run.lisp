(in-package #:area51)

(defun cmd-run (args)
  "Run the project"
  (declare (ignore args))
  (let* ((config (ensure-config))
         (name (config-value config :name))
         (entry (or (config-value config :entry-point) "main")))
    (quit-unless-zero
     (nth-value 1
                (run-command
                 (lisp-eval-argv
                  (format nil "(asdf:load-system ~s :verbose nil)" name)
                  (format nil "(funcall (find-symbol ~s ~s))"
                          (string-upcase entry) (string-upcase name)))
                 :directory (uiop:getcwd)
                 :output :interactive)))))
