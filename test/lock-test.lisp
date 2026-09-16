(in-package #:area51-test)

(def-suite lock-tests :in area51-tests)
(in-suite lock-tests)

(defun write-asd (dir system-name deps)
  (ensure-directories-exist dir)
  (with-open-file (out (merge-pathnames (format nil "~a.asd" system-name) dir)
                       :direction :output :if-exists :supersede)
    (format out "(defsystem ~s :depends-on (~{~s~^ ~}) :components ())~%"
            system-name deps)))

(defun init-git-repo (dir &key (message "init") tag)
  (ensure-directories-exist dir)
  (area51::run-command! '("git" "init") :directory dir)
  (area51::run-command! '("git" "config" "user.email" "area51@example.com")
                        :directory dir)
  (area51::run-command! '("git" "config" "user.name" "area51")
                        :directory dir)
  (area51::run-command! '("git" "config" "commit.gpgsign" "false")
                        :directory dir)
  (area51::run-command! '("git" "add" ".") :directory dir)
  (area51::run-command! (list "git" "commit" "-m" message) :directory dir)
  (when tag
    (area51::run-command! (list "git" "tag" tag) :directory dir))
  (area51::git-rev-parse dir))

(defun search-github-cache (root name)
  (directory (merge-pathnames (format nil "github/~a-*/" name) root)))

(test cache-dir-includes-source-and-revision
  (let ((area51::*packages-dir* #p"/tmp/area51-cache/"))
    (is (string= "/tmp/area51-cache/github/lib-abc123/"
                 (namestring (area51::cache-dir-for "lib" :github "abc123"))))
    (is (string= "/tmp/area51-cache/quicklisp/alexandria-deadbeef/"
                 (namestring (area51::cache-dir-for "alexandria" :quicklisp
                                                    "deadbeef"))))
    (is (not (string= (namestring (area51::cache-dir-for "lib" :github "v1"))
                      (namestring (area51::cache-dir-for "lib" :github "v2")))))))

(test lock-package-path-ignores-stored-absolute-path
  (let ((area51::*packages-dir* #p"/tmp/area51-cache/"))
    (is (string= "/tmp/area51-cache/github/lib-abc123/"
                 (area51::lock-package-path
                  (list :name "lib"
                        :source :github
                        :sha "abc123"
                        :path "/other/machine/lib/"))))))

(test lock-package-path-uses-quicklisp-project-name
  "System name and release project can differ; the cache is the project dir."
  (let ((area51::*packages-dir* #p"/tmp/area51-cache/"))
    (is (string= "/tmp/area51-cache/quicklisp/cl-ppcre-deadbeef/"
                 (area51::lock-package-path
                  (list :name "cl-ppcre-unicode"
                        :source :quicklisp
                        :project "cl-ppcre"
                        :sha1 "deadbeef"))))))

(test lock-entry-omits-absolute-path
  (let ((entry (area51::lock-entry-from-resolved
                (list :name "lib"
                      :source :github
                      :url "https://example.com/lib.git"
                      :sha "abc123"
                      :path "/home/user/.area51/packages/lib/"))))
    (is (string= "lib" (getf entry :name)))
    (is (eq :github (getf entry :source)))
    (is (string= "abc123" (getf entry :sha)))
    (is (null (getf entry :path)))))

(test install-plan-empty-rewrites-lock
  (is (eq :empty (area51::install-plan (list :dependencies nil)
                                       (list :packages '((:name "stale"))))))
  (is (eq :empty (area51::install-plan (list :dependencies nil) nil))))

(test install-plan-restores-covering-lock
  (let* ((dep (list :name "lib"
                    :url "https://example.com/lib.git"))
         (lock (list :depends '("lib")
                     :packages
                     (list (list :name "lib"
                                 :source :github
                                 :url "https://example.com/lib.git"
                                 :sha "abc123")))))
    (is (eq :restore (area51::install-plan (list :dependencies (list dep)) lock)))))

(test install-plan-resolves-when-lock-missing-or-mismatch
  (let ((dep (list :name "lib" :url "https://example.com/lib.git")))
    (is (eq :resolve (area51::install-plan (list :dependencies (list dep)) nil)))
    (is (eq :resolve
            (area51::install-plan
             (list :dependencies (list dep))
             (list :packages
                   (list (list :name "lib"
                               :source :github
                               :url "https://example.com/other.git"
                               :sha "abc123"))))))
    (is (eq :resolve
            (area51::install-plan
             (list :dependencies (list dep))
             (list :packages
                   (list (list :name "lib"
                               :source :github
                               :url "https://example.com/lib.git"
                               :sha ""))))))
    (is (eq :resolve
            (area51::install-plan
             (list :dependencies
                   (list (list :name "lib"
                               :url "https://example.com/lib.git"
                               :ref "v2")))
             (list :depends '("lib")
                   :packages
                   (list (list :name "lib"
                               :source :github
                               :url "https://example.com/lib.git"
                               :ref "v1"
                               :sha "abc123"))))))
    (is (eq :resolve
            (area51::install-plan
             (list :dependencies
                   (list (list :name "keep"
                               :url "https://example.com/keep.git")))
             (list :depends '("keep" "gone")
                   :packages
                   (list (list :name "keep"
                               :source :github
                               :url "https://example.com/keep.git"
                               :sha "abc123")
                         (list :name "gone"
                               :source :github
                               :url "https://example.com/gone.git"
                               :sha "def456"))))))))

(test spec-for-prefers-explicit-github
  (let* ((explicit (list :name "dep"
                         :url "https://example.com/fork.git"
                         :ref "v2"))
         (specs (area51::explicit-spec-table (list explicit))))
    (is (equal explicit
               (area51::spec-for "dep" specs (list :name "dep"))))))

(test resolve-all-uses-explicit-spec-for-transitive-name
  "A later direct Git pin must win over a name-only transitive steal."
  (let* ((caller-dir (make-temp-dir "area51-caller"))
         (dep-dir (make-temp-dir "area51-dep"))
         (seen nil))
    (unwind-protect
         (progn
           (write-asd caller-dir "caller" '("dep"))
           (write-asd dep-dir "dep" '())
           (let ((resolved
                   (area51::resolve-all
                    (list :dependencies
                          (list (list :name "caller")
                                (list :name "dep"
                                      :url "https://example.com/fork.git"
                                      :ref "v2")))
                    :resolve-dep-fn
                    (lambda (dep)
                      (push (copy-list dep) seen)
                      (if (string= (getf dep :name) "caller")
                          caller-dir
                          dep-dir)))))
             (is (= 2 (length resolved)))
             (let ((dep-calls (remove "caller" (reverse seen)
                                      :key (lambda (d) (getf d :name))
                                      :test #'string=)))
               (is (plusp (length dep-calls)))
               (is (every (lambda (d)
                            (and (string= "https://example.com/fork.git"
                                          (getf d :url))
                                 (string= "v2" (getf d :ref))))
                          dep-calls)))
             (is (eq :github
                     (getf (find "dep" resolved
                                 :key (lambda (p) (getf p :name))
                                 :test #'string=)
                           :source)))))
      (uiop:delete-directory-tree caller-dir :validate t :if-does-not-exist :ignore)
      (uiop:delete-directory-tree dep-dir :validate t :if-does-not-exist :ignore))))

(test cmd-install-empty-deps-rewrites-lock
  (let ((dir (make-temp-dir "area51-empty-lock")))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (uiop:with-current-directory (dir)
             (area51::write-config (list :name "app"
                                         :version "0.1.0"
                                         :license "MIT"
                                         :entry-point "main"
                                         :dependencies nil)
                                   dir)
             (area51::write-lock (list :dist-version "old"
                                       :packages '((:name "stale-lib"
                                                    :source :quicklisp
                                                    :sha1 "abc")))
                                 dir)
             (area51::cmd-install nil)
             (let ((lock (area51::read-lock dir)))
               (is (null (getf lock :packages))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test cmd-install-restores-lock-without-resolving
  (let ((dir (make-temp-dir "area51-restore"))
        (packages (make-temp-dir "area51-restore-pkgs")))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (let* ((area51::*packages-dir* packages)
                  (cache (area51::cache-dir-for "lib" :github "abc123")))
             (ensure-directories-exist cache)
             (uiop:with-current-directory (dir)
               (area51::write-config
                (list :name "app"
                      :version "0.1.0"
                      :license "MIT"
                      :entry-point "main"
                      :dependencies (list (list :name "lib"
                                                :url "https://example.com/lib.git")))
                dir)
               (area51::write-lock
                (list :dist-version "pinned"
                      :depends '("lib")
                      :packages (list (list :name "lib"
                                            :source :github
                                            :url "https://example.com/lib.git"
                                            :sha "abc123")))
                dir)
               (area51::cmd-install nil)
               (let ((lock (area51::read-lock dir)))
                 (is (string= "pinned" (getf lock :dist-version)))
                 (is (string= "abc123"
                              (getf (first (getf lock :packages)) :sha)))
                 (is (null (getf (first (getf lock :packages)) :path)))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore)
      (uiop:delete-directory-tree packages :validate t :if-does-not-exist :ignore))))

(test github-cache-identity-keeps-two-revisions
  (let ((repo (make-temp-dir "area51-git-src"))
        (packages (make-temp-dir "area51-git-pkgs")))
    (unwind-protect
         (progn
           (write-asd repo "lib" '())
           (with-open-file (out (merge-pathnames "version.txt" repo)
                                :direction :output)
             (write-string "v1" out))
           (init-git-repo repo :message "v1" :tag "v1")
           (with-open-file (out (merge-pathnames "version.txt" repo)
                                :direction :output :if-exists :supersede)
             (write-string "v2" out))
           (area51::run-command! '("git" "add" "version.txt") :directory repo)
           (area51::run-command! '("git" "commit" "-m" "v2") :directory repo)
           (area51::run-command! '("git" "tag" "v2") :directory repo)
           (let* ((area51::*packages-dir* packages)
                  (url (string-right-trim "/" (namestring repo)))
                  (r1 (area51::resolve-github
                       (list :name "lib" :url url :ref "v1")))
                  (r2 (area51::resolve-github
                       (list :name "lib" :url url :ref "v2"))))
             (is (not (string= (getf r1 :sha) (getf r2 :sha))))
             (is (not (string= (getf r1 :path) (getf r2 :path))))
             (is (probe-file (getf r1 :path)))
             (is (probe-file (getf r2 :path)))
             (is (search "/github/lib-" (getf r1 :path)))
             (let ((v1 (uiop:read-file-string
                        (merge-pathnames "version.txt" (getf r1 :path))))
                   (v2 (uiop:read-file-string
                        (merge-pathnames "version.txt" (getf r2 :path)))))
               (is (search "v1" v1))
               (is (search "v2" v2)))
             (is (= 2 (length (search-github-cache packages "lib"))))))
      (uiop:delete-directory-tree repo :validate t :if-does-not-exist :ignore)
      (uiop:delete-directory-tree packages :validate t :if-does-not-exist :ignore))))

(test restore-github-from-lock-sha
  (let ((repo (make-temp-dir "area51-restore-src"))
        (packages (make-temp-dir "area51-restore-git-pkgs")))
    (unwind-protect
         (progn
           (write-asd repo "lib" '())
           (with-open-file (out (merge-pathnames "pin.txt" repo)
                                :direction :output)
             (write-string "locked" out))
           (let ((sha (init-git-repo repo :message "lock-me")))
             (with-open-file (out (merge-pathnames "pin.txt" repo)
                                  :direction :output :if-exists :supersede)
               (write-string "newer" out))
             (area51::run-command! '("git" "add" "pin.txt") :directory repo)
             (area51::run-command! '("git" "commit" "-m" "newer") :directory repo)
             (let* ((area51::*packages-dir* packages)
                    (url (string-right-trim "/" (namestring repo)))
                    (path (area51::restore-package
                           (list :name "lib"
                                 :source :github
                                 :url url
                                 :sha sha))))
               (is (probe-file path))
               (is (search sha (namestring path)))
               (is (search "locked"
                           (uiop:read-file-string
                            (merge-pathnames "pin.txt" path)))))))
      (uiop:delete-directory-tree repo :validate t :if-does-not-exist :ignore)
      (uiop:delete-directory-tree packages :validate t :if-does-not-exist :ignore))))

(test restore-package-signals-when-download-fails
  (let ((packages (make-temp-dir "area51-restore-fail")))
    (unwind-protect
         (let ((area51::*packages-dir* packages)
               (*error-output* (make-broadcast-stream)))
           (signals area51::restore-failed
             (area51::restore-package
              (list :name "missing-lib"
                    :source :quicklisp
                    :project "missing-lib"
                    :url "https://example.invalid/missing-lib.tgz"
                    :sha1 "deadbeef"))))
      (uiop:delete-directory-tree packages :validate t :if-does-not-exist :ignore))))

(test find-system-in-cache-rejects-multiple-revisions
  (let ((packages (make-temp-dir "area51-multi-rev")))
    (unwind-protect
         (let* ((area51::*packages-dir* packages)
                (a (area51::cache-dir-for "lib" :github "aaa"))
                (b (area51::cache-dir-for "lib" :github "bbb")))
           (write-asd a "lib" '())
           (write-asd b "lib" '())
           (signals area51::dependency-conflict
             (area51::find-system-in-cache "lib")))
      (uiop:delete-directory-tree packages :validate t :if-does-not-exist :ignore))))

(test asdf-setup-uses-computed-lock-paths
  (let ((dir (make-temp-dir "area51-asdf-lock"))
        (packages (make-temp-dir "area51-asdf-pkgs")))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (let ((area51::*packages-dir* packages))
             (uiop:with-current-directory (dir)
               (area51::write-lock
                (list :packages
                      (list (list :name "lib"
                                  :source :github
                                  :sha "abc123"
                                  :path "/old/machine/lib/")))
                dir)
               (let ((form (area51::asdf-setup-form)))
                 (is (search "github/lib-abc123" form))
                 (is (not (search "/old/machine/lib/" form)))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore)
      (uiop:delete-directory-tree packages :validate t :if-does-not-exist :ignore))))

(test empty-lock-does-not-register-global-packages
  (let ((dir (make-temp-dir "area51-empty-asdf"))
        (packages (make-temp-dir "area51-empty-pkgs")))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (let ((area51::*packages-dir* packages))
             (uiop:with-current-directory (dir)
               (area51::write-lock (list :depends nil :packages nil) dir)
               (let ((form (area51::asdf-setup-form)))
                 (is (search ":inherit-configuration" form))
                 (is (not (search (namestring packages) form)))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore)
      (uiop:delete-directory-tree packages :validate t :if-does-not-exist :ignore))))
