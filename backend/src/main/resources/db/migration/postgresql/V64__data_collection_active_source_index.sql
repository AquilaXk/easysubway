CREATE UNIQUE INDEX CONCURRENTLY ux_data_collection_runs_active_source
    ON data_collection_runs (active_source);
