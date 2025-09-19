;; Market Condition Adjuster Contract
;; Dynamic coverage adjustment based on local economic indicators
;; and market conditions to ensure fair and accurate protection

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_REGION (err u402))
(define-constant ERR_INVALID_INDICATOR (err u403))
(define-constant ERR_REGION_NOT_FOUND (err u404))
(define-constant ERR_INVALID_ADJUSTMENT (err u405))
(define-constant ERR_INDICATOR_NOT_FOUND (err u406))
(define-constant BASE_ADJUSTMENT u100) ;; 100% baseline adjustment
(define-constant MAX_ADJUSTMENT u200) ;; Maximum 200% adjustment
(define-constant MIN_ADJUSTMENT u50) ;; Minimum 50% adjustment
(define-constant VOLATILITY_THRESHOLD u15) ;; 15% volatility threshold

;; Data Variables
(define-data-var total-regions uint u0)
(define-data-var total-indicators uint u0)
(define-data-var global-adjustment uint BASE_ADJUSTMENT)
(define-data-var last-global-update uint u0)
(define-data-var adjustment-active bool true)

;; Data Maps
;; Geographic regions for market analysis
(define-map regions
  { region-id: uint }
  {
    name: (string-ascii 64),
    country-code: (string-ascii 8),
    population: uint,
    economic-tier: (string-ascii 16), ;; "developed", "emerging", "frontier"
    is-active: bool
  }
)

;; Economic indicators by region
(define-map economic-indicators
  { region-id: uint, indicator-type: (string-ascii 32) }
  {
    current-value: uint,
    baseline-value: uint,
    variance: uint,
    last-updated: uint,
    data-source: (string-ascii 64),
    reliability-score: uint ;; 0-100
  }
)

;; Market conditions tracking
(define-map market-conditions
  { region-id: uint, period: uint }
  {
    unemployment-rate: uint,
    gig-demand-index: uint,
    cost-of-living: uint,
    seasonal-factor: uint,
    market-volatility: uint,
    recorded-at: uint
  }
)

;; Coverage adjustments by region
(define-map coverage-adjustments
  { region-id: uint }
  {
    base-multiplier: uint,
    seasonal-multiplier: uint,
    volatility-multiplier: uint,
    final-adjustment: uint,
    last-calculated: uint,
    effective-until: uint
  }
)

;; Historical adjustment records
(define-map adjustment-history
  { region-id: uint, period: uint }
  {
    adjustment-factor: uint,
    primary-reason: (string-ascii 64),
    contributing-factors: (list 5 (string-ascii 32)),
    applied-at: uint,
    duration: uint
  }
)

;; Seasonal adjustment patterns
(define-map seasonal-patterns
  { region-id: uint, month: uint }
  {
    demand-multiplier: uint,
    supply-multiplier: uint,
    historical-variance: uint,
    confidence-level: uint,
    years-of-data: uint
  }
)

;; Volatility tracking
(define-map volatility-metrics
  { region-id: uint }
  {
    short-term-volatility: uint,
    medium-term-volatility: uint,
    long-term-volatility: uint,
    volatility-trend: (string-ascii 16), ;; "increasing", "decreasing", "stable"
    last-spike: uint
  }
)

;; Authorized data providers
(define-map authorized-providers
  { provider: principal }
  {
    is-authorized: bool,
    provider-type: (string-ascii 32), ;; "economic", "weather", "platform"
    authorized-at: uint,
    reliability-rating: uint
  }
)

;; Public Functions

;; Register a new region for market analysis
(define-public (register-region 
  (name (string-ascii 64)) 
  (country-code (string-ascii 8)) 
  (population uint) 
  (economic-tier (string-ascii 16))
)
  (let
    (
      (region-id (+ (var-get total-regions) u1))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> (len name) u0) ERR_INVALID_REGION)
    
    ;; Register region
    (map-set regions
      { region-id: region-id }
      {
        name: name,
        country-code: country-code,
        population: population,
        economic-tier: economic-tier,
        is-active: true
      }
    )
    
    ;; Initialize coverage adjustment
    (map-set coverage-adjustments
      { region-id: region-id }
      {
        base-multiplier: BASE_ADJUSTMENT,
        seasonal-multiplier: BASE_ADJUSTMENT,
        volatility-multiplier: BASE_ADJUSTMENT,
        final-adjustment: BASE_ADJUSTMENT,
        last-calculated: stacks-block-height,
        effective-until: (+ stacks-block-height u1000)
      }
    )
    
    ;; Initialize volatility metrics
    (map-set volatility-metrics
      { region-id: region-id }
      {
        short-term-volatility: u0,
        medium-term-volatility: u0,
        long-term-volatility: u0,
        volatility-trend: "stable",
        last-spike: u0
      }
    )
    
    ;; Update counter
    (var-set total-regions region-id)
    
    (ok region-id)
  )
)

;; Update economic indicator for a region
(define-public (update-economic-indicator 
  (region-id uint) 
  (indicator-type (string-ascii 32)) 
  (current-value uint) 
  (baseline-value uint)
  (data-source (string-ascii 64))
  (reliability-score uint)
)
  (let
    (
      (variance (if (> current-value baseline-value)
                  (- current-value baseline-value)
                  (- baseline-value current-value)))
    )
    (asserts! (is-authorized-provider tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? regions { region-id: region-id })) ERR_REGION_NOT_FOUND)
    (asserts! (<= reliability-score u100) ERR_INVALID_INDICATOR)
    
    ;; Update indicator
    (map-set economic-indicators
      { region-id: region-id, indicator-type: indicator-type }
      {
        current-value: current-value,
        baseline-value: baseline-value,
        variance: variance,
        last-updated: stacks-block-height,
        data-source: data-source,
        reliability-score: reliability-score
      }
    )
    
    ;; Trigger adjustment recalculation
    (try! (recalculate-regional-adjustment region-id))
    
    (ok true)
  )
)

;; Update market conditions for a region
(define-public (update-market-conditions 
  (region-id uint) 
  (period uint)
  (unemployment-rate uint)
  (gig-demand-index uint)
  (cost-of-living uint)
  (seasonal-factor uint)
  (market-volatility uint)
)
  (begin
    (asserts! (is-authorized-provider tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? regions { region-id: region-id })) ERR_REGION_NOT_FOUND)
    
    ;; Update market conditions
    (map-set market-conditions
      { region-id: region-id, period: period }
      {
        unemployment-rate: unemployment-rate,
        gig-demand-index: gig-demand-index,
        cost-of-living: cost-of-living,
        seasonal-factor: seasonal-factor,
        market-volatility: market-volatility,
        recorded-at: stacks-block-height
      }
    )
    
    ;; Update volatility metrics
    (try! (update-volatility-metrics region-id market-volatility))
    
    ;; Trigger adjustment recalculation
    (try! (recalculate-regional-adjustment region-id))
    
    (ok true)
  )
)

;; Recalculate regional adjustment factors
(define-public (recalculate-regional-adjustment (region-id uint))
  (let
    (
      (region-info (unwrap! (map-get? regions { region-id: region-id }) ERR_REGION_NOT_FOUND))
      (current-adjustment (unwrap! (map-get? coverage-adjustments { region-id: region-id }) ERR_REGION_NOT_FOUND))
    )
    (asserts! (is-authorized-provider tx-sender) ERR_UNAUTHORIZED)
    
    (let
      (
        (base-mult (calculate-base-multiplier region-id))
        (seasonal-mult (calculate-seasonal-multiplier region-id))
        (volatility-mult (calculate-volatility-multiplier region-id))
        (final-adj (calculate-final-adjustment base-mult seasonal-mult volatility-mult))
      )
      
      ;; Ensure adjustment is within bounds
      (let
        (
          (bounded-adjustment (min (max final-adj MIN_ADJUSTMENT) MAX_ADJUSTMENT))
        )
        
        ;; Update adjustment
        (map-set coverage-adjustments
          { region-id: region-id }
          {
            base-multiplier: base-mult,
            seasonal-multiplier: seasonal-mult,
            volatility-multiplier: volatility-mult,
            final-adjustment: bounded-adjustment,
            last-calculated: stacks-block-height,
            effective-until: (+ stacks-block-height u500)
          }
        )
        
        ;; Record in history
        (map-set adjustment-history
          { region-id: region-id, period: stacks-block-height }
          {
            adjustment-factor: bounded-adjustment,
            primary-reason: "market-conditions-update",
            contributing-factors: (list "unemployment" "demand" "volatility"),
            applied-at: stacks-block-height,
            duration: u500
          }
        )
        
        (ok bounded-adjustment)
      )
    )
  )
)

;; Update seasonal patterns
(define-public (update-seasonal-pattern 
  (region-id uint) 
  (month uint) 
  (demand-multiplier uint) 
  (supply-multiplier uint)
  (historical-variance uint)
  (confidence-level uint)
  (years-of-data uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-some (map-get? regions { region-id: region-id })) ERR_REGION_NOT_FOUND)
    (asserts! (and (>= month u1) (<= month u12)) ERR_INVALID_INDICATOR)
    
    (map-set seasonal-patterns
      { region-id: region-id, month: month }
      {
        demand-multiplier: demand-multiplier,
        supply-multiplier: supply-multiplier,
        historical-variance: historical-variance,
        confidence-level: confidence-level,
        years-of-data: years-of-data
      }
    )
    
    (ok true)
  )
)

;; Authorize data provider
(define-public (authorize-provider 
  (provider principal) 
  (provider-type (string-ascii 32)) 
  (reliability-rating uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= reliability-rating u100) ERR_INVALID_INDICATOR)
    
    (map-set authorized-providers
      { provider: provider }
      {
        is-authorized: true,
        provider-type: provider-type,
        authorized-at: stacks-block-height,
        reliability-rating: reliability-rating
      }
    )
    
    (ok true)
  )
)

;; Update global adjustment factor
(define-public (update-global-adjustment (new-adjustment uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (and (>= new-adjustment MIN_ADJUSTMENT) (<= new-adjustment MAX_ADJUSTMENT)) ERR_INVALID_ADJUSTMENT)
    
    (var-set global-adjustment new-adjustment)
    (var-set last-global-update stacks-block-height)
    
    (ok new-adjustment)
  )
)

;; Read-Only Functions

;; Get region information
(define-read-only (get-region-info (region-id uint))
  (map-get? regions { region-id: region-id })
)

;; Get economic indicator
(define-read-only (get-economic-indicator (region-id uint) (indicator-type (string-ascii 32)))
  (map-get? economic-indicators { region-id: region-id, indicator-type: indicator-type })
)

;; Get market conditions
(define-read-only (get-market-conditions (region-id uint) (period uint))
  (map-get? market-conditions { region-id: region-id, period: period })
)

;; Get coverage adjustment for region
(define-read-only (get-coverage-adjustment (region-id uint))
  (map-get? coverage-adjustments { region-id: region-id })
)

;; Get current adjustment factor for region
(define-read-only (get-current-adjustment-factor (region-id uint))
  (match (map-get? coverage-adjustments { region-id: region-id })
    adjustment-data
    (let
      (
        (effective-until (get effective-until adjustment-data))
        (final-adjustment (get final-adjustment adjustment-data))
      )
      ;; Check if adjustment is still valid
      (if (> effective-until stacks-block-height)
        (some final-adjustment)
        (some BASE_ADJUSTMENT) ;; Return base if expired
      )
    )
    none
  )
)

;; Get volatility metrics
(define-read-only (get-volatility-metrics (region-id uint))
  (map-get? volatility-metrics { region-id: region-id })
)

;; Get seasonal pattern
(define-read-only (get-seasonal-pattern (region-id uint) (month uint))
  (map-get? seasonal-patterns { region-id: region-id, month: month })
)

;; Get adjustment history
(define-read-only (get-adjustment-history (region-id uint) (period uint))
  (map-get? adjustment-history { region-id: region-id, period: period })
)

;; Get global adjustment
(define-read-only (get-global-adjustment)
  (var-get global-adjustment)
)

;; Get total regions
(define-read-only (get-total-regions)
  (var-get total-regions)
)

;; Check if adjustment is active
(define-read-only (is-adjustment-active)
  (var-get adjustment-active)
)

;; Private Functions

;; Calculate base multiplier from economic indicators
(define-private (calculate-base-multiplier (region-id uint))
  ;; Simplified calculation based on unemployment and economic tier
  ;; In real implementation, would analyze multiple economic indicators
  (let
    (
      (unemployment-indicator (map-get? economic-indicators { region-id: region-id, indicator-type: "unemployment" }))
    )
    (match unemployment-indicator
      indicator-data
      (let
        (
          (current-unemploy (get current-value indicator-data))
          (baseline-unemploy (get baseline-value indicator-data))
        )
        ;; Higher unemployment = higher adjustment (more coverage needed)
        (if (> current-unemploy baseline-unemploy)
          (+ BASE_ADJUSTMENT (/ (* (- current-unemploy baseline-unemploy) u20) u100))
          BASE_ADJUSTMENT
        )
      )
      BASE_ADJUSTMENT
    )
  )
)

;; Calculate seasonal multiplier
(define-private (calculate-seasonal-multiplier (region-id uint))
  ;; Simplified seasonal calculation
  ;; In real implementation, would use current month and seasonal patterns
  BASE_ADJUSTMENT
)

;; Calculate volatility multiplier
(define-private (calculate-volatility-multiplier (region-id uint))
  (match (map-get? volatility-metrics { region-id: region-id })
    volatility-data
    (let
      (
        (short-term-vol (get short-term-volatility volatility-data))
      )
      ;; Higher volatility = higher adjustment
      (if (> short-term-vol VOLATILITY_THRESHOLD)
        (+ BASE_ADJUSTMENT (/ (* (- short-term-vol VOLATILITY_THRESHOLD) u10) u100))
        BASE_ADJUSTMENT
      )
    )
    BASE_ADJUSTMENT
  )
)

;; Calculate final adjustment from multipliers
(define-private (calculate-final-adjustment (base uint) (seasonal uint) (volatility uint))
  ;; Weighted combination of factors
  (/ (+ (* base u50) (* seasonal u30) (* volatility u20)) u100)
)

;; Update volatility metrics
(define-private (update-volatility-metrics (region-id uint) (current-volatility uint))
  (let
    (
      (current-metrics (unwrap! (map-get? volatility-metrics { region-id: region-id }) ERR_REGION_NOT_FOUND))
      (trend (if (> current-volatility (get short-term-volatility current-metrics))
               "increasing"
               (if (< current-volatility (get short-term-volatility current-metrics)) "decreasing" "stable")))
    )
    
    (map-set volatility-metrics
      { region-id: region-id }
      (merge current-metrics
        {
          short-term-volatility: current-volatility,
          volatility-trend: trend,
          last-spike: (if (> current-volatility (* (get short-term-volatility current-metrics) u2)) 
                       stacks-block-height
                       (get last-spike current-metrics))
        }
      )
    )
    
    (ok true)
  )
)

;; Check if provider is authorized
(define-private (is-authorized-provider (provider principal))
  (default-to false
    (get is-authorized (map-get? authorized-providers { provider: provider }))
  )
)

;; Helper function for min
(define-private (min (a uint) (b uint))
  (if (<= a b) a b)
)

;; Helper function for max
(define-private (max (a uint) (b uint))
  (if (>= a b) a b)
)

