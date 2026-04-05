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
