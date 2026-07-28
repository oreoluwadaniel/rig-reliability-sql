# Project 02: Failure Frequency and Downtime Exposure

**What is actually breaking, how often, and how much operating time does it cost us?**

Script: [`failure_downtime_analysis.sql`](failure_downtime_analysis.sql)
Database: PostgreSQL 14
Setup required: run [`../sql/00_schema.sql`](../sql/00_schema.sql) first

---

## 1. Business Problem

Maintenance gets measured in money because money is easy to measure. It is usually the wrong measure.

The cost of a repair is what you paid the contractor. The cost of the failure is the production you did not sell while the asset sat idle. Those two numbers are not related to each other in any reliable way. A seal costs very little and can stop a well for three days. A planned overhaul costs a great deal and is scheduled for a window when nothing is running.

So a maintenance function that only tracks spend is watching the smaller of the two numbers and missing the larger one entirely.

This project looks at the other side. It asks which assets fail most often, where the lost hours accumulate, which types of fault do the most damage, and whether reliability across the fleet is holding steady or slipping.

There is a second question underneath the first one, and it is the more useful one. Two assets can lose the same hundred hours in completely different ways. One loses them across twenty short stoppages. The other loses them in a single week long outage. Those are different problems with different causes and different fixes, and a report that ranks on total hours alone cannot tell them apart. Getting that distinction into the output is most of the value of this analysis.

## 2. Data Source

Two tables out of the ten CSV files in this dataset.

**`maintenance.csv`**, 3,000 events. The core table for this project. Every row is one failure and its consequences.

| Column | What it holds |
|---|---|
| `asset_id` | The asset. Prefix says what kind: WEL, PIP or REF |
| `maintenance_date` | When it failed |
| `cost_usd` | Repair cost |
| `failure_type` | Category of fault, for example Pump Failure, Corrosion, Electrical Fault |
| `downtime_hours` | Hours the asset was out of service |

**`production.csv`**, 5,000 readings. Used only where downtime needs to be weighed against what the asset produces.

| Column | What it holds |
|---|---|
| `well_id` | The well |
| `production_date` | Date of the reading |
| `oil_production_barrels`, `gas_production_mcf` | Volumes |
| `water_cut_pct`, `pressure_psi`, `temperature_c` | Operating conditions |

Two limits worth stating before anyone reads the output.

The production table holds wells only. Pipelines and refineries appear in maintenance but have no production rows, so any query comparing downtime to barrels is restricted to wells.

There is no timestamp on the downtime, only a date and a duration. So the analysis can say an asset lost 90 hours across the period. It cannot say whether those hours fell during peak production or during a shutdown when nothing was running anyway. Worth knowing before treating lost hours as directly equal to lost barrels.

## 3. Methodology

Frequency first, then duration, then cause, then trend. Each layer answers something the one before it raised.

**Frequency, with time attached.** Counting failures per asset is the obvious starting point and it is not enough on its own. Six failures over six years is routine. Six failures over six months is an asset coming apart. Same count, opposite conclusion. So the first query carries the date range and the average gap between failures alongside the count. The average gap is the closest thing this dataset offers to mean time between failures, which is the standard reliability measure, and it is what turns a count into a judgement.

**Duration, kept separate from frequency.** Total downtime per asset, with the average per failure and the worst single outage next to it. Three columns instead of one, because the shape of the downtime is the diagnosis. Many short stoppages usually means a recurring fault nobody has traced to root cause. One very long stoppage usually means a part that was not in stores. Reporting only the total hides which of the two you are dealing with.

**Concentration.** The same cumulative share approach used in project 01, applied to hours instead of dollars. This decides what kind of recommendation is possible. If a small number of assets carry most of the lost hours, a targeted programme will move the number. If the hours are spread thinly across hundreds of assets, targeting will not work and the answer has to be systemic.

**Cause, ranked by damage rather than by count.** Failure types sorted by total downtime, not by how often they occur. Those two orderings are usually different and the difference is the point. A fault that happens 400 times and clears in two hours is an irritation. A fault that happens 40 times and takes three days is where the production went.

**Cause, split by asset type.** Wells, pipelines and refineries do not fail the same way. Averaging across all three produces a number that describes none of them. This is the query that tells a planner whether corrosion is a pipeline problem or everybody's problem.

**Downtime against production, done correctly.** The corrected version of the query the original script got wrong. Details in section 4.

**Downtime where the barrels are.** Lost hours on a poor producer are a nuisance. The same hours on a top producer are lost revenue. This ranks wells on both dimensions and keeps only the ones that are bad on both.

**Trend.** Failures and hours by year. Position is arguable, direction is not.

## 4. Analysis and Error Check

I went through the original script query by query. Here is what was wrong in the four queries belonging to this project.

### The join fan-out in the downtime versus production query

This was the significant one. The original:

```sql
SELECT m.asset_id,
       SUM(m.downtime_hours) AS downtime,
       SUM(p.oil_production_barrels) AS production
FROM maintenance m
LEFT JOIN production p ON m.asset_id = p.well_id
GROUP BY m.asset_id;
```

`maintenance` holds many rows per asset. `production` holds many rows per well. Joining them at row level produces every combination of the two before the aggregation runs.

Take a well with 4 maintenance events and 3 production readings. The join returns 12 rows. `SUM(m.downtime_hours)` then adds each downtime value three times, once for each production reading it got paired with. `SUM(p.oil_production_barrels)` adds each production value four times, once per maintenance event.

Both figures come out too high. Worse, the inflation factor is different for every asset, because it depends on how many rows each one happens to have on each side. The output is not uniformly wrong by some constant you could divide out. It is wrong by a different amount in every row.

The reason this survives review is that the output looks fine. No errors, no nulls, no obviously absurd values. Just numbers that are too big.

**Fixed** by aggregating maintenance and production separately in CTEs, then joining the two one row per asset summaries. Each asset now contributes its downtime once and its production once.

### The same query silently dropped non well assets

`maintenance.asset_id` includes pipelines and refineries. `production.well_id` does not. The LEFT JOIN returns NULL production for all of them, and they sit in the results looking like assets with heavy downtime and no output.

**Fixed** with an `asset_class()` helper that labels each asset from its ID prefix, and a filter restricting the production comparison to wells. Pipelines and refineries are still analysed for frequency and downtime in queries 2.1 through 2.5 where no production data is needed.

### Failure counts with no time context

The original frequency query returned `asset_id` and `COUNT(*)`, sorted descending. Correct SQL, incomplete analysis. A raw count cannot distinguish an asset that failed six times in its first year from one that failed six times over a decade, and those two assets need entirely different responses.

**Fixed** by adding the first and last failure dates, the days covered, and the average gap between failures. The `COUNT(*) > 1` guard on the average matters: an asset with a single failure has no gap to measure, and dividing by `COUNT(*) - 1` would be a divide by zero without it.

### Failure types ranked by the wrong measure

The original ordered failure types by occurrence count and reported average downtime as a secondary column. That answers "what is most common". The question worth asking is "what costs us most", and the answer is usually a different failure type.

Average downtime alone does not fix it either, because a rare fault with a long average still may not amount to much in total. What you need is total downtime by failure type, which the original never calculated.

**Fixed** by adding total downtime, total cost, worst single outage, and each type's share of all failures and all downtime, sorted on total downtime.

### Downtime reported only as a total

Sorting assets by total hours puts the frequent minor offenders and the rare catastrophic ones in the same list with nothing to separate them. The original script explicitly said in its comments that it wanted to tell these apart, and then did not calculate the columns that would have done it.

**Fixed** by adding the average hours per failure, the worst single outage and the total expressed in days.

### What was correct

The three simple aggregations in the original, failure count by asset, total downtime by asset, and occurrences by failure type, all group correctly and produce accurate numbers as far as they go. I have kept the logic and built context columns around it. The issue with those three was never accuracy, it was that they answered a narrower question than the business was asking.

## 5. Insight

**Frequency and duration point at different assets, and both lists are needed.** The asset that fails most often is rarely the asset that loses the most hours. Frequency identifies unresolved root causes. Duration identifies where production actually went. Running one and not the other means missing half the problem, and the original script's outputs did not let you see that they were different lists.

**The shape of an asset's downtime is the diagnosis, and it is free to calculate.** Total hours divided by failure count separates the two failure patterns immediately. High total with a low average is a repeat fault, and the fix is engineering. High total with a high average is a long outage, and the fix is usually spares availability or planning. Same headline number, different department, different budget. Query 2.2 makes this visible in a column that costs nothing to add.

**Most common and most damaging are different failure types.** Ranking by count promotes whatever fails frequently and clears quickly. Ranking by total downtime promotes whatever stops the asset for days. The second ranking is the one that maps to lost production, and it is the ranking the original script did not produce.

**Failure patterns are specific to asset type.** Aggregating corrosion across wells, pipelines and refineries produces an average that matches none of them. Query 2.5 splits it, and the split is what makes the output actionable for a planner who works on one class of kit.

**Downtime only converts to money where there are barrels.** Query 2.7 is the shortlist that follows from this. Wells in the worst quarter for downtime and the best quarter for production are where lost hours become lost revenue. Every other combination is less urgent, and a report that does not make this distinction sends the team to the wrong sites.

**Direction beats position in any conversation about reliability.** Whether 40,000 hours is a lot is arguable. Whether it has risen every year for five years is not. Query 2.8 is the one that gets a decision made.

## 6. Recommendation

**Split the top of the downtime list into two groups before assigning any work.** Use the average hours per failure column from query 2.2. Repeat offenders with short outages go to reliability engineering for root cause. Single long outages go to planning and spares. Sending both to the same team wastes the effort, because the two problems have nothing in common except the number they produce.

**Attack failure types by total downtime, starting from the top of query 2.4.** The top two or three types by total hours will account for a large share of all lost production. Fixing a fault mode across the whole fleet scales in a way that fixing individual assets does not.

**Build the maintenance programme per asset type, not for the fleet.** Query 2.5 gives the dominant fault mode for wells, for pipelines and for refineries separately. Three focused programmes will beat one general one.

**Work query 2.7 first.** These are high downtime wells that also produce heavily, so this is where an hour recovered is worth the most. It is a short list by construction and it is the most defensible place to start.

**Report the trend in query 2.8 to management every quarter, and report it as a trend.** A single lifetime total invites debate about whether it is normal. A line going the wrong way for five years does not.

**Fix the timestamp gap in how downtime is recorded.** Right now there is a date and a duration but no start time. That means nobody can say whether an outage hit during production or during a planned shutdown, and that distinction is the difference between hours lost and barrels lost. It is a change to the capture process rather than to the analysis, and it would improve every reliability number reported from this data.

## 7. Business Impact

**Lost production becomes visible as its own number.** Tracking spend measures what was paid to fix things. Tracking downtime measures what the failure actually cost. The second number is usually much larger and it is the one that justifies preventive work at budget time.

**Repair effort gets aimed at the right problem.** Separating repeat faults from long outages routes each to the team that can fix it. Today both sit in the same list, so both get the same generic response and neither gets solved.

**Fleet wide fixes replace asset by asset firefighting.** Fixing the dominant failure mode across every well is a different scale of intervention from repairing one pump. Query 2.4 identifies which mode is worth that effort, which is a question the original ranking could not answer.

**The most valuable hours get recovered first.** Query 2.7 puts effort where downtime costs the most, so a fixed amount of maintenance capacity returns more production.

**Corrected numbers restore trust in the comparison.** The downtime against production figures were inflated on both sides by a varying multiple. Any conclusion drawn from them was unreliable. The fix makes the comparison usable again, and that is a prerequisite for everything above.

**Reliability becomes a trend rather than an anecdote.** Once the yearly view exists, deferring maintenance shows up as a rising line rather than as a saving. That changes how the decision gets discussed.

## 8. What Was Done

Reviewed the four failure and downtime queries in the original script and documented every issue found, including the join fan-out that made the downtime against production output wrong rather than just incomplete.

Rebuilt that query with pre-aggregated CTEs so each asset contributes its downtime once and its production once, and scoped it to wells so the comparison is valid.

Added time context to the failure frequency query so a count becomes a rate, including a guard against dividing by zero for assets with a single failure.

Extended the downtime query with the average per failure, the worst single outage and a days conversion, so frequent minor stoppages can be told apart from rare major ones.

Rewrote the failure type analysis to rank on total downtime rather than occurrence count, and added cost, worst case and share of total columns.

Added a failure type by asset type breakdown so wells, pipelines and refineries are analysed separately.

Added a downtime concentration query with cumulative share, to establish whether a targeted programme is viable before recommending one.

Added a cross ranking that isolates high downtime wells that are also high producers.

Added a year on year reliability trend, which the original had no equivalent of.

Documented the two data limitations that constrain interpretation: production covers wells only, and downtime has no start time.

## 9. Tools Used and How They Helped

**PostgreSQL 14.** Window functions, `FILTER`, `NTILE` and date arithmetic all work out of the box, so the whole analysis stays in SQL. No export step means no version of the numbers that can drift from the source.

**Common table expressions.** The fix for the fan-out. Pre-aggregating each table before the join is the correction, and CTEs make it legible. Written as nested subqueries it would work identically and be much harder to review, which matters when part of the purpose is to show the reasoning.

**Window functions.** `SUM() OVER ()` supplies the grand total to every row for the percentage columns. `SUM() OVER (ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)` builds the cumulative share. `SUM(COUNT(*)) OVER (PARTITION BY ...)` in query 2.5 gives each failure type its share within its own asset class, which is an aggregate inside a window and saves an entire extra join. `LAG()` handles the year on year comparison.

**`NTILE(4)`.** Used in query 2.7 to rank wells on downtime and production at the same time. Quartiles let two different scales be compared without inventing a conversion between hours and barrels.

**PostgreSQL date subtraction.** `MAX(date) - MIN(date)` returns an integer number of days directly, which is what makes the average gap between failures a one line calculation.

**`CASE WHEN COUNT(*) > 1`.** Guards the average gap calculation. Assets with one failure have no interval to measure and would otherwise divide by zero.

**`NULLIF()`.** Guards every other division in the script, including the percentage change calculation where the prior year could be zero.

**Explicit `::NUMERIC` casts.** Integer division in PostgreSQL truncates, so `total_oil / downtime_hours` on two integer columns silently drops the decimals. Casting one side first keeps the precision.

## 10. Results

Eight outputs, each answering a specific question.

| Query | What it gives you |
|---|---|
| 2.1 | Failure count per asset with date range and average days between failures |
| 2.2 | Total downtime per asset with average per failure, worst single outage and days lost |
| 2.3 | Assets ranked by downtime with share of total and running cumulative share |
| 2.4 | Failure types ranked by total downtime, with cost, worst case and share columns |
| 2.5 | Failure types split by asset type, with each type's share within its own class |
| 2.6 | Wells with downtime, cost and production side by side, double counting removed |
| 2.7 | The shortlist: wells in the worst quarter for downtime and the best quarter for production |
| 2.8 | Failures and lost hours by year with change on the prior year |

The concrete outcomes.

Query 2.6 now returns correct figures. The previous version inflated both downtime and production by a multiplier that varied per asset, so the ratio between them was meaningless.

Query 2.2 makes the repeat fault versus long outage distinction readable at a glance, which is the distinction that determines who fixes it.

Query 2.4 reorders failure types by damage rather than by frequency, which changes which fault modes get engineering attention.

Query 2.7 produces a short, defensible list of the wells where an hour of downtime costs the most.

Query 2.3 establishes whether a targeted programme can work at all, before anyone designs one.

Query 2.8 gives management a direction rather than a number, which is what tends to move a decision.

Every result is reproducible from the schema file and the three source CSVs.

---

### Files

```
02-failure-downtime-analysis/
├── README.md
└── failure_downtime_analysis.sql
```

### Running it

```bash
psql -d rigwatch -f sql/00_schema.sql
psql -d rigwatch -f 02-failure-downtime-analysis/failure_downtime_analysis.sql
```

Uncomment the `\copy` lines in the schema file first, and check the CSVs are in `data/`.
