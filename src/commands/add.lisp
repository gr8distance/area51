(in-package #:area51)

(defun parse-package-source (args)
  "Parse package source from arguments."
  (let ((url nil)
        (ref nil)
        (source :github))
    (loop for (key val) on args by #'cddr
          do (cond
               ((string= key "--github")
                (setf source :github
                      url (format nil "https://github.com/~a" val)))
               ((string= key "--url")
                (setf source :github
                      url val))
               ((string= key "--ref")
                (setf ref val))))
    (values source url ref)))

(defun find-project-asd (name)
  "Find the project's .asd file."
  (let ((path (merge-pathnames (format nil "~a.asd" name)
                               (uiop:getcwd))))
    (when (probe-file path) path)))

(defun asd-add-dep (asd-path dep-name)
  "Add a dependency to the .asd file's :depends-on."
  (let* ((content (uiop:read-file-string asd-path))
         (form (with-input-from-string (s content)
                 (let ((*read-eval* nil)) (read s)))))
    (when (and (listp form)
               (symbolp (car form))
               (string-equal (symbol-name (car form)) "DEFSYSTEM"))
      (let* ((plist (cddr form))
             (current-deps (loop for (k v) on plist by #'cddr
                                 when (and (symbolp k)
                                           (string-equal (symbol-name k) "DEPENDS-ON"))
                                   return v)))
        (unless (member dep-name current-deps :test #'string-equal
                                              :key (lambda (d)
                                                     (if (symbolp d)
                                                         (symbol-name d)
                                                         (princ-to-string d))))
          ;; Replace :depends-on in the file text
          (let* ((new-deps (append current-deps (list dep-name)))
                 (old-dep-str (format nil ":depends-on ~s" current-deps))
                 (new-dep-str (format nil ":depends-on (~{~s~^ ~})"
                                      (mapcar (lambda (d)
                                                (if (symbolp d)
                                                    (string-downcase (symbol-name d))
                                                    d))
                                              new-deps)))
                 ;; Also handle empty list case
                 (content (if (search old-dep-str content)
                              (uiop:strcat
                               (subseq content 0 (search old-dep-str content))
                               new-dep-str
                               (subseq content (+ (search old-dep-str content)
                                                  (length old-dep-str))))
                              ;; Try matching ":depends-on ()" or ":depends-on NIL"
                              (let ((pos (search ":depends-on" content
                                                 :test #'char-equal)))
                                (when pos
                                  (let ((after (subseq content pos)))
                                    ;; Find the closing paren of depends-on value
                                    (multiple-value-bind (val end)
                                        (let ((*read-eval* nil))
                                          (read-from-string after nil nil
                                                            :start (length ":depends-on")))
                                      (declare (ignore val))
                                      (uiop:strcat
                                       (subseq content 0 pos)
                                       new-dep-str
                                       (subseq content (+ pos end))))))))))
            (when content
              (with-open-file (out asd-path :direction :output
                                            :if-exists :supersede)
                (write-string content out)))))))))

(defun asd-remove-dep (asd-path dep-name)
  "Remove a dependency from the .asd file's :depends-on."
  (let* ((content (uiop:read-file-string asd-path))
         (form (with-input-from-string (s content)
                 (let ((*read-eval* nil)) (read s)))))
    (when (and (listp form)
               (symbolp (car form))
               (string-equal (symbol-name (car form)) "DEFSYSTEM"))
      (let* ((plist (cddr form))
             (current-deps (loop for (k v) on plist by #'cddr
                                 when (and (symbolp k)
                                           (string-equal (symbol-name k) "DEPENDS-ON"))
                                   return v))
             (new-deps (remove-if (lambda (d)
                                    (string-equal dep-name
                                                  (if (symbolp d)
                                                      (symbol-name d)
                                                      d)))
                                  current-deps))
             (old-dep-str (format nil ":depends-on ~s" current-deps))
             (new-dep-str (if new-deps
                              (format nil ":depends-on (~{~s~^ ~})"
                                      (mapcar (lambda (d)
                                                (if (symbolp d)
                                                    (string-downcase (symbol-name d))
                                                    d))
                                              new-deps))
                              ":depends-on ()")))
        (when (search old-dep-str content)
          (let ((new-content
                  (uiop:strcat
                   (subseq content 0 (search old-dep-str content))
                   new-dep-str
                   (subseq content (+ (search old-dep-str content)
                                      (length old-dep-str))))))
            (with-open-file (out asd-path :direction :output
                                          :if-exists :supersede)
              (write-string new-content out))))))))

(defun cmd-add (args)
  "Add a dependency to the project"
  (when (null args)
    (format *error-output* "Usage: area51 add <package-name> [--github user/repo] [--url URL] [--ref REF]~%")
    (uiop:quit 1))
  (let* ((name (first args))
         (rest-args (rest args))
         (config (ensure-config)))
    (multiple-value-bind (source url ref)
        (parse-package-source rest-args)
      (let ((new-config (config-add-dep config name
                                        :source source
                                        :url url
                                        :ref ref)))
        (write-config new-config)
        ;; Update .asd file
        (let ((asd-path (find-project-asd (config-value config :name))))
          (when asd-path
            (asd-add-dep asd-path name)))
        (format t "Added ~a~%" name)))))
