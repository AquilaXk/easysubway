ALTER TABLE admin_role_permissions DROP CONSTRAINT admin_role_permissions_permission_code_check;

ALTER TABLE admin_role_permissions ADD CONSTRAINT admin_role_permissions_permission_code_check
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

INSERT INTO admin_role_permissions (role_code, permission_code, created_at)
SELECT role_seed.role_code, 'admin.datapack.read', CURRENT_TIMESTAMP
FROM (
    VALUES
        ('ADMIN_VIEWER'),
        ('MASTER_EDITOR'),
        ('FIELD_OPERATOR'),
        ('DATA_OPERATOR'),
        ('SECURITY_ADMIN'),
        ('SUPER_ADMIN')
) AS role_seed(role_code)
ON CONFLICT (role_code, permission_code) DO NOTHING;

INSERT INTO admin_role_permissions (role_code, permission_code, created_at)
SELECT role_seed.role_code, permission_seed.permission_code, CURRENT_TIMESTAMP
FROM (VALUES ('MASTER_EDITOR'), ('FIELD_OPERATOR')) AS role_seed(role_code)
CROSS JOIN (
    VALUES
        ('admin.datapack.evidence.review'),
        ('admin.datapack.override.request')
) AS permission_seed(permission_code)
ON CONFLICT (role_code, permission_code) DO NOTHING;

INSERT INTO admin_role_permissions (role_code, permission_code, created_at)
SELECT 'MASTER_EDITOR', permission_seed.permission_code, CURRENT_TIMESTAMP
FROM (
    VALUES
        ('admin.datapack.alias.review'),
        ('admin.datapack.quarantine.review')
) AS permission_seed(permission_code)
ON CONFLICT (role_code, permission_code) DO NOTHING;

INSERT INTO admin_role_permissions (role_code, permission_code, created_at)
SELECT 'DATA_OPERATOR', permission_seed.permission_code, CURRENT_TIMESTAMP
FROM (
    VALUES
        ('admin.datapack.source.run'),
        ('admin.datapack.candidate.build'),
        ('admin.datapack.staging.promote')
) AS permission_seed(permission_code)
ON CONFLICT (role_code, permission_code) DO NOTHING;

INSERT INTO admin_role_permissions (role_code, permission_code, created_at)
VALUES ('SECURITY_ADMIN', 'admin.datapack.audit.read', CURRENT_TIMESTAMP)
ON CONFLICT (role_code, permission_code) DO NOTHING;

INSERT INTO admin_role_permissions (role_code, permission_code, created_at)
SELECT DISTINCT 'SUPER_ADMIN', permission_code, CURRENT_TIMESTAMP
FROM admin_role_permissions
WHERE permission_code LIKE 'admin.datapack.%'
ON CONFLICT (role_code, permission_code) DO NOTHING;

INSERT INTO admin_role_permissions (role_code, permission_code, created_at)
SELECT 'SUPER_ADMIN', permission_seed.permission_code, CURRENT_TIMESTAMP
FROM (
    VALUES
        ('admin.datapack.override.approve'),
        ('admin.datapack.production.approve'),
        ('admin.datapack.rollback')
) AS permission_seed(permission_code)
ON CONFLICT (role_code, permission_code) DO NOTHING;
