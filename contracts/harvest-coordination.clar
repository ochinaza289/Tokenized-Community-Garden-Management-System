;; Harvest Coordination Contract
;; Manages produce distribution and surplus sharing

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-HARVEST-NOT-FOUND (err u301))
(define-constant ERR-INVALID-INPUT (err u302))
(define-constant ERR-INSUFFICIENT-QUANTITY (err u303))
(define-constant ERR-DISTRIBUTION-NOT-FOUND (err u304))

;; Data Variables
(define-data-var next-harvest-id uint u1)
(define-data-var next-distribution-id uint u1)
(define-data-var surplus-threshold uint u100)

;; Data Maps
(define-map harvests
  { harvest-id: uint }
  {
    harvester: principal,
    plot-id: uint,
    produce-type: (string-ascii 50),
    quantity: uint,
    harvest-date: uint,
    quality-rating: uint,
    is-surplus: bool,
    available-for-sharing: uint
  }
)

(define-map distributions
  { distribution-id: uint }
  {
    harvest-id: uint,
    recipient: principal,
    quantity: uint,
    distribution-date: uint,
    distribution-type: (string-ascii 20)
  }
)

(define-map user-harvest-history
  { user: principal }
  { harvest-ids: (list 50 uint) }
)

(define-map produce-inventory
  { produce-type: (string-ascii 50) }
  {
    total-available: uint,
    total-distributed: uint,
    current-surplus: uint,
    last-updated: uint
  }
)

(define-map community-contributions
  { user: principal }
  {
    total-harvested: uint,
    total-shared: uint,
    total-received: uint,
    contribution-score: uint
  }
)

;; Harvest Management Functions

(define-public (record-harvest (plot-id uint) (produce-type (string-ascii 50))
                              (quantity uint) (quality-rating uint))
  (let ((harvest-id (var-get next-harvest-id)))
    (asserts! (> quantity u0) ERR-INVALID-INPUT)
    (asserts! (and (<= quality-rating u5) (> quality-rating u0)) ERR-INVALID-INPUT)
    (asserts! (> (len produce-type) u0) ERR-INVALID-INPUT)

    (let ((is-surplus (>= quantity (var-get surplus-threshold))))
      (map-set harvests
        { harvest-id: harvest-id }
        {
          harvester: tx-sender,
          plot-id: plot-id,
          produce-type: produce-type,
          quantity: quantity,
          harvest-date: block-height,
          quality-rating: quality-rating,
          is-surplus: is-surplus,
          available-for-sharing: (if is-surplus (/ quantity u2) u0)
        }
      )
    )

    ;; Update user harvest history
    (let ((current-history (default-to { harvest-ids: (list) }
                                      (map-get? user-harvest-history { user: tx-sender }))))
      (map-set user-harvest-history
        { user: tx-sender }
        { harvest-ids: (unwrap! (as-max-len? (append (get harvest-ids current-history) harvest-id) u50) ERR-INVALID-INPUT) }
      )
    )

    ;; Update produce inventory
    (let ((current-inventory (default-to
                             { total-available: u0, total-distributed: u0, current-surplus: u0, last-updated: u0 }
                             (map-get? produce-inventory { produce-type: produce-type }))))
      (map-set produce-inventory
        { produce-type: produce-type }
        {
          total-available: (+ (get total-available current-inventory) quantity),
          total-distributed: (get total-distributed current-inventory),
          current-surplus: (+ (get current-surplus current-inventory)
                            (if (>= quantity (var-get surplus-threshold)) (/ quantity u2) u0)),
          last-updated: block-height
        }
      )
    )

    ;; Update community contributions
    (let ((current-contrib (default-to
                           { total-harvested: u0, total-shared: u0, total-received: u0, contribution-score: u0 }
                           (map-get? community-contributions { user: tx-sender }))))
      (map-set community-contributions
        { user: tx-sender }
        {
          total-harvested: (+ (get total-harvested current-contrib) quantity),
          total-shared: (get total-shared current-contrib),
          total-received: (get total-received current-contrib),
          contribution-score: (+ (get contribution-score current-contrib) quality-rating)
        }
      )
    )

    (var-set next-harvest-id (+ harvest-id u1))
    (ok harvest-id)
  )
)

(define-public (request-surplus-share (harvest-id uint) (requested-quantity uint))
  (let (
    (harvest (unwrap! (map-get? harvests { harvest-id: harvest-id }) ERR-HARVEST-NOT-FOUND))
    (distribution-id (var-get next-distribution-id))
  )
    (asserts! (> requested-quantity u0) ERR-INVALID-INPUT)
    (asserts! (get is-surplus harvest) ERR-INVALID-INPUT)
    (asserts! (>= (get available-for-sharing harvest) requested-quantity) ERR-INSUFFICIENT-QUANTITY)
    (asserts! (not (is-eq tx-sender (get harvester harvest))) ERR-INVALID-INPUT)

    ;; Create distribution record
    (map-set distributions
      { distribution-id: distribution-id }
      {
        harvest-id: harvest-id,
        recipient: tx-sender,
        quantity: requested-quantity,
        distribution-date: block-height,
        distribution-type: "surplus-share"
      }
    )

    ;; Update harvest availability
    (map-set harvests
      { harvest-id: harvest-id }
      (merge harvest {
        available-for-sharing: (- (get available-for-sharing harvest) requested-quantity)
      })
    )

    ;; Update recipient contributions
    (let ((current-contrib (default-to
                           { total-harvested: u0, total-shared: u0, total-received: u0, contribution-score: u0 }
                           (map-get? community-contributions { user: tx-sender }))))
      (map-set community-contributions
        { user: tx-sender }
        {
          total-harvested: (get total-harvested current-contrib),
          total-shared: (get total-shared current-contrib),
          total-received: (+ (get total-received current-contrib) requested-quantity),
          contribution-score: (get contribution-score current-contrib)
        }
      )
    )

    ;; Update harvester contributions
    (let ((harvester-contrib (default-to
                             { total-harvested: u0, total-shared: u0, total-received: u0, contribution-score: u0 }
                             (map-get? community-contributions { user: (get harvester harvest) }))))
      (map-set community-contributions
        { user: (get harvester harvest) }
        {
          total-harvested: (get total-harvested harvester-contrib),
          total-shared: (+ (get total-shared harvester-contrib) requested-quantity),
          total-received: (get total-received harvester-contrib),
          contribution-score: (+ (get contribution-score harvester-contrib) u1)
        }
      )
    )

    (var-set next-distribution-id (+ distribution-id u1))
    (ok distribution-id)
  )
)

(define-public (donate-to-food-bank (harvest-id uint) (quantity uint))
  (let (
    (harvest (unwrap! (map-get? harvests { harvest-id: harvest-id }) ERR-HARVEST-NOT-FOUND))
    (distribution-id (var-get next-distribution-id))
  )
    (asserts! (is-eq tx-sender (get harvester harvest)) ERR-NOT-AUTHORIZED)
    (asserts! (> quantity u0) ERR-INVALID-INPUT)
    (asserts! (>= (get available-for-sharing harvest) quantity) ERR-INSUFFICIENT-QUANTITY)

    ;; Create distribution record
    (map-set distributions
      { distribution-id: distribution-id }
      {
        harvest-id: harvest-id,
        recipient: CONTRACT-OWNER,
        quantity: quantity,
        distribution-date: block-height,
        distribution-type: "food-bank"
      }
    )

    ;; Update harvest availability
    (map-set harvests
      { harvest-id: harvest-id }
      (merge harvest {
        available-for-sharing: (- (get available-for-sharing harvest) quantity)
      })
    )

    ;; Update harvester contributions (bonus for food bank donation)
    (let ((current-contrib (default-to
                           { total-harvested: u0, total-shared: u0, total-received: u0, contribution-score: u0 }
                           (map-get? community-contributions { user: tx-sender }))))
      (map-set community-contributions
        { user: tx-sender }
        {
          total-harvested: (get total-harvested current-contrib),
          total-shared: (+ (get total-shared current-contrib) quantity),
          total-received: (get total-received current-contrib),
          contribution-score: (+ (get contribution-score current-contrib) u5)
        }
      )
    )

    (var-set next-distribution-id (+ distribution-id u1))
    (ok distribution-id)
  )
)

;; Read-only Functions

(define-read-only (get-harvest (harvest-id uint))
  (map-get? harvests { harvest-id: harvest-id })
)

(define-read-only (get-distribution (distribution-id uint))
  (map-get? distributions { distribution-id: distribution-id })
)

(define-read-only (get-user-harvest-history (user principal))
  (map-get? user-harvest-history { user: user })
)

(define-read-only (get-produce-inventory (produce-type (string-ascii 50)))
  (map-get? produce-inventory { produce-type: produce-type })
)

(define-read-only (get-community-contributions (user principal))
  (map-get? community-contributions { user: user })
)

(define-read-only (get-surplus-threshold)
  (var-get surplus-threshold)
)

;; Admin Functions

(define-public (set-surplus-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-threshold u0) ERR-INVALID-INPUT)
    (var-set surplus-threshold new-threshold)
    (ok true)
  )
)
