-- 1) Fix expire_offers to respect ts_end
CREATE OR REPLACE FUNCTION expire_offers()
RETURNS VOID AS $$
BEGIN
  UPDATE offers
  SET sts = 4, ts_end = NOW()
  WHERE sts = 2
    AND i_del = 0
    AND (
      (ts_ren IS NULL AND COALESCE(ts_pub, ts_crt) < NOW() - INTERVAL '30 days')
      OR
      (ts_ren IS NOT NULL AND ts_end < NOW())
    );
END;
$$ LANGUAGE plpgsql;

-- 2) Create send_renewal_reminders to notify users 3 days before expiration
CREATE OR REPLACE FUNCTION send_renewal_reminders()
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER := 0;
  v_offer RECORD;
BEGIN
  FOR v_offer IN
    SELECT id, usr_id, ttl
    FROM offers
    WHERE sts = 2 AND i_del = 0
      AND (
        (ts_ren IS NULL AND COALESCE(ts_pub, ts_crt) BETWEEN NOW() - INTERVAL '28 days' AND NOW() - INTERVAL '27 days')
        OR
        (ts_ren IS NOT NULL AND ts_end BETWEEN NOW() + INTERVAL '2 days' AND NOW() + INTERVAL '3 days')
      )
  LOOP
    -- Insert notification for the owner
    INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
    VALUES (
      v_offer.usr_id, 
      1, 
      'تذكير بتجديد العرض', 
      'العرض الخاص بك "' || COALESCE(v_offer.ttl, 'بدون عنوان') || '" سينتهي قريباً. قم بتجديده بالنقاط لتجنب نقله للأرشيف.', 
      v_offer.id,
      '/offer/' || v_offer.id,
      NOW()
    );
    v_count := v_count + 1;
  END LOOP;
  
  RETURN v_count;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION send_renewal_reminders() TO anon, authenticated, service_role;
