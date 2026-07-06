-- #1694 Part A: release request 진실 원천을 backend로 이전.
-- schemaVersion/artifactKind는 release-request.schema.json const라 저장하지 않고 조회 API가 방출한다.
CREATE TABLE datapack_release_request (
    approval_id              VARCHAR(255) NOT NULL PRIMARY KEY,
    candidate_id             VARCHAR(255) NOT NULL,
    scope_id                 VARCHAR(255) NOT NULL,
    target_channel           VARCHAR(32)  NOT NULL,
    build_spec_sha256        CHAR(64)     NOT NULL,
    source_snapshot_set_hash CHAR(64)     NOT NULL,
    approved_ledger_hash     CHAR(64)     NOT NULL,
    requested_by             VARCHAR(255) NOT NULL,
    approved_by              VARCHAR(255),
    status                   VARCHAR(32)  NOT NULL,
    dispatch_idempotency_key VARCHAR(255),
    workflow_run_url         VARCHAR(1024),
    created_at               TIMESTAMP    NOT NULL,
    approved_at              TIMESTAMP,
    updated_at               TIMESTAMP    NOT NULL
);
