(in-package #:area51)

;;; Lisp implementation abstraction layer.
;;; Currently supports SBCL. Add other implementations here.

(defparameter *lisp-impl*
  (or (uiop:getenv "AREA51_LISP") "sbcl")
  "Lisp implementation to use. Override with AREA51_LISP env var.")

(defun package-paths-from-lock ()
  "Return list of package :path strings from the current project's area51.lock.
   Returns nil if no lock file exists."
  (let ((lock (read-lock)))
    (when lock
      (loop for pkg in (getf lock :packages)
            for path = (getf pkg :path)
            when path collect path))))

(defun asdf-setup-form ()
  "Generate a form that configures ASDF to find this project's locked dependencies.
   Uses per-package :tree entries from area51.lock for true per-project
   isolation. :tree (not :directory) is used because some packages ship
   with sub-systems in subdirectories (e.g. mgl-pax/autoload/autoload.asd).
   Falls back to a :tree over the global packages dir when no lock file
   is available (e.g. during install)."
  (let ((paths (package-paths-from-lock)))
    (if paths
        (with-output-to-string (out)
          (write-string
           "(asdf:initialize-source-registry (list :source-registry "
           out)
          (dolist (p paths)
            (format out "(list :tree ~s) " p))
          (write-string ":inherit-configuration))" out))
        (format nil "(asdf:initialize-source-registry ~
                     (list :source-registry ~
                       (list :tree ~s) ~
                       :inherit-configuration))"
                (namestring *packages-dir*)))))

(defun lisp-eval-command (dir &rest eval-forms)
  "Generate a shell command to evaluate forms in a Lisp subprocess."
  (let ((impl *lisp-impl*))
    (cond
      ((string= impl "sbcl")
       (format nil "cd ~a && sbcl --noinform --non-interactive ~
                    --eval '(require :asdf)' ~
                    --eval '(setf asdf:*asdf-verbose* nil)' ~
                    --eval '~a' ~
                    --eval '(push *default-pathname-defaults* asdf:*central-registry*)' ~
                    ~{--eval '~a' ~}"
               (namestring dir)
               (asdf-setup-form)
               eval-forms))
      ((string= impl "ccl")
       (format nil "cd ~a && ccl --no-init --batch ~
                    --eval '(require :asdf)' ~
                    --eval '~a' ~
                    --eval '(push *default-pathname-defaults* asdf:*central-registry*)' ~
                    ~{--eval '~a' ~}"
               (namestring dir)
               (asdf-setup-form)
               eval-forms))
      (t
       (error "Unsupported Lisp implementation: ~a. Supported: sbcl, ccl" impl)))))

(defun lisp-save-image-form (bin-path toplevel-symbol-name package-name)
  "Generate the form to save an executable image, implementation-specific."
  (let ((impl *lisp-impl*))
    (cond
      ((string= impl "sbcl")
       (format nil "(sb-ext:save-lisp-and-die ~s ~
                     :toplevel (lambda () ~
                       (funcall (find-symbol \"~a\" \"~a\")) ~
                       (sb-ext:exit)) ~
                     :executable t :compression t)"
               bin-path toplevel-symbol-name package-name))
      ((string= impl "ccl")
       (format nil "(ccl:save-application ~s ~
                     :toplevel-function (lambda () ~
                       (funcall (find-symbol \"~a\" \"~a\")) ~
                       (ccl:quit)) ~
                     :prepend-kernel t)"
               bin-path toplevel-symbol-name package-name))
      (t
       (error "Unsupported Lisp implementation: ~a" impl)))))
