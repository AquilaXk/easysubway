ALTER TABLE admin_role_permissions DROP CONSTRAINT ck_h2_admin_role_permissions_permission;

ALTER TABLE admin_role_permissions ADD CONSTRAINT ck_h2_admin_role_permissions_permission
    CHECK (permission_code IN ('admin.view', 'admin.report.review', 'admin.master.edit', 'admin.field.operate', 'admin.data.operate', 'admin.security.audit', 'admin.security.admin', 'admin.audit.read', 'admin.privacy-log.read', 'admin.batch.retry', 'admin.operations.manage'));

ALTER TABLE admin_audit_events DROP CONSTRAINT ck_h2_admin_audit_events_type;

ALTER TABLE admin_audit_events ADD CONSTRAINT ck_h2_admin_audit_events_type
    CHECK (event_type IN ('LOGIN', 'LOGIN_FAILURE', 'LOGOUT', 'ADMIN_ACTION', 'PRIVACY_READ', 'SYSTEM_CHANGE', 'BATCH_OPERATION', 'COMMON_CODE_CHANGE', 'INCIDENT_CHANGE', 'MASTER_DATA_CHANGE'));

CREATE TABLE admin_common_code_groups (
    group_code VARCHAR(80) NOT NULL PRIMARY KEY,
    display_name VARCHAR(120) NOT NULL,
    description VARCHAR(500),
    sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE TABLE admin_common_codes (
    group_code VARCHAR(80) NOT NULL,
    code VARCHAR(80) NOT NULL,
    display_name VARCHAR(120) NOT NULL,
    description VARCHAR(500),
    sort_order INTEGER NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    PRIMARY KEY (group_code, code),
    FOREIGN KEY (group_code) REFERENCES admin_common_code_groups(group_code)
);

CREATE TABLE admin_incidents (
    incident_id VARCHAR(40) NOT NULL PRIMARY KEY,
    severity VARCHAR(40) NOT NULL,
    status VARCHAR(40) NOT NULL,
    source VARCHAR(40) NOT NULL,
    summary VARCHAR(300) NOT NULL,
    owner VARCHAR(120) NOT NULL,
    opened_at TIMESTAMP NOT NULL,
    resolved_at TIMESTAMP,
    resolution VARCHAR(500),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    CHECK (status <> 'RESOLVED' OR (resolved_at IS NOT NULL AND resolution IS NOT NULL))
);

CREATE INDEX idx_admin_common_codes_group_enabled
    ON admin_common_codes (group_code, enabled, sort_order);

CREATE INDEX idx_admin_incidents_status_opened
    ON admin_incidents (status, opened_at);

INSERT INTO admin_role_permissions (created_at, permission_code, role_code)
VALUES
    (CURRENT_TIMESTAMP, 'admin.operations.manage', 'DATA_OPERATOR'),
    (CURRENT_TIMESTAMP, 'admin.operations.manage', 'SECURITY_ADMIN'),
    (CURRENT_TIMESTAMP, 'admin.operations.manage', 'SUPER_ADMIN');

INSERT INTO admin_menu_items (hidden, display_order, display_name, parent_program_code, program_code)
VALUES
    (FALSE, 87, '공통코드', NULL, 'a-codes'),
    (FALSE, 88, '장애관리', NULL, 'a-incidents');

INSERT INTO admin_common_code_groups (group_code, display_name, description, sort_order, enabled, created_at, updated_at)
VALUES
    ('REPORT_REJECTION_REASON', '신고 반려 사유', '제보 검수에서 반복 선택하는 반려 사유', 10, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('FACILITY_STATUS_REASON', '시설 변경 사유', '시설 상태 변경 사유', 20, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BATCH_FAILURE_CATEGORY', '배치 실패 분류', '수집 배치 실패 원인 분류', 30, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_SEVERITY', '장애 심각도', '운영 incident 심각도', 40, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_STATUS', '장애 상태', '운영 incident 처리 상태', 50, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_SOURCE', '장애 출처', 'incident 발생 출처', 60, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO admin_common_codes (group_code, code, display_name, description, sort_order, enabled, created_at, updated_at)
VALUES
    ('REPORT_REJECTION_REASON', 'DUPLICATE', '중복 제보', '이미 처리 중인 동일 제보', 10, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('REPORT_REJECTION_REASON', 'INSUFFICIENT', '정보 부족', '역·시설·사진 정보 부족', 20, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('FACILITY_STATUS_REASON', 'INSPECTION', '정기 점검', '운영기관 정기 점검', 10, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('FACILITY_STATUS_REASON', 'REPORT_CONFIRMED', '제보 확인', '제보 검수 후 상태 변경', 20, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BATCH_FAILURE_CATEGORY', 'SOURCE_TIMEOUT', '원천 응답 지연', '원천 데이터 응답 시간 초과', 10, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('BATCH_FAILURE_CATEGORY', 'VALIDATION_ERROR', '검증 실패', '수집 산출물 검증 실패', 20, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_SEVERITY', 'MAJOR', 'Major', '사용자 기능 영향', 10, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_SEVERITY', 'MINOR', 'Minor', '운영 확인 필요', 20, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_STATUS', 'OPEN', 'Open', '처리 전', 10, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_STATUS', 'RESOLVED', 'Resolved', '해결됨', 20, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_SOURCE', 'HEALTH', 'Health', 'health 상태', 10, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('INCIDENT_SOURCE', 'BATCH', 'Batch', '배치 실행', 20, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
