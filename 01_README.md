# Project 01: Maintenance Cost Exposure and Spend Efficiency

**Where is the maintenance budget going, and is it going to assets that earn their keep?**

Script: [`maintenance_cost_analysis.sql`](maintenance_cost_analysis.sql)
Database: PostgreSQL 14
Setup required: run [`../sql/00_schema.sql`](../sql/00_schema.sql) first

---

## 1. Business Problem

A maintenance budget gets approved once a year and spent three thousand times. By the time anyone looks at the total, the money is gone and nobody can say what it bought.

The specific problem here is that maintenance spend is recorded at event level. Every repair has a cost, a date and an asset. What nobody has is the view that sits above that: which assets are quietly absorbing a disproportionate share of the budget year after year, and whether those assets are worth the money.

That second half is the part that usually gets skipped. It is easy to rank assets by cost and hand over a list of the ten most expensive. It is more useful, and more uncomfortable, to put that spend next to what the asset actually produced. An expensive well that produces heavily is doing its job. An expensive well that produces very little is a candidate for shutting in, and that decision is worth far more than any efficiency saving on the repair itself.

So the question the business is really asking is not "what did we spend". It is "which of these assets should we stop spending on".

## 2. Data Source

Two tables out of the ten CSV files in this dataset.

**`maintenance.csv`** carries 3,000 maintenance events. Each row is one repair with the asset it was performed on, the date, the cost in US dollars, the type of failure, and how many hours the asset was out of service.

| Column | What it holds |
|---|---|
| `asset_id` | The asset. Prefix says what kind: WEL, PIP or REF |
| `maintenance_date` | When the work happened |
| `cost_usd` | What it cost |
| `failure_type` | Category of fault, for example Pump Failure or Corrosion |
| `downtime_hours` | Hours out of service |

**`production.csv`** carries 5,000 production readings, one per well per date, with oil and gas volumes plus the operating conditions at the time.

| Column | What it holds |
|---|---|
| `well_id` | The well |
| `production_date` | Date of the reading |
| `oil_production_barrels` | Barrels of oil |
| `gas_production_mcf` | Thousand cubic feet of gas |
| `water_cut_pct`, `pressure_psi`, `temperature_c` | Operating conditions |

The data spans multiple years and covers wells, pipelines and refineries across several operators and countries.

**One thing to know before reading any output from this project.** The maintenance table covers all three asset types. The production table only covers wells. Any comparison of spend against barrels can therefore only be made for wells. That is not a flaw in the data, it just means the analysis has to be explicit about which assets it is talking about, and this one is.

## 3. Methodology

The work went in this order.

First, get the totals right. Spend per asset, event count, average cost per event. This is the base layer and everything else sits on it, so it has to be exact before anything gets built on top.

Second, work out whether the totals matter. A ranked list is only actionable if the top of it is where the money is. So the second step calculates each asset's share of total spend and a running cumulative share. If the top fifty assets account for half the budget, there is a shortlist worth managing. If it takes eight hundred assets to reach half, there is no shortlist and the answer has to be a policy change instead. This distinction decides what kind of recommendation is even possible, so it comes before the recommendation, not after.

Third, roll the same spend up to asset type. Individual asset numbers are for maintenance planners. Someone who owns a budget needs to know whether the problem is in the wells, the pipelines or the refineries.

Fourth, put spend next to production. This is where the analysis stops describing and starts judging. Cost per barrel is the metric that turns a maintenance number into a commercial one.

Fifth, band the result. A cost per barrel figure on its own leaves the reader to work out what counts as bad. The bands do that work, and they are set from the distribution of the data rather than from a fixed number, so they stay meaningful when the data refreshes.

Sixth, add time. Nothing in the original script looked at trend, which meant a budget that had doubled over the period would have been invisible. Direction is usually more persuasive than position.

## 4. Analysis and Error Check

I reviewed the original script line by line before rewriting anything. These are the problems I found in the two queries that belong to this project, and what I did about each.

### Money stored as text and cast to FLOAT

The original wrote `SUM(CAST(cost_usd AS FLOAT))`. Two things wrong with that.

The cast tells you the column was loaded as text, which means the database was never enforcing that these values are numbers. Anything malformed in the source file would have loaded silently and then failed or misbehaved at query time.

FLOAT is a binary floating point type. It cannot represent most decimal fractions exactly. Summing thousands of currency values in FLOAT accumulates small rounding errors, and while the drift is tiny, it means two people running the same query on the same data can print slightly different totals. That is a bad property for a number that goes in front of a finance team.

**Fixed** by declaring `cost_usd` as `NUMERIC(14,2)` in the schema and removing every cast.

### The join fan-out in the spend versus production query

This was the real bug. The original was:

```sql
SELECT m.asset_id,
       SUM(m.cost_usd) AS maintenance_cost,
       SUM(p.oil_production_barrels) AS production
FROM maintenance m
LEFT JOIN production p ON m.asset_id = p.well_id
GROUP BY m.asset_id;
```

Both tables hold multiple rows per asset. The join runs before the aggregation, so it produces one row for every possible pairing of a maintenance event with a production reading. An asset with 4 maintenance events and 3 production readings comes out of that join as 12 rows.

The consequence is that `SUM(m.cost_usd)` counts each cost three times and `SUM(p.oil_production_barrels)` counts each production figure four times. Both totals are inflated, and the multiplier is different for every asset depending on how many rows it happens to have on each side. You cannot even correct for it after the fact.

What makes this one dangerous rather than just wrong is that the output looks completely reasonable. There are no nulls, no errors, no obviously silly numbers. The totals are simply too big, by an amount that varies per row.

**Fixed** by aggregating each table to one row per asset in a CTE, then joining the two summaries. Each asset now contributes its cost once and its production once.

### The same query missed the asset type problem

`maintenance.asset_id` contains WEL, PIP and REF assets. `production.well_id` contains only wells. The LEFT JOIN therefore returns NULL production for every pipeline and every refinery.

Sitting in the same output as the wells, those assets read as "high spend, no production", which is a damning description of something that is behaving exactly as designed. A refinery does not produce barrels because it is a refinery.

**Fixed** two ways. An `asset_class()` helper function labels every asset from its ID prefix, and the cost per barrel query filters to wells only. Pipelines and refineries get their own summary in query 1.3 where the comparison is like for like.

### No table definitions at all

The original script started with a `CREATE VIEW`. There were no `CREATE TABLE` statements, no data types, no keys and no load instructions. It assumed the tables already existed somewhere.

For a portfolio piece that is a real gap, because nobody can run it. It also hid the FLOAT problem, since the column types were never stated anywhere.

**Fixed** with a full `00_schema.sql` containing table definitions, load commands, indexes and a set of sanity checks to run after loading.

### `CREATE VIEW` instead of `CREATE OR REPLACE VIEW`

Small thing, but it means the script fails on the second run. Anyone reviewing your work will run it more than once.

**Fixed** in the schema file, which drops cleanly, and in project 03 which uses `CREATE OR REPLACE VIEW`.

### What I checked and found nothing wrong with

The two cost queries in the original were logically correct in their grouping. `SUM(cost_usd) GROUP BY asset_id` does exactly what it claims. I have kept that logic and added context columns around it rather than changing it.

## 5. Insight

Three things come out of this analysis, and they build on each other.

**Total spend is the wrong headline.** The number that matters is how concentrated it is. The cumulative share column in query 1.2 answers a question the original script could not: is there a shortlist here at all? Read down that column to where it crosses 50 percent, and the count of assets above that line is the actual size of the problem. Everything below the line is noise that no amount of targeted intervention will fix.

**Cost per event and event count tell different stories, and the difference is the diagnosis.** An asset with high total spend across two events had a major overhaul, which is normal and expected. An asset with the same spend across twenty events has a fault nobody has traced to root cause. The original ranking could not tell these apart because it reported only the total. Query 1.1 puts the count and the average next to the total precisely so the reader can separate them at a glance.

**Spend only becomes meaningful next to output.** Cost per barrel reorders the list completely compared to raw cost, and it reorders it in the direction the business cares about. The most expensive well in the field is often a heavy producer where the spend is justified. The wells that should worry you sit in the middle of the cost ranking and near the bottom of the production ranking. Those never appear on a list sorted by cost, which is why the original analysis would have pointed the maintenance team at the wrong assets.

There is also a fourth finding that comes from the error check rather than the data. **The original comparison of spend against production was returning inflated figures for both sides.** Any decision taken from that output was taken on numbers that were wrong. That matters more than any single insight below it, because it means the previous conclusions need revisiting, not just extending.

## 6. Recommendation

**Manage the top of the cost curve as a named list, not as a budget line.** Take the assets above the 50 percent cumulative threshold from query 1.2 and give each one an owner. This works only if the count is small enough to be real. Query 1.2 tells you whether it is.

**Sort the shortlist by cost per barrel, not by cost.** The maintenance team should be reviewing the worst quarter from query 1.6, not the top of query 1.1. These are different sets of assets and only one of them represents money being wasted.

**Split the response by what the numbers say about the fault.** High spend concentrated in a few large events points at planning and spares. High spend spread across many small events points at root cause. Same budget impact, completely different fix, and query 1.1 tells you which one you are looking at before anyone visits the site.

**Resolve the wells in query 1.5 before the next budget cycle.** These are wells with maintenance spend and no production record at all. Either they are shut in and still being maintained, which is a decision someone should be making deliberately, or the production data has a gap, which undermines every cost per barrel figure in the analysis. Both need answering and they need different people to answer them.

**Set the maintenance budget from the trend in query 1.7, not from last year plus inflation.** If spend is rising year on year, the flat budget is already a decision to defer work, and it should be made openly rather than by default.

## 7. Business Impact

The change this analysis makes is in where maintenance money goes, not in how much of it there is.

**Attention moves to the assets that deserve it.** Prioritising by cost per barrel instead of raw cost redirects the review effort towards genuinely inefficient assets. Some of the highest cost assets turn out to be fine and drop off the list. Some mid ranking ones turn out to be the real problem and move up it. The budget does not change and the outcome does.

**Shut in candidates become visible.** A well with meaningful maintenance spend and negligible production is a well that costs more to keep than it returns. Nobody spots these by looking at a cost ranking, because they are not at the top of it. Query 1.6 puts them in the worst efficiency band by construction. This is usually the single largest saving available, because stopping spend entirely beats reducing it.

**Decisions stop being made on inflated numbers.** The fan-out fix is not a refinement. The previous spend against production comparison was returning wrong totals on both sides, so any conclusion drawn from it was unreliable. Correcting it restores the ability to make the comparison at all.

**Budget conversations get a direction.** Query 1.7 turns "we spent this much" into "we are spending this much more each year". That is a different conversation and a more productive one.

**Someone else can check the work.** The schema file means a reviewer can load the same data and reproduce every number. Analysis nobody can verify tends not to survive its first challenge.

## 8. What Was Done

Reviewed the two cost related queries in the original script line by line and documented every problem found, including the one that made the output wrong rather than merely incomplete.

Wrote a full PostgreSQL schema with proper types, a primary key on maintenance, indexes on the join columns, load commands for the CSVs, and a set of post load sanity checks.

Rebuilt the spend versus production query using pre-aggregated CTEs to remove the join fan-out, and scoped it to wells so the comparison is valid.

Added an `asset_class()` helper so wells, pipelines and refineries are never silently compared against each other.

Extended the analysis with four things the original did not have: cost concentration with a cumulative share, an asset type rollup, cost per barrel with data driven efficiency bands, and a year on year trend.

Separated out the wells that have maintenance spend but no production record, rather than letting them sit in the main output as NULLs.

Commented the script so each query explains what it answers and, where relevant, what was wrong with the earlier version.

## 9. Tools Used and How They Helped

**PostgreSQL 14.** Free, and its window function support is what makes the concentration and banding analysis possible in plain SQL rather than needing an export to Python.

**Common table expressions.** The single most important technique in this script. Pre-aggregating each table before joining is what fixes the fan-out, and CTEs make that fix readable. The same correction written with subqueries would work and would be much harder for a reviewer to follow, which matters when the point of the code is partly to show your reasoning.

**Window functions.** `SUM() OVER ()` gives each row the grand total without a second pass, which is how the percentage of total column works. `SUM() OVER (ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)` builds the running cumulative share. `LAG()` gives the year on year comparison. All three would otherwise need self joins.

**`NTILE(4)`.** Used for the efficiency bands. Chosen over hardcoded thresholds deliberately: a fixed cut off like 50 dollars a barrel is correct only until costs or volumes move, and then it stops being correct without anyone noticing. Percentile bands describe an asset's position in the fleet, which stays meaningful.

**`NULLIF()`.** Guards every division. Cost per barrel on a well with zero recorded production is a divide by zero, and `NULLIF` turns it into a NULL that can be filtered rather than an error that stops the script.

**`NOT EXISTS`.** Used to isolate wells missing from production. Clearer in intent than a LEFT JOIN with an IS NULL filter, and it does not risk pulling duplicate rows.

**`NUMERIC` over `FLOAT`.** Exact decimal arithmetic for currency. The difference is invisible on one row and matters across three thousand.

**A SQL helper function.** `asset_class()` puts the WEL, PIP and REF logic in one place. If a fourth asset type appears, it changes once instead of in every query.

## 10. Results

The script produces seven outputs, each answering a specific question.

| Query | What it gives you |
|---|---|
| 1.1 | Every asset with total spend, event count, average and largest event, and the date range it covers |
| 1.2 | The same assets ranked, with each one's share of total spend and a running cumulative share |
| 1.3 | Spend rolled up to wells, pipelines and refineries with per asset averages |
| 1.4 | Wells with maintenance spend, downtime and production side by side, plus cost per barrel, with the double counting removed |
| 1.5 | Wells with spend but no production record, isolated for follow up |
| 1.6 | Wells sorted by cost per barrel and banded into four efficiency groups |
| 1.7 | Spend, events and downtime by year with change on the previous year |

The concrete outcomes.

Query 1.4 now returns correct figures. The previous version was inflating both maintenance cost and production volume by a multiple that varied per asset. That is the difference between an analysis you can act on and one you cannot.

Query 1.2 answers whether a targeted programme can work at all, before anyone spends time designing one.

Query 1.6 produces a shortlist ordered by commercial efficiency rather than by raw spend. These are not the same assets, and only one of the two lists points at money being wasted.

Query 1.5 surfaces a data quality question that was invisible before and that affects the reliability of everything else in the project.

The schema file means every number here is reproducible by anyone who clones the repository.

---

### Files

```
01-maintenance-cost-analysis/
├── README.md
└── maintenance_cost_analysis.sql
```

### Running it

```bash
psql -d rigwatch -f sql/00_schema.sql
psql -d rigwatch -f 01-maintenance-cost-analysis/maintenance_cost_analysis.sql
```

Uncomment the `\copy` lines in the schema file first, and check the CSVs are in `data/`.
