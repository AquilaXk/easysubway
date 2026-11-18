-- Read-only PostgreSQL preflight. Run before deploying V63; success produces no rows or mutations.
DO $preflight$
DECLARE
    duplicate_sources TEXT;
BEGIN
    SELECT STRING_AGG(FORMAT('%s (%s RUNNING rows)', source, running_count), ', ' ORDER BY source)
    INTO duplicate_sources
    FROM (
        SELECT source, COUNT(*) AS running_count
        FROM data_collection_runs
        WHERE status = 'RUNNING'
        GROUP BY source
        HAVING COUNT(*) > 1
    ) conflicts;

    IF duplicate_sources IS NOT NULL THEN
        RAISE EXCEPTION 'V63 preflight blocked: duplicate RUNNING data_collection_runs by source: %', duplicate_sources
            USING HINT = 'Resolve each stale or duplicate run explicitly; this preflight performs no updates.';
    END IF;
END
$preflight$;
