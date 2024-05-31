;;; -*- Mode: Lisp; Package: FSet; Syntax: ANSI-Common-Lisp -*-

;;; File: relations.lisp
;;; Contents: Relations (binary and general).
;;;
;;; This file is part of FSet.  Copyright (c) 2007-2024 Scott L. Burson.
;;; FSet is licensed under the Lisp Lesser GNU Public License, or LLGPL.
;;; See: http://opensource.franz.com/preamble.html
;;; This license provides NO WARRANTY.

(in-package :fset)


(defstruct (relation
	    (:include collection)
	    (:constructor nil)
	    (:predicate relation?)
	    (:copier nil))
  "The abstract class for FSet relations.  It is a structure class.")

(defgeneric arity (rel)
  (:documentation "Returns the arity of the relation `rel'."))

(defstruct (2-relation
	    (:include relation)
	    (:constructor nil)
	    (:predicate 2-relation?)
	    (:copier nil))
  "The abstract class for FSet binary relations.  It is a structure class.")

(defmethod arity ((br 2-relation))
  2)

(defstruct (wb-2-relation
	    (:include 2-relation)
	    (:constructor make-wb-2-relation (size map0 map1))
	    (:predicate wb-2-relation?)
	    (:print-function print-wb-2-relation)
	    (:copier nil))
  "A class of functional binary relations represented as pairs of weight-
balanced binary trees.  This is the default implementation of binary relations
in FSet.  The inverse is constructed lazily, and maintained incrementally once
constructed."
  size
  map0
  map1)

(defparameter *empty-wb-2-relation* (make-wb-2-relation 0 nil nil))

(declaim (inline empty-2-relation))
(defun empty-2-relation ()
  *empty-wb-2-relation*)

(declaim (inline empty-wb-2-relation))
(defun empty-wb-2-relation ()
  *empty-wb-2-relation*)

(defmethod empty? ((br wb-2-relation))
  (zerop (wb-2-relation-size br)))

(defmethod size ((br wb-2-relation))
  (wb-2-relation-size br))

(defmethod arb ((br wb-2-relation))
  (let ((tree (wb-2-relation-map0 br)))
    (if tree
	(let ((key val (WB-Map-Tree-Arb-Pair tree)))
	  (values key (WB-Set-Tree-Arb val) t))
      (values nil nil nil))))

(defmethod contains? ((br wb-2-relation) x &optional (y nil y?))
  (check-three-arguments y? 'contains? 'wb-2-relation)
  (let ((found? set-tree (WB-Map-Tree-Lookup (wb-2-relation-map0 br) x)))
    (and found? (WB-Set-Tree-Member? set-tree y))))

;;; &&& Aaagh -- not sure this makes sense -- (setf (lookup rel x) ...) doesn't do
;;; the right thing at all, relative to this.  Maybe the setf expander for `lookup'/`@'
;;; should call an internal form of `with' that does something different on a
;;; relation...
;;; [Later] No, I don't think this is a problem.  (setf (lookup ...) ...) just doesn't
;;; make sense on a relation, any more than it does on a set.
(defmethod lookup ((br wb-2-relation) x)
  "Returns the set of values that the relation pairs `x' with."
  (let ((found? set-tree (WB-Map-Tree-Lookup (wb-2-relation-map0 br) x)))
    (if found? (make-wb-set set-tree)
      *empty-wb-set*)))

(defgeneric lookup-inv (2-relation y)
  (:documentation "Does an inverse lookup on a binary relation."))

(defmethod lookup-inv ((br wb-2-relation) y)
  (get-inverse br)
  (let ((found? set-tree (WB-Map-Tree-Lookup (wb-2-relation-map1 br) y)))
    (if found? (make-wb-set set-tree)
      *empty-wb-set*)))

(defmethod domain ((br wb-2-relation))
  (make-wb-set (WB-Map-Tree-Domain (wb-2-relation-map0 br))))

(defmethod range ((br wb-2-relation))
  (get-inverse br)
  (make-wb-set (WB-Map-Tree-Domain (wb-2-relation-map1 br))))

(defun get-inverse (br)
  (let ((m0 (wb-2-relation-map0 br))
	(m1 (wb-2-relation-map1 br)))
    (when (and m0 (null m1))
      (Do-WB-Map-Tree-Pairs (x s m0)
	(Do-WB-Set-Tree-Members (y s)
	  (let ((ignore prev (WB-Map-Tree-Lookup m1 y)))
	    (declare (ignore ignore))
	    (setq m1 (WB-Map-Tree-With m1 y (WB-Set-Tree-With prev x))))))
      ;;; Look Ma, no locking!  Assuming the write is atomic.  -- Actually, we're assuming a little
      ;;; more than that: we're assuming other threads will see a fully initialized map object if
      ;;; they read the slot shortly after we write it.  Some kind of memory barrier is &&& needed.
      (setf (wb-2-relation-map1 br) m1))
    m1))

(defgeneric inverse (2-relation)
  (:documentation "The inverse of a binary relation."))

;;; This is so fast (once the inverse is constructed) we almost don't need
;;; `lookup-inv'.  Maybe we should just put a compiler optimizer on
;;; `(lookup (inverse ...) ...)'?
(defmethod inverse ((br wb-2-relation))
  (get-inverse br)
  (make-wb-2-relation (wb-2-relation-size br) (wb-2-relation-map1 br)
		      (wb-2-relation-map0 br)))

(defmethod least ((br wb-2-relation))
  (let ((tree (wb-2-relation-map0 br)))
    (if tree
	(let ((key val (WB-Map-Tree-Least-Pair tree)))
	  (values key val t))
      (values nil nil nil))))

(defmethod greatest ((br wb-2-relation))
  (let ((tree (wb-2-relation-map0 br)))
    (if tree
	(let ((key val (WB-Map-Tree-Greatest-Pair tree)))
	  (values key val t))
      (values nil nil nil))))

(defmethod with ((br wb-2-relation) x &optional (y nil y?))
  ;; Try to provide a little support for the cons representation of pairs.
  (unless y?
    (setq y (cdr x) x (car x)))
  (let ((found? set-tree (WB-Map-Tree-Lookup (wb-2-relation-map0 br) x))
	(map1 (wb-2-relation-map1 br)))
    (if found?
	(let ((new-set-tree (WB-Set-Tree-With set-tree y)))
	  (if (eq new-set-tree set-tree)
	      br			; `y' was already there
	    (make-wb-2-relation (1+ (wb-2-relation-size br))
				(WB-Map-Tree-With (wb-2-relation-map0 br) x new-set-tree)
				(and map1
				     (let ((ignore set-tree-1
					     (WB-Map-Tree-Lookup map1 y)))
				       (declare (ignore ignore))
				       (WB-Map-Tree-With
					 map1 y (WB-Set-Tree-With set-tree-1 x)))))))
      (make-wb-2-relation (1+ (wb-2-relation-size br))
			  (WB-Map-Tree-With (wb-2-relation-map0 br) x
					    (WB-Set-Tree-With nil y))
			  (and map1
			       (let ((ignore set-tree-1
				       (WB-Map-Tree-Lookup map1 y)))
				 (declare (ignore ignore))
				 (WB-Map-Tree-With
				   map1 y (WB-Set-Tree-With set-tree-1 x))))))))

(defmethod less ((br wb-2-relation) x &optional (y nil y?))
  ;; Try to provide a little support for the cons representation of pairs.
  (unless y?
    (setq y (cdr x) x (car x)))
  (let ((found? set-tree (WB-Map-Tree-Lookup (wb-2-relation-map0 br) x))
	(map1 (wb-2-relation-map1 br)))
    (if (not found?)
	br
      (let ((new-set-tree (WB-Set-Tree-Less set-tree y)))
	(if (eq new-set-tree set-tree)
	    br
	  (make-wb-2-relation (1- (wb-2-relation-size br))
			      (if new-set-tree
				  (WB-Map-Tree-With (wb-2-relation-map0 br) x new-set-tree)
				(WB-Map-Tree-Less (wb-2-relation-map0 br) x))
			      (and map1
				   (let ((ignore set-tree
					   (WB-Map-Tree-Lookup map1 y))
					 ((new-set-tree (WB-Set-Tree-Less set-tree x))))
				     (declare (ignore ignore))
				     (if new-set-tree
					 (WB-Map-Tree-With map1 y new-set-tree)
				       (WB-Map-Tree-Less map1 y))))))))))

(defmethod union ((br1 wb-2-relation) (br2 wb-2-relation) &key)
  (let ((new-size (+ (wb-2-relation-size br1) (wb-2-relation-size br2)))
	((new-map0 (WB-Map-Tree-Union (wb-2-relation-map0 br1) (wb-2-relation-map0 br2)
				      (lambda (s1 s2)
					(let ((s (WB-Set-Tree-Union s1 s2)))
					  (decf new-size
						(- (+ (WB-Set-Tree-Size s1) (WB-Set-Tree-Size s2))
						   (WB-Set-Tree-Size s)))
					  s))))
	 (new-map1 (and (or (wb-2-relation-map1 br1) (wb-2-relation-map1 br2))
			(progn
			  (get-inverse br1)
			  (get-inverse br2)
			  (WB-Map-Tree-Union (wb-2-relation-map1 br1)
					     (wb-2-relation-map1 br2)
					     #'WB-Set-Tree-Union))))))
    (make-wb-2-relation new-size new-map0 new-map1)))

(defmethod intersection ((br1 wb-2-relation) (br2 wb-2-relation) &key)
  (let ((new-size 0)
	((new-map0 (WB-Map-Tree-Intersect (wb-2-relation-map0 br1)
					  (wb-2-relation-map0 br2)
					  (lambda (s1 s2)
					    (let ((s (WB-Set-Tree-Intersect s1 s2)))
					      (incf new-size (WB-Set-Tree-Size s))
					      (values s (and (null s) ':no-value))))))
	 (new-map1 (and (or (wb-2-relation-map1 br1) (wb-2-relation-map1 br2))
			(progn
			  (get-inverse br1)
			  (get-inverse br2)
			  (WB-Map-Tree-Intersect (wb-2-relation-map1 br1)
						 (wb-2-relation-map1 br2)
						 (lambda (s1 s2)
						   (let ((s (WB-Set-Tree-Intersect s1 s2)))
						     (values s (and (null s) ':no-value))))))))))
    (make-wb-2-relation new-size new-map0 new-map1)))

(defgeneric join (relation-a column-a relation-b column-b)
  (:documentation
    "A relational equijoin, matching up `column-a' of `relation-a' with `column-b' of
`relation-b'.  For a binary relation, the columns are named 0 (domain) and 1 (range)."))

(defmethod join ((bra wb-2-relation) cola (brb wb-2-relation) colb)
  (let ((map0a map1a (ecase cola
		       (1 (values (wb-2-relation-map0 bra) (wb-2-relation-map1 bra)))
		       (0 (progn
			    (get-inverse bra)
			    (values (wb-2-relation-map1 bra)
				    (wb-2-relation-map0 bra))))))
	(map0b map1b (ecase colb
		       (0 (values (wb-2-relation-map0 brb) (wb-2-relation-map1 brb)))
		       (1 (progn
			    (get-inverse brb)
			    (values (wb-2-relation-map1 brb)
				    (wb-2-relation-map0 brb))))))
	(new-map0 nil)
	(new-map1 nil)
	(new-size 0))
    (Do-WB-Map-Tree-Pairs (x ys map0a)
      (Do-WB-Set-Tree-Members (y ys)
	(let ((ignore s (WB-Map-Tree-Lookup map0b y)))
	  (declare (ignore ignore))
	  (when s
	    (let ((ignore prev (WB-Map-Tree-Lookup new-map0 x))
		  ((new (WB-Set-Tree-Union prev s))))
	      (declare (ignore ignore))
	      (incf new-size (- (WB-Set-Tree-Size new) (WB-Set-Tree-Size prev)))
	      (setq new-map0 (WB-Map-Tree-With new-map0 x new)))))))
    (when (or map1a map1b)
      (when (null map1b)
	(setq map1b (get-inverse brb)))
      (when (null map1a)
	(setq map1a (get-inverse bra)))
      (Do-WB-Map-Tree-Pairs (x ys map1b)
	(Do-WB-Set-Tree-Members (y ys)
	  (let ((ignore s (WB-Map-Tree-Lookup map1a y)))
	    (declare (ignore ignore))
	    (when s
	      (let ((ignore prev (WB-Map-Tree-Lookup new-map1 x)))
		(declare (ignore ignore))
		(setq new-map1
		      (WB-Map-Tree-With new-map1 x (WB-Set-Tree-Union prev s)))))))))
    (make-wb-2-relation new-size new-map0 new-map1)))


(defmethod compose ((rel wb-2-relation) (fn function))
  (2-relation-fn-compose rel fn))

(defmethod compose ((rel wb-2-relation) (fn symbol))
  (2-relation-fn-compose rel (coerce fn 'function)))

(defmethod compose ((rel wb-2-relation) (fn map))
  (2-relation-fn-compose rel fn))

(defmethod compose ((rel wb-2-relation) (fn seq))
  (2-relation-fn-compose rel fn))

(defmethod compose ((rel1 wb-2-relation) (rel2 wb-2-relation))
  (join rel1 1 rel2 0))

(defun 2-relation-fn-compose (rel fn)
  (let ((new-size 0)
	((new-map0 (gmap :wb-map (lambda (x ys)
				   (let ((result nil))
				     (Do-WB-Set-Tree-Members (y ys)
				       (setq result (WB-Set-Tree-With result (@ fn y))))
				     (incf new-size (WB-Set-Tree-Size result))
				     (values x result)))
			(:wb-map (make-wb-map (wb-2-relation-map0 rel)))))))
    (make-wb-2-relation new-size
			(wb-map-contents new-map0)
			nil)))


(defgeneric internal-do-2-relation (br elt-fn value-fn))

(defmacro do-2-relation ((key val br &optional value) &body body)
  "Enumerates all pairs of the relation `br', binding them successively to `key' and `val'
and executing `body'."
  `(block nil
     (internal-do-2-relation ,br (lambda (,key ,val) . ,body)
			     (lambda () ,value))))

(defmethod internal-do-2-relation ((br wb-2-relation) elt-fn value-fn)
  (Do-WB-Map-Tree-Pairs (x y-set (wb-2-relation-map0 br) (funcall value-fn))
    (Do-WB-Set-Tree-Members (y y-set)
      (funcall elt-fn x y))))

(defmethod convert ((to-type (eql '2-relation)) (br 2-relation) &key)
  br)

(defmethod convert ((to-type (eql 'wb-2-relation)) (br wb-2-relation) &key)
  br)

(defmethod convert ((to-type (eql 'set)) (br 2-relation) &key (pair-fn #'cons))
  (let ((result nil)
	(pair-fn (coerce pair-fn 'function)))
    (do-2-relation (x y br)
      (setq result (WB-Set-Tree-With result (funcall pair-fn x y))))
    (make-wb-set result)))

;;; I've made the default conversions between maps and 2-relations use the
;;; same pairs; that is, the conversion from a map to a 2-relation yields a
;;; functional relation with the same mappings, and the inverse conversion
;;; requires a functional relation and yields a map with the same mappings.
;;; This is mathematically elegant, but I wonder if the other kind of conversion
;;; -- where the map's range is set-valued -- is not more useful in practice,
;;; and maybe more deserving of being the default.
(defmethod convert ((to-type (eql '2-relation)) (m map) &key from-type)
  "If `from-type' is the symbol `map-to-sets', the range elements must all be
sets, and the result pairs each domain element with each member of the
corresponding range set.  Otherwise, the result pairs each domain element
with the corresponding range element directly."
  (if (eq from-type 'map-to-sets)
      (map-to-sets-to-wb-2-relation m)
    (map-to-wb-2-relation m)))

(defmethod convert ((to-type (eql 'wb-2-relation)) (m map) &key from-type)
  "If `from-type' is the symbol `map-to-sets', the range elements must all be
sets, and the result pairs each domain element with each member of the
corresponding range set.  Otherwise, the result pairs each domain element
with the corresponding range element directly."
  (if (eq from-type 'map-to-sets)
      (map-to-sets-to-wb-2-relation m)
    (map-to-wb-2-relation m)))

(defun map-to-sets-to-wb-2-relation (m)
  (let ((size 0)
	((new-tree (WB-Map-Tree-Compose
		     (wb-map-contents m)
		     #'(lambda (s)
			 (let ((s (wb-set-contents (convert 'wb-set s))))
			   (incf size (WB-Set-Tree-Size s))
			   s))))))
    (make-wb-2-relation size new-tree nil)))

(defun map-to-wb-2-relation (m)
  (let ((new-tree (WB-Map-Tree-Compose (wb-map-contents m)
				       #'(lambda (x) (WB-Set-Tree-With nil x)))))
    (make-wb-2-relation (size m) new-tree nil)))

(defmethod convert ((to-type (eql '2-relation)) (alist list)
		    &key (key-fn #'car) (value-fn #'cdr))
  (list-to-wb-2-relation alist key-fn value-fn))

(defmethod convert ((to-type (eql 'wb-2-relation)) (alist list)
		    &key (key-fn #'car) (value-fn #'cdr))
  (list-to-wb-2-relation alist key-fn value-fn))

(defun list-to-wb-2-relation (alist key-fn value-fn)
  (let ((m0 nil)
	(size 0)
	(key-fn (coerce key-fn 'function))
	(value-fn (coerce value-fn 'function)))
    (dolist (pr alist)
      (let ((k (funcall key-fn pr))
	    (v (funcall value-fn pr))
	    ((found? prev (WB-Map-Tree-Lookup m0 k))
	     ((new (WB-Set-Tree-With prev v)))))
	(declare (ignore found?))
	(when (> (WB-Set-Tree-Size new) (WB-Set-Tree-Size prev))
	  (incf size)
	  (setq m0 (WB-Map-Tree-With m0 k new)))))
    (make-wb-2-relation size m0 nil)))

(defmethod convert ((to-type (eql '2-relation))
		    (s seq)
		    &key key-fn (value-fn #'identity))
  (convert 'wb-2-relation s :key-fn key-fn :value-fn value-fn))

(defmethod convert ((to-type (eql 'wb-2-relation))
		    (s seq)
		    &key key-fn (value-fn #'identity))
  (let ((m0 nil)
	(size 0)
	(key-fn (coerce key-fn 'function))
	(value-fn (coerce value-fn 'function)))
    (do-seq (row s)
      (let ((k (funcall key-fn row))
	    (v (funcall value-fn row))
	    ((found? prev (WB-Map-Tree-Lookup m0 k))
	     ((new (WB-Set-Tree-With prev v)))))
	(declare (ignore found?))
	(when (> (WB-Set-Tree-Size new) (WB-Set-Tree-Size prev))
	  (incf size)
	  (setq m0 (WB-Map-Tree-With m0 k new)))))
    (make-wb-2-relation size m0 nil)))

(defmethod convert ((to-type (eql 'map)) (br wb-2-relation) &key)
  "This conversion requires the relation to be functional, and returns
a map representing the function; that is, the relation must map each
domain value to a single range value, and the returned map maps that
domain value to that range value."
  (2-relation-to-wb-map br))

(defmethod convert ((to-type (eql 'wb-map)) (br wb-2-relation) &key)
  "This conversion requires the relation to be functional, and returns
a map representing the function; that is, the relation must map each
domain value to a single range value, and the returned map maps that
domain value to that range value."
  (2-relation-to-wb-map br))

(defun 2-relation-to-wb-map (br)
  (let ((m nil))
    (Do-WB-Map-Tree-Pairs (x s (wb-2-relation-map0 br))
      (let ((sz (WB-Set-Tree-Size s)))
	(unless (= 1 sz)
	  (error "2-relation maps ~A to ~D values" x sz))
	(setq m (WB-Map-Tree-With m x (WB-Set-Tree-Arb s)))))
    (make-wb-map m)))

(defmethod convert ((to-type (eql 'map-to-sets)) (br wb-2-relation) &key)
  "This conversion returns a map mapping each domain value to the set of
corresponding range values."
  (make-wb-map (WB-Map-Tree-Compose (wb-2-relation-map0 br) #'make-wb-set)))

(defgeneric conflicts (2-relation)
  (:documentation
    "Returns a 2-relation containing only those pairs of `2-relation' whose domain value
is mapped to multiple range values."))

(defmethod conflicts ((br wb-2-relation))
  (let ((m0 nil)
	(size 0))
    (Do-WB-Map-Tree-Pairs (x s (wb-2-relation-map0 br))
      (when (> (WB-Set-Tree-Size s) 1)
	(setq m0 (WB-Map-Tree-With m0 x s))
	(incf size (WB-Set-Tree-Size s))))
    (make-wb-2-relation size m0 nil)))

(defun print-wb-2-relation (br stream level)
  (declare (ignore level))
  (pprint-logical-block (stream nil :prefix "#{+" :suffix " +}")
    (do-2-relation (x y br)
      (pprint-pop)
      (write-char #\Space stream)
      (pprint-newline :linear stream)
      (write (list x y) :stream stream))))

(defmethod iterator ((rel wb-2-relation) &key)
  (let ((outer (Make-WB-Map-Tree-Iterator-Internal (wb-2-relation-map0 rel)))
	(cur-dom-elt nil)
	(inner nil))
    (lambda (op)
      (ecase op
	(:get (if (WB-Map-Tree-Iterator-Done? outer)
		  (values nil nil nil)
		(progn
		  (when (or (null inner) (WB-Set-Tree-Iterator-Done? inner))
		    (let ((dom-elt inner-tree (WB-Map-Tree-Iterator-Get outer)))
		      (setq cur-dom-elt dom-elt)
		      (assert inner-tree)	; must be nonempty
		      (setq inner (Make-WB-Set-Tree-Iterator-Internal inner-tree))))
		  (values cur-dom-elt (WB-Set-Tree-Iterator-Get inner) t))))
	(:done? (WB-Map-Tree-Iterator-Done? outer))
	(:more? (not (WB-Map-Tree-Iterator-Done? outer)))))))

(gmap:def-gmap-arg-type 2-relation (rel)
  "Yields each pair of `rel', as two values."
  `((iterator ,rel)
    #'(lambda (it) (declare (type function it)) (funcall it ':done?))
    (:values 2 #'(lambda (it) (declare (type function it)) (funcall it ':get)))))

(gmap:def-gmap-arg-type wb-2-relation (rel)
  "Yields each pair of `rel', as two values."
  `((iterator ,rel)
    #'(lambda (it) (declare (type function it)) (funcall it ':done?))
    (:values 2 #'(lambda (it) (declare (type function it)) (funcall it ':get)))))

(gmap:def-gmap-res-type 2-relation (&key filterp)
  "Consumes two values from the mapped function; returns a 2-relation of the pairs.
Note that `filterp', if supplied, must take two arguments."
  `(nil (:consume 2 #'(lambda (alist x y) (cons (cons x y) alist)))
	#'(lambda (alist) (list-to-wb-2-relation alist #'car #'cdr))
	,filterp))

(gmap:def-gmap-res-type wb-2-relation (&key filterp)
  "Consumes two values from the mapped function; returns a 2-relation of the pairs.
Note that `filterp', if supplied, must take two arguments."
  `(nil (:consume 2 #'(lambda (alist x y) (cons (cons x y) alist)))
	#'(lambda (alist) (list-to-wb-2-relation alist #'car #'cdr))
	,filterp))


(define-cross-type-compare-methods relation)

(defmethod compare ((a wb-2-relation) (b wb-2-relation))
  (let ((a-size (wb-2-relation-size a))
	(b-size (wb-2-relation-size b)))
    (cond ((< a-size b-size) ':less)
	  ((> a-size b-size) ':greater)
	  (t
	   (WB-Map-Tree-Compare (wb-2-relation-map0 a) (wb-2-relation-map0 b)
				#'WB-Set-Tree-Compare)))))

(defmethod verify ((br wb-2-relation))
  ;; Slow, but thorough.
  (and (WB-Map-Tree-Verify (wb-2-relation-map0 br))
       (WB-Map-Tree-Verify (wb-2-relation-map1 br))
       (let ((size 0))
	 (and (Do-WB-Map-Tree-Pairs (x s (wb-2-relation-map0 br) t)
		(WB-Set-Tree-Verify s)
		(incf size (WB-Set-Tree-Size s))
		(or (null (wb-2-relation-map1 br))
		    (Do-WB-Set-Tree-Members (y s)
		      (let ((ignore s1 (WB-Map-Tree-Lookup (wb-2-relation-map1 br) y)))
			(declare (ignore ignore))
			(unless (WB-Set-Tree-Member? s1 x)
			  (format *debug-io* "Map discrepancy in wb-2-relation")
			  (return nil))))))
	      (or (= size (wb-2-relation-size br))
		  (progn (format *debug-io* "Size discrepancy in wb-2-relation")
			 nil))))
       (or (null (wb-2-relation-map1 br))
	   (let ((size 0))
	     (Do-WB-Map-Tree-Pairs (x s (wb-2-relation-map1 br))
	       (declare (ignore x))
	       (WB-Set-Tree-Verify s)
	       (incf size (WB-Set-Tree-Size s)))
	     (or (= size (wb-2-relation-size br))
		 (progn (format *debug-io*  "Size discrepancy in wb-2-relation")
			nil))))))


(defgeneric transitive-closure (2-relation set)
  (:documentation
    "The transitive closure of the set over the relation.  The relation may
also be supplied as a function returning a set."))

(defmethod transitive-closure ((fn function) (s set))
  (set-transitive-closure fn s))

(defmethod transitive-closure ((r 2-relation) (s set))
  (set-transitive-closure r s))

(defun set-transitive-closure (r s)
  ;; This could probably use a little more work.
  (let ((workset (set-difference
		   (reduce #'union (image r (convert 'seq s)) :initial-value (set))
		   s))
	(result s))
    (while (nonempty? workset)
      (let ((x (arb workset)))
	(removef workset x)
	(adjoinf result x)
	(unionf workset (set-difference (@ r x) result))))
    result))


(defmacro 2-relation (&rest args)
  "Constructs a 2-relation of the default implementation according to the supplied
argument subforms.  Each argument subform can be a list of the form (`key-expr'
`value-expr'), denoting a mapping from the value of `key-expr' to the value of
`value-expr'; or a list of the form ($ `expression'), in which case the
expression must evaluate to a 2-relation, all of whose mappings will be
included in the result.  Also, each of 'key-expr' and 'value-expr' can be of the
form ($ `expression'), in which case the expression must evaluate to a set, and
the elements of the set are used individually to form pairs; for example, the
result of

  (2-relation (($ (set 1 2)) ($ (set 'a 'b))))

contains the pairs <1, a>, <1, b>, <2, a>, and <2, b>."
  (expand-2-relation-constructor-form '2-relation args))

(defmacro wb-2-relation (&rest args)
  "Constructs a wb-2-relation according to the supplied argument subforms.
Each argument subform can be a list of the form (`key-expr' `value-expr'),
denoting a mapping from the value of `key-expr' to the value of `value-expr';
or a list of the form ($ `expression'), in which case the expression must
evaluate to a 2-relation, all of whose mappings will be included in the
result.  Also, each of 'key-expr' and 'value-expr' can be of the
form ($ `expression'), in which case the expression must evaluate to a set, and
the elements of the set are used individually to form pairs; for example, the
result of

  (wb-2-relation (($ (set 1 2)) ($ (set 'a 'b))))

contains the pairs <1, a>, <1, b>, <2, a>, and <2, b>."
  (expand-2-relation-constructor-form 'wb-2-relation args))

(defun expand-2-relation-constructor-form (type-name subforms)
  (let ((empty-form (ecase type-name
		      (2-relation '(empty-2-relation))
		      (wb-2-relation '(empty-wb-2-relation)))))
    (labels ((recur (subforms result)
	       (if (null subforms) result
		 (let ((subform (car subforms)))
		   (cond ((not (and (listp subform)
				    (= (length subform) 2)))
			  (error "Subforms for ~S must all be pairs expressed as 2-element~@
			      lists, or ($ x) subforms -- not ~S"
				 type-name subform))
			 ((eq (car subform) '$)
			  (if (eq result empty-form)
			      (recur (cdr subforms) (cadr subform))
			    (recur (cdr subforms) `(union ,result ,(cadr subform)))))
			 ((and (listp (car subform)) (eq (caar subform) '$)
			       (listp (cadr subform)) (eq (caadr subform) '$))
			  (let ((key-var (gensym "KEY-"))
				(vals-var (gensym "VALS-")))
			    (recur (cdr subforms)
				   `(union ,result
					   (let ((,vals-var ,(cadadr subform)))
					     (gmap :union
						   (fn (,key-var)
						     (convert ',type-name
							      (map (,key-var ,vals-var))
							      :from-type 'map-to-sets))
						   (:set ,(cadar subform))))))))
			 ((and (listp (car subform)) (eq (caar subform) '$))
			  (let ((key-var (gensym "KEY-"))
				(val-var (gensym "VAL-")))
			    (recur (cdr subforms)
				   `(union ,result
					   (let ((,val-var ,(cadr subform)))
					     (gmap :union
						   (fn (,key-var)
						     (,type-name (,key-var ,val-var)))
						   (:set ,(cadar subform))))))))
			 ((and (listp (cadr subform)) (eq (caadr subform) '$))
			  (recur (cdr subforms)
				 `(union ,result
					 (convert ',type-name
						  (map (,(car subform) ,(cadadr subform)))
						  :from-type 'map-to-sets))))
			 (t
			  (recur (cdr subforms)
				 `(with ,result ,(car subform) ,(cadr subform)))))))))
      (recur subforms empty-form))))


;;; ================================================================================
;;; List relations

;;; A list relation is a general relation (i.e. of arbitrary arity >= 2) whose tuples are
;;; in list form.  List relations support a `query' operation that takes, along with the
;;; relation, a list, of length equal to the arity, called the "pattern".  For each
;;; position, if the pattern contains the symbol `fset::?', the query is not constrained
;;; by that position; otherwise, the result set contains only those tuples with the same
;;; value in that position as the pattern has.  There is also a `query-multi' operation
;;; that is similar, but the pattern contains sets of possible values (or `?') in each
;;; position, and the result set contains all tuples with any of those values in that
;;; position.


(defstruct (list-relation
	    (:include relation)
	    (:constructor nil)
	    (:predicate list-relation?)
	    (:copier nil))
  "The abstract class for FSet list relations.  It is a structure class.
A list relation is a general relation (i.e. of arbitrary arity >= 2) whose
tuples are in list form.")

(defstruct (wb-list-relation
	    (:include list-relation)
	    (:constructor make-wb-list-relation (arity tuples indices))
	    (:predicate wb-list-relation?)
	    (:print-function print-wb-list-relation)
	    (:copier nil))
  "A class of functional relations of arbitrary arity >= 2, whose tuples
are in list form."
  arity
  tuples
  ;; a map from pattern mask to map from reduced tuple to set of tuples
  indices)


(defun empty-list-relation (&optional arity)
  "We allow the arity to be temporarily unspecified; it will be taken from
the first tuple added."
  (unless (or (null arity) (and (integerp arity) (>= arity 1)))
    (error "Invalid arity"))
  (empty-wb-list-relation arity))

(defun empty-wb-list-relation (arity)
  "We allow the arity to be temporarily unspecified; it will be taken from
the first tuple added."
  ;; If arity = 1 it's just a set... but what the heck...
  (unless (or (null arity) (and (integerp arity) (>= arity 1)))
    (error "Invalid arity"))
  (make-wb-list-relation arity (set) (map)))

(defmethod arity ((rel wb-list-relation))
  "Will return `nil' if the arity is not yet specified; see `empty-list-relation'."
  (wb-list-relation-arity rel))

(defmethod empty? ((rel wb-list-relation))
  (empty? (wb-list-relation-tuples rel)))

(defmethod size ((rel wb-list-relation))
  (size (wb-list-relation-tuples rel)))

(defmethod arb ((rel wb-list-relation))
  (arb (wb-list-relation-tuples rel)))

(defmethod contains? ((rel wb-list-relation) tuple &optional (arg2 nil arg2?))
  (declare (ignore arg2))
  (check-two-arguments arg2? 'contains? 'wb-list-relation)
  (contains? (wb-list-relation-tuples rel) tuple))

(defgeneric query (relation pattern)
  (:documentation
    "Along with the relation, takes `pattern', which is a list of length
less than or equal to the arity.  Returns all tuples whose elements match
those of the pattern, starting from the left end of both, where pattern
elements equal to `fset::?' (the symbol itself, not its value) match any
tuple value.  If the pattern's length is less than the arity, the missing
positions also match any tuple value.  (Note that `?' is intentionally
_not_ exported from `fset:' so that you won't use it accidentally.)"))

(defmethod query ((rel wb-list-relation) pattern)
  (let ((arity (wb-list-relation-arity rel)))
    (if (null arity)
	;; We don't know the arity yet, which means there are no tuples.
	(set)
      (progn
	(unless (and pattern (<= (length pattern) arity))
	  (error "Pattern is of the wrong length"))
	(let ((pattern mask (prepare-pattern arity pattern)))
	  (if (= mask (1- (ash 1 arity)))
	      (if (contains? rel pattern) (set pattern) (set))
	    (let ((reduced-tuple (reduced-tuple pattern))
		  (index (@ (wb-list-relation-indices rel) mask)))
	      (if index
		  (@ index reduced-tuple)
		(let ((index-results
			(gmap (:result list :filterp #'identity)
			      (fn (index i pat-elt)
				(and (logbitp i mask) (@ index (list pat-elt))))
			      (:arg list (get-indices rel mask))
			      (:arg index 0)
			      (:arg list pattern))))
		  ;; &&& We also want to build composite indices under some
		  ;; circumstances -- e.g. if the result set is much smaller
		  ;; than the smallest of `index-results'.
		  (if index-results
		      (reduce #'intersection
			      (sort index-results #'< :key #'size))
		    ;; Completely uninstantiated pattern
		    (wb-list-relation-tuples rel)))))))))))

(defgeneric query-multi (rel pattern)
  (:documentation
    "Like `query' (q.v.), except that `pattern' is a list where the elements that
aren't `fset::?' are sets of values rather than single values.  Returns all tuples
in the relation for which each value is a member of the corresponding set in the
pattern."))

(defmethod query-multi ((rel wb-list-relation) (pattern list))
  (let ((arity (wb-list-relation-arity rel)))
    (if (null arity)
	;; We don't know the arity yet, which means there are no tuples.
	(set)
      (progn
	(unless (<= (length pattern) arity)
	  (error "Pattern is of the wrong length"))
	(let ((pattern mask (prepare-pattern arity pattern)))
	  (if (every (fn (s) (or (eq s '?) (= (size s) 1)))
		     pattern)
	      (query rel (mapcar (fn (s) (if (eq s '?) s (arb s))) pattern))
	    (let ((index-results
		    (gmap (:result list :filterp #'identity)
			  (fn (index i pat-elt)
			    (and (logbitp i mask)
				 (gmap :union
				       (fn (pat-elt-elt) (@ index (list pat-elt-elt)))
				       (:set pat-elt))))
			  (:arg list (get-indices rel mask))
			  (:arg index 0)
			  (:arg list pattern))))
	      (if index-results
		  (reduce #'intersection
			  (sort index-results #'< :key #'size))
		(wb-list-relation-tuples rel)))))))))

(defun prepare-pattern (rel-arity pattern)
  (let ((mask (pattern-mask pattern)))
    (if (< (length pattern) rel-arity)
	(let ((nils (make-list (- rel-arity (length pattern)))))
	  (values (append pattern nils) mask))
      (values pattern mask))))

(defun pattern-mask (pattern)
  (gmap (:result sum) (fn (pat-elt i)
			(if (eq pat-elt '?) 0 (ash 1 i)))
	(:arg list pattern)
	(:index 0)))

(defmethod get-indices ((rel list-relation) mask)
  "Returns a list giving the index to use for each element of `mask'
considered as a bit set."
  ;; First we see what indices exist on each position.
  (let ((ex-inds (gmap (:result list)
		       (fn (i) (and (logbitp i mask)
				    (@ (wb-list-relation-indices rel)
				      (ash 1 i))))
		       (:arg index 0 (arity rel))))
	((unindexed (gmap (:result list)
			  (lambda (index i)
			    (and (logbitp i mask) (null index)))
			  (:arg list ex-inds)
			  (:arg index 0)))))
    ;; Now, if there were any instantiated positions for which an index did
    ;; not exist, construct indices for them.
    (if (every #'null unindexed)
	ex-inds
      (let ((new-indices (make-array (arity rel) :initial-element (empty-map (set)))))
	;; Populate the new indices
	(do-set (tuple (wb-list-relation-tuples rel))
	  (gmap nil (fn (tuple-elt unind i)
		      (when unind
			;; If we called `reduced-tuple', we'd get `(list tuple-elt)'.
			(adjoinf (@ (svref new-indices i) (list tuple-elt))
				 tuple)))
		(:list tuple)
		(:list unindexed)
		(:index 0)))
	;; Store them back in the relation.  This is unusual in that we're modifying an FSet
	;; collection, but note that we're just caching information about the contents.
	;; In particular, if two threads do this at the same time, all that goes wrong is
	;; some duplication of work.
	(let ((indices (wb-list-relation-indices rel)))
	  (gmap nil (fn (unind i)
		      (when unind
			(setf (@ indices (ash 1 i)) (svref new-indices i))))
		(:arg list unindexed)
		(:arg index 0))
	  (setf (wb-list-relation-indices rel) indices))
	(gmap :list (lambda (ex-ind new-index)
		      (or ex-ind new-index))
	      (:list ex-inds)
	      (:vector new-indices))))))

(defmethod with ((rel wb-list-relation) tuple &optional (arg2 nil arg2?))
  (declare (ignore arg2))
  (check-two-arguments arg2? 'with 'wb-list-relation)
  (let ((arity (or (wb-list-relation-arity rel)
		   (length tuple))))
    (unless (and (listp tuple) (= (length tuple) arity))
      (error "Length of tuple, ~D, does not equal arity, ~D"
	     (length tuple) arity))
    (if (contains? (wb-list-relation-tuples rel) tuple)
	rel
      (make-wb-list-relation arity (with (wb-list-relation-tuples rel) tuple)
			     (image (lambda (mask rt-map)
				      (let ((rt (reduced-tuple tuple)))
					(values mask (with rt-map rt (with (@ rt-map rt) tuple)))))
				    (wb-list-relation-indices rel))))))

(defmethod less ((rel wb-list-relation) tuple &optional (arg2 nil arg2?))
  (declare (ignore arg2))
  (check-two-arguments arg2? 'with 'wb-list-relation)
  (let ((arity (or (wb-list-relation-arity rel)
		   (length tuple))))
    (unless (and (listp tuple) (= (length tuple) arity))
      (error "Length of tuple, ~D, does not equal arity, ~D"
	     (length tuple) arity))
    (if (not (contains? (wb-list-relation-tuples rel) tuple))
	rel
      (make-wb-list-relation arity (less (wb-list-relation-tuples rel) tuple)
			     (image (lambda (mask rt-map)
				      (let ((rt (reduced-tuple tuple)))
					(values mask (with rt-map rt (less (@ rt-map rt) tuple)))))
				    (wb-list-relation-indices rel))))))

(defun reduced-tuple (tuple)
  "Returns a list of those members of `tuple' corresponding to instantiated
positions in the original pattern."
  (if (cl:find '? tuple)
      (cl:remove '? tuple)
    tuple))


(defgeneric internal-do-list-relation (rel elt-fn value-fn))

(defmacro do-list-relation ((tuple rel &optional value) &body body)
  `(block nil
     (internal-do-list-relation ,rel (lambda (,tuple) . ,body)
				(lambda () ,value))))

(defmethod internal-do-list-relation ((rel wb-list-relation) elt-fn value-fn)
  (Do-WB-Set-Tree-Members (tuple (wb-set-contents (wb-list-relation-tuples rel))
				 (funcall value-fn))
    (funcall elt-fn tuple)))

(defun print-wb-list-relation (rel stream level)
  (if (and *print-level* (>= level *print-level*))
      (format stream "#")
    (progn
      (format stream "#{* ")
      (let ((i 0))
	(do-list-relation (tuple rel)
	  (when (> i 0)
	    (format stream " "))
	  (when (and *print-length* (>= i *print-length*))
	    (format stream "...")
	    (return))
	  (incf i)
	  (let ((*print-level* (and *print-level* (1- *print-level*))))
	    (write tuple :stream stream)))
	(when (> i 0)
	  (format stream " ")))
      (format stream "*}~@[^~D~]" (arity rel)))))

(gmap:def-gmap-arg-type list-relation (rel)
  `((Make-WB-Set-Tree-Iterator-Internal (wb-set-contents (wb-list-relation-tuples ,rel)))
    #'WB-Set-Tree-Iterator-Done?
    #'WB-Set-Tree-Iterator-Get))


#||

Okay, this is a start, but:

() Don't we want to do better meta-indexing, so adding a tuple doesn't require
iterating through all the indices?  [Eh, maybe not]

() I'm not creating composite indices yet.  The plan is straightforward -- create
one when the size of the final result set is <= the square root of the size of
the smallest index set.  This is easy, but how do subsequent queries find the
composite index?  [Why "square root"?  Maybe a fixed fraction like 1/8?]

||#


;;; A query registry to be used with `list-relation'.  Register queries with `with',
;;; supplying a pattern.  The queries themselves are uninterpreted except that they are
;;; kept in sets (so bare CL closures are not a good choice).  `lookup' returns the set of
;;; queries that match the supplied tuple.  A single query registry can now be used with
;;; several list-relations of different arities, but the client has to check whether the
;;; arity of each returned query matches that of the tuple.
(defstruct (query-registry
	     (:constructor make-query-registry (list-relations)))
  ;; A map from pattern mask to a list-relation holding lists of the form
  ;; `(,query . ,masked-tuple).
  list-relations)

(defun empty-query-registry ()
  (make-query-registry (empty-map (empty-list-relation))))

(defmethod with ((reg query-registry) pattern &optional (query nil query?))
  (check-three-arguments query? 'with 'query-registry)
  (let ((mask (pattern-mask pattern)))
    (make-query-registry (with (query-registry-list-relations reg)
			       mask (with (@ (query-registry-list-relations reg) mask)
					  (cons query (reduced-tuple pattern)))))))

(defmethod less ((reg query-registry) pattern &optional (query nil query?))
  (check-three-arguments query? 'less 'query-registry)
  (if (empty? (query-registry-indices reg))
      reg
    (let ((mask (pattern-mask pattern)))
      (make-query-registry (with (query-registry-list-relations reg)
				 mask (less (@ (query-registry-list-relations reg) mask)
					    (cons query (reduced-tuple pattern))))))))

(defmethod all-queries ((reg query-registry))
  (gmap (:result union)
	(fn (_mask rel)
	  (image #'car (wb-list-relation-tuples rel)))
	(:arg map (query-registry-list-relations reg))))

(defmacro do-all-queries ((query reg &optional value) &body body)
  `(block nil
     (internal-do-all-queries ,reg (lambda (,query) . ,body)
			      (lambda () ,value))))

(defmethod internal-do-all-queries ((reg query-registry) elt-fn value-fn)
  (do-map (mask rel (query-registry-list-relations reg) (funcall value-fn))
    (declare (ignore mask))
    (do-list-relation (tuple rel)
      (funcall elt-fn (car tuple)))))

(defmethod lookup ((reg query-registry) tuple)
  "Returns all queries in `reg' whose patterns match `tuple'."
  (gmap (:result union)
	(fn (mask list-rel)
	  (let ((msk-tup (masked-tuple tuple mask)))
	    (if msk-tup (image #'car (query list-rel (cons '? msk-tup)))
	      (set))))
	(:arg map (query-registry-list-relations reg))))

(defmethod lookup-multi ((reg query-registry) set-tuple)
  "Here `set-tuple' contains a set of values in each position.  Returns
all queries in `reg' whose patterns match any member of each set."
  (gmap (:result union)
	(fn (mask list-rel)
	  (let ((msk-tup (masked-tuple set-tuple mask)))
	    (if msk-tup (image #'car (query-multi list-rel (cons '? msk-tup)))
	      (set))))
	(:arg map (query-registry-list-relations reg))))

(defun masked-tuple (tuple mask)
  (do ((mask mask (ash mask -1))
       (tuple tuple (cdr tuple))
       (result nil))
      ((= mask 0) (nreverse result))
    (when (null tuple)
      (return nil))  ; tuple is too short for mask
    (when (logbitp 0 mask)
      (push (car tuple) result))))

