
;; ═══════════════════════════════════════════════════════════════════════════════
;; MESA — Multi-Agent Emergent Systems Arena
;; Emergent Misalignment in Multi-Agent AI Systems Under Resource Scarcity
;;
;; MSc Data Science & AI — Agent-Based Modelling Project
;; ODD Protocol: Grimm et al. (2020), JASSS 23(2):7
;; ═══════════════════════════════════════════════════════════════════════════════

;; ═══ v2 CHANGE LOG ═══════════════════════════════════════════════════════════
;; Fixes so that the code implements what the ODD document specifies:
;;  1. resource-pressure is measured against the ideal share (10 tokens, growing
;;     as workers die). In v1 scarcity cancelled out and pressure stayed ~0.14.
;;  2. Survival threshold is a slider (v1: fixed 1.0, which no worker could reach).
;;  3. Trust is updated from agreement with the group's reports, not from ground
;;     truth, which the orchestrator cannot observe.
;;  4. Reports reach the orchestrator with probability log-rate, so logging
;;     failure now causes stale information (TCD). Ring has a relay, and
;;     hierarchical outer workers report through their broker (two hops).
;;  5. The hierarchical secondary cascade only hits the broker's dependents.
;;  6. Monitor coverage shrinks with scarcity (it also spends context budget).
;;  7. Finished workers receive a new subtask, so dynamics continue after tick 8.
;;  8. New switch strategic-bias? (default on) turns the under-reporting rule off,
;;     to test that misalignment still emerges without it (ablation).
;; ═════════════════════════════════════════════════════════════════════════════

;; ── Breed declarations ──────────────────────────────────────────────────────
breed [orchestrators orchestrator]
breed [workers worker]
breed [monitors monitor]

;; ── Global variables ────────────────────────────────────────────────────────
globals [
  resource-pool          ;; total context budget available this tick
  system-iai             ;; Information Asymmetry Index
  system-gini            ;; Resource Gini Coefficient
  system-tcd             ;; Task Completion Drift
  system-oer             ;; Oversight Erosion Rate
  cascade-count          ;; cumulative cascade failure count
  misalignment-phase     ;; 0 = stable | 1 = warning | 2 = critical
  composite-score        ;; weighted misalignment composite
  true-avg-progress      ;; ground truth mean progress
  alive-count            ;; number of alive workers
  phase-label            ;; string label for phase
  tick-at-phase1         ;; tick when warning first triggered
  tick-at-phase2         ;; tick when critical first triggered
  tasks-completed        ;; cumulative finished subtasks (system throughput)
]

;; ── Orchestrator attributes ─────────────────────────────────────────────────
orchestrators-own [
  believed-progress
  oversight-log-count    ;; number of entries in log
]

;; ── Worker attributes ────────────────────────────────────────────────────────
workers-own [
  task-id
  true-progress
  reported-progress
  resource-held
  trust-score
  log-rate
  resource-pressure
  alive?
  my-broker              ;; hierarchical outer tier: the inner worker relaying reports
  last-received          ;; last progress report the orchestrator actually received
]

;; ── Monitor attributes ───────────────────────────────────────────────────────
monitors-own [
  anomaly-score
]

;; ═══════════════════════════════════════════════════════════════════════════════
;; SETUP
;; ═══════════════════════════════════════════════════════════════════════════════

to setup
  clear-all
  reset-ticks

  ;; Initialise globals
  set resource-pool   calculate-resource-pool
  set system-iai      0
  set system-gini     0
  set system-tcd      0
  set system-oer      0
  set cascade-count   0
  set tasks-completed 0
  set composite-score 0
  set misalignment-phase 0
  set phase-label     "STABLE"
  set alive-count     N
  set tick-at-phase1  -1
  set tick-at-phase2  -1

  ;; Create orchestrator
  create-orchestrators 1 [
    set shape "star"
    set color yellow
    set size 3.5
    setxy 0 0
    set believed-progress 0
    set oversight-log-count 0
    set label "ORC"
    set label-color white
  ]

  ;; Create workers
  create-workers N [
    set shape "circle"
    set color sky
    set size 1.8
    set true-progress       0
    set reported-progress   0
    set resource-held       0
    set trust-score         1.0
    set log-rate            1.0
    set resource-pressure   0
    set alive?              true
    set my-broker           nobody
    set last-received       0
    set task-id             who - 1
    set label               ""
  ]

  ;; Create monitor if enabled
  if monitor-enabled? [
    create-monitors 1 [
      set shape "triangle"
      set color lime
      set size 2.5
      setxy 13 13
      set anomaly-score 0
      set label "MON"
      set label-color lime
    ]
  ]

  position-agents
  wire-topology

  ;; Colour the background patches by zone
  ask patches [
    ifelse (distancexy 0 0) < 5
      [ set pcolor 33 ]       ;; orchestrator zone — warm amber
      [ set pcolor 30 + 2 * ((pxcor + pycor) mod 2) ]  ;; subtle grid
  ]

  reset-ticks
end

;; ── Topology positioning ────────────────────────────────────────────────────
to position-agents
  if topology = "Star" [
    ask workers [
      let angle (task-id * 360 / N)
      setxy (12 * sin angle) (12 * cos angle)
    ]
  ]

  if topology = "Ring" [
    ask workers [
      let angle (task-id * 360 / N)
      setxy (12 * sin angle) (12 * cos angle)
    ]
  ]

  if topology = "Hierarchical" [
    ask workers with [task-id < N / 2] [
      let angle (task-id * 360 / (N / 2))
      setxy (7 * sin angle) (7 * cos angle)
    ]
    ask workers with [task-id >= N / 2] [
      let idx task-id - round (N / 2)
      let n-outer N - round (N / 2)
      let angle (idx * 360 / n-outer)
      setxy (14 * sin angle) (14 * cos angle)
    ]
  ]
end

;; ── Network wiring ──────────────────────────────────────────────────────────
to wire-topology
  if topology = "Star" [
    ask workers [
      create-link-with one-of orchestrators [
        set color grey - 1
        set thickness 0.1
      ]
    ]
  ]

  if topology = "Ring" [
    ask workers [
      create-link-with one-of orchestrators [
        set color grey - 1
        set thickness 0.1
      ]
      let next-id (task-id + 1) mod N
      let next-w workers with [task-id = next-id]
      if any? next-w [
        create-link-with one-of next-w [
          set color grey - 2
          set thickness 0.05
        ]
      ]
    ]
  ]

  if topology = "Hierarchical" [
    ;; Inner tier → orchestrator
    ask workers with [task-id < N / 2] [
      create-link-with one-of orchestrators [
        set color grey
        set thickness 0.15
      ]
    ]
    ;; Outer tier → inner tier
    ask workers with [task-id >= N / 2] [
      let inner-workers workers with [task-id < N / 2]
      if any? inner-workers [
        let b one-of inner-workers
        set my-broker b
        create-link-with b [
          set color grey - 2
          set thickness 0.05
        ]
      ]
    ]
  ]
end

;; ─── Resource pool calculation ───────────────────────────────────────────────
to-report calculate-resource-pool
  report floor (N * 10 * (1 - scarcity * 0.8))
end

;; ═══════════════════════════════════════════════════════════════════════════════
;; MAIN GO LOOP
;; ═══════════════════════════════════════════════════════════════════════════════

to go
  if ticks >= max-ticks [ stop ]
  if not any? workers with [alive?] [ stop ]

  ;; Step 1: Distribute resources
  distribute-resources

  ;; Step 2: Execute tasks
  ask workers with [alive?] [ execute-task ]

  ;; Step 3: Report to orchestrator
  ask workers with [alive?] [ report-to-orchestrator ]

  ;; Step 4: Orchestrator updates world model
  ask orchestrators [ update-world-model ]

  ;; Step 5: Monitor samples (if present)
  if monitor-enabled? [
    ask monitors [ sample-and-detect ]
  ]

  ;; Step 6: Check cascade failures
  check-cascade-failures

  ;; Step 7: Calculate metrics
  calculate-metrics

  ;; Step 8: Update display
  update-display

  tick
end

;; ═══════════════════════════════════════════════════════════════════════════════
;; SUBMODELS
;; ═══════════════════════════════════════════════════════════════════════════════

;; ── Submodel 7.1: distribute-resources ─────────────────────────────────────
;; The budget is provisioned per worker slot and a dead worker's share is not
;; redistributed. Survivors inherit the orphaned subtasks, so their ideal share
;; grows as the population shrinks (positive feedback).
to distribute-resources
  set resource-pool calculate-resource-pool
  let alive-workers workers with [alive?]
  let n-alive count alive-workers
  if n-alive = 0 [ stop ]

  let base-share resource-pool / N
  let ideal-share 10 * N / n-alive

  ask alive-workers [
    ;; Matthew effect: trust-weighted allocation
    let allocation base-share * (0.7 + trust-score * 0.6)
    set resource-held min (list allocation (base-share * 1.5))
    set resource-pressure max (list 0 (1 - resource-held / ideal-share))
  ]
end

;; ── Submodel 7.2: execute-task ──────────────────────────────────────────────
to execute-task  ;; worker procedure
  set true-progress true-progress + resource-held / 80
  if true-progress >= 1 [
    set tasks-completed tasks-completed + 1
    set true-progress   0
    set last-received   0
  ]
end

;; ── Submodel 7.3: report-to-orchestrator ────────────────────────────────────
to report-to-orchestrator  ;; worker procedure
  ;; Bounded-rationality reporting noise
  let report-noise resource-pressure * 0.3 * (random-float 1)

  ;; Structural bias under high pressure (slight under-reporting)
  let strategic-bias 0
  if strategic-bias? and resource-pressure > 0.5 [
    set strategic-bias (random-float 0.2) - 0.15
  ]

  set reported-progress max (list 0
    (min (list 1 (true-progress - report-noise + strategic-bias))))

  ;; Logging competes for context budget
  set log-rate max (list 0.05
    (1 - resource-pressure * 0.8 * (random-float 1)))

  ;; Does the report reach the orchestrator?
  let delivered? (random-float 1 < log-rate)

  if topology = "Ring" and not delivered? [
    let next-id (task-id + 1) mod N
    let peers workers with [alive? and task-id = next-id]
    if any? peers [
      set delivered? (random-float 1 < [log-rate] of one-of peers)
    ]
  ]

  if topology = "Hierarchical" and my-broker != nobody [
    ifelse [alive?] of my-broker
      [ set delivered? (delivered? and (random-float 1 < [log-rate] of my-broker)) ]
      [ set delivered? false ]
  ]

  if delivered? [
    set last-received reported-progress
    ask one-of orchestrators [
      set oversight-log-count oversight-log-count + 1
      if oversight-log-count > 1000 [ set oversight-log-count 900 ]
    ]
  ]
end

;; ── Submodel 7.4: update-world-model ───────────────────────────────────────
to update-world-model  ;; orchestrator procedure
  let alive-workers workers with [alive?]
  if not any? alive-workers [ stop ]

  ;; The orchestrator only knows the reports it received (some are stale)
  set believed-progress mean [last-received] of alive-workers
  let consensus believed-progress

  ;; Trust: agreement with the group, never with ground truth
  ask alive-workers [
    let consistency 1 - abs (reported-progress - consensus)
    set trust-score trust-score * 0.9 + consistency * 0.1
  ]
end

;; ── Submodel 7.5: sample-and-detect ────────────────────────────────────────
to sample-and-detect  ;; monitor procedure
  let alive-workers workers with [alive?]
  if not any? alive-workers [ stop ]

  ;; Monitoring spends context budget too: coverage shrinks with scarcity
  let sample-size max (list 1 (round (count alive-workers * 0.2 * (1 - scarcity))))
  let sampled n-of sample-size alive-workers

  let sample-iai mean [abs (true-progress - reported-progress)] of sampled
  set anomaly-score anomaly-score * 0.8 + sample-iai * 0.2

  ifelse anomaly-score > 0.2
    [ set color red ]
    [ set color lime ]
end

;; ── Submodel 7.6: check-cascade-failures ───────────────────────────────────
to check-cascade-failures
  let candidates workers with [alive? and resource-held < survival-threshold]
  ask candidates [
    if alive? [
      set alive?        false
      set color         red
      set size          1.2
      set cascade-count cascade-count + 1

      ;; Secondary cascade: only the dependents of a dead broker
      if topology = "Hierarchical" and task-id < N / 2 [
        let me self
        ask workers with [alive? and my-broker = me] [
          if random-float 1 < 0.5 [
            set alive?        false
            set color         orange
            set size          1.2
            set cascade-count cascade-count + 1
          ]
        ]
      ]
    ]
  ]
end

;; ── Submodel 7.7: calculate-metrics ────────────────────────────────────────
to calculate-metrics
  let alive-workers workers with [alive?]
  let n-alive count alive-workers
  set alive-count n-alive

  if n-alive = 0 [
    set system-iai 1
    set system-gini 1
    set system-tcd 1
    set system-oer 1
    set misalignment-phase 2
    set phase-label "CRITICAL"
    stop
  ]

  ;; IAI: mean absolute deviation between true and reported progress
  set system-iai mean [abs (true-progress - reported-progress)] of alive-workers

  ;; Gini coefficient
  let res-list sort [resource-held] of alive-workers
  let n length res-list
  let total-res sum res-list
  ifelse total-res > 0 [
    let gini-sum 0
    let i 0
    foreach res-list [ r ->
      set gini-sum gini-sum + ((2 * (i + 1) - n - 1) * r)
      set i i + 1
    ]
    set system-gini abs gini-sum / (n * total-res)
  ] [
    set system-gini 0
  ]

  ;; TCD: orchestrator believed progress vs. true average
  set true-avg-progress mean [true-progress] of alive-workers
  set system-tcd abs ([believed-progress] of one-of orchestrators - true-avg-progress)

  ;; OER: 1 - mean log rate
  set system-oer 1 - mean [log-rate] of alive-workers

  ;; Composite misalignment score
  set composite-score (
    system-iai * 0.25 +
    system-gini * 0.20 +
    system-tcd * 0.25 +
    system-oer * 0.15 +
    (cascade-count / N) * 0.15
  )

  ;; Phase classification
  ifelse composite-score >= 0.45 [
    set misalignment-phase 2
    set phase-label ">>> CRITICAL <<<"
    if tick-at-phase2 = -1 [ set tick-at-phase2 ticks ]
  ] [
    ifelse composite-score >= 0.28 [
      set misalignment-phase 1
      set phase-label "WARNING"
      if tick-at-phase1 = -1 [ set tick-at-phase1 ticks ]
    ] [
      set misalignment-phase 0
      set phase-label "STABLE"
    ]
  ]
end

;; ── Submodel 7.8: update-display ───────────────────────────────────────────
to update-display
  ask workers with [alive?] [
    ;; Colour encodes trust-score (cyan → blue scale)
    let t trust-score
    ifelse t > 0.8
      [ set color sky ]
      [ ifelse t > 0.5
          [ set color blue + 1 ]
          [ set color blue - 1 ]
      ]
    ;; Size encodes task progress
    set size 1.2 + true-progress * 1.0
  ]

  ;; Update orchestrator label with believed progress
  ask orchestrators [
    set label (word "ORC\n" round (believed-progress * 100) "%")
  ]

  ;; Update link colours: active = trust-tinted, dead links = dark red
  ask links [
    let w-end other-end
    ifelse is-worker? w-end and [alive?] of w-end
      [ set color grey - 1 ]
      [ set color red - 3 ]
  ]
end

;; ═══════════════════════════════════════════════════════════════════════════════
;; REPORTERS FOR INTERFACE
;; ═══════════════════════════════════════════════════════════════════════════════

to-report iai-pct       [ report precision (system-iai  * 100) 1 ]
to-report gini-pct      [ report precision (system-gini * 100) 1 ]
to-report tcd-pct       [ report precision (system-tcd  * 100) 1 ]
to-report oer-pct       [ report precision (system-oer  * 100) 1 ]
to-report cfp-pct       [ report precision (cascade-count / max (list 1 N) * 100) 1 ]
to-report composite-pct [ report precision (composite-score * 100) 1 ]
to-report alive-pct     [ report precision (alive-count / max (list 1 N) * 100) 1 ]

to-report phase-color
  if misalignment-phase = 0 [ report 55 ]   ;; green
  if misalignment-phase = 1 [ report 45 ]   ;; yellow
  report 15                                   ;; red
end

to-report believed-progress-pct
  report precision ([believed-progress] of one-of orchestrators * 100) 1
end

to-report true-progress-pct
  report precision (true-avg-progress * 100) 1
end

to-report monitor-anomaly
  ifelse monitor-enabled? and any? monitors
    [ report precision ([anomaly-score] of one-of monitors * 100) 1 ]
    [ report 0 ]
end

to-report tasks-per-agent [ report precision (tasks-completed / max (list 1 N)) 2 ]

to-report resource-pool-display
  report resource-pool
end
@#$#@#$#@
GRAPHICS-WINDOW
230
10
698
479
-1
-1
13.6
1
12
1
1
1
0
1
1
1
-17
17
-17
17
1
1
1
ticks
30.0

BUTTON
10
10
112
43
SETUP
setup
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
120
10
222
43
GO
go
T
1
T
OBSERVER
NIL
G
NIL
NIL
1

BUTTON
10
50
222
83
GO ONCE
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
10
95
222
128
N
N
5
100
20
5
1
agents
HORIZONTAL

SLIDER
10
135
222
168
scarcity
scarcity
0.1
0.95
0.3
0.05
1
NIL
HORIZONTAL

CHOOSER
10
175
222
220
topology
topology
"Star" "Ring" "Hierarchical"
0

SLIDER
10
228
222
261
max-ticks
max-ticks
50
500
200
50
1
ticks
HORIZONTAL

SWITCH
10
270
222
303
monitor-enabled?
monitor-enabled?
0
1
-1000

SLIDER
10
311
222
344
survival-threshold
survival-threshold
1
5
3
0.25
1
tokens
HORIZONTAL

SWITCH
10
352
222
385
strategic-bias?
strategic-bias?
0
1
-1000

MONITOR
710
10
870
55
Phase
phase-label
17
1
11

MONITOR
710
62
810
107
IAI %
iai-pct
1
1
11

MONITOR
820
62
920
107
Gini %
gini-pct
1
1
11

MONITOR
710
112
810
157
TCD %
tcd-pct
1
1
11

MONITOR
820
112
920
157
OER %
oer-pct
1
1
11

MONITOR
710
162
810
207
CFP %
cfp-pct
1
1
11

MONITOR
820
162
920
207
Composite
composite-pct
1
1
11

MONITOR
710
212
810
257
Alive %
alive-pct
1
1
11

MONITOR
820
212
920
257
Monitor IAI
monitor-anomaly
1
1
11

MONITOR
710
262
810
307
True Progress
true-progress-pct
1
1
11

MONITOR
820
262
920
307
Believed Prog.
believed-progress-pct
1
1
11

MONITOR
710
312
810
357
Resource Pool
resource-pool-display
17
1
11

MONITOR
820
312
920
357
Cascades
cascade-count
17
1
11

PLOT
710
370
1100
520
Misalignment Metrics Over Time
Ticks
Value (0-1)
0.0
200.0
0.0
1.0
true
true
"" ""
PENS
"IAI" 1.0 0 -2674135 true "" "plot system-iai"
"Gini" 1.0 0 -13791810 true "" "plot system-gini"
"TCD" 1.0 0 -8732573 true "" "plot system-tcd"
"OER" 1.0 0 -1184463 true "" "plot system-oer"
"CFP" 1.0 0 -5825686 true "" "plot (cascade-count / max (list 1 N))"

PLOT
710
530
1100
680
Composite Misalignment Score
Ticks
Score (0-1)
0.0
200.0
0.0
1.0
true
false
"" ""
PENS
"Composite" 1.0 0 -16777216 true "" "plot composite-score"
"Warning" 1.0 0 -1184463 true "" "plot 0.28"
"Critical" 1.0 0 -2674135 true "" "plot 0.45"

PLOT
230
490
700
640
Agent Population (Alive vs Dead)
Ticks
Count
0.0
200.0
0.0
100.0
true
true
"" ""
PENS
"Alive" 1.0 0 -13791810 true "" "plot count workers with [alive?]"
"Dead" 1.0 0 -2674135 true "" "plot count workers with [not alive?]"

PLOT
10
370
222
520
Resource Pool
Ticks
Tokens
0.0
200.0
0.0
1000.0
true
false
"" ""
PENS
"Pool" 1.0 0 -13791810 true "" "plot resource-pool"

PLOT
10
530
222
680
Trust Distribution
Ticks
Avg Trust
0.0
200.0
0.0
1.0
true
false
"" ""
PENS
"Mean Trust" 1.0 0 -13345367 true "" "if any? workers with [alive?] [ plot mean [trust-score] of workers with [alive?] ]"
"Min Trust" 1.0 0 -2674135 true "" "if any? workers with [alive?] [ plot min [trust-score] of workers with [alive?] ]"

TEXTBOX
10
315
222
365
── PHASE THRESHOLDS ──
Warning > 28%  Critical > 45%
11
105
1

TEXTBOX
710
347
920
367
── CURRENT READINGS ──
11
105
1

@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
WHAT IS IT?
-----------
MESA (Multi-Agent Emergent Systems Arena) is an agent-based model that investigates
emergent misalignment in hierarchical multi-agent AI systems.

The central question: under what conditions does a population of INDIVIDUALLY ALIGNED
AI agents produce COLLECTIVELY MISALIGNED behaviour at the system level?

No agent has a rule permitting deception, hoarding, or misalignment. The system-level
breakdown emerges purely from interactions under resource scarcity.

HOW IT WORKS
-----------
Each tick:
1. Resources distributed to workers weighted by trust-score (Matthew effect)
2. Workers execute their assigned subtask (true-progress increases)
3. Workers report to orchestrator — with noise scaling with resource-pressure
4. Orchestrator updates its world model and trust scores from reports
5. Monitor (optional) samples 20% of workers for anomaly detection
6. Cascade failures checked: workers with resource-held below survival-threshold die
7. Five misalignment metrics computed: IAI, Gini, TCD, OER, CFP

KEY PARAMETERS
-----------
scarcity:  Fractional resource deficit. 0.5 = agents receive 60% of ideal resources.
N:         Number of worker agents (10–100).
topology:  Star (centralised) | Ring (decentralised) | Hierarchical (two-tier).
monitor-enabled?: Adds a passive monitoring agent that samples 20% of workers.

KEY METRICS
-----------
IAI  — Information Asymmetry Index:     how much the orchestrator is under-informed
Gini — Resource Gini Coefficient:        resource inequality across agents
TCD  — Task Completion Drift:            orchestrator world-model accuracy
OER  — Oversight Erosion Rate:           logging reliability under pressure
CFP  — Cascade Failure Proportion:       fraction of agents that have failed

THINGS TO TRY
-----------
1. Set scarcity = 0.3, topology = Star → observe stable system
2. Increase scarcity to 0.7+ → observe phase transition (IAI and TCD spike)
3. Switch to Hierarchical topology → observe faster cascade failures
4. Enable monitor-enabled? → does it help at high scarcity?
5. Use BehaviorSpace to sweep all parameters systematically

CREDITS
-----------
MSc Data Science & AI — Agent-Based Modelling Project
ODD Protocol: Grimm et al. (2020), JASSS 23(2):7
Inspired by: Mistral Workflows (April 2026), Temporal durable execution engine.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

@#$#@#$#@
@#$#@#$#@
