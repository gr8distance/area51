(in-package #:area51)

(defparameter *default-repl-port* 4005
  "Default port for the slynk server started by 'area51 repl'.")

(defun parse-repl-port (args)
  "Parse --port N from args, return integer or nil."
  (loop for (k v) on args by #'cddr
        when (and (stringp k) (string= k "--port") v)
          return (ignore-errors (parse-integer v))))

(defun repl-sbcl-argv (project-name port)
  "Build an argv list (no shell) that launches sbcl to host a slynk server.
   Running as a direct child (without an intermediate /bin/sh) means Ctrl-C
   in the parent can be explicitly forwarded to this process via its PID."
  (list "sbcl" "--noinform" "--non-interactive"
        "--eval" "(require :asdf)"
        "--eval" "(setf asdf:*asdf-verbose* nil)"
        "--eval" (asdf-setup-form)
        "--eval" "(push *default-pathname-defaults* asdf:*central-registry*)"
        "--eval" (format nil "(asdf:load-system ~s :verbose nil)" project-name)
        "--eval" (concatenate 'string
                              "(handler-case (asdf:load-system :slynk :verbose nil) "
                              "(error (e) "
                              "(format *error-output* \"area51: could not load slynk: ~a~%area51: install slynk via Quicklisp or add it as a dep.~%\" e) "
                              "(uiop:quit 1)))")
        "--eval" (format nil
                         "(handler-case (funcall (find-symbol \"CREATE-SERVER\" :slynk) :port ~d :dont-close t) (sb-bsd-sockets:address-in-use-error () (format *error-output* \"area51: port ~d is already in use.~~%area51: pass --port N to pick another port.~~%\") (uiop:quit 1)))"
                         port port)
        "--eval" (format nil
                         "(handler-case (loop (sleep 3600)) (sb-sys:interactive-interrupt () (format t \"~~&area51: stopping slynk...~~%\") (ignore-errors (funcall (find-symbol \"STOP-SERVER\" :slynk) ~d)) (uiop:quit 0)))"
                         port)))

(defun cmd-repl (args)
  "Start a slynk server with the project loaded, for SLY/SLIME connect."
  (let* ((config (ensure-config))
         (name (config-value config :name))
         (port (or (parse-repl-port args) *default-repl-port*)))
    (format t "area51: loading ~a and starting slynk on port ~d~%" name port)
    (format t "area51: connect with M-x sly-connect RET 127.0.0.1 RET ~d RET~%" port)
    (format t "area51: Ctrl-C to stop~%~%")
    (let ((process (uiop:launch-program
                    (repl-sbcl-argv name port)
                    :directory (uiop:getcwd)
                    :output :interactive
                    :error-output :interactive)))
      (unwind-protect
          (handler-case
              (uiop:wait-process process)
            (sb-sys:interactive-interrupt ()
              (format t "~&area51: shutting down...~%")
              ;; The child installs a handler for SIGINT that calls
              ;; slynk:stop-server, so forwarding SIGINT (not SIGTERM) gives
              ;; us a clean socket release.
              (ignore-errors
                (uiop:run-program
                 (list "kill" "-INT"
                       (princ-to-string (uiop:process-info-pid process)))
                 :ignore-error-status t))
              (ignore-errors (uiop:wait-process process))
              (uiop:quit 0)))
        (when (uiop:process-alive-p process)
          (ignore-errors (uiop:terminate-process process :urgent t)))))))
