/* ============================================================
   PROJECT 02
   FAILURE FREQUENCY AND DOWNTIME EXPOSURE

   Question this script answers:
   What is actually breaking, how often, and how much
   operating time does it cost us?

   Cost is only half the story. An asset can be cheap to fix
   and still be the worst thing in the field if it keeps
   stopping production. This script looks at frequency and
   lost hours instead of dollars.

   Requires: sql/00_schema.sql to have been run first.
   Tested on PostgreSQL 14.
   ============================================================ */


/* ------------------------------------------------------------
   2.1  HOW OFTEN EACH ASSET FAILS

   Failure count per asset, with the time span it happened
   over and the average gap between events.

   The original returned just asset_id and a count. That is
   fine as far as it goes, but a count with no time context
   is misleading. Six failures in six years is routine
   maintenance. Six failures in six months is an asset that
   needs taking out of service.

   The average days between failures is the number that
   separates those two cases, and it is the closest thing this
   dataset gives you to mean time between failures.
------------------------------------------------------------ */

SELECT
    asset_id,
    asset_class(asset_id)                        AS asset_type,
    COUNT(*)                                     AS failure_count,
    MIN(maintenance_date)                        AS first_failure,
    MAX(maintenance_date)                        AS latest_failure,
    (MAX(maintenance_date) - MIN(maintenance_date)) AS days_covered,
    CASE
        WHEN COUNT(*) > 1
        THEN ROUND(
                (MAX(maintenance_date) - MIN(maintenance_date))::NUMERIC
                / (COUNT(*) - 1),
             1)
    END AS avg_days_between_failures
FROM maintenance
GROUP BY asset_id
ORDER BY failure_count DESC, avg_days_between_failures ASC;


/* ------------------------------------------------------------
   2.2  WHERE THE LOST HOURS SIT

   Total downtime per asset, alongside the failure count, so
   frequent small stoppages can be told apart from rare long
   ones.

   These two groups need opposite responses. Lots of short
   outages usually means a recurring fault nobody has traced
   to root cause. One very long outage usually means a part
   that was not in stores when it was needed. Ranking on total
   hours alone hides the difference, so both columns are here
   and the average is spelled out.
------------------------------------------------------------ */

SELECT
    asset_id,
    asset_class(asset_id)              AS asset_type,
    COUNT(*)                           AS failure_count,
    SUM(downtime_hours)                AS total_downtime_hours,
    ROUND(AVG(downtime_hours), 1)      AS avg_hours_per_failure,
    MAX(downtime_hours)                AS longest_single_outage,
    ROUND(SUM(downtime_hours) / 24.0, 1) AS total_downtime_days
FROM maintenance
GROUP BY asset_id
ORDER BY total_downtime_hours DESC;


/* ------------------------------------------------------------
   2.3  DOWNTIME CONCENTRATION

   Same idea as the cost Pareto in project 01, applied to
   hours.

   The point of this query is to size the problem before
   solving it. If a small number of assets carry most of the
   lost hours, a targeted programme will work. If the hours
   are spread evenly across hundreds of assets, targeting will
   not move the number and the answer has to be something
   systemic like spares policy or inspection frequency.
------------------------------------------------------------ */

WITH asset_downtime AS (
    SELECT
        asset_id,
        asset_class(asset_id) AS asset_type,
        COUNT(*)              AS failure_count,
        SUM(downtime_hours)   AS total_downtime
    FROM maintenance
    GROUP BY asset_id
)
SELECT
    ROW_NUMBER() OVER (ORDER BY total_downtime DESC) AS downtime_rank,
    asset_id,
    asset_type,
    failure_count,
    total_downtime,
    ROUND(100.0 * total_downtime / SUM(total_downtime) OVER (), 3)
        AS pct_of_total_downtime,
    ROUND(
        100.0 * SUM(total_downtime) OVER (
            ORDER BY total_downtime DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(total_downtime) OVER (),
    2) AS cumulative_pct_of_downtime
FROM asset_downtime
ORDER BY total_downtime DESC;


/* ------------------------------------------------------------
   2.4  WHAT KIND OF FAILURES ARE THESE

   Failure types ranked by how often they happen, with the
   downtime and cost they carry.

   The original ordered by occurrence count. That answers
   "what is most common" but not "what hurts most", and those
   are rarely the same failure type. A fault that happens 400
   times and takes two hours to clear is an annoyance. A fault
   that happens 40 times and takes three days is where the
   lost production actually is.

   Total downtime is added here for exactly that reason, and
   the sort is on total hours rather than count.
------------------------------------------------------------ */

SELECT
    failure_type,
    COUNT(*)                        AS occurrences,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_all_failures,
    SUM(downtime_hours)             AS total_downtime_hours,
    ROUND(AVG(downtime_hours), 1)   AS avg_downtime_hours,
    MAX(downtime_hours)             AS worst_outage_hours,
    SUM(cost_usd)                   AS total_cost,
    ROUND(AVG(cost_usd), 2)         AS avg_cost_per_event,
    ROUND(100.0 * SUM(downtime_hours) / SUM(SUM(downtime_hours)) OVER (), 2)
        AS pct_of_all_downtime
FROM maintenance
GROUP BY failure_type
ORDER BY total_downtime_hours DESC;


/* ------------------------------------------------------------
   2.5  FAILURE TYPES BY ASSET TYPE

   Wells, pipelines and refineries do not fail the same way,
   and lumping them together produces an average that
   describes none of them.

   This crosstab shows which failure modes belong to which
   kind of kit. It is the query that tells a maintenance
   planner whether corrosion is a pipeline issue, a well
   issue, or everybody's issue.
------------------------------------------------------------ */

SELECT
    asset_class(asset_id)           AS asset_type,
    failure_type,
    COUNT(*)                        AS occurrences,
    SUM(downtime_hours)             AS total_downtime_hours,
    ROUND(AVG(downtime_hours), 1)   AS avg_downtime_hours,
    SUM(cost_usd)                   AS total_cost,
    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (PARTITION BY asset_class(asset_id)),
    2) AS pct_within_asset_type
FROM maintenance
GROUP BY 1, 2
ORDER BY asset_type, total_downtime_hours DESC;


/* ------------------------------------------------------------
   2.6  DOWNTIME AGAINST PRODUCTION

   The corrected version of the original query 4.

   The original joined maintenance to production and then
   summed both sides:

       SELECT m.asset_id,
              SUM(m.downtime_hours) AS downtime,
              SUM(p.oil_production_barrels) AS production
       FROM maintenance m
       LEFT JOIN production p ON m.asset_id = p.well_id
       GROUP BY m.asset_id;

   Because both tables hold several rows per asset, the join
   multiplies them together before the SUM runs. Every
   downtime figure gets repeated once per production reading,
   and every production figure gets repeated once per
   maintenance event. Both totals come out too high, and by a
   different multiple for each asset, so you cannot even
   correct for it afterwards.

   Aggregating each side separately and joining the results
   fixes it. Pipelines and refineries are excluded because
   they carry no production rows.
------------------------------------------------------------ */

WITH downtime AS (
    SELECT
        asset_id,
        COUNT(*)            AS failure_count,
        SUM(downtime_hours) AS total_downtime_hours,
        SUM(cost_usd)       AS total_cost
    FROM maintenance
    GROUP BY asset_id
),
well_output AS (
    SELECT
        well_id,
        COUNT(*)                    AS production_readings,
        SUM(oil_production_barrels) AS total_oil_barrels,
        ROUND(AVG(water_cut_pct), 2) AS avg_water_cut_pct,
        ROUND(AVG(pressure_psi), 0)  AS avg_pressure_psi
    FROM production
    GROUP BY well_id
)
SELECT
    d.asset_id,
    d.failure_count,
    d.total_downtime_hours,
    d.total_cost,
    o.production_readings,
    o.total_oil_barrels,
    o.avg_water_cut_pct,
    o.avg_pressure_psi,
    ROUND(o.total_oil_barrels::NUMERIC / NULLIF(d.total_downtime_hours, 0), 1)
        AS barrels_per_downtime_hour
FROM downtime d
LEFT JOIN well_output o
       ON d.asset_id = o.well_id
WHERE asset_class(d.asset_id) = 'Well'
ORDER BY d.total_downtime_hours DESC;


/* ------------------------------------------------------------
   2.7  HIGH DOWNTIME ON HIGH PRODUCING WELLS

   Downtime matters most where the barrels are. A hundred lost
   hours on a well that barely produces is a nuisance. The
   same hundred hours on a top producer is real lost revenue.

   This ranks wells on both dimensions and keeps the ones that
   are in the worst quarter for downtime and the best quarter
   for production. That combination is the shortlist worth
   taking into a planning meeting.
------------------------------------------------------------ */

WITH downtime AS (
    SELECT asset_id, COUNT(*) AS failure_count,
           SUM(downtime_hours) AS total_downtime
    FROM maintenance
    GROUP BY asset_id
),
well_output AS (
    SELECT well_id, SUM(oil_production_barrels) AS total_oil
    FROM production
    GROUP BY well_id
),
ranked AS (
    SELECT
        d.asset_id,
        d.failure_count,
        d.total_downtime,
        o.total_oil,
        NTILE(4) OVER (ORDER BY d.total_downtime DESC) AS downtime_quartile,
        NTILE(4) OVER (ORDER BY o.total_oil DESC)      AS production_quartile
    FROM downtime d
    JOIN well_output o ON d.asset_id = o.well_id
    WHERE asset_class(d.asset_id) = 'Well'
      AND o.total_oil > 0
)
SELECT
    asset_id,
    failure_count,
    total_downtime      AS total_downtime_hours,
    total_oil           AS total_oil_barrels,
    downtime_quartile,
    production_quartile,
    'High downtime on a high producing well' AS why_it_is_here
FROM ranked
WHERE downtime_quartile = 1
  AND production_quartile = 1
ORDER BY total_downtime DESC, total_oil DESC;


/* ------------------------------------------------------------
   2.8  IS RELIABILITY DRIFTING

   Failures and lost hours by year.

   One line per year is often the most persuasive output in
   the whole analysis, because it shows direction rather than
   position. Management can argue about whether 40,000 hours
   is a lot. They cannot argue with the same number rising
   every year for five years.
------------------------------------------------------------ */

WITH yearly AS (
    SELECT
        EXTRACT(YEAR FROM maintenance_date)::INT AS year,
        COUNT(*)                                 AS failures,
        COUNT(DISTINCT asset_id)                 AS assets_affected,
        SUM(downtime_hours)                      AS total_downtime_hours,
        ROUND(AVG(downtime_hours), 1)            AS avg_downtime_per_failure
    FROM maintenance
    GROUP BY 1
)
SELECT
    year,
    failures,
    assets_affected,
    total_downtime_hours,
    avg_downtime_per_failure,
    total_downtime_hours - LAG(total_downtime_hours) OVER (ORDER BY year)
        AS downtime_change_vs_prior_year,
    ROUND(
        100.0 * (failures - LAG(failures) OVER (ORDER BY year))
        / NULLIF(LAG(failures) OVER (ORDER BY year), 0),
    2) AS pct_change_in_failures
FROM yearly
ORDER BY year;
