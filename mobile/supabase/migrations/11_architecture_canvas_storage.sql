-- Migration 11: durable, owner-scoped Architecture Blueprint and canvas storage.
-- Run after migrations 07-10. Architectures are private by default.

BEGIN;

CREATE TABLE IF NOT EXISTS public.architectures (
    architecture_id TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
    project_id TEXT REFERENCES public.build_projects(project_id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private')),
    current_version INTEGER NOT NULL DEFAULT 1 CHECK (current_version >= 1),
    current_blueprint JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS public.architecture_versions (
    version_id TEXT PRIMARY KEY,
    architecture_id TEXT NOT NULL REFERENCES public.architectures(architecture_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL CHECK (version_number >= 1),
    blueprint JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    UNIQUE (architecture_id, version_number)
);

CREATE TABLE IF NOT EXISTS public.canvas_events (
    event_id TEXT PRIMARY KEY,
    architecture_id TEXT NOT NULL REFERENCES public.architectures(architecture_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    architecture_version INTEGER NOT NULL CHECK (architecture_version >= 1),
    sequence_number INTEGER NOT NULL CHECK (sequence_number >= 1),
    idempotency_key TEXT NOT NULL,
    event_type TEXT NOT NULL,
    operation JSONB NOT NULL,
    validation_errors JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    UNIQUE (architecture_id, sequence_number),
    UNIQUE (architecture_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS public.canvas_snapshots (
    snapshot_id TEXT PRIMARY KEY,
    architecture_id TEXT NOT NULL REFERENCES public.architectures(architecture_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    architecture_version INTEGER NOT NULL CHECK (architecture_version >= 1),
    sequence_number INTEGER NOT NULL CHECK (sequence_number >= 0),
    blueprint JSONB NOT NULL,
    scene JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_architectures_user_updated
ON public.architectures (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_architecture_versions_architecture_number
ON public.architecture_versions (architecture_id, version_number);

CREATE INDEX IF NOT EXISTS idx_canvas_events_architecture_sequence
ON public.canvas_events (architecture_id, sequence_number);

CREATE INDEX IF NOT EXISTS idx_canvas_snapshots_architecture_sequence
ON public.canvas_snapshots (architecture_id, sequence_number DESC, created_at DESC);

CREATE OR REPLACE FUNCTION public.touch_architecture_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS architectures_updated_at ON public.architectures;
CREATE TRIGGER architectures_updated_at
BEFORE UPDATE ON public.architectures
FOR EACH ROW EXECUTE FUNCTION public.touch_architecture_updated_at();

ALTER TABLE public.architectures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.architecture_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canvas_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canvas_snapshots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own architectures" ON public.architectures;
DROP POLICY IF EXISTS "Users can insert their own architectures" ON public.architectures;
DROP POLICY IF EXISTS "Users can update their own architectures" ON public.architectures;
DROP POLICY IF EXISTS "Users can delete their own architectures" ON public.architectures;

CREATE POLICY "Users can view their own architectures"
ON public.architectures FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own architectures"
ON public.architectures FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own architectures"
ON public.architectures FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own architectures"
ON public.architectures FOR DELETE TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own architecture versions" ON public.architecture_versions;
DROP POLICY IF EXISTS "Users can insert their own architecture versions" ON public.architecture_versions;

CREATE POLICY "Users can view their own architecture versions"
ON public.architecture_versions FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own architecture versions"
ON public.architecture_versions FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own canvas events" ON public.canvas_events;
DROP POLICY IF EXISTS "Users can insert their own canvas events" ON public.canvas_events;

CREATE POLICY "Users can view their own canvas events"
ON public.canvas_events FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own canvas events"
ON public.canvas_events FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own canvas snapshots" ON public.canvas_snapshots;
DROP POLICY IF EXISTS "Users can insert their own canvas snapshots" ON public.canvas_snapshots;

CREATE POLICY "Users can view their own canvas snapshots"
ON public.canvas_snapshots FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own canvas snapshots"
ON public.canvas_snapshots FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

COMMIT;
