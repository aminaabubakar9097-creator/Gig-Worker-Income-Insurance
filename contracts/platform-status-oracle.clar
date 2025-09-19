;; Platform Status Oracle Contract
;; Monitors gig platform uptime and demand fluctuations to trigger coverage
;; when platforms become unavailable or experience significant demand drops

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_PLATFORM (err u402))
(define-constant ERR_INVALID_STATUS (err u403))
(define-constant ERR_PLATFORM_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u405))
(define-constant MIN_UPTIME_THRESHOLD u95) ;; 95% uptime threshold
(define-constant DEMAND_DROP_THRESHOLD u20) ;; 20% demand drop threshold

;; Data Variables
(define-data-var total-platforms uint u0)
(define-data-var last-update-block uint u0)
(define-data-var emergency-mode bool false)

;; Data Maps
;; Platform registration and basic info
(define-map platforms
  { platform-id: uint }
  {
    name: (string-ascii 64),
    owner: principal,
    is-active: bool,
    registration-block: uint
  }
)

;; Platform status tracking
(define-map platform-status
  { platform-id: uint }
  {
    current-uptime: uint, ;; percentage (0-100)
    last-status-update: uint,
    consecutive-downtime: uint,
    total-downtime-events: uint,
    is-operational: bool
  }
)

;; Demand tracking for platforms
(define-map platform-demand
  { platform-id: uint }
  {
    current-demand: uint,
    baseline-demand: uint,
    demand-variance: uint,
    last-demand-update: uint,
    demand-trend: (string-ascii 16) ;; "increasing", "decreasing", "stable"
  }
)

;; Historical uptime records
(define-map uptime-history
  { platform-id: uint, period: uint }
  {
    uptime-percentage: uint,
    recorded-at: uint,
    downtime-duration: uint
  }
)

;; Platform outage events
(define-map outage-events
  { platform-id: uint, event-id: uint }
  {
    start-time: uint,
    end-time: uint,
    severity: (string-ascii 16), ;; "minor", "major", "critical"
    affected-users: uint,
    cause: (string-ascii 128)
  }
)

;; Authorization for oracle operators
(define-map authorized-operators
  { operator: principal }
  { is-authorized: bool, authorized-at: uint }
)

;; Public Functions

;; Register a new platform for monitoring
(define-public (register-platform (name (string-ascii 64)) (owner principal))
  (let
    (
      (platform-id (+ (var-get total-platforms) u1))
      (current-block stacks-block-height)
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> (len name) u0) ERR_INVALID_PLATFORM)
    
    ;; Register platform
    (map-set platforms
      { platform-id: platform-id }
      {
        name: name,
        owner: owner,
        is-active: true,
        registration-block: current-block
      }
    )
    
    ;; Initialize platform status
    (map-set platform-status
      { platform-id: platform-id }
      {
        current-uptime: u100,
        last-status-update: current-block,
        consecutive-downtime: u0,
        total-downtime-events: u0,
        is-operational: true
      }
    )
    
    ;; Initialize demand tracking
    (map-set platform-demand
      { platform-id: platform-id }
      {
        current-demand: u100,
        baseline-demand: u100,
        demand-variance: u0,
        last-demand-update: current-block,
        demand-trend: "stable"
      }
    )
    
    ;; Update counter
    (var-set total-platforms platform-id)
    
    (ok platform-id)
  )
)

;; Update platform uptime status
(define-public (update-platform-status (platform-id uint) (uptime uint) (is-operational bool))
  (let
    (
      (current-status (unwrap! (map-get? platform-status { platform-id: platform-id }) ERR_PLATFORM_NOT_FOUND))
      (current-block stacks-block-height)
    )
    (asserts! (is-authorized-operator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (<= uptime u100) ERR_INVALID_STATUS)
    (asserts! (is-some (map-get? platforms { platform-id: platform-id })) ERR_PLATFORM_NOT_FOUND)
    
    ;; Calculate consecutive downtime
    (let
      (
        (new-consecutive-downtime
          (if (< uptime MIN_UPTIME_THRESHOLD)
            (+ (get consecutive-downtime current-status) u1)
            u0
          )
        )
        (new-total-events
          (if (and (>= (get consecutive-downtime current-status) u1) (>= uptime MIN_UPTIME_THRESHOLD))
            (+ (get total-downtime-events current-status) u1)
            (get total-downtime-events current-status)
          )
        )
      )
      
      ;; Update platform status
      (map-set platform-status
        { platform-id: platform-id }
        {
          current-uptime: uptime,
          last-status-update: current-block,
          consecutive-downtime: new-consecutive-downtime,
          total-downtime-events: new-total-events,
          is-operational: is-operational
        }
      )
      
      ;; Record in history
      (map-set uptime-history
        { platform-id: platform-id, period: current-block }
        {
          uptime-percentage: uptime,
          recorded-at: current-block,
          downtime-duration: (if (< uptime u100) (- u100 uptime) u0)
        }
      )
      
      ;; Update last update block
      (var-set last-update-block current-block)
      
      (ok true)
    )
  )
)

;; Update platform demand metrics
(define-public (update-demand-metrics (platform-id uint) (current-demand uint) (baseline-demand uint))
  (let
    (
      (current-block stacks-block-height)
      (demand-variance (if (> current-demand baseline-demand)
                        (- current-demand baseline-demand)
                        (- baseline-demand current-demand)))
      (trend (if (> current-demand baseline-demand)
               "increasing"
               (if (< current-demand baseline-demand) "decreasing" "stable")))
    )
    (asserts! (is-authorized-operator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? platforms { platform-id: platform-id })) ERR_PLATFORM_NOT_FOUND)
    
    (map-set platform-demand
      { platform-id: platform-id }
      {
        current-demand: current-demand,
        baseline-demand: baseline-demand,
        demand-variance: demand-variance,
        last-demand-update: current-block,
        demand-trend: trend
      }
    )
    
    (ok true)
  )
)

;; Record platform outage event
(define-public (record-outage-event 
  (platform-id uint) 
  (event-id uint) 
  (start-time uint) 
  (end-time uint)
  (severity (string-ascii 16))
  (affected-users uint)
  (cause (string-ascii 128))
)
  (begin
    (asserts! (is-authorized-operator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? platforms { platform-id: platform-id })) ERR_PLATFORM_NOT_FOUND)
    (asserts! (> end-time start-time) ERR_INVALID_STATUS)
    
    (map-set outage-events
      { platform-id: platform-id, event-id: event-id }
      {
        start-time: start-time,
        end-time: end-time,
        severity: severity,
        affected-users: affected-users,
        cause: cause
      }
    )
    
    (ok true)
  )
)

;; Authorize oracle operator
(define-public (authorize-operator (operator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set authorized-operators
      { operator: operator }
      { is-authorized: true, authorized-at: stacks-block-height }
    )
    
    (ok true)
  )
)

;; Emergency mode toggle
(define-public (toggle-emergency-mode)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (var-set emergency-mode (not (var-get emergency-mode)))
    (ok (var-get emergency-mode))
  )
)

;; Read-Only Functions

;; Get platform information
(define-read-only (get-platform-info (platform-id uint))
  (map-get? platforms { platform-id: platform-id })
)

;; Get platform current status
(define-read-only (get-platform-status (platform-id uint))
  (map-get? platform-status { platform-id: platform-id })
)

;; Get platform demand metrics
(define-read-only (get-platform-demand (platform-id uint))
  (map-get? platform-demand { platform-id: platform-id })
)

;; Check if platform requires coverage trigger
(define-read-only (should-trigger-coverage (platform-id uint))
  (match (map-get? platform-status { platform-id: platform-id })
    status-data
    (let
      (
        (uptime (get current-uptime status-data))
        (consecutive-down (get consecutive-downtime status-data))
        (is-operational (get is-operational status-data))
      )
      (match (map-get? platform-demand { platform-id: platform-id })
        demand-data
        (let
          (
            (current-demand (get current-demand demand-data))
            (baseline-demand (get baseline-demand demand-data))
            (demand-drop (if (> baseline-demand current-demand)
                          (/ (* (- baseline-demand current-demand) u100) baseline-demand)
                          u0))
          )
          ;; Trigger coverage if:
          ;; 1. Uptime below threshold OR
          ;; 2. Platform not operational OR
          ;; 3. Consecutive downtime > 2 periods OR
          ;; 4. Demand dropped significantly
          (or
            (< uptime MIN_UPTIME_THRESHOLD)
            (not is-operational)
            (> consecutive-down u2)
            (> demand-drop DEMAND_DROP_THRESHOLD)
          )
        )
        false
      )
    )
    false
  )
)

;; Get outage event details
(define-read-only (get-outage-event (platform-id uint) (event-id uint))
  (map-get? outage-events { platform-id: platform-id, event-id: event-id })
)

;; Get uptime history
(define-read-only (get-uptime-history (platform-id uint) (period uint))
  (map-get? uptime-history { platform-id: platform-id, period: period })
)

;; Get total platforms count
(define-read-only (get-total-platforms)
  (var-get total-platforms)
)

;; Check if emergency mode is active
(define-read-only (is-emergency-mode)
  (var-get emergency-mode)
)

;; Get last update block
(define-read-only (get-last-update)
  (var-get last-update-block)
)

;; Private Functions

;; Check if operator is authorized
(define-private (is-authorized-operator (operator principal))
  (default-to false
    (get is-authorized (map-get? authorized-operators { operator: operator }))
  )
)

