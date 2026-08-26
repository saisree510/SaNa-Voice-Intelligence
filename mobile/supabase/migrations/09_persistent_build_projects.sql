-- Migration 09: durable, owner-scoped Build Mode project metadata.
-- Run after migrations 07 and 08. This intentionally does not import the
-- legacy Railway JSON store: those records cannot be safely verified.

BEGIN;

CREATE TABLE IF NOT EXISTS public.build_projects (
    project_id TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    specification TEXT NOT NULL,
    workspace_path TEXT NOT NULL,
    artifact_path TEXT,
    status TEXT NOT NULL CHECK (status IN ('drafting', 'plan_generated', 'approved', 'executing', 'completed', 'failed')),
    plan_summary TEXT,
    session_id TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS public.build_runs (
    run_id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES public.build_projects(project_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL,
    prompt TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('running', 'completed', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS public.build_run_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id TEXT NOT NULL REFERENCES public.build_runs(run_id) ON DELETE CASCADE,
    project_id TEXT NOT NULL REFERENCES public.build_projects(project_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    sequence_no INTEGER NOT NULL CHECK (sequence_no >= 0),
    event_type TEXT NOT NULL,
    message TEXT NOT NULL,
    details JSONB,
    event_timestamp TIMESTAMPTZ NOT NULL,
    UNIQUE (run_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS public.build_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id TEXT NOT NULL REFERENCES public.build_projects(project_id) ON DELETE CASCADE,
    run_id TEXT NOT NULL REFERENCES public.build_runs(run_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    UNIQUE (project_id, run_id, path)
);

CREATE INDEX IF NOT EXISTS idx_build_projects_user_updated
ON public.build_projects (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_build_runs_project_created
ON public.build_runs (project_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_build_run_events_run_sequence
ON public.build_run_events (run_id, sequence_no ASC);

CREATE INDEX IF NOT EXISTS idx_build_files_project_run
ON public.build_files (project_id, run_id);

CREATE OR REPLACE FUNCTION public.touch_build_project_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS build_projects_updated_at ON public.build_projects;
CREATE TRIGGER build_projects_updated_at
BEFORE UPDATE ON public.build_projects
FOR EACH ROW EXECUTE FUNCTION public.touch_build_project_updated_at();

ALTER TABLE public.build_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.build_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.build_run_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.build_files ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own build projects" ON public.build_projects;
DROP POLICY IF EXISTS "Users can insert their own build projects" ON public.build_projects;
DROP POLICY IF EXISTS "Users can update their own build projects" ON public.build_projects;
DROP POLICY IF EXISTS "Users can delete their own build projects" ON public.build_projects;

CREATE POLICY "Users can view their own build projects"
ON public.build_projects FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own build projects"
ON public.build_projects FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own build projects"
ON public.build_projects FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own build projects"
ON public.build_projects FOR DELETE TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own build runs" ON public.build_runs;
DROP POLICY IF EXISTS "Users can insert their own build runs" ON public.build_runs;
DROP POLICY IF EXISTS "Users can update their own build runs" ON public.build_runs;
DROP POLICY IF EXISTS "Users can delete their own build runs" ON public.build_runs;

CREATE POLICY "Users can view their own build runs"
ON public.build_runs FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own build runs"
ON public.build_runs FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own build runs"
ON public.build_runs FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own build runs"
ON public.build_runs FOR DELETE TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own build events" ON public.build_run_events;
DROP POLICY IF EXISTS "Users can insert their own build events" ON public.build_run_events;

CREATE POLICY "Users can view their own build events"
ON public.build_run_events FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own build events"
ON public.build_run_events FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own build files" ON public.build_files;
DROP POLICY IF EXISTS "Users can insert their own build files" ON public.build_files;

CREATE POLICY "Users can view their own build files"
ON public.build_files FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own build files"
ON public.build_files FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

COMMIT;
