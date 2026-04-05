(in-package #:area51-test)

(def-suite config-tests :in area51-tests)
(in-suite config-tests)

;;; --- parse-config-forms ---

(test parse-project-basic
  "Parse a minimal project form."
  (let ((config (area51::parse-config-forms
                 '((project "my-app" :version "1.0" :license "MIT"
                    :entry-point "main")))))
    (is (string= "my-app" (getf config :name)))
    (is (string= "1.0" (getf config :version)))
    (is (string= "MIT" (getf config :license)))
    (is (string= "main" (getf config :entry-point)))))

(test parse-project-defaults
  "Missing keys get defaults."
  (let ((config (area51::parse-config-forms '((project "app")))))
    (is (string= "app" (getf config :name)))
    (is (string= "0.1.0" (getf config :version)))
    (is (string= "MIT" (getf config :license)))
    (is (string= "main" (getf config :entry-point)))))

(test parse-deps-quicklisp
  "Deps without :github are Quicklisp (no :url, no :github)."
  (let* ((config (area51::parse-config-forms
                  '((project "app")
                    (deps ("alexandria") ("cl-ppcre")))))
         (deps (getf config :dependencies)))
    (is (= 2 (length deps)))
    (is (string= "alexandria" (getf (first deps) :name)))
    (is (null (getf (first deps) :github)))
    (is (null (getf (first deps) :url)))))

(test parse-deps-github
  "Deps with :github get url resolved."
  (let* ((config (area51::parse-config-forms
                  '((project "app")
                    (deps ("my-lib" :github "user/my-lib")))))
         (dep (first (getf config :dependencies))))
    (is (string= "my-lib" (getf dep :name)))
    (is (string= "user/my-lib" (getf dep :github)))
    (is (string= "https://github.com/user/my-lib.git" (getf dep :url)))))

(test parse-deps-with-ref
  "Deps can pin a ref."
  (let* ((config (area51::parse-config-forms
                  '((project "app")
                    (deps ("lib" :github "user/lib" :ref "v1.0")))))
         (dep (first (getf config :dependencies))))
    (is (string= "v1.0" (getf dep :ref)))))

(test parse-dev-deps
  "dev-deps get :groups :dev."
  (let* ((config (area51::parse-config-forms
                  '((project "app")
                    (deps ("alexandria"))
                    (dev-deps ("fiveam" :github "lispci/fiveam")))))
         (deps (getf config :dependencies)))
    (is (= 2 (length deps)))
    (let ((dev-dep (find "fiveam" deps :key (lambda (d) (getf d :name))
                                       :test #'string=)))
      (is (eq :dev (getf dev-dep :groups))))))

;;; --- config-add-dep / config-remove-dep ---

(test add-dep-to-config
  "Adding a dep appends to dependencies."
  (let* ((config (list :name "app" :dependencies nil))
         (new (area51::config-add-dep config "alexandria")))
    (is (= 1 (length (getf new :dependencies))))
    (is (string= "alexandria" (getf (first (getf new :dependencies)) :name)))))

(test add-duplicate-dep
  "Adding a duplicate dep does nothing."
  (let* ((config (list :name "app"
                       :dependencies (list (list :name "alexandria"))))
         (new (area51::config-add-dep config "alexandria")))
    (is (= 1 (length (getf new :dependencies))))))

(test remove-dep-from-config
  "Removing a dep removes it."
  (let* ((config (list :name "app"
                       :dependencies (list (list :name "alexandria")
                                           (list :name "cl-ppcre"))))
         (new (area51::config-remove-dep config "alexandria")))
    (is (= 1 (length (getf new :dependencies))))
    (is (string= "cl-ppcre" (getf (first (getf new :dependencies)) :name)))))

;;; --- config-dependencies-for ---

(test deps-for-all
  "Mode :all returns everything."
  (let ((config (list :name "app"
                      :dependencies (list (list :name "a")
                                          (list :name "b" :groups :dev)))))
    (is (= 2 (length (area51::config-dependencies-for config :all))))))

(test deps-for-production
  "Mode :production excludes :dev."
  (let ((config (list :name "app"
                      :dependencies (list (list :name "a")
                                          (list :name "b" :groups :dev)))))
    (is (= 1 (length (area51::config-dependencies-for config :production))))
    (is (string= "a" (getf (first (area51::config-dependencies-for config :production)) :name)))))

;;; --- write/read roundtrip ---

(test config-roundtrip
  "write-config then read-config produces equivalent config."
  (let* ((dir (uiop:ensure-pathname
               (format nil "~aarea51-test-~a/"
                       (uiop:temporary-directory)
                       (get-universal-time))
               :ensure-directory t))
         (config (list :name "roundtrip-app"
                       :version "2.0"
                       :description ""
                       :license "MIT"
                       :entry-point "main"
                       :dependencies (list (list :name "alexandria")
                                           (list :name "my-lib"
                                                 :github "user/my-lib"
                                                 :url "https://github.com/user/my-lib.git")))))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (area51::write-config config dir)
           (let ((loaded (area51::read-config dir)))
             (is (string= "roundtrip-app" (getf loaded :name)))
             (is (string= "2.0" (getf loaded :version)))
             (is (= 2 (length (getf loaded :dependencies))))
             ;; Quicklisp dep
             (let ((alex (find "alexandria" (getf loaded :dependencies)
                               :key (lambda (d) (getf d :name))
                               :test #'string=)))
               (is (not (null alex)))
               (is (null (getf alex :github))))
             ;; GitHub dep
             (let ((mylib (find "my-lib" (getf loaded :dependencies)
                                :key (lambda (d) (getf d :name))
                                :test #'string=)))
               (is (not (null mylib)))
               (is (string= "user/my-lib" (getf mylib :github))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))
