(in-package #:area51)

(defun run-command (command &key (output :string))
  "Run a shell command, return (values output exit-code)"
  (let ((error-output (if (eq output :interactive) :interactive :string)))
    (multiple-value-bind (out err code)
        (uiop:run-program command
                          :output output
                          :error-output error-output
                          :ignore-error-status t)
      (declare (ignore err))
      (values out code))))

(defun run-command! (command)
  "Run a shell command, signal error on failure"
  (multiple-value-bind (out code) (run-command command)
    (unless (zerop code)
      (error "Command failed (~d): ~a" code command))
    out))

(defun git-clone (url dest &key ref)
  "Clone a git repository"
  (run-command! (format nil "git clone ~a ~a" url dest))
  (when ref
    (run-command! (format nil "cd ~a && git checkout ~a" dest ref))))

(defun git-rev-parse (dir)
  "Get current commit SHA"
  (string-trim '(#\Newline #\Space)
               (run-command! (format nil "cd ~a && git rev-parse HEAD" dir))))
