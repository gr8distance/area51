(in-package #:area51-test)

(def-suite status-tests :in area51-tests)
(in-suite status-tests)

(defun make-temp-dir (prefix)
  (uiop:ensure-pathname
   (format nil "~a~a-~a-~a/"
           (uiop:temporary-directory)
           prefix
           (get-universal-time)
           (random 1000000))
   :ensure-directory t))

(test finish-tests-passes-through-success
  "A true FiveAM result is returned unchanged."
  (is (eq t (finish-tests t))))

(test finish-tests-errors-on-failure
  "A false FiveAM result becomes an error, so test-op cannot stay green."
  (signals error (finish-tests nil)))

(test test-op-invokes-run-tests
  "area51-test.asd must call RUN-TESTS, not RUN! alone."
  (let* ((asd (asdf:system-source-file "area51-test"))
         (text (uiop:read-file-string asd)))
    (is (search "run-tests" text))
    (is (not (search "fiveam :run!" text)))))

(test quit-unless-zero-returns-zero
  (is (zerop (area51::quit-unless-zero 0 (lambda (code)
                                          (error "should not exit ~a" code))))))

(test quit-unless-zero-forwards-nonzero
  "Non-zero child status is passed to EXIT instead of being dropped."
  (let ((seen nil))
    (area51::quit-unless-zero 23 (lambda (code) (setf seen code)))
    (is (= 23 seen))))

(test resolved-packages-or-error-ok
  (let ((resolved '((:name "alexandria"))))
    (is (eq resolved (area51::resolved-packages-or-error resolved nil)))))

(test resolved-packages-or-error-signals
  (let ((*error-output* (make-broadcast-stream)))
    (signals area51::unresolved-dependencies
      (area51::resolved-packages-or-error nil '("missing-lib")))))

(test resolve-all-signals-when-unresolved
  "A missing dep must not return a partial result that install could lock."
  (let ((*error-output* (make-broadcast-stream)))
    (signals area51::unresolved-dependencies
      (area51::resolve-all
       (list :dependencies (list (list :name "missing-lib-xyz")))
       :resolve-dep-fn (lambda (dep)
                         (declare (ignore dep))
                         nil)))))

(test resolve-all-succeeds-with-stub
  (let* ((dir (make-temp-dir "area51-resolve-ok"))
         (config (list :dependencies (list (list :name "stub-lib")))))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (let ((resolved
                   (area51::resolve-all
                    config
                    :resolve-dep-fn (lambda (dep)
                                      (declare (ignore dep))
                                      dir))))
             (is (= 1 (length resolved)))
             (is (string= "stub-lib" (getf (first resolved) :name)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))
