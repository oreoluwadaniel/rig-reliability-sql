# Maintenance Spend & Asset Efficiency Intelligence

**A PostgreSQL asset economics project that connects maintenance expenditure with production output to identify cost concentration, inefficient wells, potential shut-in candidates, and where maintenance budget can create the greatest operational value.**

---

## Business Problem

Knowing how much was spent on maintenance is accounting.

Knowing whether that spend is economically justified is a business decision.

A maintenance team can report every repair, every invoice, and every dollar spent and still be unable to answer the question management actually cares about:

> **Are we spending maintenance money on assets that are worth maintaining?**

Raw maintenance cost cannot answer that.

A well may absorb significant maintenance spend because it is one of the operation's highest-producing assets. That may be entirely justified.

Another well may consume less maintenance budget but produce so little that every barrel becomes expensive to keep online.

Those two assets should not receive the same decision.

The real problem is therefore not simply controlling maintenance cost.

It is **allocating maintenance resources according to asset value.**

This project builds that decision layer by combining maintenance expenditure, repair frequency, downtime, asset type, production output, and cost efficiency into one analytical framework.

The analysis answers:

* Where is maintenance budget concentrated?
* Which assets repeatedly consume maintenance resources?
* Is high spend caused by recurring repairs or isolated major work?
* Which asset classes account for the largest share of maintenance expenditure?
* Which wells justify their maintenance cost through production?
* Which wells consume significant maintenance resources while producing little?
* Which maintained wells have no production record at all?
* Is maintenance expenditure improving or escalating over time?

The result moves maintenance reporting from:

> **What did we spend?**

to:

> **Where should we keep spending, where should we investigate, and where should we reconsider the asset altogether?**

---

# Business Value

Maintenance budgets are constrained.

The objective is therefore not simply to minimize maintenance spend.

Cutting maintenance indiscriminately can destroy more value than it saves.

The better objective is:

> **Direct maintenance capacity toward assets where continued spend is economically justified.**

The decision framework looks like this:

```text
                    MAINTENANCE SPEND
                           |
             +-------------+-------------+
             |                           |
             v                           v
       HOW MUCH?                    HOW OFTEN?
       Total Spend                Event Frequency
             |                           |
             +-------------+-------------+
                           |
                           v
                 WHERE IS SPEND
                   CONCENTRATED?
                           |
                           v
                  WHAT ASSET TYPE?
                           |
                           v
                   WHAT DOES THE
                     ASSET PRODUCE?
                           |
                           v
                   COST PER BARREL
                           |
             +-------------+-------------+
             |                           |
             v                           v
       HIGH OUTPUT                 LOW OUTPUT
       HIGH SPEND                  HIGH SPEND
             |                           |
             v                           v
      SPEND MAY BE                INVESTIGATE
       JUSTIFIED                  ECONOMICS
                                         |
                              +----------+----------+
                              |                     |
                              v                     v
                         REPAIR / OPTIMIZE      SHUT-IN REVIEW
```

The purpose is not to automatically label expensive assets as bad.

It is to distinguish **productive expenditure from inefficient expenditure.**

---

# What the Analysis Answers

The project produces seven decision layers.

### 1. Maintenance Spend Exposure

Which assets consume the most maintenance budget?

### 2. Spend Concentration

How much of total maintenance expenditure is concentrated in a relatively small part of the fleet?

### 3. Asset-Class Cost Exposure

Are wells, pipelines, or refineries driving the maintenance budget?

### 4. Maintenance Cost vs. Production

Does the output from each well justify the maintenance expenditure associated with it?

### 5. Missing Production Exposure

Which wells continue to receive maintenance spend despite having no production record?

### 6. Cost Efficiency Segmentation

Which wells sit at the inefficient end of the fleet when maintenance cost is measured against production?

### 7. Maintenance Spend Trend

Is the maintenance burden improving, stable, or increasing over time?

---

# Data

The project uses two operational datasets.

| Dataset           | Records | Role                                                  |
| ----------------- | ------: | ----------------------------------------------------- |
| `maintenance.csv` |   3,000 | Maintenance expenditure, failure events, and downtime |
| `production.csv`  |   5,000 | Well production volumes and operating conditions      |

---

## Maintenance Data

Each row represents one maintenance event.

Key fields include:

| Field              | Purpose                             |
| ------------------ | ----------------------------------- |
| `asset_id`         | Identifies the asset                |
| `maintenance_date` | Date maintenance occurred           |
| `cost_usd`         | Cost of the maintenance event       |
| `failure_type`     | Recorded equipment failure category |
| `downtime_hours`   | Hours the asset was unavailable     |

Asset IDs also encode equipment class:

```text
WEL → Well
PIP → Pipeline
REF → Refinery
```

This becomes important when maintenance expenditure is compared with production.

---

## Production Data

Production records contain:

* Oil production
* Gas production
* Water cut
* Pressure
* Temperature

The production table contains **well data only**.

Pipelines and refineries therefore remain part of maintenance cost analysis but are excluded from cost-per-barrel calculations.

That distinction prevents assets from being incorrectly classified as unproductive simply because production data does not apply to their asset type.

---

# Analytical Framework

The analysis moves from financial exposure to asset economics.

```text
MAINTENANCE EVENTS
        |
        v
TOTAL SPEND BY ASSET
        |
        v
SPEND FREQUENCY & EVENT SIZE
        |
        v
SPEND CONCENTRATION
        |
        v
ASSET CLASS
        |
        v
PRODUCTION OUTPUT
        |
        v
MAINTENANCE COST PER BARREL
        |
        v
EFFICIENCY SEGMENT
        |
        v
MAINTENANCE PRIORITY
```

Each stage narrows the decision.

---

# Methodology

## Step 1: Establish Maintenance Cost Exposure

The first layer measures:

* Total maintenance spend per asset
* Number of maintenance events
* Average cost per event
* Largest individual maintenance event
* First and most recent maintenance dates

Total cost alone is not enough.

Consider:

```text
Asset A
$200,000 maintenance spend
2 events

Asset B
$200,000 maintenance spend
20 events
```

Same total cost.

Different problem.

Asset A may have undergone major scheduled work.

Asset B may be experiencing repeated faults that continue consuming maintenance resources.

The event count and average event cost make that distinction visible.

---

# Step 2: Determine Whether Spend Is Concentrated

A ranked cost list tells you who spent the most.

It does not tell you whether focusing on those assets will materially change the budget.

The project therefore calculates:

* Asset maintenance spend
* Percentage of total maintenance expenditure
* Running cumulative share of expenditure

Conceptually:

```text
Assets Ranked by Maintenance Spend

Asset 01  █████████████████
Asset 02  █████████████
Asset 03  ██████████
Asset 04  ███████
Asset 05  █████
...
```

The cumulative calculation answers a strategic question:

> **How many assets account for a major share of maintenance expenditure?**

If a small group drives half the spend, targeted intervention is realistic.

If hundreds of assets are required to reach the same threshold, the issue is more systemic and may require maintenance policy changes rather than asset-by-asset action.

The concentration analysis therefore determines what kind of intervention is practical before one is recommended.

---

# Step 3: Understand Spend by Asset Class

Individual asset rankings support maintenance planners.

Management also needs to understand where maintenance expenditure sits across the operation.

The analysis therefore rolls spend up by:

* Wells
* Pipelines
* Refineries

This provides:

* Total spend by asset class
* Number of assets maintained
* Average spend per asset

That makes it possible to distinguish a fleet-wide maintenance issue from a problem concentrated in one equipment class.

---

# Step 4: Connect Maintenance Spend to Production

This is where maintenance reporting becomes asset economics.

Raw maintenance spend asks:

> How expensive is this asset?

Cost per barrel asks:

> **How expensive is this asset relative to what it produces?**

The metric is:

```text
Maintenance Cost per Barrel
=
Total Maintenance Cost
÷
Total Oil Production
```

This changes the ranking.

A high-maintenance well with strong production may remain economically reasonable.

A moderate-maintenance well with weak production may be far more concerning.

Example:

```text
Well A
Maintenance Spend: $500,000
Production: 500,000 barrels

Cost per Barrel: $1.00
```

versus:

```text
Well B
Maintenance Spend: $200,000
Production: 20,000 barrels

Cost per Barrel: $10.00
```

Well A costs more in absolute terms.

Well B carries ten times the maintenance burden per barrel.

A raw cost ranking prioritizes Well A.

An efficiency ranking surfaces Well B.

That is why spend cannot be interpreted without output.

---

# SQL Review & Model Corrections

The original analysis contained one structural issue that materially affected the business conclusion.

## 1. Maintenance and Production Were Joined at the Wrong Grain

The original pattern was:

```sql
SELECT
    m.asset_id,
    SUM(m.cost_usd) AS maintenance_cost,
    SUM(p.oil_production_barrels) AS production
FROM maintenance m
LEFT JOIN production p
    ON m.asset_id = p.well_id
GROUP BY m.asset_id;
```

Both tables contain multiple records per asset.

Suppose a well has:

```text
4 maintenance records
3 production records
```

Joining the raw tables produces:

```text
4 × 3 = 12 rows
```

Each maintenance record is repeated for every production record.

Each production record is repeated for every maintenance record.

The resulting totals are inflated.

Worse, the amount of inflation depends on how many records each asset has.

That means the error is not uniform across the fleet.

The SQL runs successfully.

The output can look reasonable.

The underlying asset economics are still wrong.

---

## Correction: Aggregate Before Joining

The corrected architecture is:

```text
MAINTENANCE
     |
     v
Aggregate to
One Row per Asset
     |
     +---------------------+
                           |
PRODUCTION                 |
     |                     |
     v                     |
Aggregate to               |
One Row per Well ----------+
                           |
                           v
                 ASSET ECONOMICS
```

Maintenance is summarized independently.

Production is summarized independently.

Only the asset-level summaries are joined.

This ensures each dollar of maintenance spend and each barrel of production is counted once.

---

# 2. Non-Well Assets Were Being Compared With Well Production

The maintenance dataset contains:

```text
WEL
PIP
REF
```

The production dataset contains wells.

A direct LEFT JOIN therefore gives pipelines and refineries:

```text
production = NULL
```

Without asset classification, this can make a perfectly normal refinery appear to be:

> High maintenance cost, zero production.

That is not poor performance.

It is an invalid comparison.

The corrected model introduces an `asset_class()` helper and limits production-efficiency calculations to wells.

Pipelines and refineries are evaluated separately through asset-class maintenance reporting.

---

# 3. Currency Was Stored as Text and Converted to FLOAT

The original analysis used:

```sql
CAST(cost_usd AS FLOAT)
```

for financial aggregation.

That creates two problems.

First, storing currency as text means the database is not enforcing numeric integrity at ingestion.

Second, `FLOAT` is an approximate numeric type.

Currency should use exact decimal arithmetic.

The corrected schema defines:

```text
cost_usd → NUMERIC(14,2)
```

and removes the runtime casts.

Financial values are therefore validated at load time and aggregated using an appropriate numeric type.

---

# 4. The Original Project Had No Reproducible Schema

The original script assumed tables already existed.

There were no:

* Table definitions
* Data types
* Keys
* Load instructions
* Indexes
* Post-load validation checks

That makes the analysis difficult for another person to reproduce and hides structural problems such as incorrect column types.

The project now includes a complete PostgreSQL schema and loading workflow.

---

# Step 5: Surface Maintained Wells With No Production Record

A maintained well with no production record requires investigation.

There are at least two possible explanations.

### Operational Explanation

The well may be shut in or otherwise non-producing while maintenance expenditure continues.

That raises an asset economics question:

> **Why are we continuing to spend on this well?**

### Data Explanation

The well may be producing, but its production records are missing.

That raises a data-quality question:

> **Can we trust the cost-per-barrel calculation for the fleet?**

Those are completely different problems.

The project isolates these wells instead of allowing them to disappear into NULL values inside the main efficiency analysis.

---

# Step 6: Segment Wells by Maintenance Efficiency

A cost-per-barrel number still leaves management with another question:

> What counts as high?

Hardcoding an arbitrary threshold creates a rule that can become stale as fleet economics change.

Instead, the project uses quartiles to compare each well against the current portfolio.

```text
Best Efficiency
      |
      |  Q1
      |
      |  Q2
      |
      |  Q3
      |
      |  Q4
      v
Worst Efficiency
```

This creates four relative efficiency bands.

The worst-performing quartile becomes the first group for commercial review.

This does not mean every asset in that quartile should be shut in.

It means those assets deserve investigation before additional maintenance budget is committed.

---

# Step 7: Track Maintenance Economics Over Time

A maintenance total has limited meaning without direction.

Suppose annual maintenance expenditure is:

```text
2021    $4.2M
2022    $4.8M
2023    $5.6M
2024    $6.7M
```

The important information is not only the latest total.

It is the trajectory.

The project therefore tracks:

* Annual maintenance spend
* Number of maintenance events
* Annual downtime
* Change from the previous year

This gives management visibility into whether maintenance burden is:

* Declining
* Stable
* Increasing

Budget planning can then respond to operational reality rather than simply rolling last year's number forward.

---

# Key Insights

## High Maintenance Cost Does Not Automatically Mean Poor Performance

An expensive asset may also be one of the fleet's most productive.

Removing it from service because it ranks high on maintenance cost could destroy value.

Maintenance expenditure needs production context.

---

## Cost per Barrel Can Reverse the Priority List

Raw spend prioritizes expensive assets.

Efficiency analysis prioritizes expensive output.

Those are not the same thing.

A moderate-cost well with very low production can be a larger commercial problem than the highest-maintenance well in the portfolio.

---

## Spend Concentration Determines the Strategy

If a small number of assets consume most maintenance expenditure, a targeted program can materially change the budget.

If expenditure is widely distributed, asset-by-asset intervention will have limited effect.

The concentration curve tells management which situation it is dealing with.

---

## Event Frequency Helps Explain Why an Asset Is Expensive

Two assets with equal maintenance spend may require completely different responses.

```text
Few expensive interventions
        |
        v
Major maintenance work
        |
        v
Planning / spares / overhaul review
```

versus:

```text
Many smaller interventions
        |
        v
Recurring reliability issue
        |
        v
Root cause investigation
```

Total spend identifies the exposure.

Event frequency helps diagnose it.

---

## Missing Production Is a Business Issue, Not Just a NULL

Maintenance spend against a well with no production record should never quietly disappear from an efficiency report.

Either the well is receiving maintenance despite not producing, or the production data is incomplete.

Both require action.

---

## Maintenance Trend Changes the Budget Conversation

A static cost total says:

> We spent $X.

A trend says:

> Maintenance expenditure has increased for three consecutive years.

The second statement supports a management decision.

---

# Recommendations

## 1. Manage Maintenance Spend as an Asset Portfolio

Do not manage the maintenance budget only by department or total spend.

Use the concentration analysis to identify the assets responsible for the largest share of expenditure.

Give those assets explicit ownership and review.

---

## 2. Prioritize Efficiency, Not Absolute Cost

Do not automatically target the highest-cost wells.

Review wells with the highest maintenance cost per barrel first.

These are the assets where maintenance expenditure is least supported by output.

---

## 3. Separate Recurring Repair Problems From Major Work

Use maintenance event count and average event cost together.

### Many events + high cumulative spend

Investigate recurring failure mechanisms.

### Few events + high spend

Review overhaul scope, planning, contractor cost, and parts strategy.

The financial exposure may look identical.

The intervention should not.

---

## 4. Investigate Every Maintained Well With No Production Record

Each one should be classified as either:

```text
Operational Issue
```

or:

```text
Data Issue
```

If the well is genuinely non-producing, management should determine whether continued maintenance is economically justified.

If production data is missing, the data problem should be corrected before relying on fleet efficiency rankings.

---

## 5. Review the Worst Efficiency Quartile Before the Next Budget Cycle

The worst cost-per-barrel group should become a commercial review list.

Possible decisions may include:

* Continue maintenance
* Investigate recurring failures
* Change maintenance strategy
* Reduce intervention frequency
* Reassess operating plan
* Consider shut-in review where operationally appropriate

The SQL does not make those decisions automatically.

It identifies where those decisions deserve attention.

---

## 6. Build Maintenance Budgets From Trend and Asset Economics

Do not set the next budget simply as:

```text
Last Year's Budget
+
Inflation
```

Use:

* Maintenance spend trend
* Event trend
* Downtime trend
* Asset-level cost efficiency

to understand what is actually driving the requirement.

---

# Business Impact

## Maintenance Capital Can Be Allocated More Rationally

The project shifts budget attention from the assets that simply cost the most toward the assets where maintenance cost is least supported by production.

That improves the quality of allocation without assuming the solution is simply to reduce the overall maintenance budget.

---

## Inefficient Wells Become Visible

Assets with weak production and meaningful maintenance expenditure can sit unnoticed in the middle of a raw cost ranking.

Cost-per-barrel analysis moves them into view.

These assets are candidates for deeper technical and commercial review.

---

## Potential Shut-In Candidates Can Be Investigated Earlier

The project does not declare that an inefficient well should be shut in.

It identifies wells where continued maintenance expenditure deserves scrutiny because output is weak relative to cost.

That turns shut-in review from an anecdotal decision into a data-supported investigation.

---

## Maintenance Strategy Can Be Tailored to the Cost Pattern

Recurring low-value repairs and isolated major maintenance events no longer appear as the same problem simply because their annual cost is equal.

That allows engineering, planning, and procurement teams to respond differently.

---

## Budget Concentration Becomes Visible

Management can see whether maintenance exposure sits in a manageable group of assets or is distributed across the operation.

That determines whether targeted intervention or broader policy change is likely to produce the better return.

---

## Financial Comparisons Are Built on Correct Totals

The aggregate-before-join correction removes the row multiplication that previously inflated maintenance and production totals.

Without this correction, cost-per-barrel comparisons could rank assets using distorted economics.

With it, asset-level comparisons become usable for decision support.

---

# What Was Built

The completed project includes:

* Asset Maintenance Spend Analysis
* Maintenance Event Frequency Analysis
* Spend Concentration Analysis
* Asset-Class Cost Analysis
* Maintenance Cost vs. Production Analysis
* Missing Production Investigation
* Cost-per-Barrel Efficiency Segmentation
* Year-over-Year Maintenance Trend Analysis

The project also corrected:

* Many-to-many join fan-out
* Invalid production comparisons across asset classes
* Approximate financial arithmetic
* Missing schema and reproducibility controls
* Missing production records being buried inside NULL outputs

---

# Tools & SQL Techniques

### PostgreSQL 14

Used for the complete analysis and data model.

### Common Table Expressions

Used to aggregate maintenance and production independently before joining them.

This is the key architectural correction that prevents duplicated totals.

### Window Functions

Used for:

* Percentage of total spend
* Running cumulative expenditure
* Efficiency segmentation
* Year-over-year comparison

### `SUM() OVER()`

Calculates each asset's contribution to total maintenance spend.

### Running `SUM() OVER()`

Builds the cumulative spend curve used to measure cost concentration.

### `LAG()`

Compares annual maintenance performance against the previous year.

### `NTILE(4)`

Creates relative cost-efficiency quartiles without relying on arbitrary fixed thresholds.

### `NULLIF()`

Prevents divide-by-zero errors when calculating maintenance cost per barrel.

### `NOT EXISTS`

Isolates maintained wells without corresponding production records.

### `NUMERIC(14,2)`

Provides exact decimal storage and calculation for maintenance expenditure.

### `asset_class()`

Centralizes the logic used to distinguish wells, pipelines, and refineries from asset IDs.

---

# Results

The SQL workflow produces seven decision-ready outputs.

| Output                       | Decision Supported                                                 |
| ---------------------------- | ------------------------------------------------------------------ |
| Asset Spend Profile          | Identifies where maintenance money is being consumed               |
| Spend Concentration          | Determines whether targeted cost intervention is viable            |
| Asset-Class Spend            | Shows which equipment classes drive maintenance exposure           |
| Cost vs. Production          | Measures whether well output supports maintenance expenditure      |
| Missing Production Watchlist | Flags maintained wells requiring operational or data investigation |
| Efficiency Segmentation      | Identifies the least efficient wells relative to the fleet         |
| Maintenance Trend            | Shows whether maintenance burden is improving or escalating        |

The project ultimately transforms:

```text
3,000 MAINTENANCE EVENTS
          |
          v
     WHERE DID THE
       MONEY GO?
          |
          v
     WHICH ASSETS
     CONSUME MOST?
          |
          v
    WHAT DO THOSE
     ASSETS PRODUCE?
          |
          v
   WHAT DOES MAINTENANCE
      COST PER BARREL?
          |
          v
   WHICH ASSETS JUSTIFY
     CONTINUED SPEND?
          |
          v
    WHERE SHOULD THE
     NEXT MAINTENANCE
       DOLLAR GO?
```

That is the core business value of the project.

It turns historical maintenance transactions into an **asset economics and maintenance allocation system.**

---

# Data & Interpretation Limits

This analysis measures maintenance efficiency using the information available in the dataset.

It should not be interpreted as a complete asset profitability model.

Maintenance cost per barrel does not include:

* Revenue per barrel
* Commodity price
* Operating expenditure outside maintenance
* Transportation cost
* Taxes
* Royalties
* Capital expenditure
* Remaining reserves
* Expected future production
* Decommissioning cost

Therefore:

> **High maintenance cost per barrel is a review signal, not an automatic shut-in decision.**

A production asset can carry relatively high maintenance cost and still remain commercially attractive once revenue and future reserves are considered.

A true shut-in or asset-retirement model would require those additional economic inputs.

The purpose of this project is narrower and defensible:

> **Identify where maintenance expenditure appears least efficient relative to recorded production so management knows where deeper commercial review should begin.**

---

# Repository Structure

```text
01-maintenance-cost-analysis/
├── README.md
└── maintenance_cost_analysis.sql
```

---

# Running the Project

Requires PostgreSQL 12 or later. Developed against PostgreSQL 14.

```bash
psql -d rigwatch -f sql/00_schema.sql
psql -d rigwatch -f 01-maintenance-cost-analysis/maintenance_cost_analysis.sql
```

Before running the schema, uncomment the required `\copy` statements and confirm the source CSV files are available in the repository's `data/` directory.
