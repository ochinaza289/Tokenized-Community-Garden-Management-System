;; Educational Programming Contract
;; Organizes gardening workshops and skill development

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-WORKSHOP-NOT-FOUND (err u401))
(define-constant ERR-INVALID-INPUT (err u402))
(define-constant ERR-WORKSHOP-FULL (err u403))
(define-constant ERR-ALREADY-REGISTERED (err u404))
(define-constant ERR-REGISTRATION-NOT-FOUND (err u405))

;; Data Variables
(define-data-var next-workshop-id uint u1)
(define-data-var next-registration-id uint u1)
(define-data-var workshop-fee uint u25)

;; Data Maps
(define-map workshops
  { workshop-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 300),
    instructor: principal,
    category: (string-ascii 50),
    skill-level: (string-ascii 20),
    max-participants: uint,
    current-participants: uint,
    date: uint,
    duration: uint,
    fee: uint,
    is-active: bool
  }
)

(define-map registrations
  { registration-id: uint }
  {
    workshop-id: uint,
    participant: principal,
    registration-date: uint,
    attendance-status: (string-ascii 20),
    completion-status: (string-ascii 20),
    feedback-rating: uint
  }
)

(define-map user-registrations
  { user: principal }
  { registration-ids: (list 30 uint) }
)

(define-map user-skills
  { user: principal }
  {
    completed-workshops: uint,
    skill-categories: (list 10 (string-ascii 50)),
    total-hours: uint,
    certification-level: (string-ascii 20),
    mentor-status: bool
  }
)

(define-map instructor-profiles
  { instructor: principal }
  {
    total-workshops: uint,
    total-participants: uint,
    average-rating: uint,
    specializations: (list 5 (string-ascii 50)),
    is-certified: bool
  }
)

;; Workshop Management Functions

(define-public (create-workshop (title (string-ascii 100)) (description (string-ascii 300))
                               (category (string-ascii 50)) (skill-level (string-ascii 20))
                               (max-participants uint) (date uint) (duration uint) (fee uint))
  (let ((workshop-id (var-get next-workshop-id)))
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> max-participants u0) ERR-INVALID-INPUT)
    (asserts! (> date block-height) ERR-INVALID-INPUT)
    (asserts! (> duration u0) ERR-INVALID-INPUT)

    (map-set workshops
      { workshop-id: workshop-id }
      {
        title: title,
        description: description,
        instructor: tx-sender,
        category: category,
        skill-level: skill-level,
        max-participants: max-participants,
        current-participants: u0,
        date: date,
        duration: duration,
        fee: fee,
        is-active: true
      }
    )

    ;; Update instructor profile
    (let ((current-profile (default-to
                           { total-workshops: u0, total-participants: u0, average-rating: u0,
                             specializations: (list), is-certified: false }
                           (map-get? instructor-profiles { instructor: tx-sender }))))
      (map-set instructor-profiles
        { instructor: tx-sender }
        (merge current-profile {
          total-workshops: (+ (get total-workshops current-profile) u1)
        })
      )
    )

    (var-set next-workshop-id (+ workshop-id u1))
    (ok workshop-id)
  )
)

(define-public (register-for-workshop (workshop-id uint))
  (let (
    (workshop (unwrap! (map-get? workshops { workshop-id: workshop-id }) ERR-WORKSHOP-NOT-FOUND))
    (registration-id (var-get next-registration-id))
  )
    (asserts! (get is-active workshop) ERR-WORKSHOP-NOT-FOUND)
    (asserts! (< (get current-participants workshop) (get max-participants workshop)) ERR-WORKSHOP-FULL)
    (asserts! (> (get date workshop) block-height) ERR-INVALID-INPUT)

    ;; Create registration
    (map-set registrations
      { registration-id: registration-id }
      {
        workshop-id: workshop-id,
        participant: tx-sender,
        registration-date: block-height,
        attendance-status: "registered",
        completion-status: "pending",
        feedback-rating: u0
      }
    )

    ;; Update workshop participant count
    (map-set workshops
      { workshop-id: workshop-id }
      (merge workshop {
        current-participants: (+ (get current-participants workshop) u1)
      })
    )

    ;; Update user registrations
    (let ((current-registrations (default-to { registration-ids: (list) }
                                            (map-get? user-registrations { user: tx-sender }))))
      (map-set user-registrations
        { user: tx-sender }
        { registration-ids: (unwrap! (as-max-len? (append (get registration-ids current-registrations) registration-id) u30) ERR-INVALID-INPUT) }
      )
    )

    (var-set next-registration-id (+ registration-id u1))
    (ok registration-id)
  )
)

(define-public (mark-attendance (registration-id uint) (attended bool))
  (let (
    (registration (unwrap! (map-get? registrations { registration-id: registration-id }) ERR-REGISTRATION-NOT-FOUND))
    (workshop (unwrap! (map-get? workshops { workshop-id: (get workshop-id registration) }) ERR-WORKSHOP-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get instructor workshop)) ERR-NOT-AUTHORIZED)

    (map-set registrations
      { registration-id: registration-id }
      (merge registration {
        attendance-status: (if attended "attended" "absent")
      })
    )

    (ok true)
  )
)

(define-public (complete-workshop (registration-id uint) (completion-rating uint))
  (let (
    (registration (unwrap! (map-get? registrations { registration-id: registration-id }) ERR-REGISTRATION-NOT-FOUND))
    (workshop (unwrap! (map-get? workshops { workshop-id: (get workshop-id registration) }) ERR-WORKSHOP-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get participant registration)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get attendance-status registration) "attended") ERR-INVALID-INPUT)
    (asserts! (and (<= completion-rating u5) (> completion-rating u0)) ERR-INVALID-INPUT)

    ;; Update registration
    (map-set registrations
      { registration-id: registration-id }
      (merge registration {
        completion-status: "completed",
        feedback-rating: completion-rating
      })
    )

    ;; Update user skills
    (let ((current-skills (default-to
                          { completed-workshops: u0, skill-categories: (list), total-hours: u0,
                            certification-level: "beginner", mentor-status: false }
                          (map-get? user-skills { user: tx-sender }))))
      (map-set user-skills
        { user: tx-sender }
        {
          completed-workshops: (+ (get completed-workshops current-skills) u1),
          skill-categories: (get skill-categories current-skills),
          total-hours: (+ (get total-hours current-skills) (get duration workshop)),
          certification-level: (if (>= (+ (get completed-workshops current-skills) u1) u10)
                                  "advanced"
                                  (get certification-level current-skills)),
          mentor-status: (>= (+ (get completed-workshops current-skills) u1) u15)
        }
      )
    )

    (ok true)
  )
)

(define-public (cancel-registration (registration-id uint))
  (let (
    (registration (unwrap! (map-get? registrations { registration-id: registration-id }) ERR-REGISTRATION-NOT-FOUND))
    (workshop (unwrap! (map-get? workshops { workshop-id: (get workshop-id registration) }) ERR-WORKSHOP-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get participant registration)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get attendance-status registration) "registered") ERR-INVALID-INPUT)
    (asserts! (> (get date workshop) block-height) ERR-INVALID-INPUT)

    ;; Update registration status
    (map-set registrations
      { registration-id: registration-id }
      (merge registration { attendance-status: "cancelled" })
    )

    ;; Update workshop participant count
    (map-set workshops
      { workshop-id: (get workshop-id registration) }
      (merge workshop {
        current-participants: (- (get current-participants workshop) u1)
      })
    )

    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-workshop (workshop-id uint))
  (map-get? workshops { workshop-id: workshop-id })
)

(define-read-only (get-registration (registration-id uint))
  (map-get? registrations { registration-id: registration-id })
)

(define-read-only (get-user-registrations (user principal))
  (map-get? user-registrations { user: user })
)

(define-read-only (get-user-skills (user principal))
  (map-get? user-skills { user: user })
)

(define-read-only (get-instructor-profile (instructor principal))
  (map-get? instructor-profiles { instructor: instructor })
)

(define-read-only (get-workshop-fee)
  (var-get workshop-fee)
)

;; Admin Functions

(define-public (set-workshop-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set workshop-fee new-fee)
    (ok true)
  )
)

(define-public (certify-instructor (instructor principal))
  (let ((current-profile (default-to
                         { total-workshops: u0, total-participants: u0, average-rating: u0,
                           specializations: (list), is-certified: false }
                         (map-get? instructor-profiles { instructor: instructor }))))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set instructor-profiles
      { instructor: instructor }
      (merge current-profile { is-certified: true })
    )

    (ok true)
  )
)
