# MESA v2: BehaviorSpace setup

Open **Tools → BehaviorSpace → New**. Create the five experiments below.
Common settings for all of them:

- **Setup commands:** `setup`
- **Go commands:** `go`
- **Stop condition:** leave empty (`go` stops by itself at `max-ticks` or when every worker is dead)
- **Time limit:** 0
- **Measure runs at every step:** OFF (ON only for experiment 5)
- Keep `max-ticks` = 200 and `monitor-enabled?` = true
- Run with **Table output**, and as many parallel runs as your CPU allows

## Reporters ("Measure runs using these reporters", one per line)

```
system-iai
system-gini
system-tcd
system-oer
cascade-count / N
alive-count / N
tasks-completed / N
misalignment-phase
ifelse-value any? workers with [alive?] [mean [resource-pressure] of workers with [alive?]] [1]
ifelse-value any? monitors [[anomaly-score] of one-of monitors] [-1]
```

## Experiments

| # | Name | Vary | Fixed | Reps | Runs |
|---|------|------|-------|------|------|
| 1 | main-sweep | `scarcity` [0.1 0.05 0.95]; `topology` "Star" "Ring" "Hierarchical" | N = 50, survival-threshold = 3, strategic-bias? = true | 30 | 1,620 |
| 2 | threshold | `survival-threshold` 2.5, 3, 3.5; `scarcity` [0.8 0.025 0.95]; `topology` all three | N = 50, strategic-bias? = true | 20 | 1,260 |
| 3 | population | `N` 10, 25, 50, 100; `scarcity` 0.5, 0.7, 0.85, 0.9; `topology` "Star" "Hierarchical" | survival-threshold = 3 | 20 | 640 |
| 4 | no-bias | `scarcity` [0.1 0.1 0.9]; `strategic-bias?` = false | topology "Star", N = 50, survival-threshold = 3 | 30 | 270 |
| 5 | trajectories | `scarcity` 0.3, 0.6, 0.85, 0.95 | topology "Star", N = 50, survival-threshold = 3. **Measure runs at every step: ON** | 5 | 20 |

Run experiment 1 first. In NetLogo, a variable with a range is written `["scarcity" [0.1 0.05 0.95]]`, meaning start, step, end.
Text values need quotes: `["topology" "Star" "Ring" "Hierarchical"]`.

## Sanity check before the long runs

Run 10 or so runs by hand with N = 50, Star, survival-threshold = 3. The final values should be close to this:

| scarcity | IAI | TCD | OER | tasks per worker |
|----------|-----|-----|-----|------------------|
| 0.5 | about 0.03 | about 0.04 | about 0.09 | about 18 |
| 0.8 | about 0.09 | about 0.09 | about 0.22 | about 11 |
| 0.9 | about 0.15 | about 0.17 | about 0.26 | about 8 |
| 0.95 | the system collapses (alive near 0) | | | |

The values come from an independent Python re-implementation, so small differences (about 0.01) are normal.
If your numbers are far off, send me a screenshot of the monitors.
