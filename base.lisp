(in-package #:talk)

(defvar *slides* (make-hash-table))
(defvar *can-switch* t)
(defvar *slide-num* 0)
(defvar *group-num* 0)
(defvar *text-blending-params* (make-blending-params))
(defvar *slide-viewport* (make-viewport))
(defvar *frame-bg-color* (v! 0.082 0.082 0.082 0.0))
(defvar *default-item-font-size* 75)
(defvar *item-line-spacing* 1.5)
(defvar *default-chapter-font-size* 110)
(defvar *default-title-font-size* 100)

(defun add-slide (number slide)
  (let ((current (gethash number *slides*)))
    (when current
      (free current))
    (when (= number *slide-num*)
      (setf *group-num* (1- (slide-group-count)))))
  (setf (gethash number *slides*) slide))

(defmethod render-element ((obj t) auto-pos)
  (format t "~%<STUB RENDER ~a>" obj))

(defun next ()
  (let ((slide (gethash *slide-num* *slides*)))
    (when slide
      (let ((group-count (slide-group-count)))
        (incf *group-num*)
        (if (>= *group-num* group-count)
            (next-slide)
            (render-slide))))))

(defun prev ()
  (decf *group-num*)
  (if (< *group-num* 1)
      (prev-slide)
      (render-slide)))

(defun next-slide ()
  (incf *slide-num*)
  (if (> (slide-group-count) 0)
      (setf *group-num* 1)
      (setf *group-num* 0))
  (render-slide))

(defun prev-slide ()
  (when (> *slide-num* 0)
    (decf *slide-num*))
  (setf *group-num* (1- (slide-group-count)))
  (render-slide))

(defun slide-group-count ()
  (let ((slide (gethash *slide-num* *slides*)))
    (if slide
        (length (slot-value slide 'element-groups))
        0)))

;;------------------------------------------------------------

(defclass slide ()
  ((element-groups :initarg :element-groups :initform nil)))

(defun make-slide (&rest element-groups)
  (make-instance 'slide :element-groups element-groups))

(defmethod free ((obj slide))
  (with-slots (element-groups) obj
    (loop :for group :in element-groups :do
       (map 'nil #'free group))))

(defun render-slide ()
  (cepl-utils:with-setf (clear-color *cepl-context*) *frame-bg-color*
    (with-viewport *slide-viewport*
      (as-frame
        (let ((slide (gethash *slide-num* *slides*)))
          (when slide
            (%render-slide slide)))))))

(defun %render-slide (obj)
  (let ((pos (v! -0.9 0.85))
        (vp-size (viewport-resolution (current-viewport))))
    (labels ((auto-pos (size &optional xpos spacing)
               (or xpos
                   (prog1 pos
                     (incf (y pos)
                           (* (- (/ (elt size 1) (y vp-size)))
                              (or spacing *item-line-spacing*)))))))
      (with-slots (element-groups) obj
        (loop :for group :in element-groups :for i :below (1+ *group-num*) :do
           (when group
             (loop :for element :in group :do
                (initialize element)
                (render-element element #'auto-pos))))))))

;;------------------------------------------------------------

(defclass frame ()
  ((func :initarg :func :initform nil)
   (viewport :initarg :viewport :initform nil)))

(defun make-frame (func &optional pos size)
  (make-instance 'frame :viewport (make-viewport (or size '(200 200))
                                                 (or pos '(0 0)))
                 :func func))

(defmethod initialize ((obj frame))
  nil)

(defmethod free ((obj frame))
  nil)

(defmethod render-element ((obj frame) auto-pos)
  (declare (ignore auto-pos))
  (with-slots (func viewport) obj
    (with-viewport viewport
      (cepl-utils:with-setf (clear-color *cepl-context*) *frame-bg-color*
        (funcall func)))))

;;------------------------------------------------------------

(defclass image ()
  ((path :initarg :path :initform nil)
   (pos :initarg :pos :initform (v! 0 0))
   (texture :initarg :texture :initform nil)))

(defun make-image (path &optional pos)
  (make-instance 'image :path path :pos (when pos (v! pos))))

(defmethod initialize ((obj image))
  (with-slots (path texture) obj
    (unless texture
      (assert path)
      (setf texture (sample
                     (dirt:load-image-to-texture
                      (asdf:system-relative-pathname :talk path)))))))

(defmethod free ((obj image))
  (with-slots (text texture) obj
    (when texture
      (free (sampler-texture texture)))))

(defmethod render-element ((obj image) auto-pos)
  (with-slots (texture pos) obj
    (with-blending *text-blending-params*
      (nineveh::draw-tex-at
       texture (funcall auto-pos (dimensions
                                  (sampler-texture texture))
                        pos)))))

;;------------------------------------------------------------

(defclass big-text ()
  ((text :initarg :text :initform nil)
   (pos :initarg :pos :initform (v! 0 0))
   (texture :initarg :texture :initform nil)))

(defun make-big-text (text &optional pos)
  (make-instance 'big-text :text text :pos (or pos (v! 0 0))))

(defmethod initialize ((obj big-text))
  (with-slots (text texture) obj
    (unless texture
      (assert text)
      (setf texture (sample
                     (cepl.sdl2-ttf:text-to-tex
                      text (get-font "DroidSans-Bold.ttf"
                                     *default-chapter-font-size*)
                      (v! 250 250 250 0)))))))

(defmethod free ((obj big-text))
  (with-slots (text texture) obj
    (when texture
      (free (sampler-texture texture)))))

(defmethod render-element ((obj big-text) auto-pos)
  (with-slots (texture pos) obj
    (with-blending *text-blending-params*
      (nineveh::draw-tex-at
       texture (funcall auto-pos (dimensions
                                  (sampler-texture texture))
                        pos)))))

;;------------------------------------------------------------

(defclass text ()
  ((text :initarg :text :initform nil)
   (spacing :initarg :spacing :initform nil)
   (point-size :initarg :point-size :initform *default-item-font-size*)
   (font-name :initarg :font-name :initform "DroidSans.ttf")
   (pos :initarg :pos :initform (v! 0 0))
   (texture :initarg :texture :initform nil)))

(defun make-text (text
                  &optional pos point-size (font-name "DroidSans.ttf")
                    spacing)
  (make-instance 'text
                 :text text
                 :font-name font-name
                 :pos (when pos (v! pos))
                 :point-size (or point-size *default-item-font-size*)
                 :spacing spacing))

(defmethod initialize ((obj text))
  (with-slots (text texture font-name point-size) obj
    (unless texture
      (assert text)
      (when (> (length text) 0)
        (setf texture (sample
                       (cepl.sdl2-ttf:text-to-tex
                        text (get-font font-name point-size)
                        (v! 230 230 230 0))
                       :wrap :clamp-to-edge))))))

(defmethod free ((obj text))
  (with-slots (text texture) obj
    (when texture
      (free (sampler-texture texture)))))

(defmethod render-element ((obj text) auto-pos)
  (with-slots (texture pos spacing) obj
    (if texture
        (with-blending *text-blending-params*
          (nineveh::draw-tex-at texture
                                (funcall auto-pos (dimensions
                                                   (sampler-texture texture))
                                         pos
                                         spacing)
                                nil))
        (funcall auto-pos '(0 50) nil))))

;;------------------------------------------------------------

(defmethod parse-element ((element string))
  (parse-element `(:text ,element)))

(defmethod parse-element ((element list))
  (ecase (first element)
    (:text (destructuring-bind (text &key pos
                                     size
                                     spacing
                                     (font "DroidSans.ttf"))
               (rest element)
             `(make-text ,text ',pos ,size ,font ,spacing)))
    (:image (destructuring-bind (path &key pos) (rest element)
              `(make-image ,path ',pos)))
    (:frame (destructuring-bind (func &key pos size) (rest element)
              (assert (eq (first func) 'function) ()
                      "frame arg ~a is not a function literal" func)
              `(make-frame ,(if func
                                `(lambda () (,(second func)))
                                #'identity)
                           ',pos
                           ',(or size '(200 200)))))))

(defmethod regular-slide ((number integer) (name string) (element-groups list))
  (assert (every #'listp element-groups))
  (let* ((foo (append `((list (make-text ,name (v! -0.9 0.9)
                                         *default-title-font-size*
                                         "DroidSans-Bold.ttf")))
                      (loop :for group :in element-groups :collect
                         (cons 'list
                               (loop :for element :in group :collect
                                  (when element (parse-element element))))))))
    `(add-slide ,number (make-slide ,@foo))))

(defmethod chapter-slide ((number integer) (name string))
  `(add-slide ,number (make-slide (list (make-big-text ,name)))))

;;------------------------------------------------------------

(defmacro slide (number name &body element-groups)
  (if element-groups
      (regular-slide number name element-groups)
      (chapter-slide number name)))

;;------------------------------------------------------------

(nineveh:def-simple-main-loop talk
  (setf (viewport-dimensions *slide-viewport*)
        (cepl::window-dimensions))
  (render-slide)
  (cond
    ((skitter:key-down-p skitter.sdl2.keys:key.n)
     (when *can-switch*
       (setf *can-switch* nil)
       (next)))
    ((skitter:key-down-p skitter.sdl2.keys:key.p)
     (when *can-switch*
       (setf *can-switch* nil)
       (prev)))
    (t (setf *can-switch* t))))
