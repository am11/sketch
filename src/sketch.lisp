;;;; sketch.lisp

(in-package #:sketch)

;;; "sketch" goes here. Hacks and glory await!


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                  ;;;
;;;     _|_|_|  _|    _|  _|_|_|_|  _|_|_|_|_|    _|_|_|  _|    _|   ;;;
;;;   _|        _|  _|    _|            _|      _|        _|    _|   ;;;
;;;     _|_|    _|_|      _|_|_|        _|      _|        _|_|_|_|   ;;;
;;;         _|  _|  _|    _|            _|      _|        _|    _|   ;;;
;;;   _|_|_|    _|    _|  _|_|_|_|      _|        _|_|_|  _|    _|   ;;;
;;;                                                                  ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defstruct env
  ;; Drawing
  (fill nil)
  (stroke nil)
  ;; Debugging
  (debug-key-pressed nil)
  (red-screen nil))

;;; Temporary, until done automatically by sdl2kit
(kit.sdl2:start)
;;;

(defparameter *env* (make-env))

(defclass sketch (kit.sdl2:gl-window)
  (;; Timekeeping
   (start-time :initform (get-internal-real-time))
   (last-frame-time :initform (get-internal-real-time))
   (restart-sketch :initform t)
   ;; Window parameters
   (title :initform "Sketch")
   (framerate :initform :auto)
   (width :initform 200)
   (height :initform 200)
   (copy-pixels :initform nil)))

(defun framelimit (window &optional (fps 60))
  "Limits the framerate by using sdl2:delay. Technically, it is not
the correct way to do things, but it will have to do for now."
  ;; Adapted from k-stz's code found in sdl2kit cube example. Used
  ;; with permission.
  (with-slots (last-frame-time) window
    (let ((elapsed-time (- (get-internal-real-time) last-frame-time))
	  (time-per-frame (/ internal-time-units-per-second fps)))
      (when (< elapsed-time time-per-frame)
	(sdl2:delay (floor (* 1000 (/ (- time-per-frame elapsed-time)
				      internal-time-units-per-second)))))
      (setf last-frame-time (get-internal-real-time)))))

(defmethod kit.sdl2:render ((s sketch))
  (with-slots (width height framerate restart-sketch copy-pixels) s
    (cond (copy-pixels (gl:read-buffer :front)
		       (gl:draw-buffer :back)
		       (gl:copy-pixels 0 0 width height :color))
	  (t (gl:clear-color 0.0 1.0 0.0 1.0)
	     (gl:clear :color-buffer-bit)))    
    (when restart-sketch
      (handler-case
      	  (setup s)
      	(error () (progn
      		    (gl:clear-color 1.0 1.0 0.0 1.0)
      		    (gl:clear :color-buffer-bit))))
      (setf restart-sketch nil))
    (if (and (env-red-screen *env*)
	     (env-debug-key-pressed *env*))
	(progn
	  (setf (env-red-screen *env*) nil
		(env-debug-key-pressed *env*) nil)
	  (draw s))	
	(handler-case
	    (progn
	      (when (env-red-screen *env*)
		(setf restart-sketch t))
	      (setf (env-red-screen *env*) nil
		    (env-debug-key-pressed *env*) nil)
	      (draw s))
	  (error () (progn
		      (gl:clear-color 1.0 0.0 0.0 1.0)
		      (gl:clear :color-buffer-bit)
		      (setf (env-red-screen *env*) t)))))    
    (when (not (equal framerate :auto))
      (framelimit s framerate))))

(defmethod initialize-instance :after ((w sketch) &key &allow-other-keys)
  (setf (kit.sdl2:idle-render w) t)
  (sdl2:gl-set-swap-interval 1)
  (with-slots (width height) w
    (gl:viewport 0 0 width height)
    (gl:matrix-mode :projection)
    (gl:ortho 0 width height 0 -1 1)
    (gl:matrix-mode :modelview)
    (gl:load-identity))
  (gl:enable :line-smooth)
  (gl:hint :line-smooth-hint :nicest)
  (gl:enable :blend)
  (gl:blend-func :src-alpha :one-minus-src-alpha)
  (gl:clear-color 0.0 0.0 0.0 1.0)
  (gl:clear :color-buffer-bit)
  (gl:clear :depth-buffer-bit))

(defgeneric setup (sketch)
  (:documentation "Called before creating the sketch window.")
  (:method ((s sketch)) ()))

(defgeneric draw (sketch)
  (:documentation "Called repeatedly after creating the sketch window,
used for drawing.")
  (:method ((s sketch)) ()))

;;; Macros

(defparameter *sketch-slot-hash-table* (make-hash-table))

(defmacro defsketch (sketch-name window-options slot-bindings &body body)
  "Defines a class, inheriting from SKETCH:SKETCH. It is used for convenience
because it provides a compact syntax for declaring window options, let-like
init-form for providing slots and inline draw body. It also takes care about
communicating new title, sketch and height values to SDL backend. Additionaly,
defining a class using defsketch enables selected Sketch methods, like DRAW and
SETUP to automatically wrap their bodies inside WITH-SLOTS, using all slot names."
  (let* ((sketch-title (getf window-options :title "Sketch"))
	 (sketch-width (getf window-options :width 200))
	 (sketch-height (getf window-options :height 200))
	 (sketch-framerate (getf window-options :framerate :auto))
	 (sketch-copy-pixels (getf window-options :copy-pixels nil))
	 ;; We need to append SKETCH-TITLE, SKETCH-WIDTH, SKETCH-HEIGHT
	 ;; and SKETCH-FRAMERATE from WINDOW-OPTIONS to SLOT-BINDINGS.
	 ;; If SLOT-BINDINGS already contains any of these, we're going
	 ;; to replace them - declaring title, width, height or framerate
	 ;; along with other slots is technically illegal in Sketch, but
	 ;; currently, we're just going to use the values provided inside
	 ;; WINDOW-OPTIONS, or fallback to defaults silently.
	 (slot-bindings
	  (append (remove-if
		   #'(lambda (x)
		       (member (car x)
			       '(title width height framerate copy-pixels)))
		   slot-bindings)
		  `((title ,sketch-title)
		    (width ,sketch-width)
		    (height ,sketch-height)
		    (framerate ,sketch-framerate)
		    (copy-pixels ,sketch-copy-pixels))))	 
	 (slots (mapcar #'car slot-bindings))	 
	 (initforms (mapcar #'(lambda (binding)
			       `(,(car binding) :initform ,(cadr binding)))
			    slot-bindings)))
    ;; We are going to need slot names available during macroexpansion, so that
    ;; our enhanced methods can know what slots should be provided to WITH-SLOTS.
    ;; This is accomplished by saving slot names provided via SLOT-BINDINGS and
    ;; WINDOW-OPTIONS into *SKETCH-SLOT-HASH-TABLE*.
    (setf (gethash sketch-name *sketch-slot-hash-table*) slots)
    
    `(progn
       (defclass ,sketch-name (sketch)
	 ,initforms)
       
       (defmethod draw ((window ,sketch-name))
	 (with-slots ,(gethash sketch-name *sketch-slot-hash-table*) window
	   ,@body))
       
       (defmethod initialize-instance :after ((window ,sketch-name) &key &allow-other-keys)
	 (let ((sdl-win (kit.sdl2:sdl-window window)))
	   (sdl2:set-window-title sdl-win ,sketch-title)
	   (sdl2:set-window-size sdl-win ,sketch-width ,sketch-height)))
       
       ,(alexandria:when-let ((debug-scancode (getf window-options :debug nil)))
	  `(defmethod kit.sdl2:keyboard-event :after ((window ,sketch-name) s ts rp keysym)
	     (when (and (env-red-screen *env*)
			(sdl2:scancode= (sdl2:scancode-value keysym) ,debug-scancode))
	       (setf (env-debug-key-pressed *env*) t)))))))

(defmacro define-sketch-setup (sketch-name &body body)
  "Defines a sketch SETUP method. Body is wrapped with WITH-SLOTS for all slots defined. "
  `(defmethod setup ((window ,sketch-name))
     (with-slots ,(gethash sketch-name *sketch-slot-hash-table*) window
       ,@body)))



  #|

  Not sure what to do with these yet.

  (defmethod textinput-event :after ((window test-window) ts text)
  )

  (defmethod keyboard-event :after ((window test-window) state ts repeat-p keysym)
  )

  (defmethod mousewheel-event ((window simple-window) ts x y)
  )

  (defmethod textinput-event ((window simple-window) ts text)
  )

  (defmethod keyboard-event ((window simple-window) state ts repeat-p keysym)
  )

  (defmethod mousebutton-event ((window simple-window) state ts b x y)
  )

  (defmethod mousemotion-event ((window simple-window) ts mask x y xr yr)
  )

  |#
