(require :asdf)

(push (make-pathname :defaults *load-pathname*
		 :name nil
		 :type nil
		 :directory (butlast (pathname-directory *load-pathname*)))
      asdf:*central-registry*)

(with-output-to-string (*trace-output*)
  (with-output-to-string (*standard-output*)
      (asdf:load-system :daemonization)))

(defparameter *daemon-conf* '(:main-function  nil
			      :pid-file "my-daemon-exp"
			      :exit nil
			      :name nil
			      :user nil
			      :group nil
			      :before-parent-exit-fn nil)) 

(defun daemon-cmd (cmd)
  (daemonization:daemonized cmd *daemon-conf* :on-error :as-ignore-errors))

(defun daemon-status ()
  (daemonization:daemonized "status" *daemon-conf* :on-error :as-ignore-errors))

(princ "Tests daemonized ... ")
(defparameter *parent-pid* (daemonization:getpid))
(terpri)
(block tests 
  (flet ((return-if-child () 
	   (when (/= *parent-pid* (daemonization:getpid))
	     (return-from tests t))))
    (if (and 
	 (progn (format t "~%try start ...~%") (daemon-cmd "start") (return-if-child) (eql daemon-share:ex-ok (daemon-status)))
	 (progn (format t "~%try stop ...~%") (daemon-cmd "stop") (not (eql daemon-share:ex-ok (daemon-status))))
	 (progn (format t "~%try start ...~%") (daemon-cmd "start") (return-if-child) (eql daemon-share:ex-ok (daemon-status)))
	 (progn (format t "~%try kill ...~%") (daemon-cmd "kill") (not (eql daemon-share:ex-ok (daemon-status))))
	 (progn (format t "~%try start ...~%") (daemon-cmd "start") (return-if-child) (eql daemon-share:ex-ok (daemon-status)))
	 (progn (format t "~%try restart ...~%") (daemon-cmd "restart") (return-if-child) (eql daemon-share:ex-ok (daemon-status)))
	 (progn (format t "~%try stop ...~%")(daemon-cmd "stop") (not (eql daemon-share:ex-ok (daemon-status))))

	 #|(let ((*daemon-conf* *daemon-conf*))
	   (format t "~%--- TRY CHANGE USER --~%")
	   (setf (getf *daemon-conf* :user) "lispuser")
	   (and 
	    (progn (format t "~%try start ...~%") (daemon-cmd "start") (return-if-child) (eql daemon-share:ex-ok (daemon-status)))
	    (progn (format t "~%try stop ...~%") (daemon-cmd "stop") (not (eql daemon-share:ex-ok (daemon-status))))))
	 |#
	 )
	(princ " ... Tests passed.")
	(princ " ... Tests failed."))
    (terpri)
    (quit)))