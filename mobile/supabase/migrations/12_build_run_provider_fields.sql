-- Migration 12: Add provider tracking and blueprint linkage to build tables
-- Adds provider label and blueprint hash to build_projects and build_runs
-- so every build is visibly distinguishable as DeepCode vs Prototype Scaffold.

-- build_projects: track which coding agent produced the project and the approved blueprint version
ALTER TABLE build_projects
    ADD COLUMN IF NOT EXISTS architecture_id TEXT,
    ADD COLUMN IF NOT EXISTS blueprint_version INTEGER,
    ADD COLUMN IF NOT EXISTS blueprint_hash TEXT,
    ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'prototype_scaffold';

-- build_runs: track provider and blueprint hash per individual run
ALTER TABLE build_runs
    ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'prototype_scaffold',
    ADD COLUMN IF NOT EXISTS blueprint_hash TEXT;

-- Index for filtering by provider (useful for admin/analytics queries)
CREATE INDEX IF NOT EXISTS idx_build_projects_provider ON build_projects(provider);
CREATE INDEX IF NOT EXISTS idx_build_runs_provider ON build_runs(provider);

-- Index for architecture linkage
CREATE INDEX IF NOT EXISTS idx_build_projects_architecture_id ON build_projects(architecture_id)
    WHERE architecture_id IS NOT NULL;

COMMENT ON COLUMN build_projects.provider IS 'deepcode | prototype_scaffold — the coding agent that executed this build';
COMMENT ON COLUMN build_projects.blueprint_hash IS 'SHA-256 of the approved Architecture Blueprint JSON at build approval time';
COMMENT ON COLUMN build_runs.provider IS 'deepcode | prototype_scaffold — the coding agent that executed this run';
COMMENT ON COLUMN build_runs.blueprint_hash IS 'SHA-256 of the Architecture Blueprint bound to this run';
