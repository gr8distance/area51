(in-package #:area51)

(defun parse-package-source (args)
  "Parse package source from arguments.
   Returns (values github url ref)."
  (let ((github nil)
        (url nil)
        (ref nil))
    (loop for (key val) on args by #'cddr
          do (cond
               ((string= key "--github")
                (setf github val
                      url (format nil "https://github.com/~a.git" val)))
               ((string= key "--url")
                (setf url val))
               ((string= key "--ref")
                (setf ref val))))
    (values github url ref)))

(defun cmd-add (args)
  "Add a dependency to the project"
  (when (null args)
    (format *error-output* "Usage: area51 add <package-name> [--github user/repo] [--url URL] [--ref REF]~%")
    (uiop:quit 1))
  (let* ((name (first args))
         (rest-args (rest args))
         (config (ensure-config)))
    (multiple-value-bind (github url ref)
        (parse-package-source rest-args)
      (let ((new-config (config-add-dep config name
                                        :github github
                                        :url url
                                        :ref ref)))
        (write-config new-config)
        ;; Update .asd file
        (let ((asd-path (find-project-asd (config-value config :name))))
          (when asd-path
            (asd-add-dep asd-path name)))
        (format t "Added ~a~%" name)))))
