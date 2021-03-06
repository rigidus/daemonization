(defpackage :daemon-logging 
  (:use :cl)
  (:export #:log-info #:log-err #:defun-ext #:wrap-log
	   #:print-log-info-p #:print-log-err-p
	   #:log-indent #:log-indent-size
	   #:print-log-layer-p #:print-internal-call-p
	   #:print-called-form-with-result-p
	   #:fn-log-info #:fn-log-err #:fn-log-trace 	   
	   #:*log-prefix*
	   #:add-daemon-log #:get-daemon-log-list
	   #:print-log-datetime-p
	   #:disabled-functions-logging
	   #:disabled-layers-logging
	   #:*process-type*
	   
	   #:create-log-plist
	   #:get-log-layer
	   #:*log-mode*
	   #:*trace-fn*
	   #:*trace-type*

	   #:base-logger
	   #:*logger*
	   #:fn-create-log-plist #:fn-correct-log-plist
	   #:fn-wrapped-begin-fmt-str #:fn-print-pair 
	   #:fn-get-datetime
	   #:print-call-p

	   ;;Utils
	   #:with-tmp-logger))

(in-package :daemon-logging)

;;; Logging configure parameters
(defparameter *log-prefix* nil)

(defparameter *simple-log* nil)

(defparameter *process-type* nil)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Logging for actions on differently layers, for using
;;; defining +log-layer+ (if it not defining then reading name of current package), 
;;; fn-log-info, and fn-log-err slots of object into *logger* special variable. Example:

(defconstant +log-layer+ :logging-layer)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;; Logging native parameter ;;;;;;;;;;
;;; For added log strings
(defparameter *daemon-logs* nil)

;;; For defun-ext and wrap-fmt-str ;;;;;;;;;;;;;;;;;;
(defparameter *def-in-package* nil)
(defparameter *trace-fn* nil)

;;; For pointing logging mode ;;;;;;;;;;;;;;;;;;;;;;
(defparameter *log-mode* :info "Must be (or :trace :info :error)")
(defparameter *trace-type* nil "Must be (or :call :result)")
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;; Main logger structure ;;;;;;;;;;;;;;;;;;;
(defstruct base-logger 
  (fn-log-info #'(lambda (fmt-str &rest args)
		   (apply #'format t fmt-str args)))
  (fn-log-err #'(lambda (fmt-str &rest args)
		  (apply #'format t fmt-str args)))
  (fn-log-trace #'(lambda (fmt-str)
		     (funcall #'princ fmt-str)))
  (fn-create-log-plist (lambda (fmt-str &key extra-fmt-str (indent ""))
			 (list :message (concatenate 'string indent fmt-str)
			       :extra-message extra-fmt-str)))
  (fn-correct-log-plist #'identity)
  (fn-wrapped-begin-fmt-str nil)
  (fn-print-pair (lambda (pair)
		   (format nil " ~S ~S" (first pair) (second pair))))
  (fn-get-datetime (lambda ()
		     (multiple-value-bind (sec min hour date month year)
			 (get-decoded-time)
		       (format nil "~D.~2,'0D.~2,'0D ~2,'0D:~2,'0D:~2,'0D"
			       year month date hour min sec))))
  
  (log-indent 0)
  (log-indent-size 2)
  (print-call-p t)
  (print-called-form-with-result-p t)
  (print-internal-call-p t)
  (print-log-info-p t)
  (print-log-err-p t)
  (print-log-layer-p t)
  (print-log-datetime-p nil)

  (disabled-functions-logging nil)
  (disabled-layers-logging nil)
  )

(declaim (type (or null base-logger) *logger*))
(defparameter *logger* (make-base-logger) "Contains logger object with the parameters for controlling logging operations")
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun add-daemon-log (log)
  (push log *daemon-logs*)
  log)

(defun get-daemon-log-list ()
  (nth-value 0 (read-from-string (format nil 
				       "(~A)"
				       (apply #'concatenate 'string (reverse *daemon-logs*))))))

(defun get-indent ()
  (make-string (base-logger-log-indent *logger*) :initial-element #\Space))

(defun get-fn-log-info () (base-logger-fn-log-info *logger*))
(defun get-fn-log-err () (base-logger-fn-log-err *logger*))
(defun get-fn-log-trace () (base-logger-fn-log-trace *logger*))

(defun get-log-layer ()
  (let ((layer-sym (when *def-in-package* (find-symbol (symbol-name '+LOG-LAYER+) *def-in-package*))))
    (if (and layer-sym (boundp layer-sym)) 
	(symbol-value layer-sym)
	(read-from-string (concatenate 'string ":" (package-name (or *def-in-package* *package*)))))))

;;; Checking
;(get-log-layer)
;(log-info "test")
;(log-info "test: ~S")
;(syslog-info "test")
;(defun-ext f (x y) (log-info "this f") (+ x (g y)))
;(defun-ext g (x) (log-info "this g") (* x x))
;(f 3 4)
;;;;;;;;;;;;;;;;;



;;;;; Utils ;;;;;;;;;;;;;;
(defmacro with-tmp-slots (slots-newvals obj &body body 
			  &aux slots s-slots s-oldvals s-obj)
  (setf slots (mapcar #'first slots-newvals)
	s-slots (gentemp "SLOTS-")
	s-oldvals (gentemp "OLDVALS-")
	s-obj (gentemp "OBJ-"))
  `(let ((,s-obj ,obj))
     (with-slots ,slots ,s-obj
     (let ((,s-oldvals (list ,@slots))
	   (,s-slots ',slots))
       (prog2
	   (progn ,@(mapcar #'(lambda (x) (cons 'setf x))
			    slots-newvals))
	   (progn ,@body)
	 (loop 
	    :for slot :in ,s-slots
	    :for oldval :in ,s-oldvals
	    :do (setf (slot-value ,s-obj slot) oldval)))))))

(defmacro with-tmp-logger (slots-newvals &body body)
  `(with-tmp-slots ,slots-newvals *logger*
     ,@body))

(defmacro create-log-plist (&rest details)
  (cons 'append 
	(loop 
	   for detail in details
	   for key = (first detail)
	   for message = (second detail)
	   if (= 2 (length detail)) do (setq detail (append detail '(t)))
	   collect `(when ,(third detail) (list ,key ,message)))))
	  
(defun wrap-fmt-str (fmt-str &key extra-fmt-str (indent "") &aux log-plist)
  (with-slots (fn-create-log-plist 
	       fn-correct-log-plist
	       fn-wrapped-begin-fmt-str
	       fn-print-pair)
      *logger*
    (when *simple-log* 
      (return-from wrap-fmt-str fmt-str))
    (setq log-plist (funcall fn-create-log-plist
			     fmt-str 
			     :extra-fmt-str extra-fmt-str
			     :indent indent))
    (when fn-correct-log-plist (setf log-plist (funcall fn-correct-log-plist log-plist)))
    (apply 'concatenate 
	   (append (list 'string (string #\Newline) "(")
		   (when fn-wrapped-begin-fmt-str
		     (multiple-value-bind (begin-str log-pl) 
			 (funcall fn-wrapped-begin-fmt-str log-plist indent)
		       (prog1 (when begin-str (list begin-str))
			 (when log-pl (setf log-plist log-pl)))))
		   (loop
		      :for pair :on log-plist :by #'cddr 
		      :for log-cur-str = (funcall fn-print-pair (subseq pair 0 2))
		      :if log-cur-str :collect (concatenate 'string " " log-cur-str))
		   (list ")")))))

(defun slashing-str (str)
  (if (not (stringp str))
      str
      (loop 
	 for char across str
	 when (char= #\" char) collect #\\ into result
	 collect char into result
	 finally (return (coerce result 'string)))))

(defun slashing-str-args (args)
  (mapcar (lambda (arg) 	
	    (if (not (stringp arg))
		arg
		(slashing-str arg)))
	  args))

(defun logging (fn-log format-str &rest args)
  (let ((*print-pretty* nil)) 
    (apply fn-log (funcall #'wrap-fmt-str format-str :indent (get-indent)) (slashing-str-args args))))


(defmacro log-share ((format-str &rest args) getter-fn-log var-control log-mode)
  `(let ((fn-log (,getter-fn-log)))
     (when (and fn-log ,var-control)
       (let ((*def-in-package* (load-time-value *package*))
	     (*log-mode* ,log-mode))
	 (logging fn-log ,format-str ,@args)))))

(defmacro log-info (format-str &rest args)
  `(log-share (,format-str ,@args) get-fn-log-info (base-logger-print-log-info-p *logger*) :info))

(defmacro log-err (format-str &rest args)
  `(log-share (,format-str ,@args) get-fn-log-err (base-logger-print-log-err-p *logger*) :error))

(defun syslog-trace (form-str &key extra-form-str trace-type)
  (declare (type (member :call :result) trace-type)
	   (type string form-str)
	   (type (or null string) extra-form-str))
  (let ((*log-mode* :trace)
	(*trace-type* trace-type)
	(*print-pretty* nil))
    (funcall (get-fn-log-trace) (funcall #'wrap-fmt-str
					 form-str
					 :extra-fmt-str extra-form-str
					 :indent (get-indent)))))
			        
(defun syslog-call-into (form-str)
  (syslog-trace form-str :trace-type :call)
  (incf (base-logger-log-indent *logger*) (base-logger-log-indent-size *logger*)))
  
(defun syslog-call-out (result-form-str &optional called-form-str)  
  (decf (base-logger-log-indent *logger*) (base-logger-log-indent-size *logger*))
  (if (< (base-logger-log-indent *logger*) 0)
      (error "(base-logger-log-indent *logger*) not must be less zero. Not correct log operation."))
  (syslog-trace result-form-str :extra-form-str called-form-str :trace-type :result))
  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmacro with-gensyms ((&rest vars) &body body)
  `(let ,(loop for var in vars collect `(,var (gensym)))
     ,@body))

(eval-when (:compile-toplevel :load-toplevel)
  (defun remove-declare-ignore (body)
    (flet ((declare-ignore-form-p (form &aux (fst-sym (first form)))
	     (and (eq 'declare fst-sym)
		  (member (first (second form))
			  '(ignore ignorable)))))
      (loop for form in body 
	 when (or (atom form) (not (declare-ignore-form-p form)))
	 collect form)))

  ;(remove-declare-ignore '((declare (ignore x)) (declare (ignorable y)) (+ 3 2) t))    

  (defun present-args (args)
    (flet ((as-keyword (sym)
	     (if (keywordp sym)
		 sym
		 (read-from-string 
		  (concatenate 'string ":" (symbol-name sym))))))
      (loop
	 with cur-arg-type
	 with result
	 for arg in args
	 do (if (and (symbolp arg) (char= #\& (elt (symbol-name arg) 0)))
		(setq cur-arg-type arg)
		(if (null cur-arg-type)
		    (push arg result)
		    (case cur-arg-type
		      (&optional (push (if (atom arg) 
					   arg
					   (first arg))
				     result))
		      (&key (let ((arg (if (atom arg) 
					   arg
					   (first arg))))
			      (push (as-keyword arg) result)
			      (push arg result)))
		      (&rest (push ''&rest result)
			     (push arg result))
		      (&aux nil))))
	 finally (return (reverse result)))))
  ;(present-args '("no-daemon"))
  ;(present-args '(x y &optional (v 34) &key r m))    

  (defun is-special-or-macro-p (fn-sym)
    (or (special-operator-p fn-sym) (macro-function fn-sym)))
  );eval-when 

(defun correct-sym (sym)
    (format nil 
	    (if (eql (symbol-package sym)
		     (find-package *def-in-package*))
		"~A"
		"~S")
	    sym))

#|(defun present-function (function)  
  (third (multiple-value-list (function-lambda-expression function))))
|#

(defun object-is-not-printable-p (obj)
  (handler-case (let ((*print-readably* t)) 
		  (format nil "~S" obj)
		  nil)
    (print-not-readable () t)))

(defun str-list-close (str)
  (concatenate 'string
	       (subseq str 0 (1- (length str)))
	       ")"))

(defun present-form (&optional form &rest extra-forms)
  (cond 
    ((null form) "NIL")
    ((null extra-forms)
     (cond 
       ((consp form)  (if (and (= 2 (length form)) 
			       (eq 'quote (first form)))
			  (format nil "'~A" (present-form (second form)))
			  (str-list-close 
			   (format nil "(~{~A ~}" (mapcar #'present-form form)))))
       ((symbolp form) (correct-sym form))
       ;((functionp form) (format nil "~S" (present-function form)))    
       (t (format nil 
		  (if (object-is-not-printable-p form)
		      "|~S|"
		      "~S")
		  form))))
     (t (str-list-close (format nil "(:VALUES ~{~A ~}" (mapcar #'present-form (cons form extra-forms)))))))

(defun is-logging-p (fn-sym package)
  (and (not (member fn-sym (base-logger-disabled-functions-logging *logger*)))
       (not (member (package-name package)
	       (base-logger-disabled-layers-logging *logger*)
	       :test #'string-equal
	       :key #'princ-to-string))))

(defmacro wrap-log-form (form)
  (with-gensyms (form-str res fn args)
    `(if (not (base-logger-print-internal-call-p *logger*))
	 ,form
	   (let* ((*logger* (copy-base-logger *logger*))
		  (*def-in-package* (load-time-value *package*))		
		  (,fn ',(first form))
		  ,@(unless (is-special-or-macro-p (first form))
			    `((,args (list ,@(rest form)))))
		  (,form-str (present-form 
			      ,(if (is-special-or-macro-p (first form)) 
				   `(quote ,form)
				   `(cons ,fn ,args)))))
	     (when (is-logging-p ,fn *def-in-package*)
	       (syslog-call-into ,form-str))
	     (let ((,res (multiple-value-list 
			  ,(if (is-special-or-macro-p (first form))
			       form
			       `(apply ,fn ,args)))))
	       (when (is-logging-p ,fn *def-in-package*)
		 (syslog-call-out (apply #'present-form ,res) 
				  (when (base-logger-print-called-form-with-result-p *logger*) ,form-str)))
	       (apply #'values ,res))))))

(defmacro wrap-log (&rest forms)
  `(progn ,@(loop for form in forms
	       collect `(wrap-log-form ,form))))

(defmacro defun-ext (name args &body body)
  (with-gensyms (form-str res this-name)
    `(defun ,name ,args 
       (let* ((*logger* (copy-base-logger *logger*))
	      (,this-name ',name)
	      (*def-in-package* (load-time-value *package*))
	      (*trace-fn* ',name)	      
	      (,form-str (present-form (cons ',name 
					     (mapcar #'(lambda (arg)
							 (if (consp arg)
							     (list 'quote arg)
							     arg))
						     (list ,@(present-args args)))))))
	 (when (and (slot-value *logger* 'print-call-p) 
		    (is-logging-p ,this-name *def-in-package*))
	   (syslog-call-into ,form-str))

	 (let ((,res (multiple-value-list 
		      (locally ,@(remove-declare-ignore body)))))	   
	   (when (and (slot-value *logger* 'print-call-p)
		      (is-logging-p ,this-name *def-in-package*))
	     (apply #'syslog-call-out (apply #'present-form ,res) 
		    (when (base-logger-print-called-form-with-result-p *logger*) 
		      (list ,form-str))))
	   (apply #'values ,res))))))

;(defun-ext f (x y &key z) (log-info "this f") (+ x z (g y)))
;(defun-ext g (x) (log-info "this g") (* x x))
;(f 3 4 :z 1)
