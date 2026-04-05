(in-package #:area51)

(defun cmd-install (args)
  "Install all dependencies."
  (declare (ignore args))
  (let* ((config (ensure-config))
         (deps (config-dependencies config)))
    (if (null deps)
        (format t "No dependencies to install~%")
        (progn
          (format t "Installing ~d package~:p...~%" (length deps))
          (let* ((dist-version (ensure-quicklisp-index))
                 (resolved (resolve-all config)))
            (write-lock (list :dist-version dist-version
                              :packages resolved))
            (format t "~%Resolved ~d package~:p. Lock file written.~%"
                    (length resolved)))))))
