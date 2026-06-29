ALTER TABLE admin_role_permissions DROP CONSTRAINT ck_h2_admin_role_permissions_permission;

ALTER TABLE admin_role_permissions ADD CONSTRAINT ck_h2_admin_role_permissions_permission
    CHECK (permission_code IN (
        'admin.view',
        'admin.report.review',
        'admin.report.photo.read',
        'admin.master.edit',
        'admin.field.operate',
        'admin.data.operate',
        'admin.security.audit',
        'admin.security.admin',
        'admin.audit.read',
        'admin.privacy-log.read',
        'admin.batch.retry',
        'admin.operations.manage',
        'admin.datapack.read',
        'admin.datapack.source.run',
        'admin.datapack.alias.review',
        'admin.datapack.quarantine.review',
        'admin.datapack.evidence.review',
        'admin.datapack.override.request',
        'admin.datapack.override.approve',
        'admin.datapack.candidate.build',
        'admin.datapack.staging.promote',
        'admin.datapack.production.approve',
        'admin.datapack.rollback',
        'admin.datapack.audit.read'
    ));

MERGE INTO admin_role_permissions (role_code, permission_code, created_at)
KEY (role_code, permission_code)
SELECT DISTINCT role_code, 'admin.datapack.read', CURRENT_TIMESTAMP
FROM admin_role_permissions
WHERE permission_code = 'admin.view';

MERGE INTO admin_role_permissions (role_code, permission_code, created_at)
KEY (role_code, permission_code)
SELECT role_seed.role_code, permission_seed.permission_code, CURRENT_TIMESTAMP
FROM (VALUES ('MASTER_EDITOR'), ('FIELD_OPERATOR')) AS role_seed(role_code)
CROSS JOIN (
    VALUES
        ('admin.datapack.evidence.review'),
        ('admin.datapack.override.request')
) AS permission_seed(permission_code);

MERGE INTO admin_role_permissions (role_code, permission_code, created_at)
KEY (role_code, permission_code)
SELECT 'MASTER_EDITOR', permission_seed.permission_code, CURRENT_TIMESTAMP
FROM (
    VALUES
        ('admin.datapack.alias.review'),
        ('admin.datapack.quarantine.review')
) AS permission_seed(permission_code);

MERGE INTO admin_role_permissions (role_code, permission_code, created_at)
KEY (role_code, permission_code)
SELECT 'DATA_OPERATOR', permission_seed.permission_code, CURRENT_TIMESTAMP
FROM (
    VALUES
        ('admin.datapack.source.run'),
        ('admin.datapack.candidate.build'),
        ('admin.datapack.staging.promote')
) AS permission_seed(permission_code);

MERGE INTO admin_role_permissions (role_code, permission_code, created_at)
KEY (role_code, permission_code)
VALUES ('SECURITY_ADMIN', 'admin.datapack.audit.read', CURRENT_TIMESTAMP);

MERGE INTO admin_role_permissions (role_code, permission_code, created_at)
KEY (role_code, permission_code)
SELECT DISTINCT 'SUPER_ADMIN', permission_code, CURRENT_TIMESTAMP
FROM admin_role_permissions
WHERE permission_code LIKE 'admin.datapack.%';

MERGE INTO admin_role_permissions (role_code, permission_code, created_at)
KEY (role_code, permission_code)
SELECT 'SUPER_ADMIN', permission_seed.permission_code, CURRENT_TIMESTAMP
FROM (
    VALUES
        ('admin.datapack.override.approve'),
        ('admin.datapack.production.approve'),
        ('admin.datapack.rollback')
) AS permission_seed(permission_code);
