(in-package #:area51)

(defun cmd-install (args)
  "Install dependencies. Restore from area51.lock when it covers the config;
   otherwise resolve and rewrite the lock. Empty deps always write an empty lock."
  (declare (ignore args))
  (let* ((config (ensure-config))
         (lock (read-lock))
         (plan (install-plan config lock)))
    (ecase plan
      (:empty
       (write-lock (list :dist-version (getf lock :dist-version)
                         :depends nil
                         :packages nil))
       (format t "No dependencies to install~%"))
      (:restore
       (format t "Restoring ~d package~:p from lock...~%"
               (length (getf lock :packages)))
       (restore-lock lock)
       (format t "~%Restored ~d package~:p.~%"
               (length (getf lock :packages))))
      (:resolve
       (format t "Installing ~d package~:p...~%"
               (length (config-dependencies config)))
       (let* ((dist-version (ensure-quicklisp-index))
              (resolved (resolve-all config)))
         (write-lock (list :dist-version dist-version
                           :depends (config-dep-names config)
                           :packages (mapcar #'lock-entry-from-resolved resolved)))
         (format t "~%Resolved ~d package~:p. Lock file written.~%"
                 (length resolved)))))))
