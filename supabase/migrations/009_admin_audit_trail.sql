CREATE TABLE admin_audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_id UUID NOT NULL REFERENCES profiles(id) ON DELETE SET NULL,
    target_id UUID NOT NULL REFERENCES profiles(id) ON DELETE SET NULL,
    building_id UUID REFERENCES buildings(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    old_status TEXT,
    new_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_audit_log_building ON admin_audit_log(building_id);
CREATE INDEX idx_admin_audit_log_admin ON admin_audit_log(admin_id);
CREATE INDEX idx_admin_audit_log_target ON admin_audit_log(target_id);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view audit log for their building" ON admin_audit_log
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE profiles.id = auth.uid()
              AND profiles.role = 'admin'
              AND profiles.building_id = admin_audit_log.building_id
        )
    );
