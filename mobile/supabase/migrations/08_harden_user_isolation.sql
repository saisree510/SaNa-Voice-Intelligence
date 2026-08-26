-- Migration 08: reconcile the deployed conversation schema and enforce
-- authenticated ownership. This migration is intentionally transactional:
-- any failed preflight or ownership check rolls back all changes.
--
-- Scope: conversations, messages, and conversation_events. The legacy
-- user_profiles schema is not deployed or used by the application, so it is
-- deliberately excluded pending a separate product/schema decision.

BEGIN;

-- Production must already have the parent resources. Do not create an
-- incomplete conversation schema from this hardening migration.
DO $$
BEGIN
    IF to_regclass('public.conversations') IS NULL THEN
        RAISE EXCEPTION 'Missing public.conversations; apply the base conversation schema first';
    END IF;

    IF to_regclass('public.messages') IS NULL THEN
        RAISE EXCEPTION 'Missing public.messages; apply the base conversation schema first';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'conversations'
          AND column_name = 'user_id'
          AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'public.conversations.user_id must exist and be NOT NULL before ownership hardening';
    END IF;
END $$;

-- Some existing deployments have messages but not conversation_events. Create
-- the event table in its final ownership-aware shape when it is absent.
CREATE TABLE IF NOT EXISTS public.conversation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    from_mode TEXT,
    to_mode TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Add direct ownership columns without assuming an existing column has the
-- correct type, values, or foreign-key constraint.
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS user_id UUID;
ALTER TABLE public.conversation_events ADD COLUMN IF NOT EXISTS user_id UUID;

-- Reject orphaned or conflicting records instead of assigning an arbitrary
-- owner or silently making records inaccessible.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.messages m
        LEFT JOIN public.conversations c ON c.id = m.conversation_id
        WHERE c.id IS NULL
    ) THEN
        RAISE EXCEPTION 'Cannot harden messages: orphaned conversation_id records exist';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.conversation_events e
        LEFT JOIN public.conversations c ON c.id = e.conversation_id
        WHERE c.id IS NULL
    ) THEN
        RAISE EXCEPTION 'Cannot harden conversation_events: orphaned conversation_id records exist';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.messages m
        JOIN public.conversations c ON c.id = m.conversation_id
        WHERE m.user_id IS NOT NULL AND m.user_id <> c.user_id
    ) THEN
        RAISE EXCEPTION 'Cannot harden messages: conflicting owner values exist';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.conversation_events e
        JOIN public.conversations c ON c.id = e.conversation_id
        WHERE e.user_id IS NOT NULL AND e.user_id <> c.user_id
    ) THEN
        RAISE EXCEPTION 'Cannot harden conversation_events: conflicting owner values exist';
    END IF;
END $$;

UPDATE public.messages m
SET user_id = c.user_id
FROM public.conversations c
WHERE m.conversation_id = c.id AND m.user_id IS NULL;

UPDATE public.conversation_events e
SET user_id = c.user_id
FROM public.conversations c
WHERE e.conversation_id = c.id AND e.user_id IS NULL;

ALTER TABLE public.messages ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE public.conversation_events ALTER COLUMN user_id SET NOT NULL;

-- Add the direct ownership foreign keys when a prior partial migration did
-- not create them. Existing equivalent foreign keys are preserved.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE contype = 'f'
          AND conrelid = 'public.messages'::regclass
          AND confrelid = 'auth.users'::regclass
          AND conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'public.messages'::regclass AND attname = 'user_id' AND NOT attisdropped)]::smallint[]
    ) THEN
        ALTER TABLE public.messages
        ADD CONSTRAINT messages_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE contype = 'f'
          AND conrelid = 'public.conversation_events'::regclass
          AND confrelid = 'auth.users'::regclass
          AND conkey = ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid = 'public.conversation_events'::regclass AND attname = 'user_id' AND NOT attisdropped)]::smallint[]
    ) THEN
        ALTER TABLE public.conversation_events
        ADD CONSTRAINT conversation_events_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_conversations_user_updated
ON public.conversations (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_user_conversation
ON public.messages (user_id, conversation_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_conversation_events_user_conversation
ON public.conversation_events (user_id, conversation_id, created_at ASC);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can insert their own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can update their own conversations" ON public.conversations;
DROP POLICY IF EXISTS "Users can delete their own conversations" ON public.conversations;

CREATE POLICY "Users can view their own conversations"
ON public.conversations FOR SELECT TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own conversations"
ON public.conversations FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own conversations"
ON public.conversations FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own conversations"
ON public.conversations FOR DELETE TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can insert messages into their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can update messages in their conversations" ON public.messages;
DROP POLICY IF EXISTS "Users can delete messages in their conversations" ON public.messages;

CREATE POLICY "Users can view messages in their conversations"
ON public.messages FOR SELECT TO authenticated
USING (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
));

CREATE POLICY "Users can insert messages into their conversations"
ON public.messages FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
));

CREATE POLICY "Users can update messages in their conversations"
ON public.messages FOR UPDATE TO authenticated
USING (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
))
WITH CHECK (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
));

CREATE POLICY "Users can delete messages in their conversations"
ON public.messages FOR DELETE TO authenticated
USING (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
));

DROP POLICY IF EXISTS "Users can view events in their conversations" ON public.conversation_events;
DROP POLICY IF EXISTS "Users can insert events into their conversations" ON public.conversation_events;
DROP POLICY IF EXISTS "Users can update events in their conversations" ON public.conversation_events;
DROP POLICY IF EXISTS "Users can delete events in their conversations" ON public.conversation_events;

-- Events are append-only: authenticated users can read and add events only
-- for conversations they own. Conversation deletion cascades their removal.
CREATE POLICY "Users can view events in their conversations"
ON public.conversation_events FOR SELECT TO authenticated
USING (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = conversation_events.conversation_id AND c.user_id = auth.uid()
));

CREATE POLICY "Users can insert events into their conversations"
ON public.conversation_events FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id AND EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = conversation_events.conversation_id AND c.user_id = auth.uid()
));

-- Final consistency check before commit. Any failure aborts the transaction.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.messages m
        JOIN public.conversations c ON c.id = m.conversation_id
        WHERE m.user_id <> c.user_id
    ) OR EXISTS (
        SELECT 1
        FROM public.conversation_events e
        JOIN public.conversations c ON c.id = e.conversation_id
        WHERE e.user_id <> c.user_id
    ) THEN
        RAISE EXCEPTION 'Ownership consistency check failed after backfill';
    END IF;
END $$;

COMMIT;
