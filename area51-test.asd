(defsystem "area51-test"
  :description "Tests for area51"
  :license "MIT"
  :depends-on ("area51" "fiveam")
  :components ((:module "test"
                :components
                ((:file "package")
                 (:file "config-test" :depends-on ("package"))
                 (:file "resolver-test" :depends-on ("package"))
                 (:file "quicklisp-test" :depends-on ("package")))))
  :perform (test-op (op c)
             (uiop:symbol-call :fiveam :run!
                               (uiop:find-symbol* :area51-tests :area51-test))))
