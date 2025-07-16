;; Data Consolidation Contract
;; Handles financial data submission and consolidation

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-AMOUNT (err u201))
(define-constant ERR-INVALID-PERIOD (err u202))
(define-constant ERR-DATA-EXISTS (err u203))
(define-constant ERR-DATA-NOT-FOUND (err u204))
(define-constant ERR-PERIOD-CLOSED (err u205))

;; Data Variables
(define-data-var next-entry-id uint u1)
(define-data-var consolidation-manager principal tx-sender)

;; Data Maps
(define-map financial-data
  { entry-id: uint }
  {
    entity-id: (string-ascii 20),
    account-code: (string-ascii 15),
    amount: int,
    period: (string-ascii 10),
    data-type: (string-ascii 20),
    submission-block: uint,
    submitted-by: principal,
    is-validated: bool
  }
)

(define-map entity-data-index
  { entity-id: (string-ascii 20), period: (string-ascii 10), account-code: (string-ascii 15) }
  { entry-id: uint }
)

(define-map period-status
  { period: (string-ascii 10) }
  { is-open: bool, close-block: uint }
)

(define-map consolidated-totals
  { period: (string-ascii 10), account-code: (string-ascii 15) }
  { total-amount: int, entry-count: uint, last-updated: uint }
)

;; Public Functions

;; Submit financial data
(define-public (submit-financial-data
  (entity-id (string-ascii 20))
  (account-code (string-ascii 15))
  (amount int)
  (period (string-ascii 10))
  (data-type (string-ascii 20))
)
  (let
    (
      (entry-id (var-get next-entry-id))
      (period-info (default-to { is-open: true, close-block: u0 } (map-get? period-status { period: period })))
    )
    (asserts! (get is-open period-info) ERR-PERIOD-CLOSED)
    (asserts! (is-none (map-get? entity-data-index { entity-id: entity-id, period: period, account-code: account-code })) ERR-DATA-EXISTS)

    (map-set financial-data
      { entry-id: entry-id }
      {
        entity-id: entity-id,
        account-code: account-code,
        amount: amount,
        period: period,
        data-type: data-type,
        submission-block: block-height,
        submitted-by: tx-sender,
        is-validated: false
      }
    )

    (map-set entity-data-index
      { entity-id: entity-id, period: period, account-code: account-code }
      { entry-id: entry-id }
    )

    (var-set next-entry-id (+ entry-id u1))
    (ok entry-id)
  )
)

;; Validate financial data entry
(define-public (validate-data-entry (entry-id uint))
  (let
    (
      (entry-data (unwrap! (map-get? financial-data { entry-id: entry-id }) ERR-DATA-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get consolidation-manager)) ERR-NOT-AUTHORIZED)

    (map-set financial-data
      { entry-id: entry-id }
      (merge entry-data { is-validated: true })
    )

    ;; Update consolidated totals
    (update-consolidated-total (get period entry-data) (get account-code entry-data) (get amount entry-data))
    (ok true)
  )
)

;; Close consolidation period
(define-public (close-period (period (string-ascii 10)))
  (begin
    (asserts! (is-eq tx-sender (var-get consolidation-manager)) ERR-NOT-AUTHORIZED)

    (map-set period-status
      { period: period }
      { is-open: false, close-block: block-height }
    )
    (ok true)
  )
)

;; Reopen consolidation period
(define-public (reopen-period (period (string-ascii 10)))
  (begin
    (asserts! (is-eq tx-sender (var-get consolidation-manager)) ERR-NOT-AUTHORIZED)

    (map-set period-status
      { period: period }
      { is-open: true, close-block: u0 }
    )
    (ok true)
  )
)

;; Update consolidation manager
(define-public (update-consolidation-manager (new-manager principal))
  (begin
    (asserts! (is-eq tx-sender (var-get consolidation-manager)) ERR-NOT-AUTHORIZED)
    (var-set consolidation-manager new-manager)
    (ok true)
  )
)

;; Private Functions

;; Update consolidated total for account
(define-private (update-consolidated-total (period (string-ascii 10)) (account-code (string-ascii 15)) (amount int))
  (let
    (
      (current-total (default-to { total-amount: 0, entry-count: u0, last-updated: u0 }
                     (map-get? consolidated-totals { period: period, account-code: account-code })))
    )
    (map-set consolidated-totals
      { period: period, account-code: account-code }
      {
        total-amount: (+ (get total-amount current-total) amount),
        entry-count: (+ (get entry-count current-total) u1),
        last-updated: block-height
      }
    )
  )
)

;; Read-only Functions

;; Get financial data entry
(define-read-only (get-financial-data (entry-id uint))
  (map-get? financial-data { entry-id: entry-id })
)

;; Get entity data for period and account
(define-read-only (get-entity-data (entity-id (string-ascii 20)) (period (string-ascii 10)) (account-code (string-ascii 15)))
  (match (map-get? entity-data-index { entity-id: entity-id, period: period, account-code: account-code })
    index-data (map-get? financial-data { entry-id: (get entry-id index-data) })
    none
  )
)

;; Get consolidated total
(define-read-only (get-consolidated-total (period (string-ascii 10)) (account-code (string-ascii 15)))
  (map-get? consolidated-totals { period: period, account-code: account-code })
)

;; Get period status
(define-read-only (get-period-status (period (string-ascii 10)))
  (default-to { is-open: true, close-block: u0 } (map-get? period-status { period: period }))
)

;; Get next entry ID
(define-read-only (get-next-entry-id)
  (var-get next-entry-id)
)

;; Get consolidation manager
(define-read-only (get-consolidation-manager)
  (var-get consolidation-manager)
)
