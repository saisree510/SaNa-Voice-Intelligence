-- Migration 07: Persistent Conversations Schema, Indexes, & RLS Policies
-- Enables PostgreSQL persistence for conversations, messages, and conversation_events

-- 1. Create conversations table
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL DEFAULT 'New Conversation',
    mode TEXT NOT NULL DEFAULT 'general',
    preview_text TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Index for fetching user conversations ordered by update time
CREATE INDEX IF NOT EXISTS idx_conversations_user_updated 
ON public.conversations (user_id, updated_at DESC);

-- 2. Create messages table
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    sender TEXT NOT NULL CHECK (sender IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('voice', 'text')),
    idempotency_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_conversation_idempotency UNIQUE (conversation_id, idempotency_key)
);

-- Index for fetching message history in chronological order
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created 
ON public.messages (conversation_id, created_at ASC);

-- 3. Create conversation_events table
CREATE TABLE IF NOT EXISTS public.conversation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    from_mode TEXT,
    to_mode TEXT,
    payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Index for querying events for a conversation
CREATE INDEX IF NOT EXISTS idx_conversation_events_created 
ON public.conversation_events (conversation_id, created_at ASC);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_events ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for conversations
CREATE POLICY "Users can view their own conversations"
ON public.conversations FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own conversations"
ON public.conversations FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own conversations"
ON public.conversations FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own conversations"
ON public.conversations FOR DELETE
USING (auth.uid() = user_id);

-- 6. RLS Policies for messages
CREATE POLICY "Users can view messages in their conversations"
ON public.messages FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.conversations c 
        WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
    )
);

CREATE POLICY "Users can insert messages into their conversations"
ON public.messages FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.conversations c 
        WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
    )
);

CREATE POLICY "Users can update messages in their conversations"
ON public.messages FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM public.conversations c 
        WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
    )
);

CREATE POLICY "Users can delete messages in their conversations"
ON public.messages FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM public.conversations c 
        WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
    )
);

-- 7. RLS Policies for conversation_events
CREATE POLICY "Users can view events in their conversations"
ON public.conversation_events FOR SELECT
USING (
    EXISTS (
        SELECT 1 FROM public.conversations c 
        WHERE c.id = conversation_events.conversation_id AND c.user_id = auth.uid()
    )
);

CREATE POLICY "Users can insert events into their conversations"
ON public.conversation_events FOR INSERT
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.conversations c 
        WHERE c.id = conversation_events.conversation_id AND c.user_id = auth.uid()
    )
);
