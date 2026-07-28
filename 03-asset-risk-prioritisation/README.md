# Project 03: Asset Risk Scoring and Maintenance Prioritisation

**Out of three thousand assets, which ones does a maintenance team go and look at on Monday morning?**

Script: [`asset_risk_prioritisation.sql`](asset_risk_prioritisation.sql)
Database: PostgreSQL 14
Setup required: run [`../sql/00_schema.sql`](../sql/00_schema.sql) first

---

## 1. Business Problem

Projects 01 and 02 each produced a ranked list. One ranked by money, one ranked by lost hours. Both are correct and neither is enough, because an asset can top one list and sit unremarkably in the middle of the other.

That leaves a maintenance manager with three lists and no way to combine them. In practice what happens is that whichever list was presented most recently wins, or the assets that appear near the top of all three get picked by eye. Neither is a method, and neither survives being questioned.

The problem this project solves is narrower and more practical than it sounds. A maintenance team has finite capacity. Someone has to decide which assets get inspected this week. That decision is currently made on judgement, experience and whoever shouted loudest, and it produces a different answer depending on who is asked.

What is needed is a single ordered list, short enough to act on, built from a rule that is written down. Written down matters as much as the ranking itself. A priority list nobody can explain gets overridden the first time an operations manager disagrees with it. A priority list with visible weights can be argued with, adjusted, and then actually followed.

The original script attempted exactly this in its final query. The intent was right. The execution had problems serious enough that the output would have sent the team to the wrong assets, and section 4 covers them in detail.

## 2. Data Source

All three tables, joined into a single asset level view.

**`maintenance.csv`**, 3,000 events. Failure history: asset, date, cost, failure type, downtime hours.

**`production.csv`**, 5,000 readings. Well level output: oil barrels, gas volume, water cut, pressure, temperature. Wells only.

**`emissions.csv`**, 3,000 readings. Environmental performance by asset: CO2 tons, methane leakage, energy consumption. Covers wells, pipelines and refineries, so it is the only one of the three that lines up with the full range of asset IDs in maintenance.

The three are combined in `v_asset_reliability`, which produces one row per asset with failure history, production totals and emissions averages side by side.

**Three limits that shape how the output should be read.**

Production covers wells only. Pipelines and refineries carry NULL in those columns. That is expected and is labelled rather than hidden.

There is no date alignment between the three tables. A 2018 failure and a 2024 production reading belong to the same asset and to completely different moments. The view reports lifetime totals and names them as such. It does not claim that the production figure next to a failure is the production around that failure, because the data cannot support that claim.

The maintenance CSV has no unique event identifier. Without one there is no safe way to count distinct failures once the table is joined to anything. The schema adds a surrogate primary key, and that single change is what makes the corrected version of this analysis possible at all.

## 3. Methodology

**Fix the foundation first.** The view everything else reads from was producing duplicated rows. Rebuilding it correctly came before any scoring, because scoring built on inflated inputs would be precisely wrong. Details in section 4.

**Put the three tables on a common grain.** Each source is aggregated to one row per asset before anything is joined. The result is a view where one row means one asset, which is what every downstream query already assumed it meant.

**Check the emissions relationship, and be careful about what it shows.** The question is whether assets that emit heavily also fail often. Reported two ways: asset level detail, and a quartile summary. The quartile summary is the more honest of the two, because if the two rankings were unrelated the average failure count would sit roughly flat across all four bands. A visible gradient means something. A flat line means the relationship is not there, and that is a legitimate finding worth reporting rather than burying.

**Flag the assets that are bad on two dimensions at once.** Assets in the top 10 percent for both failure count and downtime. Thresholds come from percentiles rather than from picked numbers, which is a deliberate choice covered below.

**Score every asset instead of filtering.** A pass or fail flag throws away the ordering inside the group that passes. Percentile ranking each asset on downtime, frequency and cost, then combining with weights, gives a single continuous score with everything still in order.

**Check the list is a workable size.** Before handing anyone a priority list, count it. If the top band contains four hundred assets, the banding has failed no matter how sound the scoring is, because nobody inspects four hundred assets. This check comes before the final output rather than after.

**Reduce to something printable.** The last query returns only the top band and only the columns a planner needs. A report that needs interpretation before anyone can act on it does not get acted on.

### Why percentiles instead of fixed thresholds

This is the main methodological choice in the project, so it is worth being explicit.

The original used hardcoded numbers: more than 5 failures, more than 100 hours, more than 3 failures. Fixed thresholds have two failure modes. Nobody can explain where the number came from, so it gets challenged and cannot be defended. And it goes stale silently. A threshold set when the fleet averaged 2 failures per asset means something entirely different once the fleet averages 6, and nothing in the code announces that it has stopped working.

A percentile threshold describes a position in the fleet. The top 10 percent is the top 10 percent whatever happens to the underlying numbers, it is defensible in a meeting because it means something in plain English, and it stays correct when the data refreshes.

The trade off is real and worth stating. Percentile thresholds always return roughly the same number of assets, so if the whole fleet improves, the same proportion still gets flagged. For a work prioritisation list that is the right behaviour, because the team's capacity has not changed either. For a safety threshold it would be the wrong behaviour, and an absolute limit would be correct there.

## 4. Analysis and Error Check

This project inherited the two worst problems in the original script. Both are set out in full because the reasoning matters more than the fix.

### The view was multiplying rows

The original:

```sql
CREATE VIEW v_asset_reliability AS
SELECT m.asset_id, m.maintenance_date, m.cost_usd, m.failure_type,
       m.downtime_hours, p.well_id, p.oil_production_barrels, p.date,
       e.co2_tons, e.methane_leakage_tons, e.energy_consumption_mwh
FROM maintenance m
LEFT JOIN production p ON m.asset_id = p.well_id
LEFT JOIN emissions  e ON m.asset_id = e.asset_id;
```

None of the three tables has one row per asset. `maintenance` holds many events per asset, `production` holds many readings per well, `emissions` holds many readings per asset. Joining all three at row level returns every combination of the three.

An asset with 4 maintenance events, 3 production readings and 2 emissions readings comes out as 24 rows. It should be 4. Every aggregate taken off this view is wrong, and the multiplier is different for every asset.

The second problem is the missing date condition. Nothing constrains a maintenance event to be joined to a production reading from anywhere near the same period. A 2018 failure joins to a 2024 reading. Even with the duplication removed, the production figure sitting next to a failure is lifetime production, not production around the failure.

The third problem is the one that would have caught out any future reader. The view's column list looks like an asset summary. Anyone would reasonably assume one row per asset. It is in fact an event level join wearing an asset level name, and nothing in the code says so.

**Fixed** by aggregating each source to one row per asset in a CTE and then joining the three summaries. The view now genuinely has the grain its name implies. Lifetime totals are labelled as lifetime totals rather than implying a link the data cannot support.

### The emissions query counted the wrong thing entirely

The original:

```sql
SELECT asset_id, AVG(co2_tons) AS avg_emissions, COUNT(*) AS failures
FROM v_asset_reliability
GROUP BY asset_id
ORDER BY avg_emissions DESC;
```

Because the view had already multiplied every asset's rows, `COUNT(*)` was not a failure count. It was maintenance events multiplied by production readings multiplied by emissions readings. The column was labelled `failures` and contained a number with no operational meaning at all.

`AVG(co2_tons)` had the same problem in a subtler form. Averaging over duplicated rows weights each asset by how many maintenance and production rows it happens to have. Assets that failed more often pulled the emissions average around for reasons that had nothing to do with emissions. This one is nastier than the count, because the result still looks like a plausible average.

**Fixed** by reading from the rebuilt view, where one row is one asset. The count is now a real failure count and the average is a real average. I also added a quartile summary, because the asset level list makes a relationship easy to imagine and hard to verify, and added a note in the script that co-occurrence is not causation. Both are more likely driven by how hard the asset is worked.

### Documentation and code disagreed in the priority query

The comment block above the original query 9 said:

> Immediate Maintenance Required: Assets with more than eight recorded maintenance events.
> High Risk: Assets with more than 120 hours of accumulated downtime.
> Stable: Assets currently below the defined intervention thresholds.

The code underneath said:

```sql
CASE
    WHEN COUNT(*) > 3 THEN 'Immediate Maintenance Required'
    WHEN SUM(downtime_hours) > 100 THEN 'High Risk'
        WHEN SUM(downtime_hours) > 50 THEN 'Medium Risk'
    ELSE 'Low Risk'
END
```

Three disagreements. Eight events in the comment against 3 in the code. 120 hours against 100. Three named tiers in the comment against four in the code, with a Medium Risk tier that the documentation never mentions.

This is worse than either being wrong on its own, because a reader has no way to tell which one was intended. It is also the kind of thing a technical reviewer spots in the first minute, and once found it puts every other number in the file in doubt.

The indentation on the third `WHEN` is misaligned as well. Cosmetic, but in a portfolio piece it reads as carelessness in a query that is already contradicting itself.

### The CASE ladder made one dimension override the other

Bigger than the threshold mismatch, and easier to miss.

Because `COUNT(*) > 3` is evaluated first, an asset with 4 failures and 20 hours of downtime is labelled Immediate Maintenance Required. An asset with 3 failures and 600 hours of downtime fails that first test and falls through to High Risk.

The second asset has lost thirty times more operating time. The ladder ranks it lower. That is not a threshold that needs tuning, it is the wrong structure for the question: a sequential CASE cannot combine two dimensions, it can only let the first one it checks win.

**Fixed** by replacing the ladder with a weighted score. Each asset is percentile ranked on downtime, failure frequency and cost, and the three are combined:

| Dimension | Weight | Reasoning |
|---|---|---|
| Downtime | 50% | Lost hours are lost production. Closest proxy for money the data offers |
| Frequency | 30% | Repeat failures signal an unsolved root cause, which is what maintenance can actually fix |
| Cost | 20% | Real, but partly a consequence of the other two, so the smallest share |

The weights are visible in the code and stated here. Change them and the ranking changes, which is the point. The final output also breaks out each dimension's contribution to the score, so anyone can see why a given asset ranked where it did.

### Two definitions of risky in one file

The original query 7 used more than 5 failures and more than 100 hours. Query 9 used more than 3 failures for what was effectively the same question. Two thresholds for one concept in a single script.

**Fixed** by deriving both from the same percentile logic, so the two queries agree by construction rather than by someone remembering to keep them in step.

### No way to count distinct failures

The maintenance CSV has no event identifier. Once joined to anything, `COUNT(*)` counts join output rows rather than events, and there is no `COUNT(DISTINCT ...)` available to fall back on.

**Fixed** by adding `maintenance_id BIGSERIAL PRIMARY KEY` in the schema. Small change, and it is what makes a correct failure count possible after a join.

### `CREATE VIEW` rather than `CREATE OR REPLACE VIEW`

The script fails on the second run. Anyone reviewing the work will run it more than once.

**Fixed.**

## 5. Insight

**The single most important finding is that the previous risk list was not a risk list.** The view feeding it was duplicating rows, the failure count in the emissions query was a join artefact, and the priority CASE ranked an asset with 20 lost hours above one with 600. A maintenance team following that output would have been sent to the wrong assets while genuinely failing equipment stayed on the Monitor line. That has to be said first, because everything else is an improvement on top of a foundation that was not sound.

**No single dimension identifies the assets that matter.** Cost, frequency and downtime each produce a different ranking, and the assets that matter most are the ones that appear in the upper reaches of all three without necessarily topping any of them. Those assets are invisible to every single dimension list, which is why three separate reports do not add up to a priority list.

**A pass or fail flag throws away most of the information.** Query 3.3 tells you which assets clear both thresholds. It cannot tell you which of them to do first, and it cannot distinguish an asset that just cleared the line from one far beyond it. The continuous score in 3.4 keeps that ordering, which is what makes it usable when capacity runs out halfway down the list.

**Showing the score's components is what makes it trustworthy.** The final output breaks out the downtime, frequency and cost contributions separately. An asset scoring 96 because it never stops failing needs a different response from one scoring 96 because of a single catastrophic outage. A bare score hides that, and hidden scores get ignored the first time someone disagrees with one.

**The emissions and failure relationship should be reported honestly, whichever way it comes out.** Query 3.2 tests whether high emitting assets also fail more often. A visible gradient across the quartiles means something worth investigating. A flat line means the relationship is not there, and that is a real finding. What matters either way is that co-occurrence is not causation, and both are plausibly driven by how hard the asset is worked. Overstating this would be the easiest mistake in the whole project.

**A prioritisation method is only as good as the size of the list it produces.** Query 3.5 exists because a perfectly scored top band of four hundred assets is not a priority list, it is the same problem restated. Checking the band sizes is part of the method, not a footnote to it.

## 6. Recommendation

**Adopt the weighted score from query 3.4 as the standing prioritisation method, and publish the weights.** The weights matter less than the fact that they are visible. A rule everyone can see gets followed and improved. A rule nobody can explain gets overridden.

**Work the Inspect Now band from query 3.6 first, and read the contribution columns before assigning anyone.** High downtime contribution means engineering. High frequency contribution means root cause. High cost contribution with low downtime usually means an asset nearing the end of its economic life, which is a replacement decision rather than a maintenance one.

**Check the band sizes in query 3.5 against actual team capacity and tune the cut offs until the top band is about a week of work.** The 95 and 85 boundaries in the script are starting points, not findings. They should be set by how many assets a team can realistically visit.

**Revisit any decision made from the earlier risk output.** The previous ranking was built on a view that duplicated rows and a CASE that inverted the ordering. Assets deprioritised under it may have been the wrong ones. This is not a comfortable recommendation and it is the correct one.

**Report the emissions and failure comparison as an observation, not a conclusion.** If the gradient in query 3.2 is real, it is worth investigating whether asset utilisation drives both. It is not evidence that emissions cause failures, and presenting it that way would be indefensible the first time someone asked.

**Add a start time to the downtime records.** Right now there is a date and a duration but no time of day. Without it, nobody can say whether an outage hit during production or during a planned shutdown. That distinction would let the downtime weight be replaced by actual barrels lost, which would make the whole score materially better.

**Re-run the scoring monthly.** Percentile based scoring re-ranks automatically as the data refreshes, so this needs no maintenance beyond scheduling it.

## 7. Business Impact

**The maintenance team gets one list instead of three.** Capacity goes to the assets carrying the most combined risk rather than to whichever report was circulated most recently. Same resources, better placed.

**The list can be defended.** Visible weights and per dimension contributions mean the ranking survives being questioned. That is the difference between a method that gets adopted and one that gets quietly ignored.

**Prioritisation stops inverting.** The old CASE could rank an asset with 20 lost hours above one with 600. Correcting it changes which assets get attention, and this is the change with the largest operational consequence in the project.

**Downstream numbers become correct.** The rebuilt view feeds every query here. With the duplication removed, the failure counts, cost totals and emissions averages are real numbers rather than join artefacts.

**Work sizing becomes part of the output.** Query 3.5 shows how many assets each band contains and how much of total downtime each band covers. That turns the analysis into something a supervisor can resource against.

**The method survives the data changing.** Percentile thresholds re-rank as the fleet changes. Fixed thresholds go stale without announcing it, which is the failure mode that quietly retires most internal reports.

## 8. What Was Done

Rebuilt `v_asset_reliability` from scratch. Aggregated all three source tables to one row per asset before joining, so the view now has the grain its name implies and its aggregates are correct.

Documented the three separate problems in the original view: the row multiplication across three tables, the absence of any date condition, and the mismatch between the view's apparent grain and its actual one.

Corrected the emissions query, which had been reporting a join artefact under the column name `failures`, and added a quartile summary so the relationship can be assessed rather than assumed.

Found and documented the contradiction between the priority query's comments and its code: eight events against three, 120 hours against 100, three tiers against four.

Replaced the sequential CASE ladder with a weighted percentile score, after establishing that the ladder let failure count override downtime entirely and could rank a 20 hour asset above a 600 hour one.

Set the weights explicitly, documented the reasoning for each, and broke out every dimension's contribution in the final output so the ranking can be interrogated.

Replaced both hardcoded threshold sets with percentile logic, so the two risk queries agree by construction, and wrote down the trade off that choice involves.

Added a band sizing query so the priority list can be checked against real team capacity before anyone is assigned to it.

Added a final output containing only the top band and only the columns a planner needs.

Added a surrogate primary key to the maintenance table in the schema, which is what makes counting distinct failures after a join possible.

## 9. Tools Used and How They Helped

**PostgreSQL 14.** `PERCENT_RANK`, `PERCENTILE_CONT`, `NTILE` and `MODE() WITHIN GROUP` are all standard here. The whole scoring model stays in SQL with no export step, so there is no second version of the numbers that can drift from the source.

**Common table expressions inside a view.** The fix for the fan-out. Aggregating each source before joining is the correction, and doing it in CTEs inside the view definition means every downstream query inherits the fix automatically rather than having to remember it.

**`PERCENT_RANK()`.** The core of the scoring. It converts each metric to a 0 to 1 position within the fleet, which is what lets dollars, hours and event counts be combined without inventing exchange rates between them. Chosen over `NTILE` here because it is continuous, so the ordering inside each band is preserved.

**`PERCENTILE_CONT()`.** Derives the top 10 percent thresholds in query 3.3 from the data. This is the replacement for the hardcoded numbers, and it is what lets the threshold be stated in English as "the worst 10 percent of the fleet".

**`NTILE(4)`.** Used for the emissions bands, where four readable groups are more useful than a continuous rank. Different job from `PERCENT_RANK`, which is why both appear.

**`MODE() WITHIN GROUP (ORDER BY failure_type)`.** Returns each asset's most common failure type in the view. Doing this with `GROUP BY` and a row number would take an entire extra CTE.

**`CROSS JOIN` against a single row CTE.** Query 3.3 computes both percentile thresholds once and cross joins them onto every row. A correlated subquery would recompute them per row, and putting them in the output makes the thresholds visible to whoever reads the results.

**`CREATE OR REPLACE VIEW`.** The script now re-runs cleanly.

**`BIGSERIAL PRIMARY KEY`.** Added to maintenance in the schema. Enables an accurate event count after any join, which the source data made impossible.

**`NULLIF()` and `NULLS LAST`.** Guard the divisions and keep assets with no emissions data from sorting to the top of query 3.2.

## 10. Results

Six outputs, moving from foundation to action list.

| Query | What it gives you |
|---|---|
| 3.1 | `v_asset_reliability`, rebuilt. One row per asset, correct aggregates, all three tables |
| 3.2 | Emissions against failure activity, at asset level and summarised into quartile bands |
| 3.3 | Assets in the top 10 percent for both failure count and downtime, with the thresholds shown |
| 3.4 | Every asset scored 0 to 100, banded into four actions, with each dimension's contribution |
| 3.5 | How many assets fall in each action band and how much downtime each band covers |
| 3.6 | The Monday morning list: top band only, planner columns only |

The concrete outcomes.

The view now returns one row per asset. Everything reading from it produces real numbers instead of join artefacts, which is the fix the rest of the project depends on.

Query 3.2 reports a real failure count where the original reported a meaningless product of three row counts, and it reports the relationship at group level where it can actually be assessed.

Query 3.4 replaces a CASE ladder that could rank a 20 hour asset above a 600 hour one with a score that weighs all three dimensions and shows its working.

Query 3.5 makes the output resourceable, by answering how much work the recommendation actually implies.

Query 3.6 reduces three thousand assets to a list short enough to print and specific enough to act on.

The percentile approach means all of this re-ranks correctly when the data refreshes, with no thresholds to maintain.

Every result is reproducible from the schema file and the three source CSVs.

---

### Files

```
03-asset-risk-prioritisation/
├── README.md
└── asset_risk_prioritisation.sql
```

### Running it

```bash
psql -d rigwatch -f sql/00_schema.sql
psql -d rigwatch -f 03-asset-risk-prioritisation/asset_risk_prioritisation.sql
```

Uncomment the `\copy` lines in the schema file first, and check the CSVs are in `data/`.
