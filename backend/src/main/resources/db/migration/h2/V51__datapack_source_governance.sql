ALTER TABLE data_source_snapshots ADD COLUMN coverage_count INTEGER;
ALTER TABLE data_source_snapshots ADD COLUMN diff_summary_json CLOB;
ALTER TABLE data_source_snapshots ADD COLUMN governance_policy_version VARCHAR(32);
ALTER TABLE data_source_snapshots ADD COLUMN governance_policy_sha256 VARCHAR(64);

UPDATE data_source_snapshots
SET coverage_count = row_count
WHERE coverage_count IS NULL;

ALTER TABLE data_source_snapshots ADD CONSTRAINT chk_data_source_snapshots_coverage_count CHECK (coverage_count >= 0);
ALTER TABLE data_source_snapshots ADD CONSTRAINT chk_data_source_snapshots_governance_pair CHECK ((governance_policy_version IS NULL) = (governance_policy_sha256 IS NULL));
ALTER TABLE data_source_snapshots ADD CONSTRAINT fk_data_source_snapshots_previous_source FOREIGN KEY (previous_snapshot_id, source_id) REFERENCES data_source_snapshots(snapshot_id, source_id) ON DELETE RESTRICT ON UPDATE RESTRICT;

CREATE UNIQUE INDEX uq_data_source_snapshots_previous_child ON data_source_snapshots (previous_snapshot_id);
