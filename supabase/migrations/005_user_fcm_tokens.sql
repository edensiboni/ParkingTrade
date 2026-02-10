-- Store FCM (and web push) tokens per user for sending push notifications.
-- One user can have multiple tokens (e.g. phone + web, or multiple devices).

CREATE TABLE user_fcm_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (token)
);

CREATE INDEX idx_user_fcm_tokens_user_id ON user_fcm_tokens(user_id);
CREATE INDEX idx_user_fcm_tokens_platform ON user_fcm_tokens(user_id, platform);

ALTER TABLE user_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Users can manage only their own tokens
CREATE POLICY "Users can insert own FCM tokens" ON user_fcm_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own FCM tokens" ON user_fcm_tokens
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own FCM tokens" ON user_fcm_tokens
    FOR DELETE USING (auth.uid() = user_id);

-- Users can read their own tokens (e.g. for cleanup). Edge Functions use service role and bypass RLS.
CREATE POLICY "Users can read own FCM tokens" ON user_fcm_tokens
    FOR SELECT USING (auth.uid() = user_id);

CREATE TRIGGER update_user_fcm_tokens_updated_at BEFORE UPDATE ON user_fcm_tokens
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
