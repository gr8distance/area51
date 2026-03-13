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

;;; --- .asd parsing ---

(defun find-asd-files (dir)
  "Find all .asd files in a directory (non-recursive)."
  (let ((pattern (merge-pathnames "*.asd" dir)))
    (directory pattern)))

(defun parse-asd-depends (asd-path)
  "Extract :depends-on list from a .asd file."
  (handler-case
      (with-open-file (in asd-path :direction :input)
        (let ((*read-eval* nil)
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
                               do (return-from parse-asd-depends
                                    (mapcar (lambda (d)
                                              (string-downcase
                                               (if (symbolp d)
                                                   (symbol-name d)
                                                   (princ-to-string d))))
                                            val)))))))
    (error () nil)))

(defun builtin-system-p (name)
  "Check if a system name is built-in."
  (or (member name *builtin-systems* :test #'string-equal)
      (uiop:string-prefix-p "sb-" name)))

(defun find-system-in-cache (name)
  "Search for a system in cached packages by scanning .asd files."
  (let ((packages-dir (namestring *packages-dir*)))
    (when (probe-file packages-dir)
      (dolist (pkg-dir (directory (merge-pathnames "*/" packages-dir)))
        (dolist (asd (find-asd-files pkg-dir))
          (when (string-equal name (pathname-name asd))
            (return-from find-system-in-cache pkg-dir)))))))

;;; --- Dependency resolution ---

(defun resolve-dep (dep)
  "Resolve a single dependency, download if needed.
   Returns the local path to the package."
  (let* ((name (getf dep :name))
         (url (getf dep :url))
         (ref (getf dep :ref))
         (cache-dir (package-cache-dir name)))
    (ensure-area51-dirs)
    (if (probe-file cache-dir)
        (progn
          (format t "  ~a (cached)~%" name)
          cache-dir)
        (progn
          (format t "  ~a <- ~a~%" name url)
          (git-clone url (namestring cache-dir) :ref ref)
          cache-dir))))

(defun resolve-all (config &key (mode :all))
  "Resolve all dependencies recursively.
   MODE - :all or :production
   1. Resolve direct dependencies from area51.lisp
   2. Parse each package's .asd for :depends-on
   3. Recursively resolve transitive dependencies
   4. Report unresolved dependencies"
  (let ((deps (config-dependencies-for config mode))
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
                              :sha (ignore-errors
                                     (git-rev-parse (namestring path)))))
                  ;; Find transitive dependencies
                  (dolist (asd (find-asd-files path))
                    (let ((transitive-deps (parse-asd-depends asd)))
                      (dolist (td transitive-deps)
                        (unless (or (gethash td resolved)
                                    (builtin-system-p td))
                          ;; Check if it exists in cache
                          (let ((cached-path (find-system-in-cache td)))
                            (if cached-path
                                ;; Found in cache, mark resolved directly
                                (setf (gethash td resolved)
                                      (list :name td
                                            :path (namestring cached-path)
                                            :sha (ignore-errors
                                                   (git-rev-parse
                                                    (namestring cached-path)))))
                                ;; Not found anywhere
                                (pushnew td unresolved :test #'string=))))))))
                ;; Failed to resolve
                (pushnew name unresolved :test #'string=))))))
    ;; Report unresolved
    (when unresolved
      (format *error-output* "~%Unresolved dependencies:~%")
      (dolist (name (sort unresolved #'string<))
        (format *error-output* "  ~a  (add with: area51 add ~a --github <user/repo>)~%" name name)))
    ;; Return resolved list
    (let ((results nil))
      (maphash (lambda (k v)
                 (declare (ignore k))
                 (push v results))
               resolved)
      (sort results #'string< :key (lambda (r) (getf r :name))))))
