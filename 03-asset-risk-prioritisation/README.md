# Asset Risk Scoring & Maintenance Prioritization System

**A PostgreSQL reliability analytics system that ranks assets by operational risk and converts 3,000 maintenance records into a focused, capacity-aware maintenance worklist.**

---

## Business Problem

Maintenance teams rarely have enough people, time, or budget to inspect every asset showing signs of trouble.

The real question is not:

> Which assets have failed?

It is:

> **Which assets should the maintenance team inspect first, and why?**

That distinction matters.

An asset can fail frequently without causing much downtime. Another can fail only a few times but shut operations down for hundreds of hours. A third may not lead either list but consistently combine high maintenance cost, repeated failures, and significant downtime.

Looking at those metrics separately produces different priority lists.

That creates an operational problem:

```text
Highest Maintenance Cost
          |
Highest Failure Frequency
          |
Highest Downtime
          |
          v
   THREE DIFFERENT
    PRIORITY LISTS
          |
          v
   Which one does the
   maintenance team use?
```

This project solves that problem by combining three dimensions of asset reliability:

* Downtime exposure
* Failure frequency
* Maintenance cost

into a single **0 to 100 Asset Risk Score**.

The output is not another maintenance dashboard.

It is an ordered work queue showing **which assets require attention first, what is driving their risk, and how much work each priority band creates for the maintenance team.**

---

# Business Value

The system turns maintenance data into a resource-allocation decision.

Instead of giving a maintenance manager three separate reports and expecting them to reconcile the results manually, the project creates one workflow:

```text
MAINTENANCE HISTORY
        |
        v
FAILURE FREQUENCY
        |
        +-------------------+
                            |
DOWNTIME ------------------+
                            |
MAINTENANCE COST ----------+
                            |
                            v
                    ASSET RISK SCORE
                         0 - 100
                            |
             +--------------+--------------+
             |              |              |
             v              v              v
         INSPECT         SCHEDULE        MONITOR
           NOW           MAINTENANCE
             |
             v
      WEEKLY WORKLIST
```

This gives maintenance planners a consistent method for deciding where limited engineering capacity should go first.

---

# What the System Answers

The analysis is built around six operational questions.

### 1. Which assets fail most often?

Identify equipment with recurring maintenance events that may indicate unresolved reliability problems.

### 2. Which assets create the most downtime?

Separate frequent minor problems from failures that materially affect operating availability.

### 3. Which assets consume the most maintenance spend?

Identify equipment absorbing disproportionate maintenance resources.

### 4. Which assets are severe across multiple dimensions?

Find assets sitting near the top of both failure frequency and downtime rather than relying on one metric alone.

### 5. What should the maintenance team prioritize?

Combine downtime, frequency, and cost into a single ranked Asset Risk Score.

### 6. Is the resulting workload realistic?

Measure how many assets fall into each priority band before handing the list to operations.

That final question is important.

A model that labels 400 assets as urgent has not prioritized anything.

---

# Data

The project uses three operational datasets.

| Dataset           | Records | Business Role                                        |
| ----------------- | ------: | ---------------------------------------------------- |
| `maintenance.csv` |   3,000 | Maintenance events, failure type, cost, and downtime |
| `production.csv`  |   5,000 | Well production and operating readings               |
| `emissions.csv`   |   3,000 | CO2, methane leakage, and energy consumption         |

These sources are combined into an asset-level reliability model.

---

## Maintenance Data

Contains:

* Asset ID
* Maintenance date
* Failure type
* Maintenance cost
* Downtime hours

This is the primary source for reliability scoring.

---

## Production Data

Contains well-level operational readings including:

* Oil production
* Gas production
* Water cut
* Pressure
* Temperature

Production data covers **wells only**.

Pipelines and refineries therefore carry `NULL` production values by design.

They are not interpreted as zero-production assets.

---

## Emissions Data

Contains:

* CO2 emissions
* Methane leakage
* Energy consumption

Unlike production, emissions data covers wells, pipelines, and refineries.

This allows environmental performance to be compared against reliability patterns across the broader asset base.

---

# Analytical Architecture

A central requirement of the project was ensuring that:

> **One row in the reliability layer represents one asset.**

Each source is therefore aggregated independently before the datasets are joined.

```text
MAINTENANCE
    |
    v
Aggregate by Asset
    |
    +------------------+
                       |
PRODUCTION             |
    |                  |
    v                  |
Aggregate by Asset ----+----> v_asset_reliability
                       |             |
EMISSIONS              |             |
    |                  |             v
    v                  |       Reliability Analysis
Aggregate by Asset ----+             |
                                     v
                              Percentile Scoring
                                     |
                                     v
                              Priority Bands
                                     |
                                     v
                              Maintenance Worklist
```

This architecture prevents one-to-many joins from multiplying asset records and corrupting downstream metrics.

---

# Methodology

## Step 1: Build a Reliable Asset-Level Foundation

Maintenance, production, and emissions all contain multiple records per asset.

Joining them directly would create combinations of those records rather than one clean asset summary.

The project therefore aggregates each dataset to asset level first and only then joins them into:

`v_asset_reliability`

The resulting view contains one row per asset with:

* Failure count
* Total downtime
* Maintenance cost
* Most common failure type
* Production metrics where applicable
* Emissions metrics

Every downstream analysis inherits the same grain.

---

## Step 2: Examine Failure and Emissions Behavior

The project tests whether higher-emitting assets also show higher failure activity.

Rather than relying only on individual asset rows, assets are grouped into emissions quartiles.

That makes it easier to ask:

> Do failure levels materially change as emissions increase?

If failure activity rises across the quartiles, there is a relationship worth investigating.

If the pattern remains flat, the data does not support that relationship.

Either result is useful.

The analysis deliberately does **not** claim that emissions cause failures.

Both may instead be influenced by another factor such as asset utilization.

---

## Step 3: Identify Multi-Dimensional Reliability Risk

The next layer isolates assets in the **top 10% of the fleet for both failure frequency and downtime**.

This identifies equipment that is not simply problematic on one dimension.

It is problematic on both.

Thresholds are derived using fleet percentiles rather than arbitrary fixed numbers.

---

# Why Percentiles Instead of Fixed Thresholds?

A rule such as:

```text
More than 5 failures = High Risk
```

looks simple, but it creates two problems.

First, someone eventually asks:

> Why five?

If the number has no operational basis, the rule is difficult to defend.

Second, the threshold becomes stale as fleet behavior changes.

If average failure frequency rises from two events to six, a five-failure threshold no longer represents exceptional performance.

Percentiles answer a different question:

> **Where does this asset sit relative to the rest of the fleet?**

For example:

```text
Top 10% Failure Frequency
+
Top 10% Downtime
=
Severe Relative Reliability Exposure
```

As fleet performance changes, the ranking recalculates automatically.

### Trade-Off

Percentiles are appropriate here because this is a **work prioritization system**.

They would not be appropriate for a hard safety limit.

If equipment must never exceed a defined pressure, temperature, or regulatory threshold, that limit should remain absolute regardless of how the rest of the fleet performs.

---

# Asset Risk Score

Filtering assets into risky and not risky still leaves one problem:

**Which risky asset comes first?**

The project therefore scores every asset continuously.

Three dimensions contribute to the final score:

| Risk Dimension    | Weight | Business Reason                                                  |
| ----------------- | -----: | ---------------------------------------------------------------- |
| Downtime          |    50% | Closest available measure of lost operational availability       |
| Failure Frequency |    30% | Repeated failures indicate unresolved reliability problems       |
| Maintenance Cost  |    20% | Measures financial resources already being consumed by the asset |

Each metric is percentile-ranked from 0 to 1 before weighting.

Conceptually:

```text
Asset Risk Score =
    Downtime Rank × 50%
  + Failure Rank  × 30%
  + Cost Rank     × 20%
```

The result is converted to a **0 to 100 score**.

---

# Why Normalize Before Combining?

Downtime is measured in hours.

Maintenance spend is measured in dollars.

Failure frequency is measured in events.

Adding the raw numbers together would be meaningless.

For example:

```text
400 downtime hours
+ $30,000 maintenance cost
+ 12 failures
```

does not produce a meaningful risk value.

Percentile ranking converts each metric into its **relative position within the fleet** before they are combined.

This allows different units to contribute to one score without pretending an hour of downtime is mathematically equivalent to a dollar of maintenance spend.

---

# Explainable Prioritization

The final output does not return only a risk score.

It also shows how each dimension contributed to that score.

That matters operationally.

Two assets can both score 92 while representing completely different maintenance problems.

```text
ASSET A
Risk Score: 92

Downtime Contribution: High
Failure Contribution: Moderate
Cost Contribution: Moderate

Likely issue:
Large operational disruption
```

versus:

```text
ASSET B
Risk Score: 92

Downtime Contribution: Moderate
Failure Contribution: High
Cost Contribution: High

Likely issue:
Repeated expensive maintenance
```

The same score can therefore lead to different interventions.

The score prioritizes the asset.

The component metrics help explain **why it was prioritized**.

---

# Maintenance Priority Bands

The continuous risk score is converted into action-oriented maintenance bands.

Conceptually:

```text
0 -------------------------------------------- 100

LOWER RISK                            HIGHER RISK

Monitor     Planned Work     Schedule     Inspect Now
```

The highest band becomes the maintenance team's immediate worklist.

The exact band boundaries are treated as operating parameters rather than universal truths.

They should be calibrated against actual maintenance capacity.

---

# Capacity-Aware Prioritization

A technically correct priority model can still fail operationally.

If the system produces:

> 437 assets requiring immediate inspection

but the maintenance team can inspect 25 assets per week, the output is not actionable.

The project therefore measures:

* Number of assets per priority band
* Share of total downtime represented by each band
* Size of the highest-priority work queue

This allows management to align the model with actual field capacity.

The target is not:

> **Find every risky asset.**

The target is:

> **Identify the highest-value maintenance work that available capacity can realistically execute.**

---

# SQL Review & Model Corrections

Before building the final scoring model, the original SQL was reviewed against the structure of the source data.

Several issues materially affected the original ranking.

---

## 1. Three-Way Join Fan-Out

The original reliability view joined maintenance, production, and emissions directly at row level.

All three contain multiple observations per asset.

That creates multiplication.

For an asset with:

```text
4 maintenance events
3 production readings
2 emissions readings
```

a direct join can produce:

```text
4 × 3 × 2 = 24 rows
```

Those 24 rows do not represent 24 real events.

They are combinations created by the join.

Any downstream:

* `COUNT()`
* `SUM()`
* `AVG()`

can therefore become distorted.

### Correction

Each dataset is aggregated to one row per asset **before** joining.

The reliability view now has the grain its name implies:

> **One asset = one row**

---

## 2. Failure Count Was Measuring Join Output

The original emissions analysis used:

`COUNT(*) AS failures`

against the multiplied reliability view.

That did not count failures.

It counted rows produced by the join.

A metric labelled `failures` therefore contained an operationally meaningless number.

The rebuilt asset-level view corrects the issue at the source.

---

## 3. Documentation and Scoring Logic Disagreed

The original documentation described one set of thresholds while the SQL implemented another.

Examples included:

* More than 8 events in the documentation vs. more than 3 in the SQL
* More than 120 downtime hours vs. more than 100
* Three documented risk tiers vs. four implemented tiers

For a prioritization system, this creates a governance problem.

If the maintenance manager cannot determine which rule is authoritative, the ranking cannot be trusted.

The replacement scoring method removes the conflicting threshold definitions.

---

## 4. Sequential Risk Rules Could Invert Priority

The original risk classification evaluated failure count before downtime.

That meant an asset with:

```text
4 failures
20 downtime hours
```

could receive a higher priority than one with:

```text
3 failures
600 downtime hours
```

because the first asset triggered the first `CASE` condition.

The second asset lost **30 times more operating time** but could still receive the lower classification.

That is not a threshold problem.

It is a scoring-architecture problem.

### Correction

The sequential rule was replaced with a weighted score that evaluates all three dimensions simultaneously.

---

## 5. Multiple Definitions of "Risky"

Different sections of the original analysis used different failure thresholds for effectively the same concept.

The corrected model derives risk positions from a shared percentile framework so the definitions remain consistent across queries.

---

## 6. Maintenance Events Had No Unique Identifier

The original maintenance source did not provide a unique event ID.

Once maintenance records are joined to another one-to-many table, `COUNT(*)` can no longer safely represent the number of real maintenance events.

The schema adds:

`maintenance_id BIGSERIAL PRIMARY KEY`

This creates an identifiable maintenance-event grain and makes event counting reliable after joins.

---

# Key Insights

## One Metric Is Not Enough

Maintenance cost, downtime, and failure frequency identify different assets.

An asset does not need to rank first on any one measure to be one of the fleet's biggest reliability problems.

The highest-priority equipment is often the equipment that performs badly across several dimensions simultaneously.

That is why the combined score is more useful than three independent rankings.

---

## Downtime Deserves the Largest Weight

Failure count tells you how often something breaks.

Maintenance cost tells you how expensive it has been to maintain.

Downtime tells you how much operational availability has already been lost.

With the available data, downtime is therefore the closest proxy for business interruption.

That is why it receives 50% of the score.

---

## Repeated Failures Point Toward Root Cause Problems

An asset repeatedly returning to maintenance may indicate that previous work treated symptoms rather than the underlying failure mechanism.

A high frequency contribution should therefore trigger more than another routine repair.

It should trigger root cause investigation.

---

## High Cost Does Not Always Mean Repair

An asset with high maintenance spend but comparatively modest downtime and frequency may present a different question:

> **Is this equipment still economically worth maintaining?**

That turns a maintenance problem into a repair-versus-replacement decision.

---

## Explainability Matters

A score nobody can explain is difficult to use operationally.

Showing the contribution of downtime, failure frequency, and cost allows engineers and planners to challenge the ranking with evidence rather than intuition.

That makes the model adjustable without making it arbitrary.

---

# Recommendations

## 1. Use the Risk Score as the Weekly Maintenance Queue

Recalculate the ranking on a regular schedule and use the highest-priority band as the starting point for maintenance planning.

---

## 2. Match Intervention to the Risk Driver

Do not treat every high-risk asset the same.

### Downtime-driven risk

Prioritize reliability engineering and operational availability.

### Frequency-driven risk

Perform root cause analysis and investigate recurring failure modes.

### Cost-driven risk

Review repair economics, maintenance strategy, and possible replacement.

### High across all dimensions

Escalate for immediate reliability review.

---

## 3. Set Priority Bands From Real Team Capacity

If the team can inspect 20 assets per week, the highest-priority band should produce something close to a workable queue.

The score ranks risk.

Operational capacity determines where the action boundary should sit.

---

## 4. Reassess Decisions Made From the Previous Ranking

Because the earlier model contained row multiplication and sequential scoring problems, previous priority decisions based on that output should be reconsidered.

The corrected model can materially change which assets appear at the top.

---

## 5. Improve Downtime Capture

The current data records downtime duration and date but not the exact start time.

That prevents the analysis from distinguishing between:

* Downtime during active production
* Planned shutdown periods
* Low-utilization periods

Capturing outage start and end timestamps would allow future versions to estimate actual production loss rather than using downtime hours as a proxy.

---

## 6. Move Toward Production-Loss-Based Risk

With better time alignment, the current:

```text
Downtime Hours
```

component could eventually become:

```text
Estimated Production Lost
×
Unit Economic Value
```

That would move prioritization closer to direct economic exposure.

---

# Business Impact

The project changes maintenance prioritization from:

> **Which asset looks worst?**

to:

> **Which asset creates the greatest combined operational burden, and where should limited maintenance capacity go first?**

That produces several practical improvements.

### Better allocation of maintenance capacity

Engineering effort is directed toward assets carrying the strongest combination of downtime, recurring failure, and maintenance spend.

### Less dependence on intuition

Priority is based on a documented scoring framework rather than whichever metric or stakeholder receives the most attention.

### Earlier identification of chronic assets

Equipment that performs poorly across several dimensions becomes visible even when it does not top any individual ranking.

### More defensible maintenance planning

Weights and score components are visible, allowing operations teams to understand and challenge the model.

### Workload visibility

Management can see how much work each risk band creates before committing resources.

### Repeatable prioritization

Percentile scoring automatically recalculates as fleet behavior changes.

---

# What Was Built

The completed system includes:

* Asset-Level Reliability Model
* Failure Frequency Analysis
* Downtime Exposure Analysis
* Maintenance Cost Analysis
* Emissions vs. Failure Comparison
* Multi-Dimensional High-Risk Asset Detection
* 0 to 100 Asset Risk Score
* Weighted Risk Contributions
* Maintenance Priority Bands
* Priority Band Capacity Analysis
* Final Maintenance Worklist

The project also corrected:

* Three-table join fan-out
* Invalid failure counting
* Conflicting risk definitions
* Sequential priority inversion
* Missing maintenance event identifiers
* Non-repeatable view creation

---

# Tools & SQL Techniques

### PostgreSQL 14

Used for the complete reliability model and prioritization workflow.

### Common Table Expressions

Each operational source is aggregated independently before joining, preventing one-to-many fan-out.

### `PERCENT_RANK()`

Normalizes downtime, failure frequency, and maintenance cost onto comparable relative scales.

### `PERCENTILE_CONT()`

Creates fleet-relative intervention thresholds such as the top 10% for failure frequency and downtime.

### `NTILE(4)`

Creates readable emissions quartiles for group-level comparison.

### `MODE() WITHIN GROUP`

Identifies each asset's most common recorded failure type.

### `CROSS JOIN`

Makes calculated percentile thresholds available across the relevant asset records without recalculating them row by row.

### `BIGSERIAL PRIMARY KEY`

Creates a reliable maintenance-event identifier where the original source lacked one.

### `NULLIF()`

Protects calculations against divide-by-zero conditions.

### `NULLS LAST`

Keeps unavailable production or emissions values from distorting ranked outputs.

### `CREATE OR REPLACE VIEW`

Allows the analytical pipeline to be rerun without manually removing the existing view.

---

# Results

The final SQL workflow produces six decision layers.

| Output                        | Business Use                                                       |
| ----------------------------- | ------------------------------------------------------------------ |
| Asset Reliability View        | Creates one trusted asset-level reliability source                 |
| Emissions & Failure Analysis  | Tests whether environmental and reliability patterns move together |
| Severe Multi-Dimensional Risk | Identifies assets in the top 10% for both failures and downtime    |
| Asset Risk Score              | Ranks the entire fleet from 0 to 100                               |
| Priority Band Summary         | Measures workload and downtime exposure by intervention level      |
| Maintenance Worklist          | Gives planners the highest-priority assets requiring action        |

The most important result is operational:

**3,000 maintenance events are converted into one ranked maintenance decision process.**

Instead of separate cost, downtime, and failure reports competing for attention, the maintenance team gets:

```text
WHAT NEEDS ATTENTION
        +
WHY IT NEEDS ATTENTION
        +
HOW URGENT IT IS
        +
HOW MUCH WORK THE LIST CREATES
```

That makes the output useful not only for reliability analysis, but for **actual maintenance planning and resource allocation**.

---

# Repository Structure

```text
03-asset-risk-prioritisation/
├── README.md
└── asset_risk_prioritisation.sql
```

---

# Running the Project

Requires PostgreSQL 12 or later. Developed against PostgreSQL 14.

```bash
psql -d rigwatch -f sql/00_schema.sql
psql -d rigwatch -f 03-asset-risk-prioritisation/asset_risk_prioritisation.sql
```

Before running the schema, uncomment the required `\copy` statements and confirm the source CSV files are available in the repository's `data/` directory.

---

## Data Limitations

This project should be interpreted as a **maintenance prioritization and reliability decision-support system**, not a predictive failure model.

The available data does not provide sufficient time alignment to establish production loss around individual failure events, and production readings cover wells only.

The current score therefore prioritizes assets using observed maintenance burden:

* Downtime
* Failure frequency
* Maintenance cost

With timestamp-aligned production, operating state, asset criticality, repair history, and replacement-cost data, the framework could be extended into a more comprehensive **asset criticality and predictive maintenance system**.
