-- Migration 10: durable private ZIP artifacts for completed Build Mode projects.
-- Run after migration 09. The FastAPI backend writes through its server-only
-- service-role key; direct browser archive access remains disabled.

BEGIN;

INSERT INTO storage.buckets (id, name, public)
VALUES ('soul-build-artifacts', 'soul-build-artifacts', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Users can view their own Soul build artifacts" ON storage.objects;

CREATE POLICY "Users can view their own Soul build artifacts"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'soul-build-artifacts'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

COMMIT;
