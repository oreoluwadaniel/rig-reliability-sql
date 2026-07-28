/*===========================================================
KEPT FOR REFERENCE. DO NOT RUN.

This is the original working script, unchanged, so the before
and after can be compared directly.

The problems in it are documented in full in the three
project READMEs. In short:

  - The view below joins three tables that all hold many rows
    per asset, so it multiplies rows. Every aggregate taken
    off it is inflated.
  - Queries 4 and 8 have the same fan-out.
  - Query 6 reports a join artefact under the column name
    "failures".
  - Query 9's comments and code disagree on every threshold,
    and its CASE ladder lets failure count override downtime.
  - Queries 7 and 9 use two different definitions of risky.
  - There are no table definitions anywhere.

The corrected versions live in 01, 02 and 03.
===========================================================*/


/*===========================================================
ASSET RELIABILITY, FAILURE RISK &
PREDICTIVE MAINTENANCE SYSTEM

## Operational Challenge

Unexpected equipment failures create more than maintenance
costs. They interrupt production, increase downtime, consume
maintenance resources, and can reduce the reliability of
critical operating assets.

Management needs a clear way to identify which assets are
creating the greatest operational burden and where maintenance
teams should intervene before performance deteriorates
further.

## Management Questions

1. Which assets generate the highest maintenance costs?
2. Which assets experience repeated failures?
3. Where is downtime concentrated across operations?
4. How does equipment downtime relate to production output?
5. Which failure types cause the greatest disruption?
6. Are emissions patterns associated with failure activity?
7. Which assets show signs of elevated reliability risk?
8. Is maintenance spending supporting productive assets?
9. Which assets should receive immediate maintenance attention?

## Analytical Approach

The system combines maintenance history, production activity,
and environmental performance to create a unified view of
asset reliability.

The analysis moves from historical performance to operational
risk identification:

Maintenance Cost > Failure Frequency > Downtime Exposure
> Production Performance > Failure Pattern Analysis
> Asset Risk Identification > Maintenance Prioritization

===========================================================*/

/*-----------------------------------------------------------
FOUNDATION: ASSET RELIABILITY DATA MODEL

Create a consolidated analytical view connecting maintenance
events with production and emissions information.

This provides a common foundation for evaluating asset
reliability, operational performance, and maintenance risk.
-----------------------------------------------------------*/

CREATE VIEW v_asset_reliability AS
SELECT
m.asset_id,
m.maintenance_date,
m.cost_usd,
m.failure_type,
m.downtime_hours,
p.well_id,
p.oil_production_barrels,
p.date,
e.co2_tons,
e.methane_leakage_tons,
e.energy_consumption_mwh
FROM maintenance m
LEFT JOIN production p
ON m.asset_id = p.well_id
LEFT JOIN emissions e
ON m.asset_id = e.asset_id;

/*-----------------------------------------------------------

1. MAINTENANCE COST EXPOSURE

Measures total maintenance spending for each asset and ranks
the assets consuming the greatest maintenance resources.

Assets with consistently high costs may require deeper
reliability reviews or replacement assessments.
-----------------------------------------------------------*/

SELECT
asset_id,
SUM(CAST(cost_usd AS FLOAT)) AS total_maintenance_cost
FROM maintenance
GROUP BY asset_id
ORDER BY total_maintenance_cost DESC;

/*-----------------------------------------------------------
2. FAILURE FREQUENCY ANALYSIS

Measures how often each asset appears in maintenance records
to identify equipment experiencing repeated reliability
issues.

Frequent failures can indicate recurring defects, aging
equipment, or maintenance strategies that are not resolving
the underlying problem.
-----------------------------------------------------------*/

SELECT
asset_id,
COUNT(*) AS failure_count
FROM maintenance
GROUP BY asset_id
ORDER BY failure_count DESC;

/*-----------------------------------------------------------
3. DOWNTIME EXPOSURE

Measures accumulated downtime for each asset to identify
equipment creating the greatest disruption to operations.

This helps separate frequent minor incidents from assets
causing significant operational interruptions.
-----------------------------------------------------------*/

SELECT
asset_id,
SUM(downtime_hours) AS total_downtime
FROM maintenance
GROUP BY asset_id
ORDER BY total_downtime DESC;

/*-----------------------------------------------------------
4. DOWNTIME & PRODUCTION PERFORMANCE

Compares asset downtime with recorded production output to
provide visibility into how reliability issues relate to
operational performance.

Assets combining significant downtime with important
production volumes may require higher maintenance priority.
-----------------------------------------------------------*/

SELECT
m.asset_id,
SUM(m.downtime_hours) AS downtime,
SUM(p.oil_production_barrels) AS production
FROM maintenance m
LEFT JOIN production p
ON m.asset_id = p.well_id
GROUP BY m.asset_id;

/*-----------------------------------------------------------
5. FAILURE MODE ANALYSIS

Identifies the most common failure types and measures the
average downtime associated with each one.

This helps maintenance teams understand whether operational
disruption is being driven by recurring failure patterns or
specific high impact failure categories.
-----------------------------------------------------------*/

SELECT
failure_type,
COUNT(*) AS occurrences,
AVG(downtime_hours) AS avg_downtime
FROM maintenance
GROUP BY failure_type
ORDER BY occurrences DESC;

/*-----------------------------------------------------------
6. EMISSIONS & ASSET FAILURE PROFILE

Compares average CO2 emissions with recorded failure activity
across assets.

This provides an additional operational signal for examining
whether assets with elevated emissions also show higher
maintenance activity.
-----------------------------------------------------------*/

SELECT
asset_id,
AVG(co2_tons) AS avg_emissions,
COUNT(*) AS failures
FROM v_asset_reliability
GROUP BY asset_id
ORDER BY avg_emissions DESC;

/*-----------------------------------------------------------
7. CRITICAL ASSET RISK IDENTIFICATION

Flags assets showing both repeated maintenance activity and
significant accumulated downtime.

Assets exceeding both thresholds represent stronger
candidates for reliability investigation and maintenance
prioritization.
-----------------------------------------------------------*/

SELECT
asset_id,
COUNT(*) AS failures,
SUM(downtime_hours) AS downtime,
SUM(CAST(cost_usd AS FLOAT)) AS cost
FROM maintenance
GROUP BY asset_id
HAVING
COUNT(*) > 5
AND SUM(downtime_hours) > 100;

/*-----------------------------------------------------------
8. MAINTENANCE SPEND VS PRODUCTION PERFORMANCE

Compares maintenance expenditure with production output for
each asset.

This helps management evaluate whether high maintenance
spending is associated with productive assets or whether
resources are being consumed by underperforming equipment.
-----------------------------------------------------------*/

SELECT
m.asset_id,
SUM(m.cost_usd) AS maintenance_cost,
SUM(p.oil_production_barrels) AS production
FROM maintenance m
LEFT JOIN production p
ON m.asset_id = p.well_id
GROUP BY m.asset_id;

/*-----------------------------------------------------------
9. MAINTENANCE PRIORITY ENGINE

Converts historical reliability indicators into clear
maintenance priorities based on failure frequency and
accumulated downtime.

Immediate Maintenance Required:
Assets with more than eight recorded maintenance events.

High Risk:
Assets with more than 120 hours of accumulated downtime.

Stable:
Assets currently below the defined intervention thresholds.

The output gives maintenance teams a simple way to prioritize
assets requiring further inspection or intervention.
-----------------------------------------------------------*/

SELECT
asset_id,
COUNT(*) AS failures,
SUM(downtime_hours) AS downtime,
SUM(CAST(cost_usd AS FLOAT)) AS cost,
CASE
    WHEN COUNT(*) > 3 THEN 'Immediate Maintenance Required'
    WHEN SUM(downtime_hours) > 100 THEN 'High Risk'
        WHEN SUM(downtime_hours) > 50 THEN 'Medium Risk'
    ELSE 'Low Risk'
END AS maintenance_action
FROM maintenance
GROUP BY asset_id;

/*===========================================================
DECISION VALUE

The final analysis gives Operations and Maintenance teams a
structured view of asset reliability rather than treating
maintenance events as isolated incidents.

Management can use the outputs to:

- Identify assets repeatedly consuming maintenance resources.
- Find equipment responsible for significant downtime.
- Prioritize critical assets for maintenance intervention.
- Understand which failure types create the most disruption.
- Compare maintenance spending with production performance.
- Investigate reliability patterns alongside emissions data.
- Focus maintenance resources where operational exposure is
greatest.
- Support a shift from reactive maintenance toward more
proactive asset management.

The result is a SQL based reliability monitoring framework
that turns maintenance history into practical asset
prioritization and operational decision support.
===========================================================*/
