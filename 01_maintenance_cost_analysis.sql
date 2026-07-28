/* ============================================================
   PROJECT 01
   MAINTENANCE COST EXPOSURE AND SPEND EFFICIENCY

   Question this script answers:
   Where is the maintenance budget going, and is it going to
   assets that earn their keep?

   Requires: sql/00_schema.sql to have been run first.
   Tested on PostgreSQL 14.
   ============================================================ */


/* ------------------------------------------------------------
   1.1  WHAT EACH ASSET COSTS US

   Total maintenance spend per asset, plus the two numbers you
   always want next to a total: how many events made it up,
   and what the average event cost.

   A total on its own is ambiguous. An asset with 400,000
   dollars of spend across two events is a different problem
   from an asset with 400,000 dollars across twenty. The first
   is probably a major overhaul. The second is an asset that
   will not stay fixed.

   Changed from the original:
   The original cast cost_usd to FLOAT. FLOAT is a binary
   approximation, so summing thousands of currency values in
   it introduces rounding drift. cost_usd is NUMERIC now and
   the cast is gone.
------------------------------------------------------------ */

SELECT
    asset_id,
    asset_class(asset_id)                    AS asset_type,
    COUNT(*)                                 AS maintenance_events,
    SUM(cost_usd)                            AS total_maintenance_cost,
    ROUND(AVG(cost_usd), 2)                  AS avg_cost_per_event,
    MAX(cost_usd)                            AS largest_single_event,
    MIN(maintenance_date)                    AS first_event,
    MAX(maintenance_date)                    AS latest_event
FROM maintenance
GROUP BY asset_id
ORDER BY total_maintenance_cost DESC;


/* ------------------------------------------------------------
   1.2  HOW CONCENTRATED IS THE SPEND

   A ranked list tells you who is at the top. It does not tell
   you whether the top matters.

   This adds the share of total spend each asset accounts for
   and a running cumulative share. Read down the cumulative
   column until it crosses 50 percent. However many assets it
   took to get there is the size of the problem you actually
   have to manage.

   If 30 assets out of 3,000 account for half the budget, the
   fix is a named list of 30 assets. If it takes 1,200 assets
   to reach half, there is no shortlist to be had and the
   answer has to be a policy change instead.
------------------------------------------------------------ */

WITH asset_cost AS (
    SELECT
        asset_id,
        asset_class(asset_id) AS asset_type,
        COUNT(*)              AS maintenance_events,
        SUM(cost_usd)         AS total_cost
    FROM maintenance
    GROUP BY asset_id
)
SELECT
    ROW_NUMBER() OVER (ORDER BY total_cost DESC)  AS cost_rank,
    asset_id,
    asset_type,
    maintenance_events,
    total_cost,
    ROUND(100.0 * total_cost / SUM(total_cost) OVER (), 3) AS pct_of_total_spend,
    ROUND(
        100.0 * SUM(total_cost) OVER (
            ORDER BY total_cost DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(total_cost) OVER (),
    2) AS cumulative_pct_of_spend
FROM asset_cost
ORDER BY total_cost DESC;


/* ------------------------------------------------------------
   1.3  SPEND BY ASSET TYPE

   Rolls the same spend up to wells, pipelines and refineries
   so the picture can be handed to someone who owns a budget
   rather than an individual pump.
------------------------------------------------------------ */

SELECT
    asset_class(asset_id)                    AS asset_type,
    COUNT(DISTINCT asset_id)                 AS assets,
    COUNT(*)                                 AS maintenance_events,
    SUM(cost_usd)                            AS total_cost,
    ROUND(AVG(cost_usd), 2)                  AS avg_cost_per_event,
    ROUND(SUM(cost_usd) / COUNT(DISTINCT asset_id), 2) AS avg_cost_per_asset,
    ROUND(100.0 * SUM(cost_usd) / SUM(SUM(cost_usd)) OVER (), 2) AS pct_of_total_spend
FROM maintenance
GROUP BY 1
ORDER BY total_cost DESC;


/* ------------------------------------------------------------
   1.4  SPEND AGAINST PRODUCTION

   This is the query the original script got wrong, and it is
   worth being precise about why.

   The original was:

       SELECT m.asset_id,
              SUM(m.cost_usd)  AS maintenance_cost,
              SUM(p.oil_production_barrels) AS production
       FROM maintenance m
       LEFT JOIN production p ON m.asset_id = p.well_id
       GROUP BY m.asset_id;

   Both tables hold many rows per asset. Joining them before
   aggregating produces one row for every possible pairing.
   An asset with 4 maintenance events and 3 production
   readings yields 12 rows, so the cost is counted 3 times
   over and the production is counted 4 times over. Neither
   total is real, and the ratio between them is not real
   either.

   The fix is to collapse each table to one row per asset
   first, then join. Now every asset contributes its cost once
   and its production once.

   The second fix is the WHERE clause. Pipelines and
   refineries do not appear in the production table at all, so
   the original returned NULL production for every one of
   them. Left in the same list as wells, they look like assets
   that burn money and produce nothing. They are excluded here
   and reported separately in 1.5.
------------------------------------------------------------ */

WITH maint AS (
    SELECT
        asset_id,
        COUNT(*)      AS maintenance_events,
        SUM(cost_usd) AS total_maintenance_cost,
        SUM(downtime_hours) AS total_downtime_hours
    FROM maintenance
    GROUP BY asset_id
),
prod AS (
    SELECT
        well_id,
        COUNT(*)                      AS production_readings,
        SUM(oil_production_barrels)   AS total_oil_barrels,
        SUM(gas_production_mcf)       AS total_gas_mcf
    FROM production
    GROUP BY well_id
)
SELECT
    m.asset_id,
    m.maintenance_events,
    m.total_maintenance_cost,
    m.total_downtime_hours,
    p.production_readings,
    p.total_oil_barrels,
    ROUND(m.total_maintenance_cost / NULLIF(p.total_oil_barrels, 0), 2)
        AS maintenance_cost_per_barrel
FROM maint m
LEFT JOIN prod p
       ON m.asset_id = p.well_id
WHERE asset_class(m.asset_id) = 'Well'
ORDER BY m.total_maintenance_cost DESC;


/* ------------------------------------------------------------
   1.5  WELLS WITH SPEND BUT NO PRODUCTION RECORD

   Kept as its own query rather than hidden inside the one
   above.

   These are wells that appear in the maintenance table and do
   not appear in the production table. That is either a real
   operational fact, meaning the well is shut in and still
   being maintained, or it is a data gap. Both are worth
   knowing about and they need different follow ups, so the
   honest thing is to surface them and say so rather than let
   them sit as NULLs in the main output.
------------------------------------------------------------ */

SELECT
    m.asset_id,
    COUNT(*)            AS maintenance_events,
    SUM(m.cost_usd)     AS total_maintenance_cost,
    SUM(m.downtime_hours) AS total_downtime_hours
FROM maintenance m
WHERE asset_class(m.asset_id) = 'Well'
  AND NOT EXISTS (
        SELECT 1 FROM production p WHERE p.well_id = m.asset_id
      )
GROUP BY m.asset_id
ORDER BY total_maintenance_cost DESC;


/* ------------------------------------------------------------
   1.6  COST EFFICIENCY BANDS

   Turns cost per barrel into something a person can act on.

   The bands are set from the data rather than from a number
   somebody picked. NTILE splits the wells into four equal
   groups by cost per barrel, so the labels stay meaningful
   even if the underlying cost base moves. A hardcoded
   threshold of, say, 50 dollars a barrel is correct only
   until prices or volumes change, and then it quietly stops
   being correct without anyone noticing.

   Only wells with recorded production are ranked, because
   cost per barrel is undefined without a denominator.
------------------------------------------------------------ */

WITH maint AS (
    SELECT asset_id, COUNT(*) AS events, SUM(cost_usd) AS total_cost
    FROM maintenance
    GROUP BY asset_id
),
prod AS (
    SELECT well_id, SUM(oil_production_barrels) AS total_oil
    FROM production
    GROUP BY well_id
),
joined AS (
    SELECT
        m.asset_id,
        m.events,
        m.total_cost,
        p.total_oil,
        m.total_cost / p.total_oil AS cost_per_barrel
    FROM maint m
    JOIN prod p ON m.asset_id = p.well_id
    WHERE p.total_oil > 0
)
SELECT
    asset_id,
    events                          AS maintenance_events,
    total_cost                      AS total_maintenance_cost,
    total_oil                       AS total_oil_barrels,
    ROUND(cost_per_barrel, 2)       AS cost_per_barrel,
    CASE NTILE(4) OVER (ORDER BY cost_per_barrel DESC)
        WHEN 1 THEN 'Worst quarter, review first'
        WHEN 2 THEN 'Above average cost'
        WHEN 3 THEN 'Below average cost'
        WHEN 4 THEN 'Best quarter, leave alone'
    END AS efficiency_band
FROM joined
ORDER BY cost_per_barrel DESC;


/* ------------------------------------------------------------
   1.7  IS SPEND GROWING

   Maintenance cost by year, with the change on the previous
   year.

   Nothing in the original script looked at time, which meant
   a budget that had doubled over the period would have been
   invisible. A single lifetime total cannot tell you whether
   a problem is getting better or worse, and that is usually
   the first thing anyone senior asks.
------------------------------------------------------------ */

WITH yearly AS (
    SELECT
        EXTRACT(YEAR FROM maintenance_date)::INT AS year,
        COUNT(*)                                 AS maintenance_events,
        SUM(cost_usd)                            AS total_cost,
        SUM(downtime_hours)                      AS total_downtime_hours
    FROM maintenance
    GROUP BY 1
)
SELECT
    year,
    maintenance_events,
    total_cost,
    total_downtime_hours,
    total_cost - LAG(total_cost) OVER (ORDER BY year) AS change_vs_prior_year,
    ROUND(
        100.0 * (total_cost - LAG(total_cost) OVER (ORDER BY year))
        / NULLIF(LAG(total_cost) OVER (ORDER BY year), 0),
    2) AS pct_change_vs_prior_year
FROM yearly
ORDER BY year;
