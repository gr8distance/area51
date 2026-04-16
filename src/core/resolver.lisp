(in-package #:area51)

(defparameter *builtin-systems*
  '("asdf" "uiop" "cl" "sb-posix" "sb-bsd-sockets" "sb-concurrency"
    "sb-cltl2" "sb-introspect" "sb-rotate-byte" "sb-sprof" "sb-rt"
    "sb-grovel" "sb-aclrepl" "sb-cover")
  "Systems that come with the Lisp implementation.")

(defun ensure-area51-dirs ()
  (ensure-directories-exist *packages-dir*))

(defun package-cache-dir (name)
  (merge-pathnames (format nil "~a/" name) *packages-dir*))

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
  "Find all .asd files in a directory (non-recursive)."
  (let ((pattern (merge-pathnames "*.asd" dir)))
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

(defun find-system-in-cache (name)
  "Search for a system in cached packages by scanning .asd files."
  (let ((packages-dir (namestring *packages-dir*))
        (base-name (base-system-name name)))
    (when (probe-file packages-dir)
      (dolist (pkg-dir (directory (merge-pathnames "*/" packages-dir)))
        (dolist (asd (find-asd-files pkg-dir))
          ;; Direct match by filename
          (when (string-equal name (pathname-name asd))
            (return-from find-system-in-cache pkg-dir))
          ;; Subsystem: match by base name
          (when (and (not (string= name base-name))
                     (string-equal base-name (pathname-name asd)))
            (return-from find-system-in-cache pkg-dir)))))))

;;; --- Dependency resolution ---

(defun dep-is-github-p (dep)
  "Check if a dep has a GitHub/URL source."
  (or (getf dep :url) (getf dep :github)))

(defun resolve-dep (dep)
  "Resolve a single dependency, download if needed.
   Deps with :url or :github → git clone.
   Deps without → Quicklisp."
  (let* ((name (getf dep :name))
         (url (getf dep :url))
         (ref (getf dep :ref))
         (cache-dir (package-cache-dir name)))
    (ensure-area51-dirs)
    (if (dep-is-github-p dep)
        ;; GitHub source
        (if (probe-file cache-dir)
            (progn
              (format t "  ~a (cached)~%" name)
              cache-dir)
            (progn
              (format t "  ~a <- ~a~%" name url)
              (git-clone url (namestring cache-dir) :ref ref)
              cache-dir))
        ;; Quicklisp source — check direct cache first, then scan
        (if (probe-file cache-dir)
            (progn
              (format t "  ~a (cached)~%" name)
              cache-dir)
            (let ((cached (find-system-in-cache name)))
              (if cached
                  (progn
                    (format t "  ~a (cached)~%" name)
                    cached)
                  (progn
                    (format t "  ~a <- quicklisp~%" name)
                    (let ((path (download-quicklisp-package name)))
                      (or path
                          (progn
                            (format *error-output*
                                    "  ~a not found in Quicklisp index~%" name)
                            nil))))))))))

(defun resolve-all (config)
  "Resolve all dependencies recursively.
   1. Resolve direct dependencies from area51.lisp
   2. Parse each package's .asd for :depends-on
   3. Recursively resolve transitive dependencies
   4. Report unresolved dependencies"
  (let ((deps (config-dependencies config))
        (resolved (make-hash-table :test 'equal))
        (unresolved nil)
        (queue nil))
    ;; Seed queue with direct dependencies
    (dolist (dep deps)
      (push dep queue))
    ;; Process queue
    (loop while queue do
      (let* ((dep (pop queue))
             (name (getf dep :name)))
        (unless (or (gethash name resolved)
                    (builtin-system-p name))
          ;; Resolve this dependency
          (let ((path (resolve-dep dep)))
            (if path
                (progn
                  ;; Mark as resolved
                  (setf (gethash name resolved)
                        (list :name name
                              :path (namestring path)
                              :source (if (dep-is-github-p dep) :github :quicklisp)
                              :sha (ignore-errors
                                     (git-rev-parse (namestring path)))))
                  ;; Find transitive dependencies — always queue them
                  ;; so their own transitive deps get scanned too
                  (dolist (asd (find-asd-files path))
                    (let ((transitive-deps (parse-asd-depends asd)))
                      (dolist (td transitive-deps)
                        (unless (or (gethash td resolved)
                                    (builtin-system-p td))
                          (push (list :name td) queue))))))
                ;; Failed to resolve
                (pushnew name unresolved :test #'string=))))))
    ;; Report unresolved
    (when unresolved
      (format *error-output* "~%Unresolved dependencies:~%")
      (dolist (name (sort unresolved #'string<))
        (format *error-output* "  ~a  (not found in Quicklisp or GitHub)~%" name)))
    ;; Return resolved list
    (let ((results nil))
      (maphash (lambda (k v)
                 (declare (ignore k))
                 (push v results))
               resolved)
      (sort results #'string< :key (lambda (r) (getf r :name))))))
