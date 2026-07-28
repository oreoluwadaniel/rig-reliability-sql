# Failure & Downtime Intelligence System

**A PostgreSQL reliability analytics project that identifies recurring equipment failures, measures operational downtime, isolates the failure modes causing the most disruption, and prioritizes high-production wells where lost operating hours matter most.**

---

## Business Problem

Maintenance spend tells you how much it cost to repair an asset.

It does not tell you how much the failure cost the operation.

A relatively inexpensive component can stop production for days. A costly overhaul may happen during a planned maintenance window with limited operational impact.

That means maintenance cost alone is a poor measure of reliability.

The more important questions are:

> **What keeps breaking, how often does it happen, how long does each failure keep the asset offline, and where should reliability teams intervene first?**

There is another distinction that matters just as much.

Consider two assets that each accumulated 100 hours of downtime.

```text
Asset A
20 failures
5 hours average downtime

Asset B
1 failure
100 hours downtime
```

Both lost the same number of hours.

They do not have the same reliability problem.

Asset A suggests a recurring fault that may never have been eliminated at root cause.

Asset B suggests a severe outage where repair complexity, parts availability, or maintenance planning may be the bigger issue.

A single downtime total hides that distinction.

This project builds a reliability analysis that separates:

* How often assets fail
* How severe those failures are
* Which failure modes create the most downtime
* Where downtime is concentrated across the fleet
* Which high-production wells also carry high downtime exposure
* Whether reliability is improving or deteriorating over time

The result is a system for deciding **where engineering and maintenance attention can recover the most operating availability.**

---

# Business Value

The analysis moves maintenance reporting from:

> **How much did we spend fixing equipment?**

to:

> **Where are failures disrupting operations, what is driving that disruption, and which problems should we fix first?**

The decision flow is:

```text
MAINTENANCE EVENTS
        |
        v
FAILURE FREQUENCY
        |
        v
FAILURE CADENCE
        |
        +----------------------+
                               |
DOWNTIME ----------------------+
                               |
FAILURE TYPE ------------------+
                               |
                               v
                     RELIABILITY EXPOSURE
                               |
                +--------------+--------------+
                |                             |
                v                             v
        RECURRING FAULTS              SEVERE OUTAGES
                |                             |
                v                             v
        ROOT CAUSE WORK             PLANNING / SPARES
                \                             /
                 \                           /
                  +------------+------------+
                               |
                               v
                       PRODUCTION EXPOSURE
                               |
                               v
                    MAINTENANCE PRIORITIES
```

Instead of treating every maintenance event as equivalent, the project distinguishes between problems requiring different operational responses.

---

# What the System Answers

The analysis answers eight reliability questions.

### 1. Which assets fail most frequently?

Identify equipment with repeated maintenance events.

### 2. How quickly do failures repeat?

Add time context so six failures over six months are not treated the same as six failures over six years.

### 3. Which assets create the most downtime?

Rank equipment by total operating hours lost.

### 4. Is downtime caused by repeated short failures or isolated major outages?

Measure average downtime per failure and worst individual outage.

### 5. Which failure modes create the most operational disruption?

Rank failure types by total downtime rather than frequency alone.

### 6. Do different asset classes fail differently?

Separate failure patterns across wells, pipelines, and refineries.

### 7. Which high-production wells also suffer heavy downtime?

Combine production importance with reliability exposure.

### 8. Is fleet reliability improving or deteriorating?

Track failure activity and downtime over time.

---

# Data

The project uses two operational datasets.

| Dataset           | Records | Role                                                         |
| ----------------- | ------: | ------------------------------------------------------------ |
| `maintenance.csv` |   3,000 | Failure events, maintenance cost, failure type, and downtime |
| `production.csv`  |   5,000 | Well production and operating readings                       |

---

## Maintenance Data

Each row represents a maintenance event.

Key fields include:

| Field              | Purpose                                 |
| ------------------ | --------------------------------------- |
| `asset_id`         | Identifies the asset and asset class    |
| `maintenance_date` | Date of the maintenance event           |
| `cost_usd`         | Maintenance cost                        |
| `failure_type`     | Recorded failure category               |
| `downtime_hours`   | Duration of lost operating availability |

Asset prefixes identify equipment type:

* `WEL` = Well
* `PIP` = Pipeline
* `REF` = Refinery

---

## Production Data

Production readings contain:

* Oil production
* Gas production
* Water cut
* Pressure
* Temperature

Production records exist for **wells only**.

Pipelines and refineries therefore remain part of the failure and downtime analysis but are excluded from comparisons requiring production volume.

---

# Analytical Framework

The project moves from detection to diagnosis to prioritization.

```text
                FAILURE EVENTS
                      |
                      v
             HOW OFTEN?
            Failure Frequency
                      |
                      v
             HOW QUICKLY AGAIN?
             Failure Cadence
                      |
                      v
              HOW SEVERE?
             Downtime Exposure
                      |
                      v
              WHAT FAILED?
           Failure Mode Analysis
                      |
                      v
              WHERE IS THE
            DOWNTIME CONCENTRATED?
                      |
                      v
             WHAT ASSET TYPE?
                      |
                      v
             HOW MUCH DOES THE
               ASSET PRODUCE?
                      |
                      v
            WHERE SHOULD WE
               INTERVENE?
```

Each analytical layer answers a question raised by the previous one.

---

# Methodology

## Step 1: Measure Failure Frequency With Time Context

A raw failure count is useful but incomplete.

Suppose two assets each recorded six failures.

```text
Asset A
6 failures over 6 years

Asset B
6 failures over 6 months
```

The count is identical.

The reliability signal is not.

The first query therefore calculates:

* Failure count
* First recorded failure
* Most recent failure
* Observation period
* Average days between failures

The average interval provides a practical approximation of failure cadence from the available data.

A shorter interval indicates failures are recurring more rapidly.

---

## Step 2: Measure Downtime Severity

Failure frequency tells us how often equipment breaks.

Downtime tells us how disruptive those failures are.

For each asset, the analysis calculates:

* Total downtime
* Failure count
* Average downtime per failure
* Worst individual outage
* Total downtime expressed in days

This separates two fundamentally different reliability patterns.

### Pattern A: Chronic Repeat Failure

```text
High failure count
+
High total downtime
+
Low average downtime per event
```

The asset repeatedly stops for relatively short periods.

That points toward unresolved recurring failure mechanisms.

### Pattern B: Major Outage Exposure

```text
Lower failure count
+
High total downtime
+
High average downtime per event
```

The asset fails less frequently, but individual failures are severe.

That may point toward repair complexity, spare-part availability, or maintenance planning.

Same total downtime.

Different diagnosis.

Different response.

---

# Step 3: Measure Downtime Concentration

Not every fleet should be managed the same way.

If 15 assets create most of the downtime, a targeted reliability program can materially improve fleet availability.

If downtime is distributed across hundreds of assets, fixing a handful of equipment will not solve the problem.

The project therefore calculates:

* Downtime by asset
* Each asset's share of total downtime
* Running cumulative downtime share

Conceptually:

```text
Assets Ranked by Downtime

Asset 01  ███████████████
Asset 02  ████████████
Asset 03  █████████
Asset 04  ███████
Asset 05  █████
...
```

The cumulative view answers:

> **Is reliability exposure concentrated enough for targeted intervention to work?**

That question should be answered before designing the intervention.

---

# Step 4: Rank Failure Modes by Operational Damage

The most common failure is not automatically the most important failure.

Consider:

```text
Failure Type A
400 occurrences
2 hours average downtime
= 800 downtime hours

Failure Type B
50 occurrences
30 hours average downtime
= 1,500 downtime hours
```

Failure Type A occurs eight times more frequently.

Failure Type B removes almost twice as much operating time.

A frequency-only ranking would prioritize the wrong problem.

The project therefore evaluates each failure type using:

* Number of occurrences
* Total downtime
* Average downtime
* Worst individual outage
* Total maintenance cost
* Share of all failures
* Share of all downtime

The primary ranking is based on **total downtime**.

This shifts the question from:

> What breaks most?

to:

> **What failure mode removes the most operating availability?**

---

# Step 5: Separate Failure Patterns by Asset Class

Wells, pipelines, and refineries are different operating systems.

Combining their failure behavior into one fleet-wide average can hide the patterns that matter within each class.

The analysis therefore breaks failure modes down by:

* Well
* Pipeline
* Refinery

This allows maintenance strategy to move from:

> One reliability program for everything

to:

> **Different reliability interventions for different asset classes.**

If corrosion dominates pipeline downtime but not well downtime, a fleet-wide corrosion initiative would waste resources.

The analysis makes that distinction visible.

---

# Step 6: Compare Downtime With Production

Downtime becomes more economically important when it affects high-output equipment.

The project therefore compares well-level downtime against well production.

But doing this correctly required fixing a structural SQL problem in the original analysis.

---

# SQL Review & Model Corrections

## 1. The Original Production Join Multiplied Rows

The original logic joined maintenance directly to production:

```sql
SELECT
    m.asset_id,
    SUM(m.downtime_hours) AS downtime,
    SUM(p.oil_production_barrels) AS production
FROM maintenance m
LEFT JOIN production p
    ON m.asset_id = p.well_id
GROUP BY m.asset_id;
```

The problem is grain.

Both tables contain multiple records per asset.

Suppose one well has:

```text
4 maintenance events
3 production readings
```

A direct join creates:

```text
4 × 3 = 12 rows
```

The maintenance records repeat across production records.

The production records repeat across maintenance records.

As a result:

* Downtime is inflated
* Production is inflated
* The inflation factor varies by asset

This last point is critical.

The output cannot be corrected by simply dividing every result by the same number.

Each asset has a different combination of maintenance and production records.

The SQL executes successfully.

The output looks plausible.

The numbers are still wrong.

---

## Correction: Aggregate First, Join Second

The corrected architecture is:

```text
MAINTENANCE
     |
     v
Aggregate by Asset
     |
     +--------------------+
                          |
PRODUCTION                |
     |                    |
     v                    |
Aggregate by Well --------+
                          |
                          v
                 ASSET-LEVEL COMPARISON
```

Maintenance is first reduced to one row per asset.

Production is independently reduced to one row per well.

Only then are the summaries joined.

That guarantees each asset contributes its downtime once and its production once.

---

## 2. Production Comparison Included Assets That Do Not Produce Wells Data

Maintenance covers:

* Wells
* Pipelines
* Refineries

Production covers wells only.

Without accounting for this difference, pipelines and refineries appear with:

```text
Production = NULL
```

That could easily be interpreted as poor-producing assets rather than assets for which production data simply does not exist.

The corrected analysis uses the asset ID prefix to identify asset class and restricts production-based comparisons to wells.

Pipelines and refineries remain in the reliability analysis where production data is not required.

---

## 3. Failure Frequency Had No Time Context

The original frequency analysis correctly counted failures.

But it treated:

```text
6 failures in 6 years
```

and:

```text
6 failures in 6 months
```

as equivalent.

The revised query adds:

* First failure date
* Last failure date
* Observation span
* Average interval between failures

An asset with one failure has no failure interval, so the calculation explicitly handles that case instead of attempting to divide by zero.

---

## 4. Failure Types Were Ranked by Frequency Instead of Damage

The original analysis answered:

> Which failure happens most often?

That is useful.

It is not the same as:

> Which failure causes the most operational disruption?

The corrected version adds total downtime and ranks failure modes by damage.

Frequency remains visible, but it no longer determines priority by itself.

---

## 5. Downtime Totals Hid Failure Behavior

The original downtime ranking showed total hours.

That does not distinguish:

```text
20 × 5-hour failures
```

from:

```text
1 × 100-hour failure
```

The corrected analysis adds:

* Average downtime per failure
* Maximum individual downtime
* Failure frequency

The output therefore provides both severity and recurrence.

---

# Step 7: Prioritize Downtime Where Production Is Highest

Not every downtime hour has equal operational significance.

Ten hours lost on a low-output well and ten hours lost on one of the fleet's highest-output wells create different exposure.

The project uses quartile ranking to identify wells that are simultaneously:

* In the highest downtime quartile
* In the highest production quartile

Conceptually:

```text
                     PRODUCTION
                        HIGH
                         |
             +-----------+-----------+
             |                       |
             |   HIGH PRODUCTION     |
             |    LOW DOWNTIME       |
             |                       |
LOW ---------+-----------------------+--------- HIGH
DOWNTIME     |                       |        DOWNTIME
             |                       |
             |    LOW PRODUCTION     |   PRIORITY
             |    HIGH DOWNTIME      |    WELLS
             |                       |
             +-----------+-----------+
                         |
                        LOW
                     PRODUCTION
```

The top-right group is the priority.

These wells combine substantial operational importance with poor reliability performance.

That creates a defensible starting point for intervention.

---

# Step 8: Monitor Reliability Direction

A single downtime total has limited context.

Suppose the fleet lost 20,000 hours.

Is that good?

Bad?

Normal?

Without comparison, nobody knows.

Trend changes the question.

The project tracks by year:

* Failure count
* Total downtime
* Change from prior year

This allows management to ask:

> **Is reliability getting better or worse?**

rather than arguing about whether one isolated number looks high.

---

# Key Insights

## Frequency and Downtime Identify Different Problems

The asset failing most frequently is not necessarily the asset creating the most downtime.

That means one reliability ranking is insufficient.

Frequency highlights chronic recurrence.

Downtime highlights operational disruption.

Both matter.

---

## Failure Shape Is More Useful Than Failure Total

Total downtime says how large the problem is.

Average downtime per failure helps explain what kind of problem it is.

```text
Many short failures
        |
        v
Recurring fault
        |
        v
Root cause investigation
```

versus:

```text
Few long failures
        |
        v
Major outage exposure
        |
        v
Repair planning / spares review
```

That distinction changes the maintenance response.

---

## The Most Common Failure Is Not Necessarily the Most Damaging

Occurrence count measures frequency.

Total downtime measures disruption.

Maintenance programs should not automatically target whichever failure appears most often.

They should understand which failure modes consume the most operating availability.

---

## Reliability Problems Differ by Asset Class

A fleet-wide failure average can hide asset-specific problems.

Wells, pipelines, and refineries should therefore be analyzed separately before designing reliability interventions.

---

## High Downtime Becomes More Important on High-Production Assets

Downtime alone tells you where operating availability is being lost.

Production tells you where that availability matters most.

Combining both provides a more useful prioritization signal than either metric independently.

---

## Reliability Direction Matters More Than an Isolated Total

A large lifetime downtime number is difficult to interpret without context.

A consistent year-over-year increase in downtime is much easier to act on.

Trend turns reliability from an anecdotal maintenance discussion into a measurable operational trajectory.

---

# Recommendations

## 1. Separate Chronic Failures From Major Outages

Do not send both problems through the same maintenance response.

Use failure frequency and average downtime together.

### High frequency + low average downtime

Prioritize root cause analysis.

The issue is recurrence.

### Low frequency + high average downtime

Review:

* Spare availability
* Repair lead times
* Maintenance planning
* Failure response procedures

The issue is outage severity.

---

## 2. Prioritize Failure Modes by Downtime Impact

Use the failure-mode analysis to identify the categories responsible for the largest share of lost operating hours.

Those failure modes are candidates for fleet-wide reliability programs.

Fixing one recurring failure mechanism across many assets can produce more value than repeatedly repairing individual assets after failure.

---

## 3. Build Reliability Programs by Asset Class

Do not apply one maintenance strategy uniformly across wells, pipelines, and refineries.

Use the asset-class breakdown to identify dominant failure mechanisms within each equipment group.

That allows targeted engineering programs instead of generic fleet-wide actions.

---

## 4. Start With High-Downtime, High-Production Wells

The cross-ranking provides the strongest initial intervention list available from this dataset.

These wells combine:

* High operating importance
* High downtime exposure

Recovering one hour of availability on these assets has greater operational significance than recovering the same hour on a lower-output well.

---

## 5. Track Reliability Trend Regularly

Failure frequency and downtime should be reviewed over time rather than treated as one-off portfolio statistics.

The year-over-year analysis can become a recurring management KPI showing whether reliability interventions are actually improving fleet performance.

---

## 6. Improve Downtime Data Capture

The current dataset records:

* Failure date
* Downtime duration

but not exact outage start and end timestamps.

That means the analysis cannot determine whether downtime occurred during:

* Active production
* Planned shutdown
* Low-utilization periods

Capturing outage timestamps would allow the next version of the system to distinguish:

```text
Downtime Hours
```

from:

```text
Production Hours Actually Lost
```

Those are not the same metric.

---

# Business Impact

## Maintenance Effort Becomes More Targeted

The system separates recurring failures from severe outages so each can be routed toward the appropriate intervention.

---

## Reliability Engineering Can Focus on Failure Modes, Not Just Assets

Instead of repeatedly repairing individual equipment, the business can identify failure mechanisms responsible for substantial fleet-wide downtime and attack them systematically.

---

## High-Value Operating Time Gets Priority

Combining production and downtime identifies wells where reliability improvements are most operationally significant.

This gives maintenance teams a better starting point when capacity is limited.

---

## Downtime Becomes a Management Metric

Maintenance spend answers:

> How much did repairs cost?

Downtime answers:

> How much operating availability did failures remove?

The project brings that second question into the reporting layer.

---

## Reliability Performance Becomes Measurable Over Time

Year-over-year tracking allows management to determine whether maintenance strategy is improving fleet reliability or whether disruption continues to grow.

---

## Production Comparisons Become Trustworthy

The corrected aggregate-then-join architecture removes the row multiplication that distorted the original production-versus-downtime analysis.

The resulting comparison now reflects actual asset-level totals rather than artifacts created by SQL joins.

---

# What Was Built

The completed analysis includes:

* Failure Frequency Analysis
* Failure Cadence Analysis
* Downtime Exposure Analysis
* Downtime Concentration Analysis
* Failure Mode Severity Analysis
* Asset-Class Failure Analysis
* Production vs. Downtime Comparison
* High-Production / High-Downtime Well Prioritization
* Year-over-Year Reliability Monitoring

The project also corrected:

* Many-to-many join fan-out
* Invalid production comparisons for non-well assets
* Failure counts without time context
* Frequency-only failure-mode ranking
* Downtime reporting without severity context

---

# Tools & SQL Techniques

### PostgreSQL 14

Used for the complete reliability analysis.

### Common Table Expressions

Used to pre-aggregate maintenance and production independently before joining them.

This eliminates row multiplication and makes the grain of each calculation explicit.

### Window Functions

Used for:

* Percentage contribution
* Cumulative downtime share
* Asset-class percentages
* Year-over-year comparison

### `SUM() OVER()`

Calculates each asset or failure mode's share of fleet-wide totals.

### Running `SUM() OVER()`

Builds cumulative downtime concentration.

### `LAG()`

Compares annual reliability performance with the previous year.

### `NTILE(4)`

Segments wells into production and downtime quartiles so different measurement scales can be compared without forcing them into arbitrary units.

### PostgreSQL Date Arithmetic

Measures elapsed days between the first and last recorded failure.

### `CASE`

Handles assets where a failure interval cannot be calculated because only one event exists.

### `NULLIF()`

Protects division calculations from zero denominators.

### Explicit `NUMERIC` Casting

Prevents integer division from discarding decimal precision.

---

# Results

The SQL workflow produces eight operational outputs.

| Output                           | Decision Supported                                                                       |
| -------------------------------- | ---------------------------------------------------------------------------------------- |
| Failure Frequency & Cadence      | Identifies repeat offenders and how quickly failures recur                               |
| Downtime Severity                | Shows total, average, and worst-case outage exposure                                     |
| Downtime Concentration           | Determines whether reliability exposure is concentrated enough for targeted intervention |
| Failure Mode Impact              | Identifies fault categories responsible for the most operating disruption                |
| Asset-Class Failure Analysis     | Shows how reliability problems differ across wells, pipelines, and refineries            |
| Production & Downtime Comparison | Connects well reliability with production activity using corrected asset-level totals    |
| High-Value Reliability Shortlist | Identifies wells combining high production with high downtime                            |
| Reliability Trend                | Shows whether failures and downtime are improving or deteriorating over time             |

The key output is not simply a list of assets that failed.

It is a diagnostic path from:

```text
WHAT FAILED?
      |
      v
HOW OFTEN?
      |
      v
HOW LONG?
      |
      v
WHY?
      |
      v
WHERE IS THE DAMAGE CONCENTRATED?
      |
      v
WHICH ASSETS MATTER MOST OPERATIONALLY?
      |
      v
WHAT SHOULD MAINTENANCE ADDRESS FIRST?
```

That turns 3,000 maintenance events into a structured reliability decision process rather than another historical maintenance report.

---

# Data Limitations

This project measures **observed reliability and downtime exposure**.

It does not predict future equipment failures.

Two limitations are particularly important.

### Production coverage is limited to wells

Pipelines and refineries remain part of the reliability analysis, but production-based prioritization applies only to wells.

### Downtime is not timestamp-aligned with production

The dataset records downtime duration and date but not exact outage start and end times.

The analysis can therefore say:

> This well accumulated 90 hours of downtime.

It cannot claim:

> This well lost exactly X barrels because of those 90 hours.

Making that claim would require time-aligned production and outage data.

With those fields, the system could be extended from **downtime exposure** toward **production-loss estimation and economic reliability prioritization**.

---

# Repository Structure

```text
02-failure-downtime-analysis/
├── README.md
└── failure_downtime_analysis.sql
```

---

# Running the Project

Requires PostgreSQL 12 or later. Developed against PostgreSQL 14.

```bash
psql -d rigwatch -f sql/00_schema.sql
psql -d rigwatch -f 02-failure-downtime-analysis/failure_downtime_analysis.sql
```

Before running the schema, uncomment the required `\copy` statements and confirm the source CSV files are available in the repository's `data/` directory.
