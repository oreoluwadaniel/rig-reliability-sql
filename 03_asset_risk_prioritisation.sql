/* ============================================================
   PROJECT 03
   ASSET RISK SCORING AND MAINTENANCE PRIORITISATION

   Question this script answers:
   Out of three thousand assets, which ones does a maintenance
   team go and look at on Monday morning?

   Projects 01 and 02 each ranked assets on one thing. Cost
   ranks one way, downtime ranks another, failure frequency a
   third. An asset can top one list and sit in the middle of
   the others. This script pulls the three together into a
   single ordered list of names.

   Requires: sql/00_schema.sql to have been run first.
   Tested on PostgreSQL 14.
   ============================================================ */


/* ------------------------------------------------------------
   3.1  THE RELIABILITY VIEW, REBUILT

   This replaces the v_asset_reliability view from the
   original script. It was the most serious problem in the
   whole file, so it is worth setting out plainly.

   The original was:

       CREATE VIEW v_asset_reliability AS
       SELECT m.asset_id, m.maintenance_date, m.cost_usd,
              m.failure_type, m.downtime_hours, p.well_id,
              p.oil_production_barrels, p.date, e.co2_tons,
              e.methane_leakage_tons, e.energy_consumption_mwh
       FROM maintenance m
       LEFT JOIN production p ON m.asset_id = p.well_id
       LEFT JOIN emissions  e ON m.asset_id = e.asset_id;

   Three things go wrong here.

   First, neither join is on a unique key. maintenance holds
   many rows per asset, production holds many rows per well,
   and emissions holds many rows per asset. Joining all three
   at row level gives every combination of the three. One
   asset with 4 maintenance events, 3 production readings and
   2 emissions readings produces 24 rows where it should
   produce 4. Every SUM, COUNT and AVG taken off this view is
   wrong, and the size of the error is different for every
   asset.

   Second, there is no date condition anywhere. A maintenance
   event from 2018 gets joined to a production reading from
   2024. So even after the duplication is fixed, the
   production figure sitting next to a failure is not the
   production around that failure. It is lifetime production.
   The corrected view still reports lifetime totals, but it
   labels them as such rather than implying a link that is not
   there.

   Third, the view is one grain pretending to be another. It
   looks like an asset level summary and is actually an event
   level join. Anyone reading the column list would reasonably
   assume one row per asset.

   The rebuild aggregates each source to one row per asset
   first, then joins. The grain is now genuinely one row per
   asset, which is what every downstream query expects.
------------------------------------------------------------ */

CREATE OR REPLACE VIEW v_asset_reliability AS
WITH maint AS (
    SELECT
        asset_id,
        COUNT(*)                        AS failure_count,
        SUM(cost_usd)                   AS total_maintenance_cost,
        ROUND(AVG(cost_usd), 2)         AS avg_cost_per_failure,
        SUM(downtime_hours)             AS total_downtime_hours,
        ROUND(AVG(downtime_hours), 1)   AS avg_downtime_per_failure,
        MAX(downtime_hours)             AS worst_outage_hours,
        MIN(maintenance_date)           AS first_failure,
        MAX(maintenance_date)           AS latest_failure,
        MODE() WITHIN GROUP (ORDER BY failure_type) AS most_common_failure_type
    FROM maintenance
    GROUP BY asset_id
),
prod AS (
    SELECT
        well_id,
        COUNT(*)                        AS production_readings,
        SUM(oil_production_barrels)     AS total_oil_barrels,
        SUM(gas_production_mcf)         AS total_gas_mcf,
        ROUND(AVG(water_cut_pct), 2)    AS avg_water_cut_pct,
        ROUND(AVG(pressure_psi), 0)     AS avg_pressure_psi
    FROM production
    GROUP BY well_id
),
emis AS (
    SELECT
        asset_id,
        COUNT(*)                            AS emissions_readings,
        ROUND(AVG(co2_tons), 2)             AS avg_co2_tons,
        SUM(co2_tons)                       AS total_co2_tons,
        ROUND(AVG(methane_leakage_tons), 2) AS avg_methane_tons,
        ROUND(AVG(energy_consumption_mwh), 2) AS avg_energy_mwh
    FROM emissions
    GROUP BY asset_id
)
SELECT
    m.asset_id,
    asset_class(m.asset_id)         AS asset_type,
    m.failure_count,
    m.total_maintenance_cost,
    m.avg_cost_per_failure,
    m.total_downtime_hours,
    m.avg_downtime_per_failure,
    m.worst_outage_hours,
    m.most_common_failure_type,
    m.first_failure,
    m.latest_failure,
    p.production_readings,
    p.total_oil_barrels,
    p.total_gas_mcf,
    p.avg_water_cut_pct,
    p.avg_pressure_psi,
    e.emissions_readings,
    e.avg_co2_tons,
    e.total_co2_tons,
    e.avg_methane_tons,
    e.avg_energy_mwh
FROM maint m
LEFT JOIN prod p ON m.asset_id = p.well_id
LEFT JOIN emis e ON m.asset_id = e.asset_id;


/* ------------------------------------------------------------
   3.2  EMISSIONS AND FAILURE ACTIVITY

   The corrected version of the original query 6.

   The original ran COUNT(*) against the old view and called
   the result "failures". Because the view had multiplied
   every asset's rows together, that count was not a failure
   count at all. It was maintenance events multiplied by
   production readings multiplied by emissions readings.

   The average CO2 figure had the same problem in a subtler
   form. Averaging over duplicated rows silently weights each
   asset by how many maintenance and production rows it
   happened to have, so assets that failed more often pulled
   the average around for reasons that had nothing to do with
   emissions.

   Reading the same numbers off the rebuilt view gives one row
   per asset, so the count is a real failure count and the
   average is a real average.

   One caveat that belongs in the output rather than in a
   footnote: this shows whether high emitting assets also
   break often. It does not show that one causes the other.
   Both are likely driven by how hard the asset is worked.
------------------------------------------------------------ */

SELECT
    asset_id,
    asset_type,
    failure_count,
    total_downtime_hours,
    avg_co2_tons,
    avg_methane_tons,
    avg_energy_mwh,
    NTILE(4) OVER (ORDER BY avg_co2_tons DESC NULLS LAST) AS emissions_quartile,
    NTILE(4) OVER (ORDER BY failure_count DESC)           AS failure_quartile
FROM v_asset_reliability
WHERE avg_co2_tons IS NOT NULL
ORDER BY avg_co2_tons DESC;


/* Does the pattern hold at group level. If the two rankings
   were unrelated, average failures would be roughly flat
   across all four emissions quartiles. */

WITH banded AS (
    SELECT
        asset_id,
        failure_count,
        total_downtime_hours,
        avg_co2_tons,
        NTILE(4) OVER (ORDER BY avg_co2_tons DESC) AS emissions_quartile
    FROM v_asset_reliability
    WHERE avg_co2_tons IS NOT NULL
)
SELECT
    emissions_quartile,
    CASE emissions_quartile
        WHEN 1 THEN 'Highest emitting quarter'
        WHEN 2 THEN 'Above average'
        WHEN 3 THEN 'Below average'
        WHEN 4 THEN 'Lowest emitting quarter'
    END                                     AS band,
    COUNT(*)                                AS assets,
    ROUND(AVG(avg_co2_tons), 2)             AS mean_co2_tons,
    ROUND(AVG(failure_count), 2)            AS mean_failures_per_asset,
    ROUND(AVG(total_downtime_hours), 1)     AS mean_downtime_hours
FROM banded
GROUP BY emissions_quartile
ORDER BY emissions_quartile;


/* ------------------------------------------------------------
   3.3  ASSETS THAT FAIL OFTEN AND STAY DOWN LONG

   The corrected version of the original query 7.

   The original logic was sound. It looked for assets clearing
   both a failure count threshold and a downtime threshold,
   which is the right shape of question. The problem was the
   numbers. More than 5 failures and more than 100 hours were
   picked out of the air, and the next query in the same
   script used more than 3 failures for what was effectively
   the same test. Two definitions of "risky" in one file is
   the kind of thing that gets picked apart in review.

   Here the thresholds come from the data. An asset qualifies
   if it sits in the top 10 percent for failure count and the
   top 10 percent for downtime. That definition holds up when
   the data refreshes, and it is defensible in a meeting
   because it describes a position in the fleet rather than an
   arbitrary number.
------------------------------------------------------------ */

WITH thresholds AS (
    SELECT
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY failure_count)
            AS failure_p90,
        PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY total_downtime_hours)
            AS downtime_p90
    FROM v_asset_reliability
)
SELECT
    r.asset_id,
    r.asset_type,
    r.failure_count,
    r.total_downtime_hours,
    r.total_maintenance_cost,
    r.most_common_failure_type,
    r.total_oil_barrels,
    ROUND(t.failure_p90::NUMERIC, 1)   AS failure_threshold_used,
    ROUND(t.downtime_p90::NUMERIC, 1)  AS downtime_threshold_used
FROM v_asset_reliability r
CROSS JOIN thresholds t
WHERE r.failure_count       >= t.failure_p90
  AND r.total_downtime_hours >= t.downtime_p90
ORDER BY r.total_downtime_hours DESC, r.failure_count DESC;


/* ------------------------------------------------------------
   3.4  THE PRIORITY ENGINE

   The corrected version of the original query 9, and the one
   that needed the most work.

   Two problems with the original.

   The comment block above it said "more than eight recorded
   maintenance events" and "more than 120 hours of accumulated
   downtime", and described three tiers. The code underneath
   used more than 3 events, more than 100 hours, and had four
   tiers. Documentation and logic disagreeing is worse than
   either being wrong on its own, because a reader has no way
   to know which one was intended.

   The bigger issue is the CASE ladder itself. Because failure
   count is tested first, an asset with 4 failures and 20
   hours of downtime is labelled "Immediate Maintenance
   Required", while an asset with 3 failures and 600 hours of
   downtime falls through to "High Risk". The ladder makes one
   dimension override the other, which is not what anybody
   means by risk.

   This version scores each asset on three dimensions instead,
   converts each to a percentile so they are on the same
   scale, and combines them with weights that are written down
   and can be argued with.

   Weights and the reasoning:
     Downtime  50 percent. Lost hours are lost production, so
               this is the closest proxy for money the data
               offers.
     Frequency 30 percent. Repeat failures signal an unsolved
               root cause, which is the thing maintenance can
               actually fix.
     Cost      20 percent. Real, but partly a consequence of
               the other two, so it gets the smallest share.

   Change the weights and the ranking changes. That is the
   point. They are visible and adjustable rather than hidden
   inside a threshold nobody can explain.
------------------------------------------------------------ */

WITH scored AS (
    SELECT
        asset_id,
        asset_type,
        failure_count,
        total_downtime_hours,
        total_maintenance_cost,
        most_common_failure_type,
        total_oil_barrels,
        latest_failure,
        PERCENT_RANK() OVER (ORDER BY total_downtime_hours)    AS downtime_pct,
        PERCENT_RANK() OVER (ORDER BY failure_count)           AS frequency_pct,
        PERCENT_RANK() OVER (ORDER BY total_maintenance_cost)  AS cost_pct
    FROM v_asset_reliability
),
weighted AS (
    SELECT
        *,
        ROUND(
            (100 * (
                  0.50 * downtime_pct
                + 0.30 * frequency_pct
                + 0.20 * cost_pct
            ))::NUMERIC,
        1) AS risk_score
    FROM scored
)
SELECT
    asset_id,
    asset_type,
    failure_count,
    total_downtime_hours,
    total_maintenance_cost,
    most_common_failure_type,
    total_oil_barrels,
    latest_failure,
    risk_score,
    CASE
        WHEN risk_score >= 95 THEN '1. Inspect now'
        WHEN risk_score >= 85 THEN '2. Schedule this quarter'
        WHEN risk_score >= 60 THEN '3. Monitor'
        ELSE                       '4. No action'
    END AS recommended_action,
    ROUND((100 * 0.50 * downtime_pct)::NUMERIC, 1)  AS downtime_contribution,
    ROUND((100 * 0.30 * frequency_pct)::NUMERIC, 1) AS frequency_contribution,
    ROUND((100 * 0.20 * cost_pct)::NUMERIC, 1)      AS cost_contribution
FROM weighted
ORDER BY risk_score DESC;


/* ------------------------------------------------------------
   3.5  HOW BIG IS EACH ACTION GROUP

   Before handing a priority list to anyone, check that the
   top band is a size a real team can work through.

   If "Inspect now" comes back with 400 assets, the banding
   has failed regardless of how good the scoring is, because
   nobody is inspecting 400 assets. The thresholds in 3.4
   should be tightened until the top band is a week of work.
------------------------------------------------------------ */

WITH scored AS (
    SELECT
        asset_id,
        total_downtime_hours,
        total_maintenance_cost,
        failure_count,
        ROUND(
            (100 * (
                  0.50 * PERCENT_RANK() OVER (ORDER BY total_downtime_hours)
                + 0.30 * PERCENT_RANK() OVER (ORDER BY failure_count)
                + 0.20 * PERCENT_RANK() OVER (ORDER BY total_maintenance_cost)
            ))::NUMERIC,
        1) AS risk_score
    FROM v_asset_reliability
)
SELECT
    CASE
        WHEN risk_score >= 95 THEN '1. Inspect now'
        WHEN risk_score >= 85 THEN '2. Schedule this quarter'
        WHEN risk_score >= 60 THEN '3. Monitor'
        ELSE                       '4. No action'
    END AS recommended_action,
    COUNT(*)                                AS assets,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_fleet,
    SUM(total_downtime_hours)               AS downtime_hours_covered,
    ROUND(
        100.0 * SUM(total_downtime_hours)
        / SUM(SUM(total_downtime_hours)) OVER (),
    1) AS pct_of_all_downtime_covered,
    SUM(total_maintenance_cost)             AS cost_covered
FROM scored
GROUP BY 1
ORDER BY 1;


/* ------------------------------------------------------------
   3.6  THE MONDAY MORNING LIST

   Everything above, reduced to the assets in the top band and
   the fields a planner needs to act. Nothing else.

   A report that requires interpretation before anyone can do
   anything with it is a report that sits unread. This one is
   short enough to print.
------------------------------------------------------------ */

WITH scored AS (
    SELECT
        asset_id,
        asset_type,
        failure_count,
        total_downtime_hours,
        total_maintenance_cost,
        most_common_failure_type,
        total_oil_barrels,
        latest_failure,
        ROUND(
            (100 * (
                  0.50 * PERCENT_RANK() OVER (ORDER BY total_downtime_hours)
                + 0.30 * PERCENT_RANK() OVER (ORDER BY failure_count)
                + 0.20 * PERCENT_RANK() OVER (ORDER BY total_maintenance_cost)
            ))::NUMERIC,
        1) AS risk_score
    FROM v_asset_reliability
)
SELECT
    ROW_NUMBER() OVER (ORDER BY risk_score DESC) AS priority,
    asset_id,
    asset_type,
    most_common_failure_type    AS likely_fault,
    failure_count               AS failures_to_date,
    total_downtime_hours        AS hours_lost,
    total_maintenance_cost      AS spend_to_date,
    total_oil_barrels           AS barrels_produced,
    latest_failure              AS last_seen,
    risk_score
FROM scored
WHERE risk_score >= 95
ORDER BY risk_score DESC;
