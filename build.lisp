;;; Build script for area51
;;; Usage: sbcl --load build.lisp

(require :asdf)
(push (truename ".") asdf:*central-registry*)
(asdf:load-system "area51")

(ensure-directories-exist "bin/")
(sb-ext:save-lisp-and-die "bin/area51"
  :toplevel (lambda ()
              (area51:main)
              (sb-ext:exit))
  :executable t
  :compression t)
