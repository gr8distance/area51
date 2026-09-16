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

(test parse-asd-compound-and-defsystem-depends
  (let* ((dir (uiop:ensure-pathname
               (format nil "~aarea51-asd-compound-~a/"
                       (uiop:temporary-directory)
                       (get-universal-time))
               :ensure-directory t))
         (asd-path (merge-pathnames "ver.asd" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (with-open-file (out asd-path :direction :output)
             (write-string "(defsystem \"ver\"
  :defsystem-depends-on (\"cffi-grovel\")
  :depends-on ((:version \"alexandria\" \"1.0\")
               (:feature :sbcl \"osicat\"))
  :components ())" out))
           (let ((deps (area51::parse-asd-depends asd-path)))
             (is (member "cffi-grovel" deps :test #'string=))
             (is (member "alexandria" deps :test #'string=))
             (is (member "osicat" deps :test #'string=))
             (is (not (member "(version alexandria 1.0)" deps :test #'string=)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test parse-asd-keeps-deps-after-later-reader-error
  (let* ((dir (uiop:ensure-pathname
               (format nil "~aarea51-asd-reader-~a/"
                       (uiop:temporary-directory)
                       (get-universal-time))
               :ensure-directory t))
         (asd-path (merge-pathnames "mylib.asd" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (with-open-file (out asd-path :direction :output)
             (write-string "(defpackage #:mylib.internal (:use #:cl))
(defsystem \"mylib\" :depends-on (\"alexandria\"))
(defun mylib.internal::hidden () t)" out))
           (let ((deps (area51::parse-asd-depends asd-path)))
             (is (member "alexandria" deps :test #'string=))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test parse-asd-signals-when-no-defsystem-and-reader-error
  (let* ((dir (uiop:ensure-pathname
               (format nil "~aarea51-asd-bad-~a/"
                       (uiop:temporary-directory)
                       (get-universal-time))
               :ensure-directory t))
         (asd-path (merge-pathnames "bad.asd" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (with-open-file (out asd-path :direction :output)
             (write-string "(defun nowhere::missing () t)" out))
           (signals area51::asd-parse-error
             (area51::parse-asd-depends asd-path)))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test resolve-all-skips-test-asd-files
  (let* ((dir (uiop:ensure-pathname
               (format nil "~aarea51-asd-skip-test-~a/"
                       (uiop:temporary-directory)
                       (get-universal-time))
               :ensure-directory t)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (with-open-file (out (merge-pathnames "lib.asd" dir)
                                :direction :output)
             (write-string "(defsystem \"lib\" :depends-on () :components ())" out))
           (with-open-file (out (merge-pathnames "lib-test.asd" dir)
                                :direction :output)
             (write-string "(defsystem \"lib-test\" :depends-on (\"lift\") :components ())" out))
           (let ((resolved
                   (area51::resolve-all
                    (list :dependencies (list (list :name "lib")))
                    :resolve-dep-fn (lambda (dep)
                                      (declare (ignore dep))
                                      dir))))
             (is (null (find "lift" resolved
                             :key (lambda (p) (getf p :name))
                             :test #'string=)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test dep-is-github-detection
  "Correctly identifies GitHub vs Quicklisp deps."
  (is (area51::dep-is-github-p (list :name "lib" :url "https://github.com/user/lib.git")))
  (is (area51::dep-is-github-p (list :name "lib" :github "user/lib")))
  (is (not (area51::dep-is-github-p (list :name "alexandria")))))
