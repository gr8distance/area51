(in-package #:area51)

(defparameter *builtin-systems*
  '("asdf" "uiop" "cl" "sb-posix" "sb-bsd-sockets" "sb-concurrency"
    "sb-cltl2" "sb-introspect" "sb-rotate-byte" "sb-sprof" "sb-rt"
    "sb-grovel" "sb-aclrepl" "sb-cover")
  "Systems that come with the Lisp implementation.")

(defun ensure-area51-dirs ()
  (ensure-directories-exist *packages-dir*))

(defun sanitize-cache-part (string)
  (substitute-if-not #\- (lambda (c) (or (alphanumericp c) (find c "-._")))
                     (string string)))

(defun cache-dir-for (name source revision)
  "Identify a cache directory by source and immutable revision, not by name alone."
  (merge-pathnames
   (format nil "~(~a~)/~a-~a/"
           source
           (sanitize-cache-part name)
           (sanitize-cache-part (or revision "unpinned")))
   *packages-dir*))

(defun cache-present-p (path)
  (uiop:directory-exists-p path))

(defun package-cache-dir (name &key (source :quicklisp) revision)
  (cache-dir-for name source revision))

(defun lock-cache-name (pkg)
  "Quicklisp cache dirs are keyed by release project, not by system name."
  (or (getf pkg :project) (getf pkg :name)))

(defun lock-package-path (pkg)
  "Recompute the on-disk path from lock identity. Do not trust a stored absolute path."
  (namestring
   (cache-dir-for (lock-cache-name pkg)
                  (or (getf pkg :source) :quicklisp)
                  (or (getf pkg :sha) (getf pkg :sha1)))))

;;; --- Helpers ---

(defun subsystem-p (name)
  "Check if NAME is a subsystem (contains \"/\")."
  (position #\/ name))

(defun base-system-name (name)
  "Extract base system name: \"foo/bar/baz\" → \"foo\"."
  (let ((slash (position #\/ name)))
    (if slash (subseq name 0 slash) name)))

;;; --- .asd parsing ---

(defun find-asd-files (dir)
  "Find all .asd files in a directory tree (recursive).
Some packages (e.g. mgl-pax) ship with sub-systems in subdirectories."
  (let ((pattern (merge-pathnames "**/*.asd" dir)))
    (directory pattern)))

(defun skip-sharp-dot-reader (stream subchar arg)
  "Custom reader for #. that reads the following form as data and discards it.
Used to parse .asd files safely without evaluating #. forms (e.g. :long-description
that reads README at load time)."
  (declare (ignore subchar arg))
  (let ((*read-suppress* t))
    (read stream t nil t))
  nil)

(defun make-asd-readtable ()
  "Readtable for parsing .asd files: #. forms are skipped instead of evaluated."
  (let ((rt (copy-readtable nil)))
    (set-dispatch-macro-character #\# #\. #'skip-sharp-dot-reader rt)
    rt))

(defun parse-asd-depends (asd-path)
  "Extract :depends-on from ALL defsystem forms in a .asd file.
Subsystem names (containing /) are converted to their base system name."
  (handler-case
      (let ((all-deps nil))
        (with-open-file (in asd-path :direction :input)
          (let ((*readtable* (make-asd-readtable))
                (*package* (find-package :cl-user)))
            (loop for form = (read in nil :eof)
                  until (eq form :eof)
                  when (and (listp form)
                            (symbolp (car form))
                            (string-equal (symbol-name (car form)) "DEFSYSTEM"))
                    do (let ((plist (cddr form)))
                         (loop for (key val) on plist by #'cddr
                               when (and (symbolp key)
                                         (string-equal (symbol-name key)
                                                       "DEPENDS-ON"))
                                 do (dolist (d val)
                                      (let ((name (string-downcase
                                                   (if (symbolp d)
                                                       (symbol-name d)
                                                       (princ-to-string d)))))
                                        ;; For subsystems (foo/bar), add the base name (foo)
                                        (let ((resolved-name (if (subsystem-p name)
                                                                 (base-system-name name)
                                                                 name)))
                                          (pushnew resolved-name all-deps
                                                   :test #'string=)))))))))
        (nreverse all-deps))
    (error () nil)))

(defun builtin-system-p (name)
  "Check if a system name is built-in."
  (or (member name *builtin-systems* :test #'string-equal)
      (uiop:string-prefix-p "sb-" name)))

(defun asd-matches-system-p (asd name base-name)
  (or (string-equal name (pathname-name asd))
      (and (not (string= name base-name))
           (string-equal base-name (pathname-name asd)))))

(defun find-system-in-cache (name)
  "Search cached packages for NAME. Multiple revisions of the same system
   are a conflict; do not pick an arbitrary directory."
  (let ((packages-dir (namestring *packages-dir*))
        (base-name (base-system-name name))
        (matches nil))
    (when (probe-file packages-dir)
      (dolist (pkg-dir (append (directory (merge-pathnames "github/*/" packages-dir))
                               (directory (merge-pathnames "quicklisp/*/" packages-dir))))
        (when (some (lambda (asd) (asd-matches-system-p asd name base-name))
                    (find-asd-files pkg-dir))
          (pushnew (namestring pkg-dir) matches :test #'string=))))
    (cond
      ((null matches) nil)
      ((null (rest matches)) (pathname (first matches)))
      (t (error 'dependency-conflict
                :name name
                :existing (first matches)
                :incoming (second matches))))))

;;; --- Dependency resolution ---

(define-condition unresolved-dependencies (error)
  ((names :initarg :names :reader unresolved-names))
  (:report (lambda (condition stream)
             (format stream "Unresolved dependencies: ~{~a~^, ~}"
                     (unresolved-names condition)))))

(define-condition restore-failed (error)
  ((name :initarg :name :reader restore-failed-name))
  (:report (lambda (condition stream)
             (format stream "Failed to restore package ~a"
                     (restore-failed-name condition)))))

(define-condition dependency-conflict (error)
  ((name :initarg :name :reader conflict-name)
   (existing :initarg :existing :reader conflict-existing)
   (incoming :initarg :incoming :reader conflict-incoming))
  (:report (lambda (condition stream)
             (format stream "Conflicting sources for ~a: ~s vs ~s"
                     (conflict-name condition)
                     (conflict-existing condition)
                     (conflict-incoming condition)))))

(defun report-unresolved (names)
  (format *error-output* "~%Unresolved dependencies:~%")
  (dolist (name names)
    (format *error-output* "  ~a  (not found in Quicklisp or GitHub)~%" name)))

(defun resolved-packages-or-error (resolved unresolved)
  "Return RESOLVED, or signal UNRESOLVED-DEPENDENCIES when UNRESOLVED is non-nil.
   Does not write a lock file; callers must not persist RESOLVED on this error."
  (let ((names (sort (copy-list unresolved) #'string<)))
    (when names
      (report-unresolved names)
      (error 'unresolved-dependencies :names names))
    resolved))

(defun dep-is-github-p (dep)
  "Check if a dep has a GitHub/URL source."
  (or (getf dep :url) (getf dep :github)))

(defun dep-source (dep)
  (if (dep-is-github-p dep) :github :quicklisp))

(defun nonempty-string-p (value)
  (and (stringp value) (plusp (length value))))

(defun explicit-spec-table (deps)
  "Map each directly declared dependency name to its spec."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (dep deps)
      (setf (gethash (getf dep :name) table) dep))
    table))

(defun spec-for (name specs raw)
  "Prefer the explicit area51.lisp spec over a transitive name-only entry."
  (or (gethash name specs) raw))

(defun source-key (dep)
  (list (dep-source dep)
        (getf dep :url)
        (getf dep :ref)
        (getf dep :sha)
        (getf dep :sha1)))

(defun specs-conflict-p (a b)
  (and a b (not (equal (source-key a) (source-key b)))))

(defun lock-entry-from-resolved (pkg)
  "Portable lock identity: source and revision, not an absolute path."
  (let ((entry (list :name (getf pkg :name)
                     :source (getf pkg :source))))
    (flet ((keep (key)
             (let ((value (getf pkg key)))
               (when (and value (not (and (stringp value) (zerop (length value)))))
                 (setf entry (append entry (list key value)))))))
      (keep :url)
      (keep :sha)
      (keep :sha1)
      (keep :project)
      (keep :prefix)
      (keep :ref))
    entry))

(defun lock-entry-matches-dep-p (pkg dep)
  "True when PKG can restore DEP without re-resolving.
   A changed :ref is a config/lock mismatch and must re-resolve."
  (and pkg
       (string= (getf pkg :name) (getf dep :name))
       (if (dep-is-github-p dep)
           (and (eq (getf pkg :source) :github)
                (nonempty-string-p (getf pkg :url))
                (string= (getf pkg :url) (getf dep :url))
                (equal (getf pkg :ref) (getf dep :ref))
                (nonempty-string-p (getf pkg :sha)))
           (and (eq (getf pkg :source) :quicklisp)
                (nonempty-string-p (getf pkg :url))
                (nonempty-string-p (getf pkg :sha1))))))

(defun config-dep-names (config)
  (mapcar (lambda (d) (getf d :name)) (config-dependencies config)))

(defun name-set-equal (a b)
  (null (set-exclusive-or a b :test #'string=)))

(defun lock-covers-config-p (lock config)
  "True when LOCK can restore every declared dependency and no removed
   direct dependency remains in the lock's declared set.
   Empty deps never cover a leftover lock; install must rewrite it empty."
  (let ((deps (config-dependencies config)))
    (and lock
         deps
         (name-set-equal (config-dep-names config) (getf lock :depends))
         (every (lambda (dep)
                  (lock-entry-matches-dep-p
                   (find (getf dep :name) (getf lock :packages)
                         :key (lambda (p) (getf p :name))
                         :test #'string=)
                   dep))
                deps))))

(defun install-plan (config lock)
  "Decide whether install should write an empty lock, restore, or re-resolve."
  (cond
    ((null (config-dependencies config)) :empty)
    ((lock-covers-config-p lock config) :restore)
    (t :resolve)))

(defun temporary-cache-dir (name)
  (merge-pathnames
   (format nil "tmp/~a-~a-~a/"
           (sanitize-cache-part name)
           (get-universal-time)
           (random 1000000))
   *packages-dir*))

(defun commit-cache-dir (tmp dest)
  "Publish TMP as DEST. Incomplete TMP directories are never DEST."
  (let ((dest-dir (uiop:ensure-directory-pathname dest)))
    (if (cache-present-p dest-dir)
        (progn
          (uiop:delete-directory-tree
           (uiop:ensure-directory-pathname tmp)
           :validate t :if-does-not-exist :ignore)
          dest-dir)
        (progn
          (move-directory tmp dest-dir)
          dest-dir))))

(defun normalize-resolve-result (result dep)
  (cond
    ((null result) nil)
    ((or (pathnamep result) (stringp result))
     (list :path (namestring result)
           :url (getf dep :url)
           :sha (getf dep :sha)
           :sha1 (getf dep :sha1)
           :project (getf dep :project)))
    ((listp result) result)
    (t (error "resolve-dep returned ~s" result))))

(defun result-path (result)
  (let ((path (getf result :path)))
    (when path (uiop:ensure-directory-pathname path))))

(defun resolve-github (dep)
  (let* ((name (getf dep :name))
         (url (getf dep :url))
         (ref (or (getf dep :sha) (getf dep :ref)))
         (wanted-sha (getf dep :sha)))
    (when (nonempty-string-p wanted-sha)
      (let ((cached (cache-dir-for name :github wanted-sha)))
        (when (cache-present-p cached)
          (format t "  ~a (cached)~%" name)
          (return-from resolve-github
            (list :path (namestring cached) :url url :sha wanted-sha
                  :ref (getf dep :ref))))))
    (let ((tmp (temporary-cache-dir name)))
      (ensure-directories-exist (uiop:pathname-parent-directory-pathname tmp))
      (format t "  ~a <- ~a~%" name url)
      (git-clone url (namestring tmp) :ref ref)
      (let ((sha (git-rev-parse (namestring tmp))))
        (unless (nonempty-string-p sha)
          (error "Could not determine SHA for ~a" name))
        (when (and (nonempty-string-p wanted-sha)
                   (not (string= wanted-sha sha)))
          (error "SHA mismatch for ~a: wanted ~a got ~a" name wanted-sha sha))
        (let ((dest (commit-cache-dir tmp (cache-dir-for name :github sha))))
          (list :path (namestring dest) :url url :sha sha
                :ref (getf dep :ref)))))))

(defun resolve-quicklisp (dep)
  (let* ((name (getf dep :name))
         (info (quicklisp-lookup name)))
    (when info
      (let* ((project (getf info :project))
             (url (getf info :url))
             (sha1 (getf info :sha1))
             (cache-dir (cache-dir-for project :quicklisp sha1)))
        (if (cache-present-p cache-dir)
            (progn
              (format t "  ~a (cached)~%" name)
              (list :path (namestring cache-dir)
                    :url url :sha1 sha1 :project project
                    :prefix (getf info :prefix)))
            (progn
              (format t "  ~a <- quicklisp~%" name)
              (let ((path (download-quicklisp-package name)))
                (when path
                  (list :path (namestring path)
                        :url url :sha1 sha1 :project project
                        :prefix (getf info :prefix))))))))))

(defun resolve-dep (dep)
  "Resolve a single dependency, download if needed.
   Deps with :url or :github → git clone into a revision-keyed cache.
   Deps without → Quicklisp, keyed by archive sha1.
   Returns a plist with :path and lock identity fields, or nil."
  (ensure-area51-dirs)
  (if (dep-is-github-p dep)
      (resolve-github dep)
      (resolve-quicklisp dep)))

(defun restore-github (pkg dest)
  (declare (ignore dest))
  (resolve-github (list :name (getf pkg :name)
                        :url (getf pkg :url)
                        :sha (getf pkg :sha))))

(defun restore-quicklisp (pkg dest)
  (declare (ignore dest))
  (let* ((name (or (getf pkg :project) (getf pkg :name)))
         (url (getf pkg :url))
         (sha1 (getf pkg :sha1))
         (cache-dir (cache-dir-for name :quicklisp sha1)))
    (if (cache-present-p cache-dir)
        (progn
          (format t "  ~a (cached)~%" (getf pkg :name))
          cache-dir)
        (download-release (list :project name
                                :url url
                                :sha1 sha1
                                :prefix (getf pkg :prefix))))))

(defun restore-package (pkg)
  "Materialize PKG from lock identity. Recomputes the cache path; ignores :path."
  (let* ((name (getf pkg :name))
         (dest (lock-package-path pkg))
         (source (or (getf pkg :source) :quicklisp)))
    (flet ((ensure-restored (path)
             (let ((present (and path (cache-present-p path))))
               (unless present
                 (error 'restore-failed :name name))
               path)))
      (ensure-restored
       (if (cache-present-p dest)
           (progn
             (format t "  ~a (cached)~%" name)
             dest)
           (ecase source
             (:github (getf (restore-github pkg dest) :path))
             (:quicklisp (restore-quicklisp pkg dest))))))))

(defun restore-lock (lock &key (restore-fn #'restore-package))
  (mapcar restore-fn (getf lock :packages)))

(defun resolve-all (config &key (resolve-dep-fn #'resolve-dep))
  "Resolve all dependencies recursively.
   Direct specs are kept in a name table so a transitive (:name x) cannot
   steal an explicit GitHub/URL pin. Queue is FIFO."
  (let* ((deps (config-dependencies config))
         (specs (explicit-spec-table deps))
         (resolved (make-hash-table :test 'equal))
         (resolved-specs (make-hash-table :test 'equal))
         (unresolved nil)
         (queue (copy-list deps)))
    (loop while queue do
      (let* ((raw (pop queue))
             (name (getf raw :name))
             (dep (spec-for name specs raw)))
        (cond
          ((or (null name) (builtin-system-p name)) nil)
          ((gethash name resolved)
           (when (specs-conflict-p (gethash name resolved-specs) dep)
             (error 'dependency-conflict
                    :name name
                    :existing (gethash name resolved-specs)
                    :incoming dep)))
          (t
           (let ((result (normalize-resolve-result
                          (funcall resolve-dep-fn dep) dep)))
             (if result
                 (let ((path (result-path result)))
                   (setf (gethash name resolved-specs) dep)
                   (setf (gethash name resolved)
                         (append (list :name name
                                       :source (dep-source dep))
                                 result))
                   (dolist (asd (find-asd-files path))
                     (dolist (td (parse-asd-depends asd))
                       (unless (or (gethash td resolved)
                                   (builtin-system-p td))
                         (setf queue
                               (append queue
                                       (list (spec-for td specs
                                                       (list :name td)))))))))
                 (pushnew name unresolved :test #'string=)))))))
    (let ((results nil))
      (maphash (lambda (k v)
                 (declare (ignore k))
                 (push v results))
               resolved)
      (resolved-packages-or-error
       (sort results #'string< :key (lambda (r) (getf r :name)))
       unresolved))))
