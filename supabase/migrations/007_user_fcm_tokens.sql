-- FCM token storage for push notifications.

CREATE TABLE user_fcm_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'unknown',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, token)
);

CREATE INDEX idx_user_fcm_tokens_user_id ON user_fcm_tokens(user_id);

CREATE TRIGGER update_user_fcm_tokens_updated_at BEFORE UPDATE ON user_fcm_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE user_fcm_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own tokens" ON user_fcm_tokens
    FOR ALL USING (user_id = auth.uid());
