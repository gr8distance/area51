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
          (let* ((dist-version (ensure-quicklisp-index))
                 (resolved (resolve-all config :mode mode)))
            (write-lock (list :dist-version dist-version
                              :packages resolved))
            (format t "~%Resolved ~d package~:p. Lock file written.~%"
                    (length resolved)))))))
