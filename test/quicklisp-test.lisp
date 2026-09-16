(in-package #:area51-test)

(def-suite quicklisp-tests :in area51-tests)
(in-suite quicklisp-tests)

(test parse-distinfo-basic
  "Parse key: value format."
  (let ((result (area51::parse-distinfo "name: quicklisp
version: 2026-01-01
release-index-url: http://example.com/releases.txt")))
    (is (= 3 (length result)))
    (is (string= "quicklisp" (cdr (assoc "name" result :test #'string=))))
    (is (string= "2026-01-01" (cdr (assoc "version" result :test #'string=))))))

(test split-string-by-space-basic
  "Split handles multiple spaces and edge cases."
  (is (equal '("a" "b" "c") (area51::split-string-by-space "a b c")))
  (is (equal '("a" "b") (area51::split-string-by-space "  a   b  ")))
  (is (null (area51::split-string-by-space "")))
  (is (equal '("single") (area51::split-string-by-space "single"))))

(defun make-ql-temp (prefix)
  (uiop:ensure-pathname
   (format nil "~a~a-~a-~a/"
           (uiop:temporary-directory) prefix
           (get-universal-time) (random 1000000))
   :ensure-directory t))

(test prefer-https-url-upgrades-http
  (is (string= "https://beta.quicklisp.org/dist/quicklisp.txt"
               (area51::prefer-https-url
                "http://beta.quicklisp.org/dist/quicklisp.txt")))
  (is (string= "https://example.com/a.tgz"
               (area51::prefer-https-url "https://example.com/a.tgz"))))

(test incomplete-index-is-not-fresh
  (let ((dir (make-ql-temp "area51-ql-incomplete")))
    (unwind-protect
         (let ((area51::*quicklisp-cache-dir* dir))
           (ensure-directories-exist dir)
           (with-open-file (out (area51::quicklisp-index-path "releases.txt")
                                :direction :output)
             (write-string "project http://x 1 md5 sha1 prefix" out))
           (is (not (area51::quicklisp-index-fresh-p))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test complete-index-can-be-fresh
  (let ((dir (make-ql-temp "area51-ql-complete")))
    (unwind-protect
         (let ((area51::*quicklisp-cache-dir* dir))
           (ensure-directories-exist dir)
           (dolist (name '("releases.txt" "systems.txt" "dist-version.txt"))
             (with-open-file (out (area51::quicklisp-index-path name)
                                  :direction :output)
               (write-string "ok" out)))
           (is (area51::quicklisp-index-fresh-p)))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test verify-release-archive-rejects-size-mismatch
  (let ((dir (make-ql-temp "area51-ql-size")))
    (unwind-protect
         (let ((path (merge-pathnames "a.tgz" dir)))
           (ensure-directories-exist dir)
           (with-open-file (out path :direction :output)
             (write-string "hello" out))
           (signals area51::archive-integrity-error
             (area51::verify-release-archive path (list :size 1))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test verify-release-archive-rejects-sha1-mismatch
  (let ((dir (make-ql-temp "area51-ql-sha1")))
    (unwind-protect
         (let ((path (merge-pathnames "a.tgz" dir)))
           (ensure-directories-exist dir)
           (with-open-file (out path :direction :output)
             (write-string "hello" out))
           (signals area51::archive-integrity-error
             (area51::verify-release-archive
              path (list :sha1 "0000000000000000000000000000000000000000"))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test verify-release-archive-accepts-matching-sha1
  (let ((dir (make-ql-temp "area51-ql-sha1-ok")))
    (unwind-protect
         (let ((path (merge-pathnames "a.tgz" dir)))
           (ensure-directories-exist dir)
           (with-open-file (out path :direction :output)
             (write-string "hello" out))
           (let ((sha1 (area51::file-digest "sha1" path))
                 (size (area51::file-byte-size path)))
             (is (equal path
                        (area51::verify-release-archive
                         path (list :size size :sha1 sha1))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))
