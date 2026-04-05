(in-package #:area51)

;;; Quicklisp distribution index fetcher and parser.
;;; Uses Quicklisp only as a download source — no ql:quickload at runtime.

(defparameter *quicklisp-dist-url*
  "https://beta.quicklisp.org/dist/quicklisp.txt"
  "URL for the Quicklisp distribution metadata.")

(defparameter *quicklisp-cache-dir*
  (merge-pathnames "quicklisp/" *area51-home*)
  "Local cache for Quicklisp dist index files.")

(defparameter *quicklisp-index* nil
  "In-memory cache: hash-table of system-name -> release info.")

;;; --- Dist metadata ---

(defun parse-distinfo (text)
  "Parse quicklisp.txt key: value format into an alist."
  (let ((result nil))
    (with-input-from-string (s text)
      (loop for line = (read-line s nil nil)
            while line
            do (let ((pos (position #\: line)))
                 (when pos
                   (push (cons (string-trim " " (subseq line 0 pos))
                               (string-trim " " (subseq line (1+ pos))))
                         result)))))
    (nreverse result)))

(defun fetch-distinfo ()
  "Fetch and parse the Quicklisp dist metadata."
  (multiple-value-bind (output code)
      (run-command (format nil "curl -sL ~a" *quicklisp-dist-url*))
    (unless (zerop code)
      (error "Failed to fetch Quicklisp dist info from ~a" *quicklisp-dist-url*))
    (parse-distinfo output)))

;;; --- Index fetching ---

(defun quicklisp-index-path (filename)
  (merge-pathnames filename *quicklisp-cache-dir*))

(defun fetch-quicklisp-file (url filename)
  "Download a Quicklisp index file to the cache directory."
  (ensure-directories-exist *quicklisp-cache-dir*)
  (let ((dest (namestring (quicklisp-index-path filename))))
    (multiple-value-bind (output code)
        (run-command (format nil "curl -sL -o ~a ~a" dest url))
      (declare (ignore output))
      (unless (zerop code)
        (error "Failed to download ~a" url)))
    dest))

(defun quicklisp-index-fresh-p ()
  "Check if the cached index is less than 24 hours old."
  (let ((path (quicklisp-index-path "releases.txt")))
    (when (probe-file path)
      (let* ((file-time (file-write-date path))
             (now (get-universal-time))
             (age (- now file-time)))
        (< age (* 24 60 60))))))

(defun ensure-quicklisp-index ()
  "Ensure we have a fresh local copy of the Quicklisp index.
   Returns the dist version string."
  (if (quicklisp-index-fresh-p)
      ;; Read cached dist version
      (let ((meta-path (quicklisp-index-path "dist-version.txt")))
        (when (probe-file meta-path)
          (string-trim '(#\Newline #\Space)
                       (uiop:read-file-string meta-path))))
      ;; Fetch fresh index
      (let ((distinfo (fetch-distinfo)))
        (let ((release-url (cdr (assoc "release-index-url" distinfo :test #'string=)))
              (system-url (cdr (assoc "system-index-url" distinfo :test #'string=)))
              (version (cdr (assoc "version" distinfo :test #'string=))))
          (format t "Updating Quicklisp index (~a)...~%" version)
          (fetch-quicklisp-file release-url "releases.txt")
          (fetch-quicklisp-file system-url "systems.txt")
          ;; Save dist version
          (let ((meta-path (quicklisp-index-path "dist-version.txt")))
            (with-open-file (out meta-path :direction :output :if-exists :supersede)
              (write-string version out)))
          ;; Clear in-memory cache
          (setf *quicklisp-index* nil)
          version))))

;;; --- Index parsing ---

(defun parse-releases-txt ()
  "Parse releases.txt into a hash-table: project-name -> plist.
   Plist keys: :url :size :md5 :sha1 :prefix :system-files"
  (let ((path (quicklisp-index-path "releases.txt"))
        (table (make-hash-table :test 'equal)))
    (with-open-file (in path :direction :input)
      (loop for line = (read-line in nil nil)
            while line
            unless (or (zerop (length line))
                       (char= (char line 0) #\#))
              do (let* ((fields (split-string-by-space line))
                        (name (first fields))
                        (url (second fields))
                        (size (parse-integer (third fields) :junk-allowed t))
                        (md5 (fourth fields))
                        (sha1 (fifth fields))
                        (prefix (sixth fields))
                        (system-files (nthcdr 6 fields)))
                   (setf (gethash name table)
                         (list :url url
                               :size size
                               :md5 md5
                               :sha1 sha1
                               :prefix prefix
                               :system-files system-files)))))
    table))

(defun parse-systems-txt ()
  "Parse systems.txt into a hash-table: system-name -> plist.
   Plist keys: :project :system-file :dependencies"
  (let ((path (quicklisp-index-path "systems.txt"))
        (table (make-hash-table :test 'equal)))
    (with-open-file (in path :direction :input)
      (loop for line = (read-line in nil nil)
            while line
            unless (or (zerop (length line))
                       (char= (char line 0) #\#))
              do (let* ((fields (split-string-by-space line))
                        (project (first fields))
                        (system-file (second fields))
                        (system-name (third fields))
                        (deps (nthcdr 3 fields)))
                   ;; Only store primary system (first occurrence)
                   (unless (gethash system-name table)
                     (setf (gethash system-name table)
                           (list :project project
                                 :system-file system-file
                                 :dependencies deps))))))
    table))

(defun split-string-by-space (string)
  "Split a string by spaces, returning a list of non-empty substrings."
  (let ((result nil)
        (start 0)
        (len (length string)))
    (loop
      (when (>= start len) (return))
      ;; Skip spaces
      (let ((non-space (position #\Space string :start start :test-not #'char=)))
        (unless non-space (return))
        (setf start non-space))
      ;; Find end of token
      (let ((space (position #\Space string :start start)))
        (push (subseq string start (or space len)) result)
        (setf start (or space len))))
    (nreverse result)))

;;; --- Lookup ---

(defun build-quicklisp-index ()
  "Build the combined in-memory index.
   Returns hash-table: system-name -> plist with :project, :url, :sha1, :prefix, etc."
  (let ((releases (parse-releases-txt))
        (systems (parse-systems-txt))
        (index (make-hash-table :test 'equal)))
    (maphash (lambda (system-name system-info)
               (let* ((project (getf system-info :project))
                      (release (gethash project releases)))
                 (when release
                   (setf (gethash system-name index)
                         (list :project project
                               :system-file (getf system-info :system-file)
                               :dependencies (getf system-info :dependencies)
                               :url (getf release :url)
                               :size (getf release :size)
                               :md5 (getf release :md5)
                               :sha1 (getf release :sha1)
                               :prefix (getf release :prefix))))))
             systems)
    index))

(defun get-quicklisp-index ()
  "Get the in-memory Quicklisp index, building it if needed."
  (unless *quicklisp-index*
    (setf *quicklisp-index* (build-quicklisp-index)))
  *quicklisp-index*)

(defun quicklisp-lookup (system-name)
  "Look up a system in the Quicklisp index.
   Returns a plist or nil if not found."
  (ensure-quicklisp-index)
  (gethash system-name (get-quicklisp-index)))

;;; --- Download and extract ---

(defun download-quicklisp-package (system-name)
  "Download and extract a Quicklisp package.
   Returns the path to the extracted package directory, or nil on failure."
  (let ((info (quicklisp-lookup system-name)))
    (unless info
      (return-from download-quicklisp-package nil))
    (let* ((project (getf info :project))
           (url (getf info :url))
           (prefix (getf info :prefix))
           (cache-dir (package-cache-dir project))
           (tarball-path (namestring
                          (merge-pathnames (format nil "~a.tgz" project)
                                           *quicklisp-cache-dir*))))
      ;; Already extracted?
      (when (probe-file cache-dir)
        (return-from download-quicklisp-package cache-dir))
      ;; Download tarball
      (ensure-directories-exist *quicklisp-cache-dir*)
      (ensure-area51-dirs)
      (multiple-value-bind (output code)
          (run-command (format nil "curl -sL -o ~a ~a" tarball-path url))
        (declare (ignore output))
        (unless (zerop code)
          (format *error-output* "Failed to download ~a~%" url)
          (return-from download-quicklisp-package nil)))
      ;; Extract tarball into packages dir
      ;; Quicklisp tarballs extract to a prefix/ directory
      (multiple-value-bind (output code)
          (run-command (format nil "tar xzf ~a -C ~a"
                               tarball-path (namestring *packages-dir*)))
        (declare (ignore output))
        (unless (zerop code)
          (format *error-output* "Failed to extract ~a~%" tarball-path)
          (return-from download-quicklisp-package nil)))
      ;; Rename prefix dir to project name if different
      (let ((extracted-dir (merge-pathnames (format nil "~a/" prefix)
                                            *packages-dir*)))
        (unless (string= (namestring extracted-dir)
                          (namestring cache-dir))
          (rename-file extracted-dir cache-dir)))
      ;; Clean up tarball
      (delete-file tarball-path)
      cache-dir)))
