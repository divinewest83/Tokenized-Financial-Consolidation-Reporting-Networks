;; Report Generation Contract
;; Creates and manages consolidated financial reports

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-REPORT-EXISTS (err u401))
(define-constant ERR-REPORT-NOT-FOUND (err u402))
(define-constant ERR-INVALID-PERIOD (err u403))
(define-constant ERR-ALREADY-APPROVED (err u404))
(define-constant ERR-NOT-READY (err u405))

;; Data Variables
(define-data-var next-report-id uint u1)
(define-data-var report-manager principal tx-sender)

;; Data Maps
(define-map consolidated-reports
  { report-id: uint }
  {
    period: (string-ascii 10),
    entity-scope: (string-ascii 100),
    report-type: (string-ascii 20),
    generation-block: uint,
    generated-by: principal,
    is-approved: bool,
    approval-block: uint,
    approved-by: (optional principal),
    report-hash: (buff 32)
  }
)

(define-map period-reports
  { period: (string-ascii 10), report-type: (string-ascii 20) }
  { report-id: uint }
)

(define-map report-data
  { report-id: uint, section: (string-ascii 30) }
  { data-content: (string-ascii 500), last-updated: uint }
)

(define-map report-approvals
  { report-id: uint, approver: principal }
  { approval-timestamp: uint, approval-notes: (string-ascii 200) }
)

(define-map report-distribution
  { report-id: uint }
  {
    recipients: (list 10 principal),
    distribution-block: uint,
    distribution-status: (string-ascii 20)
  }
)

;; Public Functions

;; Generate consolidated report
(define-public (generate-report
  (period (string-ascii 10))
  (entity-scope (string-ascii 100))
  (report-type (string-ascii 20))
  (report-hash (buff 32))
)
  (let
    (
      (report-id (var-get next-report-id))
    )
    (asserts! (is-none (map-get? period-reports { period: period, report-type: report-type })) ERR-REPORT-EXISTS)

    (map-set consolidated-reports
      { report-id: report-id }
      {
        period: period,
        entity-scope: entity-scope,
        report-type: report-type,
        generation-block: block-height,
        generated-by: tx-sender,
        is-approved: false,
        approval-block: u0,
        approved-by: none,
        report-hash: report-hash
      }
    )

    (map-set period-reports
      { period: period, report-type: report-type }
      { report-id: report-id }
    )

    (var-set next-report-id (+ report-id u1))
    (ok report-id)
  )
)

;; Add report section data
(define-public (add-report-section
  (report-id uint)
  (section (string-ascii 30))
  (data-content (string-ascii 500))
)
  (let
    (
      (report-data-entry (unwrap! (map-get? consolidated-reports { report-id: report-id }) ERR-REPORT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get generated-by report-data-entry)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get is-approved report-data-entry)) ERR-ALREADY-APPROVED)

    (map-set report-data
      { report-id: report-id, section: section }
      { data-content: data-content, last-updated: block-height }
    )
    (ok true)
  )
)

;; Approve report
(define-public (approve-report (report-id uint) (approval-notes (string-ascii 200)))
  (let
    (
      (report-details (unwrap! (map-get? consolidated-reports { report-id: report-id }) ERR-REPORT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get report-manager)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get is-approved report-details)) ERR-ALREADY-APPROVED)

    (map-set consolidated-reports
      { report-id: report-id }
      (merge report-details
        {
          is-approved: true,
          approval-block: block-height,
          approved-by: (some tx-sender)
        }
      )
    )

    (map-set report-approvals
      { report-id: report-id, approver: tx-sender }
      { approval-timestamp: block-height, approval-notes: approval-notes }
    )

    (ok true)
  )
)

;; Distribute report
(define-public (distribute-report (report-id uint) (recipients (list 10 principal)))
  (let
    (
      (report-details (unwrap! (map-get? consolidated-reports { report-id: report-id }) ERR-REPORT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get report-manager)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-approved report-details) ERR-NOT-READY)

    (map-set report-distribution
      { report-id: report-id }
      {
        recipients: recipients,
        distribution-block: block-height,
        distribution-status: "distributed"
      }
    )
    (ok true)
  )
)

;; Update report manager
(define-public (update-report-manager (new-manager principal))
  (begin
    (asserts! (is-eq tx-sender (var-get report-manager)) ERR-NOT-AUTHORIZED)
    (var-set report-manager new-manager)
    (ok true)
  )
)

;; Revoke report approval
(define-public (revoke-approval (report-id uint))
  (let
    (
      (report-details (unwrap! (map-get? consolidated-reports { report-id: report-id }) ERR-REPORT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get report-manager)) ERR-NOT-AUTHORIZED)
    (asserts! (get is-approved report-details) ERR-NOT-READY)

    (map-set consolidated-reports
      { report-id: report-id }
      (merge report-details
        {
          is-approved: false,
          approval-block: u0,
          approved-by: none
        }
      )
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get report details
(define-read-only (get-report (report-id uint))
  (map-get? consolidated-reports { report-id: report-id })
)

;; Get report by period and type
(define-read-only (get-report-by-period (period (string-ascii 10)) (report-type (string-ascii 20)))
  (match (map-get? period-reports { period: period, report-type: report-type })
    report-ref (map-get? consolidated-reports { report-id: (get report-id report-ref) })
    none
  )
)

;; Get report section data
(define-read-only (get-report-section (report-id uint) (section (string-ascii 30)))
  (map-get? report-data { report-id: report-id, section: section })
)

;; Get report approval details
(define-read-only (get-approval-details (report-id uint) (approver principal))
  (map-get? report-approvals { report-id: report-id, approver: approver })
)

;; Get report distribution
(define-read-only (get-report-distribution (report-id uint))
  (map-get? report-distribution { report-id: report-id })
)

;; Get next report ID
(define-read-only (get-next-report-id)
  (var-get next-report-id)
)

;; Get report manager
(define-read-only (get-report-manager)
  (var-get report-manager)
)

;; Check if report is ready for distribution
(define-read-only (is-report-ready (report-id uint))
  (match (map-get? consolidated-reports { report-id: report-id })
    report-details (get is-approved report-details)
    false
  )
)
