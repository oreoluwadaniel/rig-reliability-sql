# RigWatch

**Asset reliability analytics for oil and gas operations, in PostgreSQL.**

Three thousand maintenance events across wells, pipelines and refineries, turned into a maintenance team's Monday morning list.

---

## What this is

An operations dataset covering equipment failures, production output and emissions, analysed in SQL to answer three questions a maintenance function actually has to answer:

1. Where is the budget going, and is it going to assets worth the money?
2. What is breaking, how often, and how much operating time does it cost?
3. Of three thousand assets, which ones get inspected this week?

Each question is a separate project with its own script and its own documentation. They share a dataset and a schema, and each one stands alone.

| Project | Question | Files |
|---|---|---|
| **01** Maintenance Cost and Spend Efficiency | Where is the money going, and is it earning its keep? | [README](01-maintenance-cost-analysis/README.md) · [SQL](01-maintenance-cost-analysis/maintenance_cost_analysis.sql) |
| **02** Failure Frequency and Downtime Exposure | What is breaking, and what does it cost in lost hours? | [README](02-failure-downtime-analysis/README.md) · [SQL](02-failure-downtime-analysis/failure_downtime_analysis.sql) |
| **03** Asset Risk Scoring and Prioritisation | Which assets do we go and look at first? | [README](03-asset-risk-prioritisation/README.md) · [SQL](03-asset-risk-prioritisation/asset_risk_prioritisation.sql) |

---

## The part worth reading first

This started as a single working script. Before rewriting anything I reviewed it line by line, and the review turned up problems serious enough that the original output would have pointed a maintenance team at the wrong assets.

Every project README documents its own findings in full. The summary:

| Problem | Where | Why it mattered |
|---|---|---|
| Three way join fan-out in the reliability view | Original view | Assets appeared as many rows instead of one. Every total, count and average taken off the view was inflated, by a different multiple per asset |
| Same fan-out in two aggregate queries | Original queries 4 and 8 | Downtime, cost and production totals all too high, and the ratios between them meaningless |
| A join artefact reported as a failure count | Original query 6 | `COUNT(*)` off the broken view returned maintenance events times production readings times emissions readings, labelled `failures` |
| Comments contradicted the code | Original query 9 | Documentation said 8 events and 120 hours across three tiers. Code said 3 events and 100 hours across four |
| Sequential CASE let one dimension override another | Original query 9 | An asset with 4 failures and 20 lost hours outranked one with 3 failures and 600 lost hours |
| Two definitions of "risky" in one file | Original queries 7 and 9 | More than 5 failures in one, more than 3 in the other, for the same concept |
| Join key mismatch across asset types | Everywhere production was joined | Pipelines and refineries returned NULL production and read as assets that burn money and produce nothing |
| Currency stored as text, cast to FLOAT | Wherever cost appeared | Inexact arithmetic on money, and no type enforcement on load |
| No table definitions at all | Whole script | Nobody else could run it, and it hid the type problem |
| No unique key on maintenance events | Source data | No safe way to count distinct failures after any join |

The fan-out is the one worth understanding if you only look at one. It is the kind of bug that produces output looking entirely reasonable, with no errors, no nulls and no obviously silly numbers. The totals are simply too big, by an amount that varies per row, so you cannot even correct for it afterwards.

The original script is kept in [`original/`](original/) so the before and after can be compared directly.

---

## The data

Ten CSVs came with the dataset. These three projects use three of them.

| File | Rows | Grain | Used in |
|---|---|---|---|
| `maintenance.csv` | 3,000 | One maintenance event | 01, 02, 03 |
| `production.csv` | 5,000 | One well reading per date | 01, 02, 03 |
| `emissions.csv` | 3,000 | One asset reading per date | 03 |

Asset IDs carry their type in the prefix: `WEL` for wells, `PIP` for pipelines, `REF` for refineries. The `asset_class()` helper in the schema decodes this, and it matters more than it looks. Production data covers wells only, so without labelling the asset class a refinery shows up as an asset with high maintenance spend and zero output. It produces no barrels because it is a refinery, not because it is failing.

**Known limits, stated up front:**

- Production covers wells only. Pipelines and refineries carry NULL in those columns.
- There is no date alignment between the tables. A 2018 failure and a 2024 production reading belong to the same asset and to different moments. Totals are lifetime totals and are labelled as such.
- Downtime has a date and a duration but no start time. So the data can say an asset lost 90 hours. It cannot say whether they fell during production or during a planned shutdown, and that is the difference between hours lost and barrels lost.

---

## Running it

Needs PostgreSQL 12 or later. Tested on 14.

```bash
createdb rigwatch

# open sql/00_schema.sql and uncomment the three \copy lines first
psql -d rigwatch -f sql/00_schema.sql

psql -d rigwatch -f 01-maintenance-cost-analysis/maintenance_cost_analysis.sql
psql -d rigwatch -f 02-failure-downtime-analysis/failure_downtime_analysis.sql
psql -d rigwatch -f 03-asset-risk-prioritisation/asset_risk_prioritisation.sql
```

The schema file ends with sanity checks: row counts, asset type breakdown, join coverage, duplicate detection and null checks. Run them after loading. If the duplicate check shows more than one row per asset on either table, that is the fan-out condition the corrected scripts are built to handle, and it confirms why the original was wrong.

Every figure in the project READMEs is reproducible from these three CSVs and the schema. Clone it and check.

---

## Techniques used

| Technique | Where and why |
|---|---|
| Common table expressions | The fix for the fan-out. Pre-aggregate each table to one row per asset, then join |
| `PERCENT_RANK()` | Scores assets on a 0 to 1 scale so dollars, hours and event counts can be combined without inventing exchange rates |
| `PERCENTILE_CONT()` | Derives thresholds from the data instead of hardcoding them |
| `NTILE()` | Readable quartile bands for efficiency and emissions grouping |
| `SUM() OVER (ORDER BY ... ROWS BETWEEN ...)` | Running cumulative share, for the concentration analysis |
| `SUM(COUNT(*)) OVER (PARTITION BY ...)` | Share within group without a second pass |
| `LAG()` | Year on year change |
| `MODE() WITHIN GROUP` | Each asset's most common failure type |
| `COUNT(*) FILTER (WHERE ...)` | Multiple conditional counts in one pass, for the data quality checks |
| `NUMERIC` over `FLOAT` | Exact decimal arithmetic on currency |
| `NULLIF()` | Guards every division |
| A SQL helper function | Asset type decoding in one place instead of repeated in every query |

---

## Why percentiles instead of fixed thresholds

The main methodological choice in the repo, so it is worth being direct about the trade off.

Fixed thresholds have two failure modes. Nobody can explain where the number came from, so it cannot be defended when challenged. And it goes stale silently: a threshold set when the fleet averaged 2 failures per asset means something different once the fleet averages 6, and nothing in the code announces that it has stopped working.

Percentile thresholds describe a position in the fleet. The worst 10 percent is the worst 10 percent whatever the underlying numbers do, and it means something in plain English.

The cost is real. Percentile thresholds always flag roughly the same proportion, so if the whole fleet improves, the same share still gets flagged. For a work prioritisation list that is correct, because the team's capacity has not changed either. For a safety limit it would be wrong, and an absolute threshold would be right there.

---

## A note on the numbers

The scripts, corrections and reasoning here are complete and were written after reading the source data. The specific figures each query returns come from running it against your loaded database, which takes about a minute once the schema is in place. Nothing in this documentation quotes a result that was not derived from the data or the code itself.

---

## Repository layout

```
rig-reliability-sql/
├── README.md
├── data/
│   ├── maintenance.csv
│   ├── production.csv
│   └── emissions.csv
├── sql/
│   └── 00_schema.sql
├── original/
│   └── predictive_maintenance_original.sql
├── 01-maintenance-cost-analysis/
│   ├── README.md
│   └── maintenance_cost_analysis.sql
├── 02-failure-downtime-analysis/
│   ├── README.md
│   └── failure_downtime_analysis.sql
└── 03-asset-risk-prioritisation/
    ├── README.md
    └── asset_risk_prioritisation.sql
```
