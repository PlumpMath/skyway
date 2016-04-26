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
	      (w (/ (wlc_size->w (dereference-pointer r)) 2))

	      (h (/ (wlc_size->h (dereference-pointer r))
		    (max (/ (+ 1 memb) 2) 1)))
	      (let loop ((i 0))
		(let ((g (make->wlc_geometry
			  (if (= 1 toggle)
			      w
			      0)
			  y
			  (if (and (zero? toggle)
				   (= i (- memb 1)))
			      (wlc_size->w (dereference-pointer r))
			      w)
			  h)))
		  (wlc-view-set-geometry (array-ref views i)
					 0
					 g))
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
						       (dereference-pointer origin)
						       (caddr (car compositor))))))
	(wlc-view-bring-to-front view)
	1)))

(define (start-interactive-resize view edges origin)
  (let ((g (wlc-view-get-geometry view))
	(ox (wlc_point->x (dereference-pointer origin)))
	(oy (wlc_point->y (dereference-pointer origin))))
    (if (or (null-pointer? g)
	    (zero? (start-interactive-action view origin)))
	0
	(let ((g* (dereference-pointer g))
	      (halfw (+ (wlc_point->x (wlc_geometry->origin g*))
			(/ (wlc_size->w (wlc_geometry->size g*))
			   2)))
	      (halfh (+ (wlc_point->y (wlc_geometry->origin g*))
			(/ (wlc_size->h (wlc_geometry->size g*))
			   2))))
	  (set! compositor (make-c-struct compositor-struct
					  (make-c-struct action-struct
							 (list view
							       (if (zero? edges)
								   (logior (if (< ox halfw)
									       WLC_RESIZE_EDGE_LEFT
									       (if (> ox halfw)
										      WLC_RESIZE_EDGE_RIGHT
										      0))
									   (if (< oy halfh)
									       WLC_RESIZE_EDGE_TOP
									       (if (> oy halfh)
										   WLC_RESIZE_EDGE_BOTTOM
										   0)))
								   edges)
							       (dereference-pointer origin)))))
	  (wlc-view-set-state view WLC_BIT_RESIZING 1)))))
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
  (start-interactive-resize view edges origin))
(define (view-request-geometry view geometry)
  (display "view-request-geometry"))
(define (keyboard-key handle time modifiers key state)
  (let ((sym (wlc-keyboard-get-keysym-for-key key %null-pointer))
	(mod-and-ctrl (not (zero? (logand (wlc_modifiers->mods modifiers)
					  WLC_BIT_MOD_CTRL)))))
    (if (= state WLC_KEY_STATE_PRESSED)
	(begin
	  (if (not (zero? view))
	      (if (and mod-and-ctrl
		       (= sym XKB_KEY_q))
		  (begin
		    (wlc-view-close view)
		    1)
		  (if (and mod-and-ctrl
			   (= sym XKB_KEY_Down))
		      (begin
			(wlc-view-send-to-back view)
			(wlc-view-focus (get-topmost (wlc-view-get-output view)
						     0))
			1))))
	  (if (and mod-and-ctrl
		   (= sym XKB_KEY_Escape))
	      (begin
		(wlc-terminate)
		1)
	      (if (and mod-and-ctrl
		       (= sym XKB_KEY_Return))
		  (let ((term (if (getenv "TERMINAL")
				  (getenv "TERMINAL")
				  "weston-terminal")))
		    (wlc-exec (string->pointer term)
			      (make-vector (string-pointer term)
					   %null-pointer))
		    1))))))
  0)
(define (pointer-button view time modifiers button state position)
  (if (= state WLC_BUTTON_STATE_PRESSED)
      (begin
	(wlc-view-focus view)
	(if (not (null-pointer? view))
	    (if (and (not (zero? (logand (wlc_modifiers->mods modifiers)
					 WLC_BIT_MOD_CTRL)))
		     (= button BTN_LEFT))
		(start-interactive-move view position))
	    (if (and (not (zero? (logand (wlc_modifiers->mods modifiers)
					 WLC_BIT_MOD_CTRL)))
		     (= button BTN_RIGHT))
		(start-interactive-resize view 0 position))))
      (stop-interactive-action))
  (not (zero? (car (car compositor)))))
(define (pointer-motion handle time position)
  (if (not (zero? (car (car compositor))))
      (let ((grab (cadr (car compositor)))
	      (dx (- (wlc_point->x position)
		     (wlc_point->x grab)))
	      (dy (- (wlc_point->y position)
		     (wlc_point->y grab)))
	      (g (dereference-pointer (wlc-view-get-geometry (wlc-view-get-geometry (car (car compositor)))))))
	  (if (not (zero? (caddr (car (compositor)))))
	      (let ((min_size (make-c-struct wlc-size (list 80 40)))
		    (n g))
		(if (not (zero? (logand (caddr (car compositor))
					WLC_RESIZE_EDGE_LEFT)))
		    (set! n (make->wlc_geometry
			     (make->wlc_point (+ (wlc_point->x (wlc_geometry->origin n))
						 dx)
					      (wlc_point->y (wlc_geometry->origin n)))
			     (make->wlc_size (- (wlc_size->w (wlc_geometry->size n))
						dx)
					     (wlc_size->h (wlc_geometry->size n)))))
		    (if (not (zero? (logand (caddr (car compositor))
					    WLC_RESIZE_EDGE_RIGHT)))
			(set! n (make->wlc_geometry
				 (wlc_geometry->origin n)
				 (make->wlc_size (+ (wlc_size->w (wlc_geometry->size n))
					 	    dx)
						 (wlc_size->h (wlc_geometry->size n)))))))
		(if (not (zero? (logand (caddr (car compositor))
					WLC_RESIZE_EDGE_TOP)))
		    (set! n (make->wlc_geometry
			     (make->wlc_point (wlc_point->x (wlc_geometry->origin n))
					      (+ (wlc_point->y (wlc_geometry->origin n))
						 dy))
			     (make->wlc_size (wlc_size->w (wlc_geometry->size n))
					     (- (wlc_size->h (wlc_geometry->size n))
						dy))))
		    (if (not (zero? (logand (caddr (car compositor))
					    WLC_RESIZE_EDGE_BOTTOM)))
			(set! n (make->wlc_geometry
				 (wlc_geometry->origin n)
				 (make->wlc_size (wlc-size->w (wlc_geometry->size n))
						 (+ (wlc_size->h (wlc_geometry->size n))
						    dy))))))
		(if (>= (wlc_size->w (wlc_geometry->size n)) (wlc_size->w min_size))
		    (set! g (make->wlc_geometry
			     (make->wlc_point (wlc_point->x (wlc_geometry->origin n))
					      (wlc_point->y (wlc_geometry->origin g)))
			     (make->wlc_size (wlc_size->w (wlc_geometry->size n))
					     (wlc_size->h (wlc_geometry->size g))))))
		(if (>= (wlc_size->h (wlc_geometry->size n)) (wlc_size->h min_size))
		    (set! g (make->wlc_geometry
			     (make->wlc_point (wlc_point->x (wlc_geometry->origin g))
					      (wlc_point->y (wlc_geometry->origin n)))
			     (make->wlc_size (wlc_size->w (wlc_geometry->size g))
					     (wlc_size->h (wlc_geometry->size n))))))
		(wlc-view-set-geometry (car (car compositor))
				       (caddr (car compositor))
				       (dynamic-pointer g)))
	      (begin
		(set! g (make->wlc_geometry
			 (make->wlc_point (+ (wlc_point->x (wlc_geometry->origin g))
					     dx)
					  (+ (wlc_point->y (wlc_geometry->origin g))
					     dy))
			 (wlc_geometry->size g)))
		(wlc-view-set-geometry (car (car compositor))
				       0
				       (dynamic-pointer g))))))
  (wlc-pointer-set-position position)
  (not (zero? (car (car compositor)))))

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

