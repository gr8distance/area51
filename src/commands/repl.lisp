(in-package #:area51)

(defparameter *default-repl-port* 4005
  "Default port for the slynk server started by 'area51 repl'.")

(defun parse-repl-port (args)
  "Parse --port N from args, return integer or nil."
  (loop for (k v) on args by #'cddr
        when (and (stringp k) (string= k "--port") v)
          return (ignore-errors (parse-integer v))))

(defun cmd-repl (args)
  "Start a slynk server with the project loaded, for SLY/SLIME connect."
  (let* ((config (ensure-config))
         (name (config-value config :name))
         (port (or (parse-repl-port args) *default-repl-port*)))
    (format t "area51: loading ~a and starting slynk on port ~d~%" name port)
    (format t "area51: connect with M-x sly-connect RET 127.0.0.1 RET ~d RET~%" port)
    (format t "area51: Ctrl-C to stop~%~%")
    (run-command
     (lisp-eval-command
      (uiop:getcwd)
      (format nil "(asdf:load-system ~s :verbose nil)" name)
      "(handler-case (asdf:load-system :slynk :verbose nil) (error (e) (format *error-output* \"area51: could not load slynk: ~a~%area51: install slynk via Quicklisp or add it as a dep.~%\" e) (uiop:quit 1)))"
      (format nil
              "(handler-case ~
                 (funcall (find-symbol \"CREATE-SERVER\" :slynk) ~
                          :port ~d :dont-close t) ~
                 (sb-bsd-sockets:address-in-use-error () ~
                   (format *error-output* ~
                           \"area51: port ~d is already in use.~~%~
                            area51: pass --port N to pick another port.~~%\") ~
                   (uiop:quit 1)))"
              port port)
      (format nil
              "(handler-case (loop (sleep 3600)) ~
                 (sb-sys:interactive-interrupt () ~
                   (format t \"~~&area51: stopping slynk...~~%\") ~
                   (ignore-errors ~
                     (funcall (find-symbol \"STOP-SERVER\" :slynk) ~d)) ~
                   (uiop:quit 0)))"
              port))
     :output :interactive)))
