# EVE Unbound V1.0 — fight export fields

`Num8` exports completed attempts from the current session (up to 100). An active
attempt is not exported until it finishes. The original nine columns remain first.
Measurements use the existing roughly 200 ms recorder and game time. A short
healing/loss sequence between polls can be missed. No additional engine-wide scan
is performed for these metrics.

| Columns | Meaning |
| --- | --- |
| attempt, started_utc, world | Session attempt ID, UTC start timestamp, sampled world name |
| seconds | Attempt duration in game time |
| observed_damage_events | HP decreases grouped within a 0.3-second window; not exact hits |
| observed_hp_lost_percentage_points | Sum of trustworthy sampled HP decreases |
| longest_observed_clean_seconds | Longest observed span without a recorded HP decrease; gaps break spans |
| sampling_gaps | Discontinuities: long sample interval, changed health source or changed maximum HP |
| end_reason | Why the recorder stopped |
| observed_hp_recovered_percentage_points | Sum of trustworthy sampled HP increases; includes any visible recovery source |
| observed_recovery_events | Consecutive increases grouped within 0.3 seconds; not healing-item counts |
| start_hp_percent, end_hp_percent, min_hp_percent, max_hp_percent | Sampled HP percentage at the attempt boundaries and extrema |
| net_hp_change_pp | End HP percentage minus start HP percentage, even across sampling discontinuities |
| average_observed_hp_percent | Time-weighted trapezoidal average over valid adjacent samples; start HP if no valid interval |
| samples | Number of accepted samples, including the initial sample |
| observed_seconds | Total time covered by trusted adjacent samples |
| max_sample_gap_seconds | Largest interval between accepted samples |
| observed_seconds_below_25pct | Trusted time with both interval endpoints below 25% HP; conservative estimate |
| observed_combat_seconds, observed_lockon_seconds | Trusted time with the corresponding flag true at both endpoints |
| hp_loss_pp_per_minute, hp_recovery_pp_per_minute | Observed change divided by observed time; zero without covered time |
| health_source_start, health_source_end | Health-reading source at the attempt boundaries |
| raw_hp_start, raw_hp_end, raw_max_hp_end | Raw HP values when exposed by the health source; blank when unavailable |
| boss_challenge | Start sample's Boss Challenge flag: true, false or unknown |
| tools_start, tools_end | Tool states at the first and final samples |
| tool_action_requests | Relevant hotkey action requests during recording; not guaranteed successful changes |
| manual_marks | Manual position-save requests during recording |
| teleports | Successful position returns during recording |
| block_inputs, dodge_inputs, blue_inputs, violet_inputs | Defense-feed input observations while enabled; not verified successful defense actions |
| reversed_inputs, ambiguous_inputs | Reversed-direction and same-poll/order-unclear observations |
| tools_seen | Distinct sampled tool-state combinations, separated by a vertical bar |

HP units are percentage points: a change from 40% to 55% is 15 pp. Recovery/loss
and time-weighted metrics skip intervals longer than 1.5 seconds and intervals
with a changed maximum or health source. Boundary/extreme HP still reports sampled
values. Raw HP is deliberately blank when the source supplies only a normalized bar.

The feed samples E / Shift / W / S at roughly 33 ms when gameplay is ready. Counts
can overlap: an input initially classified as dodge can later also be classified
as reversed. Disabled or paused feed sampling cannot contribute input counts.
An active tool may switch between samples; tool_action_requests helps distinguish
activity that the sampled tool-state strings may miss.
