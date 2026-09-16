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

(defun git-ref-argument (ref)
  "Return REF if it cannot be mistaken for a git option."
  (unless (and (stringp ref)
               (plusp (length ref))
               (not (char= (char ref 0) #\-)))
    (error "Invalid git ref: ~s" ref))
  ref)

(defun git-checkout-argv (ref)
  "Checkout a commit-ish. Do not use `checkout -- REF`; that is a pathspec."
  (list "git" "checkout" "--detach" (git-ref-argument ref)))

(defun git-rev-parse-argv ()
  (list "git" "rev-parse" "HEAD"))

(defun curl-argv (url &key output-file)
  (append (list "curl" "-fsSL")
          (when output-file (list "-o" output-file))
          (list "--" url)))

(defun tar-extract-argv (tarball dest)
  (list "tar" "-xzf" tarball "-C" dest))

(defun copy-executable-argv (source dest)
  "cp -p preserves the execute bit. uiop:copy-file copies bytes only."
  (list "cp" "-p" (namestring source) (namestring dest)))

(defun copy-executable (source dest)
  (run-command! (copy-executable-argv source dest)))

(defun git-clone (url dest &key ref)
  "Clone a git repository"
  (run-command! (git-clone-argv url dest))
  (when ref
    (run-command! (git-checkout-argv ref) :directory dest)))

(defun git-rev-parse (dir)
  "Get current commit SHA"
  (string-trim '(#\Newline #\Space)
               (run-command! (git-rev-parse-argv) :directory dir)))

(defun move-directory-argv (source dest)
  (list "mv"
        (string-right-trim "/" (namestring source))
        (string-right-trim "/" (namestring dest))))

(defun move-directory (source dest)
  "Move SOURCE directory to DEST. DEST must not already exist."
  (let ((parent (uiop:pathname-parent-directory-pathname
                 (uiop:ensure-directory-pathname dest))))
    (ensure-directories-exist parent)
    (run-command! (move-directory-argv source dest))))
