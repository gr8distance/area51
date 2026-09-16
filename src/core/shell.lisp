(in-package #:area51)

(defun ensure-argv (command)
  "Return COMMAND as a list of strings, or signal if it is a shell string."
  (unless (and (consp command)
               (every (lambda (arg)
                        (or (stringp arg) (pathnamep arg)))
                      command))
    (error "Command must be a list of strings, got ~s" command))
  (mapcar (lambda (arg)
            (if (stringp arg) arg (namestring arg)))
          command))

(defun run-command (command &key (output :string) directory)
  "Run COMMAND as an argv list. DIRECTORY is passed to uiop, not via cd."
  (let ((argv (ensure-argv command))
        (error-output (if (eq output :interactive) :interactive :string)))
    (multiple-value-bind (out err code)
        (uiop:run-program argv
                          :output output
                          :error-output error-output
                          :ignore-error-status t
                          :directory directory)
      (declare (ignore err))
      (values out code))))

(defun run-command! (command &key directory)
  "Run an argv list, signal error on failure"
  (multiple-value-bind (out code) (run-command command :directory directory)
    (unless (zerop code)
      (error "Command failed (~d): ~a" code command))
    out))

(defun quit-unless-zero (code &optional (exit #'uiop:quit))
  "If CODE is non-zero, call EXIT with CODE. Return CODE when it is zero.
   EXIT is injectable so tests can observe the status without killing the process."
  (if (zerop code)
      code
      (funcall exit code)))

(defun git-clone-argv (url dest)
  (list "git" "clone" "--" url dest))

(defun git-checkout-argv (ref)
  (list "git" "checkout" "--" ref))

(defun git-rev-parse-argv ()
  (list "git" "rev-parse" "HEAD"))

(defun curl-argv (url &key output-file)
  (append (list "curl" "-fsSL")
          (when output-file (list "-o" output-file))
          (list "--" url)))

(defun tar-extract-argv (tarball dest)
  (list "tar" "-xzf" tarball "-C" dest))

(defun git-clone (url dest &key ref)
  "Clone a git repository"
  (run-command! (git-clone-argv url dest))
  (when ref
    (run-command! (git-checkout-argv ref) :directory dest)))

(defun git-rev-parse (dir)
  "Get current commit SHA"
  (string-trim '(#\Newline #\Space)
               (run-command! (git-rev-parse-argv) :directory dir)))
