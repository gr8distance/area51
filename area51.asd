(defsystem "area51"
  :version "0.1.0"
  :author ""
  :license "MIT"
  :description "Common Lisp Package Manager"
  :depends-on ()
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "config" :depends-on ("package"))
                 (:module "core"
                  :depends-on ("package" "config")
                  :components
                  ((:file "shell")
                   (:file "lisp-impl" :depends-on ("shell"))
                   (:file "resolver" :depends-on ("shell"))))
                 (:module "commands"
                  :depends-on ("package" "config" "core")
                  :components
                  ((:file "new")
                   (:file "add")
                   (:file "remove")
                   (:file "install")
                   (:file "build")
                   (:file "test")
                   (:file "run")))
                 (:file "main" :depends-on ("package" "commands"))))))
