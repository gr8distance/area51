(in-package #:area51)

(defparameter *config-filename* "area51.lisp")
(defparameter *lock-filename* "area51.lock")

(defparameter *area51-home*
  (merge-pathnames ".area51/" (user-homedir-pathname))
  "Global area51 directory for cached packages")

(defparameter *packages-dir*
  (merge-pathnames "packages/" *area51-home*)
  "Directory for downloaded packages")

;;; --- Config reading ---

(defun getf-by-name (plist name &optional default)
  "Like getf but matches keys by symbol-name (case-insensitive).
   Handles symbols that may not be in the KEYWORD package."
  (loop for (k v) on plist by #'cddr
        when (and (symbolp k) (string-equal (symbol-name k) name))
          return v
        finally (return default)))

(defun read-config-forms (path)
  "Read all top-level S-expressions from PATH with *read-eval* nil."
  (with-open-file (in path :direction :input)
    (let ((*read-eval* nil)
          (eof (gensym "EOF")))
      (loop for form = (read in nil eof)
            until (eq form eof)
            collect form))))

(defun parse-project-form (form)
  "Parse (project \"name\" :key val ...) into config plist."
  (let ((name (second form))
        (plist (cddr form)))
    (list :name name
          :version (getf-by-name plist "VERSION" "0.1.0")
          :description (getf-by-name plist "DESCRIPTION" "")
          :license (getf-by-name plist "LICENSE" "MIT")
          :entry-point (getf-by-name plist "ENTRY-POINT" "main"))))

(defun parse-dep-entry (entry)
  "Parse (\"name\" :github \"user/repo\" :ref \"v1\") into dep plist.
   No :github or :url → Quicklisp source."
  (let* ((name (first entry))
         (plist (rest entry))
         (github (getf-by-name plist "GITHUB"))
         (url (or (getf-by-name plist "URL")
                  (when github
                    (format nil "https://github.com/~a.git" github))))
         (ref (getf-by-name plist "REF"))
         (result (list :name name)))
    (when github (setf result (append result (list :github github))))
    (when url (setf result (append result (list :url url))))
    (when ref (setf result (append result (list :ref ref))))
    result))

(defun parse-config-forms (forms)
  "Convert list of S-expressions into config plist."
  (let ((config nil)
        (deps nil))
    (dolist (form forms)
      (when (and (listp form) (symbolp (car form)))
        (let ((tag (symbol-name (car form))))
          (cond
            ((string-equal tag "PROJECT")
             (setf config (parse-project-form form)))
            ((string-equal tag "DEPS")
             (dolist (entry (cdr form))
               (push (parse-dep-entry entry) deps)))))))
    (when config
      (setf (getf config :dependencies) (nreverse deps)))
    config))

(defun read-config (&optional (dir (uiop:getcwd)))
  "Read area51.lisp as data and return config plist."
  (let ((path (merge-pathnames *config-filename* dir)))
    (when (probe-file path)
      (parse-config-forms (read-config-forms path)))))

;;; --- Config writing ---

(defun write-dep-entry (stream dep)
  "Write a single dep entry as (\"name\" :github \"user/repo\") or just (\"name\") for Quicklisp."
  (let ((name (getf dep :name))
        (github (getf dep :github))
        (url (getf dep :url))
        (ref (getf dep :ref)))
    (let ((*print-case* :downcase))
      (cond
        ;; Quicklisp: just ("name")
        ((and (null github) (null url))
         (format stream "  (~s)~%" name))
        ;; GitHub shorthand
        (github
         (format stream "  (~s :github ~s" name github)
         (when ref (format stream " :ref ~s" ref))
         (format stream ")~%"))
        ;; Raw URL
        (url
         (format stream "  (~s :url ~s" name url)
         (when ref (format stream " :ref ~s" ref))
         (format stream ")~%"))))))

(defun write-config (config &optional (dir (uiop:getcwd)))
  "Write area51.lisp in the declarative S-expression format."
  (let ((path (merge-pathnames *config-filename* dir)))
    (with-open-file (out path :direction :output
                              :if-exists :supersede)
      (let ((*print-case* :downcase))
        ;; Project declaration
        (format out "(project ~s~%" (getf config :name))
        (format out "  :version ~s~%" (or (getf config :version) "0.1.0"))
        (when (and (getf config :description)
                   (not (string= (getf config :description) "")))
          (format out "  :description ~s~%" (getf config :description)))
        (format out "  :license ~s~%" (or (getf config :license) "MIT"))
        (format out "  :entry-point ~s)~%" (or (getf config :entry-point) "main"))
        ;; Dependencies
        (let ((deps (getf config :dependencies)))
          (when deps
            (format out "~%(deps~%")
            (dolist (d deps)
              (write-dep-entry out d))
            (format out ")~%")))))))

;;; --- Lock file ---

(defun read-lock (&optional (dir (uiop:getcwd)))
  "Read lock file safely."
  (let ((path (merge-pathnames *lock-filename* dir)))
    (when (probe-file path)
      (with-open-file (in path :direction :input)
        (let ((*read-eval* nil))
          (read in))))))

(defun write-lock (lock &optional (dir (uiop:getcwd)))
  "Write lock file"
  (let ((path (merge-pathnames *lock-filename* dir)))
    (with-open-file (out path :direction :output
                              :if-exists :supersede)
      (let ((*print-pretty* t)
            (*print-case* :downcase)
            (*print-right-margin* 80))
        (prin1 lock out)
        (terpri out)))))

;;; --- Config helpers ---

(defun config-value (config key)
  (getf config key))

(defun config-dependencies (config)
  (getf config :dependencies))

(defun config-dependencies-for (config mode)
  "Return dependencies. MODE is accepted for compatibility but ignored."
  (declare (ignore mode))
  (config-dependencies config))

(defun config-add-dep (config name &key github url ref)
  "Add a dependency to config, returns new config"
  (let* ((entry (list :name name))
         (entry (if github (append entry (list :github github)) entry))
         (entry (if url (append entry (list :url url)) entry))
         (entry (if ref (append entry (list :ref ref)) entry))
         (deps (config-dependencies config)))
    (if (find name deps :key (lambda (d) (getf d :name)) :test #'string=)
        (progn
          (format *error-output* "Dependency ~a already exists~%" name)
          config)
        (let ((new-config (copy-list config)))
          (setf (getf new-config :dependencies) (append deps (list entry)))
          new-config))))

(defun config-remove-dep (config name)
  "Remove a dependency from config, returns new config"
  (let ((new-config (copy-list config)))
    (setf (getf new-config :dependencies)
          (remove-if (lambda (d)
                       (string= (getf d :name) name))
                     (config-dependencies new-config)))
    new-config))

(defun ensure-config ()
  (or (read-config)
      (error "No area51.lisp found. Run 'area51 new' first.")))

;;; --- .asd file manipulation ---

(defun find-project-asd (name &optional (dir (uiop:getcwd)))
  "Find the project's .asd file."
  (let ((path (merge-pathnames (format nil "~a.asd" name) dir)))
    (when (probe-file path) path)))

(defun dep-name-string (d)
  "Normalize a dep entry (symbol or string) to a lowercase string."
  (if (symbolp d) (symbol-name d) (princ-to-string d)))

(defun format-deps-string (deps)
  "Format a list of dependency names as a :depends-on string."
  (if deps
      (format nil ":depends-on (~{~s~^ ~})"
              (mapcar (lambda (d)
                        (if (symbolp d)
                            (string-downcase (symbol-name d))
                            d))
                      deps))
      ":depends-on ()"))

(defun asd-read-depends (asd-path)
  "Read .asd file and return (values content defsystem-form current-deps).
   Returns nil if not a valid defsystem."
  (let* ((content (uiop:read-file-string asd-path))
         (form (with-input-from-string (s content)
                 (let ((*read-eval* nil)) (read s)))))
    (when (and (listp form)
               (symbolp (car form))
               (string-equal (symbol-name (car form)) "DEFSYSTEM"))
      (let ((current-deps (loop for (k v) on (cddr form) by #'cddr
                                when (and (symbolp k)
                                          (string-equal (symbol-name k) "DEPENDS-ON"))
                                  return v)))
        (values content form current-deps)))))

(defun asd-write-deps (asd-path content old-deps new-deps)
  "Replace :depends-on in .asd file content and write back.
   Uses format-deps-string for both old and new so the empty case
   ('()' in the source, NIL when read back) round-trips correctly."
  (let* ((old-str (format-deps-string old-deps))
         (new-str (format-deps-string new-deps))
         (pos (search old-str content)))
    (if pos
        (let ((new-content (uiop:strcat
                            (subseq content 0 pos)
                            new-str
                            (subseq content (+ pos (length old-str))))))
          (with-open-file (out asd-path :direction :output
                                        :if-exists :supersede)
            (write-string new-content out)))
        (format *error-output*
                "Warning: could not locate ~s in ~a; .asd left unchanged.~%"
                old-str asd-path))))

(defun asd-add-dep (asd-path dep-name)
  "Add a dependency to the .asd file's :depends-on."
  (multiple-value-bind (content form current-deps)
      (asd-read-depends asd-path)
    (declare (ignore form))
    (when content
      (unless (member dep-name current-deps
                      :test #'string-equal
                      :key #'dep-name-string)
        (asd-write-deps asd-path content current-deps
                        (append current-deps (list dep-name)))))))

(defun asd-remove-dep (asd-path dep-name)
  "Remove a dependency from the .asd file's :depends-on."
  (multiple-value-bind (content form current-deps)
      (asd-read-depends asd-path)
    (declare (ignore form))
    (when content
      (let ((new-deps (remove-if (lambda (d)
                                   (string-equal dep-name (dep-name-string d)))
                                 current-deps)))
        (asd-write-deps asd-path content current-deps new-deps)))))
