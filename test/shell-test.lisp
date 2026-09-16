(in-package #:area51-test)

(def-suite shell-tests :in area51-tests)
(in-suite shell-tests)

(test run-command-rejects-shell-string
  "A concatenated shell string must not be accepted."
  (signals error (area51::run-command "true")))

(test git-clone-argv-keeps-metacharacters-as-one-arg
  (is (equal '("git" "clone" "--" "https://example.com/x.git;rm -rf /" "/tmp/dest")
             (area51::git-clone-argv "https://example.com/x.git;rm -rf /" "/tmp/dest"))))

(test git-checkout-argv-uses-double-dash
  (is (equal '("git" "checkout" "--" "-rf")
             (area51::git-checkout-argv "-rf"))))

(test curl-argv-separates-url
  (is (equal '("curl" "-fsSL" "--" "http://x/;touch /tmp/pwned")
             (area51::curl-argv "http://x/;touch /tmp/pwned")))
  (is (equal '("curl" "-fsSL" "-o" "/tmp/out" "--" "http://x")
             (area51::curl-argv "http://x" :output-file "/tmp/out"))))

(test tar-extract-argv-is-a-list
  (is (equal '("tar" "-xzf" "/tmp/a.tgz" "-C" "/tmp/out")
             (area51::tar-extract-argv "/tmp/a.tgz" "/tmp/out"))))

(test lisp-eval-argv-is-not-a-shell-string
  (let ((argv (area51::lisp-eval-argv "(+ 1 1)")))
    (is (listp argv))
    (is (string= "sbcl" (first argv)))
    (is (not (member "cd" argv :test #'string=)))
    (is (notany (lambda (s) (search " && " s)) argv))))

(test run-command-directory-with-space
  "Working directory is passed as :directory, so paths with spaces work."
  (let ((dir (uiop:ensure-pathname
              (format nil "~aarea51 argv space-~a/"
                      (uiop:temporary-directory)
                      (random 1000000))
              :ensure-directory t)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (area51::run-command! (list "git" "init") :directory dir)
           (let ((out (area51::run-command!
                       (list "git" "rev-parse" "--is-inside-work-tree")
                       :directory dir)))
             (is (string= "true"
                          (string-trim '(#\Newline #\Space) out)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test copy-executable-keeps-execute-bit
  "upgrade must not drop +x the way uiop:copy-file does."
  (let* ((dir (uiop:ensure-pathname
               (format nil "~aarea51-copy-exec-~a/"
                       (uiop:temporary-directory)
                       (random 1000000))
               :ensure-directory t))
         (src (merge-pathnames "src.sh" dir))
         (dst (merge-pathnames "dst.sh" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (with-open-file (out src :direction :output :if-exists :supersede)
             (format out "#!/bin/sh~%echo ok~%"))
           (area51::run-command! (list "chmod" "+x" (namestring src)))
           (area51::copy-executable src dst)
           (multiple-value-bind (out code)
               (area51::run-command (list (namestring dst)))
             (declare (ignore out))
             (is (zerop code))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))
