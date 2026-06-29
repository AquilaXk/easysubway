ALTER TABLE data_source_snapshots
	ADD COLUMN raw_retention_expires_at TIMESTAMP;

UPDATE data_source_snapshots
SET raw_retention_expires_at = freshness_expires_at
WHERE raw_retention_expires_at IS NULL;

ALTER TABLE data_source_snapshots
	ALTER COLUMN raw_retention_expires_at SET NOT NULL;

ALTER TABLE data_source_snapshots
	ADD CONSTRAINT chk_data_source_snapshots_credential_redacted
		CHECK (credential_redacted = TRUE),
	ADD CONSTRAINT chk_data_source_snapshots_raw_object_uri
		CHECK ((raw_object_uri LIKE 's3://%' OR raw_object_uri LIKE 'oci://%') AND POSITION('?' IN raw_object_uri) = 0 AND POSITION('@' IN raw_object_uri) = 0 AND POSITION('#' IN raw_object_uri) = 0),
	ADD CONSTRAINT chk_data_source_snapshots_raw_retention
		CHECK (raw_retention_expires_at > retrieved_at);
