(in-package #:area51)

(defun cmd-remove (args)
  "Remove a dependency from the project"
  (when (null args)
    (format *error-output* "Usage: area51 remove <package-name>~%")
    (uiop:quit 1))
  (let* ((name (first args))
         (config (ensure-config))
         (deps (config-dependencies config)))
    (if (find name deps :key (lambda (d) (getf d :name)) :test #'string=)
        (let ((new-config (config-remove-dep config name)))
          (write-config new-config)
          ;; Update .asd file
          (let ((asd-path (find-project-asd (config-value config :name))))
            (when asd-path
              (asd-remove-dep asd-path name)))
          (format t "Removed ~a~%" name))
        (format *error-output* "Package ~a not found in dependencies~%" name))))
