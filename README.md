# RigWatch: Asset Reliability, Maintenance & Risk Intelligence System

**A PostgreSQL decision-support system for maintenance spend, equipment reliability, downtime exposure, and risk-based asset prioritization across oil and gas operations.**

---

## Project Overview

Oil and gas operators manage large asset portfolios where equipment failures, unplanned downtime, maintenance costs, and operational risk compete for the same limited maintenance resources.

The challenge is not simply knowing which equipment has failed.

Management needs to know:

> **Where is maintenance budget being spent?**
> **Which assets are repeatedly failing?**
> **Where is downtime exposure concentrated?**
> **Which equipment deserves maintenance attention first?**

RigWatch addresses that problem by transforming maintenance, production, and emissions data into a **reliability and maintenance decision-support system** for wells, pipelines, and refineries.

Using 3,000 maintenance events alongside production and emissions records, the repository evaluates asset performance across three connected areas:

1. **Maintenance Cost & Spend Efficiency**
2. **Failure Frequency & Downtime Exposure**
3. **Asset Risk Scoring & Maintenance Prioritization**

The final objective is practical:

> Turn thousands of operational records into a defensible list of assets the maintenance team should inspect first.

---

# Business Problem

Maintenance teams rarely have unlimited technicians, inspection capacity, or budget.

When thousands of assets compete for attention, prioritizing work based only on the most recent failure, the highest maintenance bill, or fixed thresholds can direct resources toward the wrong equipment.

An effective reliability strategy needs to consider several dimensions together:

* Maintenance Spend
* Failure Frequency
* Downtime Exposure
* Production Performance
* Asset Type
* Emissions Exposure
* Relative Fleet Risk

These dimensions answer different questions.

An expensive asset is not automatically inefficient.

A refinery showing no production in a well-production dataset is not automatically failing.

An asset with many maintenance events is not necessarily more urgent than one with fewer failures but hundreds of hours of downtime.

RigWatch brings these signals together to help maintenance teams distinguish:

> **High cost from poor cost efficiency**

> **Frequent maintenance from operationally significant failure**

> **Historical activity from current maintenance priority**

---

# Operational Questions

The repository is designed around three management questions.

### 1. Where is maintenance budget going?

Management needs visibility into maintenance expenditure and whether high-spend assets justify that investment through operational performance.

### 2. What is breaking, and what is the operational consequence?

Failure counts alone are insufficient.

Maintenance teams also need to understand downtime duration, failure patterns, and where reliability problems are concentrated.

### 3. Which assets should be inspected first?

With thousands of assets and limited maintenance capacity, the final output needs to convert reliability data into a prioritized worklist.

That is the core purpose of RigWatch.

---

# The Three Analysis Modules

| Project                                        | Business Question                                                            | Decision Supported                                            |
| ---------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------- |
| **01 - Maintenance Cost & Spend Efficiency**   | Where is maintenance money being spent, and which assets justify that spend? | Budget allocation and maintenance cost optimization           |
| **02 - Failure Frequency & Downtime Exposure** | Which assets fail most often, and where is operating time being lost?        | Reliability improvement and downtime reduction                |
| **03 - Asset Risk Scoring & Prioritization**   | Which assets require maintenance attention first?                            | Inspection planning and risk-based maintenance prioritization |

Each module has its own SQL script and documentation while operating from the same underlying reliability data model.

---

# System Architecture

```text
                     OIL & GAS ASSET DATA
                              |
              ---------------------------------
              |               |               |
              ↓               ↓               ↓
         MAINTENANCE      PRODUCTION       EMISSIONS
              |               |               |
              ↓               ↓               ↓
          Event-Level      Well-Level       Asset-Level
            History         Output            Exposure
              |               |               |
              ---------------------------------
                              |
                              ↓
                     DATA VALIDATION LAYER
                              |
                    -----------------------
                    |                     |
                    ↓                     ↓
              Grain Validation       Asset Classification
                    |                     |
                    -----------------------
                              |
                              ↓
                      ASSET-LEVEL MODEL
                              |
          ------------------------------------------------
          |                      |                       |
          ↓                      ↓                       ↓
    Maintenance Spend       Failure & Downtime        Emissions
       Intelligence             Intelligence          Exposure
          |                      |                       |
          ------------------------------------------------
                              |
                              ↓
                     RELIABILITY SCORING
                              |
                              ↓
                    RELATIVE FLEET RISK
                              |
                              ↓
                MAINTENANCE PRIORITY ENGINE
                              |
                ------------------------------
                |             |              |
                ↓             ↓              ↓
             MONITOR        REVIEW        PRIORITIZE
                                             |
                                             ↓
                                 MAINTENANCE WORKLIST
```

---

# Data

Ten CSV files were supplied with the wider operational dataset. RigWatch uses three.

| Dataset           |  Rows | Grain                      | Role                                             |
| ----------------- | ----: | -------------------------- | ------------------------------------------------ |
| `maintenance.csv` | 3,000 | One maintenance event      | Failure, downtime, and maintenance cost analysis |
| `production.csv`  | 5,000 | One well reading per date  | Production performance analysis                  |
| `emissions.csv`   | 3,000 | One asset reading per date | Environmental exposure within risk analysis      |

Asset IDs encode equipment type through their prefixes:

| Prefix | Asset Type |
| ------ | ---------- |
| `WEL`  | Well       |
| `PIP`  | Pipeline   |
| `REF`  | Refinery   |

The schema includes an `asset_class()` helper function that converts these identifiers into explicit asset classes.

This classification is important because the source datasets do not cover every asset type equally.

---

# Known Data Limitations

The system documents several limitations rather than hiding them behind the analysis.

### Production Covers Wells Only

Production records represent wells.

Pipelines and refineries therefore contain `NULL` production values.

A refinery with no production record does not represent a non-performing asset. It represents an asset for which barrel production is not the appropriate performance measure.

This distinction prevents valid infrastructure assets from being incorrectly classified as high-cost, zero-output equipment.

### Tables Are Not Temporally Aligned

Maintenance, production, and emissions records contain dates, but the datasets do not provide sufficient alignment to establish that activity across the three tables occurred during the same operating period.

The model therefore treats aggregated figures as:

> **Lifetime totals**

rather than pretending they represent synchronized operational windows.

### Downtime Is Not Production Loss

Maintenance records provide downtime duration but not sufficient timing information to determine whether those hours overlapped active production.

The system can therefore measure:

> **Hours of downtime**

but cannot defensibly claim:

> **Barrels of production lost**

without additional operational data.

---

# Critical Data Modeling Problems Identified

The original SQL executed successfully, but several issues could materially distort the maintenance decisions produced from it.

That distinction is central to this project:

> **SQL that runs is not necessarily SQL that supports the right decision.**

---

## 1. Three-Way Join Fan-Out

The most significant issue occurred when maintenance, production, and emissions records were joined directly at asset level.

Each table can contain multiple observations for the same asset.

For example:

```text
Asset WEL001

Maintenance Events:    4
Production Readings:  10
Emissions Readings:    5
```

A direct join can produce:

```text
4 × 10 × 5 = 200 rows
```

for one asset.

The asset does not suddenly have 200 meaningful observations.

The join created them.

---

## Business Consequence

Fan-out can inflate:

* Maintenance Costs
* Downtime Hours
* Failure Counts
* Production Totals
* Emissions Totals

Worse, the inflation factor can differ by asset because each asset has different numbers of records.

This means there is no universal correction factor that can safely repair the results afterwards.

A maintenance team using these figures could:

* Misidentify high-cost assets
* Miscalculate downtime exposure
* Misrank reliability risk
* Allocate technicians to the wrong equipment
* Direct maintenance budget away from assets with greater operational need

---

## Solution: Pre-Aggregate Before Joining

Each operational dataset is first reduced to the correct asset-level grain.

```text
Maintenance Events
       |
       ↓
Aggregate by Asset
       |
       ----------------
                      |
Production Readings  |
       |              |
       ↓              ↓
Aggregate by Asset → ASSET MODEL
                      ↑
       ↓              |
Aggregate by Asset    |
       ↑              |
       |              |
Emissions Readings ---
```

This creates one summary row per asset from each source before those summaries are joined.

The corrected model therefore combines:

> **One maintenance summary**

> **One production summary**

> **One emissions summary**

per asset.

This protects every downstream KPI and risk score from many-to-many row multiplication.

---

# Additional Logic Problems Corrected

The review identified several other issues affecting analytical reliability.

| Issue                                               | Business Risk                                              | Correction                                            |
| --------------------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------- |
| Join fan-out in reliability view                    | Inflated operational KPIs                                  | Pre-aggregate sources to asset grain                  |
| Fan-out in aggregate queries                        | Incorrect cost, production, and downtime totals            | Aggregate independently before joining                |
| `COUNT(*)` used as failure count                    | Join artefacts reported as real failures                   | Count from the maintenance event grain                |
| Comments disagreed with implemented thresholds      | Maintenance logic could be misunderstood                   | Align documentation and executable logic              |
| Sequential `CASE` prioritization                    | One risk dimension could override a more severe one        | Use multidimensional relative scoring                 |
| Two definitions of risky assets                     | Same asset could be classified differently across analyses | Standardize risk methodology                          |
| Production joined across incompatible asset classes | Pipelines/refineries appeared to produce nothing           | Explicit asset classification and NULL interpretation |
| Currency represented as text/`FLOAT`                | Weak monetary precision and validation                     | Use `NUMERIC`                                         |
| Missing table definitions                           | Analysis was not reproducible                              | Build complete PostgreSQL schema                      |
| No maintenance event identifier                     | Distinct event counting unsafe after joins                 | Preserve source grain and validate duplicates         |

---

# Module 01: Maintenance Cost & Spend Efficiency

## Objective

Determine where maintenance budget is being consumed and whether that expenditure aligns with asset performance.

The analysis evaluates:

* Total Maintenance Spend
* Spend by Asset
* Spend Concentration
* Maintenance Cost Distribution
* Cost Relative to Production Where Applicable
* Asset Efficiency Bands

The objective is not simply to identify:

> **"Which asset costs the most?"**

but:

> **"Which assets consume significant maintenance resources relative to the operational value they provide?"**

---

## Business Value

Maintenance expenditure should not be evaluated in isolation.

A high-producing well may justify greater maintenance expenditure than a lower-output asset.

This module helps management distinguish between:

> **High spend that supports productive equipment**

and

> **High spend that may indicate poor asset economics or recurring reliability problems.**

This supports more disciplined maintenance budgeting and asset-level cost review.

---

# Module 02: Failure Frequency & Downtime Exposure

## Objective

Identify where equipment reliability problems are concentrated and quantify their operational consequences.

The analysis evaluates:

* Failure Frequency
* Downtime Hours
* Failure Types
* Asset-Level Reliability Patterns
* Downtime Concentration
* Year-on-Year Changes

Failure frequency and downtime are deliberately treated as separate dimensions.

Consider:

```text
Asset A
4 maintenance events
20 downtime hours

Asset B
3 maintenance events
600 downtime hours
```

A model driven only by event count could rank Asset A as the larger problem.

Operationally, Asset B may deserve far greater attention.

RigWatch preserves both dimensions rather than allowing one metric to determine reliability priority on its own.

---

# Module 03: Asset Risk Scoring & Maintenance Prioritization

## Objective

Convert multiple reliability signals into a prioritized maintenance worklist.

This module combines asset-level indicators such as:

* Maintenance Frequency
* Downtime Exposure
* Maintenance Spend
* Production Performance Where Applicable
* Emissions Exposure

The purpose is to answer the maintenance team's most practical question:

> **"Of all the assets we operate, which ones deserve attention first?"**

---

# Why Relative Risk Scoring Is Used

A central methodological decision in RigWatch is the use of percentile-based risk scoring instead of relying entirely on fixed thresholds.

Hardcoded rules such as:

```text
Failures > 5
```

or:

```text
Downtime > 100 hours
```

create two problems.

### Threshold Origin

If the threshold has no engineering, regulatory, or historical basis, it is difficult to defend.

Why five failures?

Why 100 hours?

Without evidence, those numbers are assumptions embedded in SQL.

### Threshold Drift

Fleet behavior changes.

If average failure frequency rises from two events to six, a threshold created under the earlier operating environment may no longer identify unusually risky assets.

The code still runs.

The threshold simply becomes less useful.

---

# Percentile-Based Prioritization

`PERCENT_RANK()` places assets on a comparable 0-to-1 scale based on their position within the fleet.

This allows different measures such as:

* Dollars
* Downtime Hours
* Event Counts

to contribute to prioritization without pretending they share the same units.

A maintenance manager can then interpret a result such as:

> **This asset sits within the highest-risk portion of the fleet**

without needing to interpret several incompatible raw measures simultaneously.

---

# The Trade-Off

Percentile scoring is appropriate for **work prioritization**, not every reliability problem.

If the entire fleet improves dramatically, percentile scoring will still identify a worst-performing group.

That is useful when the question is:

> **"We can inspect 30 assets this week. Which 30 should they be?"**

It is not appropriate for absolute engineering or safety limits.

If an equipment condition becomes unsafe beyond a defined physical threshold, that absolute threshold should override relative fleet ranking.

RigWatch therefore uses percentile logic as a **maintenance prioritization method**, not as a substitute for engineering safety standards.

---

# Techniques Used

| Technique                     | Purpose                                                              |
| ----------------------------- | -------------------------------------------------------------------- |
| Common Table Expressions      | Pre-aggregate operational tables and prevent fan-out                 |
| `PERCENT_RANK()`              | Normalize different risk dimensions onto a comparable relative scale |
| `PERCENTILE_CONT()`           | Derive thresholds from fleet distributions                           |
| `NTILE()`                     | Create interpretable performance bands                               |
| Windowed `SUM()`              | Measure cumulative spend or risk concentration                       |
| `SUM(COUNT(*)) OVER (...)`    | Calculate within-group shares efficiently                            |
| `LAG()`                       | Measure year-over-year change                                        |
| `MODE() WITHIN GROUP`         | Identify each asset's most common failure type                       |
| `COUNT(*) FILTER (WHERE ...)` | Perform conditional data-quality and operational counts              |
| `NUMERIC`                     | Preserve exact arithmetic for maintenance expenditure                |
| `NULLIF()`                    | Protect ratio calculations against division by zero                  |
| SQL Helper Function           | Decode asset classes consistently throughout the repository          |

---

# Data Validation

The PostgreSQL schema includes validation checks covering:

* Row Counts
* Asset Type Distribution
* Join Coverage
* Duplicate Detection
* NULL Values
* Source Grain

These checks are part of the analytical system rather than one-time development queries.

They provide an early warning when changes in source data could compromise downstream reliability metrics.

---

# Business Impact

RigWatch turns maintenance analytics into an **operational prioritization capability**.

The system helps management improve four areas.

### Maintenance Budget Allocation

Spend analysis identifies where maintenance resources are concentrated and where expenditure requires deeper review.

### Reliability Management

Failure and downtime analysis identifies assets contributing disproportionately to operational reliability problems.

### Maintenance Prioritization

Risk scoring converts thousands of records into a ranked worklist that helps maintenance teams focus limited inspection capacity on the assets with the greatest relative exposure.

### Decision Quality

Correcting fan-out, asset-type mismatches, inconsistent thresholds, and unsafe event counting protects maintenance decisions from technically plausible but analytically incorrect results.

The shift is from:

> **"How many failures did we record?"**

to:

> **"Which assets create the greatest operational exposure, and where should our maintenance capacity go first?"**

That is the core business value of RigWatch.

---

# Skills Demonstrated

This repository demonstrates proficiency in:

* PostgreSQL
* Asset Reliability Analytics
* Maintenance Analytics
* Oil & Gas Operations Analytics
* Operational Risk Analysis
* Maintenance Cost Analysis
* Downtime Analysis
* Asset Prioritization
* Data Modeling
* SQL Debugging
* Data Quality Engineering
* Window Functions
* Percentile-Based Scoring
* KPI Development
* Decision Support Systems
* Analytical Validation

---

# Repository Structure

```text
rig-reliability-sql/
├── README.md
├── data/
│   ├── maintenance.csv
│   ├── production.csv
│   └── emissions.csv
│
├── sql/
│   └── 00_schema.sql
│
├── original/
│   └── predictive_maintenance_original.sql
│
├── 01-maintenance-cost-analysis/
│   ├── README.md
│   └── maintenance_cost_analysis.sql
│
├── 02-failure-downtime-analysis/
│   ├── README.md
│   └── failure_downtime_analysis.sql
│
└── 03-asset-risk-prioritisation/
    ├── README.md
    └── asset_risk_prioritisation.sql
```

---

# Running the Project

Requires **PostgreSQL 12 or later** and was tested on PostgreSQL 14.

```bash
createdb rigwatch

# Open sql/00_schema.sql and uncomment the required \copy statements
psql -d rigwatch -f sql/00_schema.sql

# Maintenance Cost & Spend Efficiency
psql -d rigwatch -f 01-maintenance-cost-analysis/maintenance_cost_analysis.sql

# Failure Frequency & Downtime Exposure
psql -d rigwatch -f 02-failure-downtime-analysis/failure_downtime_analysis.sql

# Asset Risk Scoring & Prioritization
psql -d rigwatch -f 03-asset-risk-prioritisation/asset_risk_prioritisation.sql
```

After loading the data, run the sanity checks included at the end of the schema before relying on the analytical outputs.

---

# Results

RigWatch delivers a three-layer asset reliability system covering:

> **Maintenance Spend Intelligence**

> **Failure & Downtime Intelligence**

> **Risk-Based Maintenance Prioritization**

The repository transforms 3,000 maintenance events, 5,000 production readings, and 3,000 emissions observations into asset-level reliability intelligence designed to support real maintenance decisions.

More importantly, the project demonstrates why analytical correctness matters operationally.

The original implementation contained data-model and scoring issues capable of inflating reliability metrics and changing which assets appeared most urgent.

The corrected architecture establishes the proper data grain, protects financial and reliability calculations from join fan-out, separates asset classes correctly, standardizes risk methodology, and produces a defensible basis for maintenance prioritization.

The final outcome is not simply a collection of SQL queries.

It is a system designed to help an operations team answer:

> **Where are we spending maintenance money?**

> **Where are reliability problems creating the greatest operational exposure?**

> **And when maintenance capacity is limited, which assets should we inspect first?**
