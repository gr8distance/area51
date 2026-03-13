(in-package #:area51)

(defun parse-install-mode (args)
  "Parse --production flag from args."
  (if (member "--production" args :test #'string=)
      :production
      :all))

(defun cmd-install (args)
  "Install dependencies.
   --production  only ungrouped deps (no dev-deps)"
  (let* ((mode (parse-install-mode args))
         (config (ensure-config))
         (deps (config-dependencies-for config mode)))
    (if (null deps)
        (format t "No dependencies to install~%")
        (progn
          (format t "Installing ~d package~:p (~a)...~%" (length deps) mode)
          (let ((resolved (resolve-all config :mode mode)))
            (write-lock (list :packages resolved))
            (format t "Done. Lock file written.~%"))))))
