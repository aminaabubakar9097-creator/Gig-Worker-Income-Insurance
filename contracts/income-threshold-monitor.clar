;; Income Threshold Monitor Contract
;; Automated tracking of worker earnings vs. historical averages
;; Detects when income falls below predetermined thresholds

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_WORKER (err u402))
(define-constant ERR_INVALID_AMOUNT (err u403))
(define-constant ERR_WORKER_NOT_FOUND (err u404))
(define-constant ERR_INSUFFICIENT_HISTORY (err u405))
(define-constant ERR_THRESHOLD_NOT_SET (err u406))
(define-constant MIN_HISTORY_PERIODS u4) ;; Minimum 4 periods for baseline
(define-constant DEFAULT_THRESHOLD_PERCENTAGE u80) ;; 80% of historical average
(define-constant COVERAGE_TRIGGER_PERIODS u2) ;; Consecutive periods below threshold

;; Data Variables
(define-data-var total-workers uint u0)
(define-data-var current-period uint u1)
(define-data-var monitoring-active bool true)
(define-data-var global-baseline uint u0)

;; Data Maps
;; Worker registration and basic info
(define-map workers
  { worker-id: uint }
  {
    address: principal,
    platform-ids: (list 10 uint),
    registration-period: uint,
    is-active: bool,
    total-periods-tracked: uint
  }
)

;; Worker earnings by period
(define-map worker-earnings
  { worker-id: uint, period: uint }
  {
    total-earnings: uint,
    platform-breakdown: (list 10 { platform-id: uint, earnings: uint }),
    recorded-at: uint,
    verified: bool
  }
)

;; Historical averages and thresholds
(define-map worker-baselines
  { worker-id: uint }
  {
    historical-average: uint,
    custom-threshold: uint,
    threshold-percentage: uint,
    last-calculated: uint,
    periods-included: uint
  }
)

;; Threshold breach tracking
(define-map threshold-breaches
  { worker-id: uint, breach-id: uint }
  {
    period-start: uint,
    period-end: uint,
    severity: (string-ascii 16), ;; "minor", "moderate", "severe"
    earnings-drop: uint,
    coverage-triggered: bool,
    resolved: bool
  }
)

;; Coverage trigger events
(define-map coverage-triggers
  { worker-id: uint, trigger-id: uint }
  {
    trigger-period: uint,
    earnings-deficit: uint,
    payout-amount: uint,
    trigger-reason: (string-ascii 64),
    processed: bool
  }
)

;; Period statistics
(define-map period-stats
  { period: uint }
  {
    total-workers: uint,
    average-earnings: uint,
    workers-below-threshold: uint,
    total-breaches: uint,
    coverage-events: uint
  }
)

;; Worker status tracking
(define-map worker-status
  { worker-id: uint }
  {
    current-streak-below: uint,
    consecutive-periods-below: uint,
    last-above-threshold: uint,
    total-breaches: uint,
    coverage-active: bool
  }
)

;; Authorization for data reporters
(define-map authorized-reporters
  { reporter: principal }
  { is-authorized: bool, authorized-at: uint }
)

;; Public Functions

;; Register a new worker for monitoring
(define-public (register-worker (worker-address principal) (platform-ids (list 10 uint)))
  (let
    (
      (worker-id (+ (var-get total-workers) u1))
      (current-period-val (var-get current-period))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> (len platform-ids) u0) ERR_INVALID_WORKER)
    
    ;; Register worker
    (map-set workers
      { worker-id: worker-id }
      {
        address: worker-address,
        platform-ids: platform-ids,
        registration-period: current-period-val,
        is-active: true,
        total-periods-tracked: u0
      }
    )
    
    ;; Initialize worker status
    (map-set worker-status
      { worker-id: worker-id }
      {
        current-streak-below: u0,
        consecutive-periods-below: u0,
        last-above-threshold: u0,
        total-breaches: u0,
        coverage-active: false
      }
    )
    
    ;; Initialize baseline with default threshold
    (map-set worker-baselines
      { worker-id: worker-id }
      {
        historical-average: u0,
        custom-threshold: u0,
        threshold-percentage: DEFAULT_THRESHOLD_PERCENTAGE,
        last-calculated: current-period-val,
        periods-included: u0
      }
    )
    
    ;; Update counter
    (var-set total-workers worker-id)
    
    (ok worker-id)
  )
)

;; Record worker earnings for a period
(define-public (record-earnings 
  (worker-id uint) 
  (period uint) 
  (total-earnings uint) 
  (platform-breakdown (list 10 { platform-id: uint, earnings: uint }))
)
  (let
    (
      (worker-info (unwrap! (map-get? workers { worker-id: worker-id }) ERR_WORKER_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (is-authorized-reporter tx-sender) ERR_UNAUTHORIZED)
    (asserts! (> total-earnings u0) ERR_INVALID_AMOUNT)
    (asserts! (get is-active worker-info) ERR_WORKER_NOT_FOUND)
    
    ;; Record earnings
    (map-set worker-earnings
      { worker-id: worker-id, period: period }
      {
        total-earnings: total-earnings,
        platform-breakdown: platform-breakdown,
        recorded-at: current-block,
        verified: true
      }
    )
    
    ;; Update worker's tracked periods count
    (map-set workers
      { worker-id: worker-id }
      (merge worker-info { total-periods-tracked: (+ (get total-periods-tracked worker-info) u1) })
    )
    
    ;; Check and update baseline if enough history
    (match (update-worker-baseline worker-id)
      success-value true
      error-value true
    )
    
    ;; Check for threshold breaches
    (match (check-threshold-breach worker-id period total-earnings)
      success-value true
      error-value true
    )
    
    (ok true)
  )
)

;; Update worker baseline calculation
(define-public (update-worker-baseline (worker-id uint))
  (let
    (
      (worker-info (unwrap! (map-get? workers { worker-id: worker-id }) ERR_WORKER_NOT_FOUND))
      (periods-tracked (get total-periods-tracked worker-info))
    )
    (asserts! (is-authorized-reporter tx-sender) ERR_UNAUTHORIZED)
    (asserts! (>= periods-tracked MIN_HISTORY_PERIODS) ERR_INSUFFICIENT_HISTORY)
    
    (let
      (
        (historical-avg (calculate-historical-average worker-id periods-tracked))
        (current-baseline (unwrap! (map-get? worker-baselines { worker-id: worker-id }) ERR_WORKER_NOT_FOUND))
        (threshold-pct (get threshold-percentage current-baseline))
        (custom-threshold (/ (* historical-avg threshold-pct) u100))
      )
      
      ;; Update baseline
      (map-set worker-baselines
        { worker-id: worker-id }
        {
          historical-average: historical-avg,
          custom-threshold: custom-threshold,
          threshold-percentage: threshold-pct,
          last-calculated: (var-get current-period),
          periods-included: periods-tracked
        }
      )
      
      (ok historical-avg)
    )
  )
)

;; Set custom threshold percentage for a worker
(define-public (set-threshold-percentage (worker-id uint) (threshold-pct uint))
  (let
    (
      (current-baseline (unwrap! (map-get? worker-baselines { worker-id: worker-id }) ERR_WORKER_NOT_FOUND))
      (historical-avg (get historical-average current-baseline))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (and (>= threshold-pct u50) (<= threshold-pct u95)) ERR_INVALID_AMOUNT)
    
    (let
      (
        (new-threshold (/ (* historical-avg threshold-pct) u100))
      )
      
      (map-set worker-baselines
        { worker-id: worker-id }
        (merge current-baseline 
          {
            custom-threshold: new-threshold,
            threshold-percentage: threshold-pct,
            last-calculated: (var-get current-period)
          }
        )
      )
      
      (ok new-threshold)
    )
  )
)

;; Record threshold breach
(define-public (record-breach 
  (worker-id uint) 
  (breach-id uint) 
  (period-start uint) 
  (period-end uint) 
  (earnings-drop uint)
  (severity (string-ascii 16))
)
  (begin
    (asserts! (is-authorized-reporter tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? workers { worker-id: worker-id })) ERR_WORKER_NOT_FOUND)
    
    (map-set threshold-breaches
      { worker-id: worker-id, breach-id: breach-id }
      {
        period-start: period-start,
        period-end: period-end,
        severity: severity,
        earnings-drop: earnings-drop,
        coverage-triggered: false,
        resolved: false
      }
    )
    
    (ok true)
  )
)

;; Advance to next monitoring period
(define-public (advance-period)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (var-set current-period (+ (var-get current-period) u1))
    (ok (var-get current-period))
  )
)

;; Authorize earnings reporter
(define-public (authorize-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set authorized-reporters
      { reporter: reporter }
      { is-authorized: true, authorized-at: stacks-block-height }
    )
    
    (ok true)
  )
)

;; Read-Only Functions

;; Get worker information
(define-read-only (get-worker-info (worker-id uint))
  (map-get? workers { worker-id: worker-id })
)

;; Get worker earnings for specific period
(define-read-only (get-worker-earnings (worker-id uint) (period uint))
  (map-get? worker-earnings { worker-id: worker-id, period: period })
)

;; Get worker baseline and threshold
(define-read-only (get-worker-baseline (worker-id uint))
  (map-get? worker-baselines { worker-id: worker-id })
)

;; Get worker current status
(define-read-only (get-worker-status (worker-id uint))
  (map-get? worker-status { worker-id: worker-id })
)

;; Check if worker needs coverage trigger
(define-read-only (should-trigger-coverage (worker-id uint))
  (match (map-get? worker-status { worker-id: worker-id })
    status-data
    (let
      (
        (consecutive-below (get consecutive-periods-below status-data))
        (coverage-active (get coverage-active status-data))
      )
      (and
        (>= consecutive-below COVERAGE_TRIGGER_PERIODS)
        (not coverage-active)
      )
    )
    false
  )
)

;; Get threshold breach details
(define-read-only (get-threshold-breach (worker-id uint) (breach-id uint))
  (map-get? threshold-breaches { worker-id: worker-id, breach-id: breach-id })
)

;; Get coverage trigger details
(define-read-only (get-coverage-trigger (worker-id uint) (trigger-id uint))
  (map-get? coverage-triggers { worker-id: worker-id, trigger-id: trigger-id })
)

;; Get current monitoring period
(define-read-only (get-current-period)
  (var-get current-period)
)

;; Get total workers count
(define-read-only (get-total-workers)
  (var-get total-workers)
)

;; Check if monitoring is active
(define-read-only (is-monitoring-active)
  (var-get monitoring-active)
)

;; Get period statistics
(define-read-only (get-period-stats (period uint))
  (map-get? period-stats { period: period })
)

;; Private Functions

;; Calculate historical average for worker
(define-private (calculate-historical-average (worker-id uint) (periods-count uint))
  (let
    (
      (current-period-val (var-get current-period))
      (start-period (if (> current-period-val periods-count) 
                     (- current-period-val periods-count) 
                     u1))
    )
    ;; Simplified calculation - would need iteration in real implementation
    ;; For now, return a calculated average based on recent periods
    (calculate-average-earnings worker-id start-period current-period-val)
  )
)

;; Calculate average earnings over period range
(define-private (calculate-average-earnings (worker-id uint) (start-period uint) (end-period uint))
  ;; Simplified implementation - in real contract would iterate through periods
  ;; Returns mock average for demonstration
  u1000
)

;; Check threshold breach for worker
(define-private (check-threshold-breach (worker-id uint) (period uint) (earnings uint))
  (match (map-get? worker-baselines { worker-id: worker-id })
    baseline-data
    (let
      (
        (threshold (get custom-threshold baseline-data))
      )
      (match (map-get? worker-status { worker-id: worker-id })
        current-status
        (if (< earnings threshold)
          ;; Below threshold
          (let
            (
              (new-consecutive (+ (get consecutive-periods-below current-status) u1))
            )
            (map-set worker-status
              { worker-id: worker-id }
              (merge current-status 
                {
                  consecutive-periods-below: new-consecutive,
                  current-streak-below: (+ (get current-streak-below current-status) u1)
                }
              )
            )
            (ok true)
          )
          ;; Above threshold - reset streak
          (begin
            (map-set worker-status
              { worker-id: worker-id }
              (merge current-status 
                {
                  consecutive-periods-below: u0,
                  current-streak-below: u0,
                  last-above-threshold: period
                }
              )
            )
            (ok true)
          )
        )
        (err ERR_WORKER_NOT_FOUND)
      )
    )
    (err ERR_THRESHOLD_NOT_SET)
  )
)

;; Check if reporter is authorized
(define-private (is-authorized-reporter (reporter principal))
  (default-to false
    (get is-authorized (map-get? authorized-reporters { reporter: reporter }))
  )
)

