(defsystem "area51-test"
  :description "Tests for area51"
  :license "MIT"
  :depends-on ("area51" "fiveam")
  :components ((:module "test"
                :components
                ((:file "package")
                 (:file "config-test" :depends-on ("package"))
                 (:file "resolver-test" :depends-on ("package"))
                 (:file "status-test" :depends-on ("package"))
                 (:file "shell-test" :depends-on ("package"))
                 (:file "quicklisp-test" :depends-on ("package"))
                 (:file "lock-test" :depends-on ("package" "status-test")))))
  :perform (test-op (op c)
             (declare (ignore op c))
             (uiop:symbol-call :area51-test :run-tests)))
