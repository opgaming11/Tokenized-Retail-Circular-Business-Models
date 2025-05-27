;; Product Lifecycle Contract
;; Tracks circular product journeys through their complete lifecycle

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u404))
(define-constant err-already-exists (err u409))
(define-constant err-invalid-input (err u400))
(define-constant err-unauthorized (err u401))

;; Lifecycle stages
(define-constant stage-production u1)
(define-constant stage-distribution u2)
(define-constant stage-retail u3)
(define-constant stage-use u4)
(define-constant stage-return u5)
(define-constant stage-refurbish u6)
(define-constant stage-reuse u7)
(define-constant stage-recycle u8)
(define-constant stage-disposal u9)

;; Data Variables
(define-data-var next-product-id uint u1)

;; Data Maps
(define-map products
  { product-id: uint }
  {
    retailer: principal,
    name: (string-ascii 64),
    category: (string-ascii 32),
    creation-block: uint,
    current-stage: uint,
    quality-score: uint,
    circular-count: uint,
    active: bool
  })

(define-map product-history
  { product-id: uint, stage: uint }
  {
    timestamp: uint,
    quality-assessment: uint,
    notes: (string-ascii 128),
    assessor: principal
  })

(define-map stage-transitions
  { product-id: uint }
  { stages-completed: (list 20 uint) })

;; Public Functions

;; Register a new product
(define-public (register-product
  (name (string-ascii 64))
  (category (string-ascii 32))
  (initial-quality uint))
  (let
    (
      (product-id (var-get next-product-id))
      (retailer tx-sender)
      (current-block block-height)
    )
    (asserts! (> (len name) u0) err-invalid-input)
    (asserts! (> (len category) u0) err-invalid-input)
    (asserts! (<= initial-quality u100) err-invalid-input)

    (map-set products
      { product-id: product-id }
      {
        retailer: retailer,
        name: name,
        category: category,
        creation-block: current-block,
        current-stage: stage-production,
        quality-score: initial-quality,
        circular-count: u0,
        active: true
      })

    (map-set product-history
      { product-id: product-id, stage: stage-production }
      {
        timestamp: current-block,
        quality-assessment: initial-quality,
        notes: "Product created",
        assessor: retailer
      })

    (map-set stage-transitions
      { product-id: product-id }
      { stages-completed: (list stage-production) })

    (var-set next-product-id (+ product-id u1))
    (ok product-id)))

;; Update product stage
(define-public (update-stage
  (product-id uint)
  (new-stage uint)
  (quality-assessment uint)
  (notes (string-ascii 128)))
  (let
    (
      (product-data (unwrap! (map-get? products { product-id: product-id }) err-not-found))
      (current-block block-height)
      (current-transitions (unwrap! (map-get? stage-transitions { product-id: product-id }) err-not-found))
    )
    (asserts! (get active product-data) err-invalid-input)
    (asserts! (<= quality-assessment u100) err-invalid-input)
    (asserts! (> new-stage (get current-stage product-data)) err-invalid-input)
    (asserts! (<= new-stage stage-disposal) err-invalid-input)

    ;; Update product data
    (map-set products
      { product-id: product-id }
      (merge product-data
        {
          current-stage: new-stage,
          quality-score: quality-assessment,
          circular-count: (if (is-eq new-stage stage-reuse)
                            (+ (get circular-count product-data) u1)
                            (get circular-count product-data))
        }))

    ;; Record stage history
    (map-set product-history
      { product-id: product-id, stage: new-stage }
      {
        timestamp: current-block,
        quality-assessment: quality-assessment,
        notes: notes,
        assessor: tx-sender
      })

    ;; Update stage transitions
    (map-set stage-transitions
      { product-id: product-id }
      { stages-completed: (unwrap-panic (as-max-len?
          (append (get stages-completed current-transitions) new-stage) u20)) })

    (ok true)))

;; Assess product quality
(define-public (assess-quality
  (product-id uint)
  (quality-score uint)
  (notes (string-ascii 128)))
  (let
    (
      (product-data (unwrap! (map-get? products { product-id: product-id }) err-not-found))
      (current-block block-height)
    )
    (asserts! (get active product-data) err-invalid-input)
    (asserts! (<= quality-score u100) err-invalid-input)

    (map-set products
      { product-id: product-id }
      (merge product-data { quality-score: quality-score }))

    (map-set product-history
      { product-id: product-id, stage: (get current-stage product-data) }
      {
        timestamp: current-block,
        quality-assessment: quality-score,
        notes: notes,
        assessor: tx-sender
      })

    (ok true)))

;; Mark product as inactive
(define-public (deactivate-product (product-id uint))
  (let
    (
      (product-data (unwrap! (map-get? products { product-id: product-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get retailer product-data)) err-unauthorized)

    (map-set products
      { product-id: product-id }
      (merge product-data { active: false }))

    (ok true)))

;; Read-only Functions

;; Get product information
(define-read-only (get-product (product-id uint))
  (map-get? products { product-id: product-id }))

;; Get product history for specific stage
(define-read-only (get-product-history (product-id uint) (stage uint))
  (map-get? product-history { product-id: product-id, stage: stage }))

;; Get all stages completed for a product
(define-read-only (get-stage-transitions (product-id uint))
  (map-get? stage-transitions { product-id: product-id }))

;; Get current product stage
(define-read-only (get-current-stage (product-id uint))
  (match (map-get? products { product-id: product-id })
    product-data (some (get current-stage product-data))
    none))

;; Get product quality score
(define-read-only (get-quality-score (product-id uint))
  (match (map-get? products { product-id: product-id })
    product-data (some (get quality-score product-data))
    none))

;; Get circular count (reuse cycles)
(define-read-only (get-circular-count (product-id uint))
  (match (map-get? products { product-id: product-id })
    product-data (some (get circular-count product-data))
    none))

;; Check if product is active
(define-read-only (is-active (product-id uint))
  (match (map-get? products { product-id: product-id })
    product-data (get active product-data)
    false))
