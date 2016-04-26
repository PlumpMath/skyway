(define-module (skyway skyway)
  #:use-module (system foreign)
  #:use-module (skyway bindings))

(define action-struct (list wlc_handle wlc_point uint32))
(define compositor-struct (list action-struct))

(define compositor (make-c-struct compositor-struct
				  (make-c-struct action-struct
						 (list 0 (make-c-struct wlc_point
									(list 0 0)) 0))))
(define (relayout output)
  (let ((r (wlc-output-get-resolution output)) (memb 0) (memb-addr (dynamic-pointer memb)))
    (if (not (null-pointer? r))
	(let ((views (wlc-output-get-views output memb-addr))
	      (toggle 0) (y 0)
	      (w (/ (wlc_size->w r) 2))

	      (h (/ (wlc_size->h r)
		    (max (/ (+ 1 memb) 2) 1)))
	      (let loop ((i 0))
		(let ((g (make-c-struct wlc_geometry
					(make-c-struct wlc_point
						       (list (if (= 1 toggle)
								 w
								 0)
							     y))
					(make-c-struct wlc_size
						       (list (if (and (zero? toggle)
								      (= i (- memb 1)))
								 (wlc_size->w r)
								 w)
							     h)))))
		  (wlc-view-set-geometry (array-ref views i) 0 (dynamic-pointer g))
		  (set! toggle (if (zero? toggle)
				   1
				   0))
		  (set! y (+ y (if (zero? toggle)
				   h
				   0)))
		  (loop (+ i 1)))))))))

(define (get-topmost output offset)
  (let ((memb 0) (views (wlc-output-get-views output (dynamic-pointer memb))))
    (if (> memb 0)
	(array-ref views (modulo (+ memb offset -1) memb))
	0)))

(define (start-interactive-action view origin)
  (if (zero? (car (car compositor)))
      0
      (begin
	(set! compositor (make-c-struct compositor-struct
				  (make-c-struct action-struct
						 (list view
						       (cadr (car compositor))
						       (dereference-pointer origin)))))
	(wlc-view-bring-to-front view)
	1)))
(define (output-resolution output from to)
  (relayout output))
(define (view-created view)
  (wlc-view-set-mask view
		     (wlc-output-get-mask
		      (wlc-view-get-output view)))
  (wlc-view-bring-to-front view)
  (wlc-view-focus view)
  (relayout (wlc-view-get-output view))
  1)
(define (view-destroyed view)
  (wlc-view-focus (get-topmost (wlc-view-get-output view)
			       0))
  (relayout (wlc-view-get-output view)))
(define (view-focus view focus)
  (wlc-view-set-state view WLC_BIT_ACTIVATED focus))
(define (view-request-move view origin)
  (start-interactive-action view origin))
(define (view-request-resize view edges origin)
  (display "view-request-resize"))
(define (view-request-geometry view geometry)
  (display "view-request-geometry"))
(define (keyboard-key handle time modifiers key state)
  (display "keyboard-key"))
(define (pointer-button handle time modifiers button state position)
  (display "pointer-button"))
(define (pointer-motion handle time position)
  (display "pointer-motion"))

(wlc-set-output-resolution-cb (procedure->pointer void
						  output-resolution
						  (list wlc_handle '* '*)))
(wlc-set-view-created-cb (procedure->pointer bool
					     view-created
					     (list wlc_handle)))
(wlc-set-view-destroyed-cb (procedure->pointer void
					      view-destroyed
					      (list wlc_handle)))
(wlc-set-view-focus-cb (procedure->pointer void
					   view-focus
					   (list wlc_handle bool)))
(wlc-set-view-request-move-cb (procedure->pointer void
						  view-request-move
						  (list wlc_handle '*)))
(wlc-set-view-request-resize-cb (procedure->pointer void
						    view-request-resize
						    (list wlc_handle uint32 '*)))
(wlc-set-view-request-geometry-cb (procedure->pointer void
						      view-request-geometry
						      (list wlc_handle '*)))
(wlc-set-keyboard-key-cb (procedure->pointer bool
					     keyboard-key
					     (list wlc_handle uint32 '* uint32 int)))
(wlc-set-pointer-button-cb (procedure->pointer bool
					       pointer-button
					       (list wlc_handle uint32 '* uint32 int '*)))
(wlc-set-pointer-motion-cb (procedure->pointer bool
					       pointer-motion
					       (list wlc_handle uint32 '*)))
(wlc-init)
(wlc-run)

