(defpackage #:area51-test
  (:use #:cl #:fiveam)
  (:export #:run-tests #:finish-tests))

(in-package #:area51-test)

(def-suite area51-tests
  :description "area51 test suite")

(in-suite area51-tests)

(defun finish-tests (passed)
  "Signal an error unless PASSED is true. FiveAM's RUN! returns NIL on failure."
  (unless passed
    (error "area51 tests failed"))
  passed)

(defun run-tests ()
  (finish-tests (fiveam:run! 'area51-tests)))
