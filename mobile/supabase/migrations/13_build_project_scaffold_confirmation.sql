-- Migration 13: Gate Prototype Scaffold builds behind explicit user consent
-- A project may only execute on the Prototype Scaffold provider (i.e. DeepCode
-- is unavailable or disabled) after the user has explicitly confirmed via
-- POST /v1/build/projects/{id}/prototype-scaffold/confirm.

ALTER TABLE build_projects
    ADD COLUMN IF NOT EXISTS scaffold_confirmed BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN build_projects.scaffold_confirmed IS
    'True once the user has explicitly consented to run this project on the Prototype Scaffold fallback instead of real DeepCode execution.';
