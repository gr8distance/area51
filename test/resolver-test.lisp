(in-package #:area51-test)

(def-suite resolver-tests :in area51-tests)
(in-suite resolver-tests)

(test builtin-system-detection
  "Built-in systems are recognized."
  (is (area51::builtin-system-p "asdf"))
  (is (area51::builtin-system-p "uiop"))
  (is (area51::builtin-system-p "sb-posix"))
  (is (area51::builtin-system-p "sb-concurrency"))
  (is (not (area51::builtin-system-p "alexandria")))
  (is (not (area51::builtin-system-p "cl-ppcre"))))

(test parse-asd-depends-basic
  "Extract :depends-on from a .asd file."
  (let* ((dir (uiop:ensure-pathname
               (format nil "~aarea51-asd-test-~a/"
                       (uiop:temporary-directory)
                       (get-universal-time))
               :ensure-directory t))
         (asd-path (merge-pathnames "test-lib.asd" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (with-open-file (out asd-path :direction :output)
             (write-string "(defsystem \"test-lib\"
                              :depends-on (\"alexandria\" \"cl-ppcre\")
                              :components ((:file \"main\")))" out))
           (let ((deps (area51::parse-asd-depends asd-path)))
             (is (= 2 (length deps)))
             (is (member "alexandria" deps :test #'string=))
             (is (member "cl-ppcre" deps :test #'string=))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test parse-asd-depends-empty
  "Empty :depends-on returns nil."
  (let* ((dir (uiop:ensure-pathname
               (format nil "~aarea51-asd-empty-~a/"
                       (uiop:temporary-directory)
                       (get-universal-time))
               :ensure-directory t))
         (asd-path (merge-pathnames "empty.asd" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (with-open-file (out asd-path :direction :output)
             (write-string "(defsystem \"empty\"
                              :depends-on ()
                              :components ((:file \"main\")))" out))
           (is (null (area51::parse-asd-depends asd-path))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test dep-is-github-detection
  "Correctly identifies GitHub vs Quicklisp deps."
  (is (area51::dep-is-github-p (list :name "lib" :url "https://github.com/user/lib.git")))
  (is (area51::dep-is-github-p (list :name "lib" :github "user/lib")))
  (is (not (area51::dep-is-github-p (list :name "alexandria")))))
