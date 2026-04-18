-- Function to automatically mark approved bookings as completed once their end_time has passed.
-- Can be invoked via pg_cron, a scheduled edge function, or on-demand.
CREATE OR REPLACE FUNCTION complete_expired_bookings()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    affected INTEGER;
BEGIN
    UPDATE booking_requests
    SET status = 'completed',
        updated_at = NOW()
    WHERE status = 'approved'
      AND end_time < NOW();

    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN affected;
END;
$$;
