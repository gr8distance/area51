(in-package #:area51)

(defparameter *config-filename* "area51.lisp")
(defparameter *lock-filename* "area51.lock")

;;; --- DSL state (populated when area51.lisp is evaluated) ---

(defvar *current-config* nil)
(defvar *current-deps* nil)
(defvar *current-group* nil)

;;; --- DSL functions (called from area51.lisp) ---

(defun project (name &key (version "0.1.0") (description "") (license "MIT")
                          (entry-point "main"))
  "Declare project metadata."
  (setf *current-config*
        (list :name name
              :version version
              :description description
              :license license
              :entry-point entry-point)))

(defun dep (name &key github url ref)
  "Declare a dependency."
  (let* ((source (cond (github :github)
                       (url :github)
                       (t :github)))
         (resolved-url (or url
                           (when github
                             (format nil "https://github.com/~a.git" github))))
         (entry (list :name name :source source))
         (entry (if resolved-url (append entry (list :url resolved-url)) entry))
         (entry (if ref (append entry (list :ref ref)) entry))
         (entry (if *current-group*
                    (append entry (list :groups *current-group*))
                    entry)))
    (push entry *current-deps*)))

(defmacro group (groups &body body)
  "Declare dependencies within a group."
  `(let ((*current-group* ',groups))
     ,@body))

;;; --- Config reading/writing ---

(defun read-config (&optional (dir (uiop:getcwd)))
  "Evaluate area51.lisp as DSL and return config plist."
  (let ((path (merge-pathnames *config-filename* dir)))
    (when (probe-file path)
      (setf *current-config* nil
            *current-deps* nil
            *current-group* nil)
      (let ((cl-user (find-package :common-lisp-user)))
        (import '(project dep group) cl-user))
      (load path :verbose nil :print nil)
      (when *current-config*
        (setf (getf *current-config* :dependencies)
              (nreverse *current-deps*)))
      *current-config*)))

(defun write-config (config &optional (dir (uiop:getcwd)))
  "Write area51.lisp as DSL form."
  (let ((path (merge-pathnames *config-filename* dir)))
    (with-open-file (out path :direction :output
                              :if-exists :supersede)
      (let ((*print-case* :downcase))
        ;; Write project declaration
        (format out "(project ~s~%" (getf config :name))
        (format out "  :version ~s~%" (or (getf config :version) "0.1.0"))
        (when (and (getf config :description)
                   (not (string= (getf config :description) "")))
          (format out "  :description ~s~%" (getf config :description)))
        (format out "  :license ~s~%" (or (getf config :license) "MIT"))
        (format out "  :entry-point ~s)~%" (or (getf config :entry-point) "main"))
        ;; Write dependencies
        (let* ((deps (getf config :dependencies))
               (ungrouped (remove-if (lambda (d) (getf d :groups)) deps))
               (grouped (remove-if-not (lambda (d) (getf d :groups)) deps)))
          ;; Ungrouped deps
          (dolist (d ungrouped)
            (format out "~%")
            (write-dep-form out d))
          ;; Grouped deps
          (let ((seen-groups nil))
            (dolist (d grouped)
              (let ((g (getf d :groups)))
                (unless (member g seen-groups :test #'equal)
                  (push g seen-groups)
                  (format out "~%(group ~s~%" g)
                  (dolist (gd (remove-if-not
                               (lambda (x) (equal (getf x :groups) g))
                               grouped))
                    (format out "  ")
                    (write-dep-form out gd))
                  (format out ")~%"))))))))))

(defun write-dep-form (stream dep)
  "Write a single dep form."
  (let* ((name (getf dep :name))
         (url (getf dep :url))
         (ref (getf dep :ref))
         (github (when (and url (search "github.com/" url))
                   (let* ((path (subseq url (+ (search "github.com/" url) 11)))
                          (path (if (uiop:string-suffix-p ".git" path)
                                    (subseq path 0 (- (length path) 4))
                                    path)))
                     path))))
    (let ((*print-case* :downcase))
      (format stream "(dep ~s" name)
      (if github
          (format stream " :github ~s" github)
          (when url (format stream " :url ~s" url)))
      (when ref (format stream " :ref ~s" ref))
      (format stream ")~%"))))

;;; --- Lock file ---

(defun read-lock (&optional (dir (uiop:getcwd)))
  "Read lock file"
  (let ((path (merge-pathnames *lock-filename* dir)))
    (when (probe-file path)
      (with-open-file (in path :direction :input)
        (read in)))))

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
  "Filter dependencies by mode.
   :all        - all dependencies
   :production - ungrouped + :production group
   :test       - ungrouped + :production + :dev + :test"
  (let ((deps (config-dependencies config)))
    (ecase mode
      (:all deps)
      (:production
       (remove-if (lambda (d)
                    (let ((groups (getf d :groups)))
                      (and groups
                           (not (member :production groups)))))
                  deps))
      (:test
       deps))))

(defun config-add-dep (config name &key (source :github) url ref)
  "Add a dependency to config, returns new config"
  (let* ((entry (list :name name :source source))
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
