DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'incident_user') THEN
    CREATE ROLE incident_user LOGIN PASSWORD 'incident_pass';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'notification_user') THEN
    CREATE ROLE notification_user LOGIN PASSWORD 'notification_pass';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'audit_user') THEN
    CREATE ROLE audit_user LOGIN PASSWORD 'audit_pass';
  END IF;
END$$;
