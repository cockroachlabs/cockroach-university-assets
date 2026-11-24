-- Talc schema: Course 1, Lab 1 solution.
-- The chat data model of a typical self-hosted team AI assistant.

-- One row per person who uses the app.
CREATE TABLE IF NOT EXISTS users (
    id           UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    email        STRING      NOT NULL UNIQUE,
    display_name STRING      NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A chat thread. Random UUID keys spread inserts across ranges instead of
-- piling every new row onto the last range (the sequential-key hotspot).
CREATE TABLE IF NOT EXISTS conversations (
    id         UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id    UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title      STRING      NOT NULL DEFAULT 'New conversation',
    model      STRING      NOT NULL DEFAULT 'talc-stub',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- The sidebar query: "this user's conversations, most recent first".
    INDEX conversations_user_recent_idx (user_id, updated_at DESC)
);

-- One row per chat turn. content is JSONB so a message can carry text,
-- tool calls and model metadata without schema changes (see Lab 2).
CREATE TABLE IF NOT EXISTS messages (
    id              UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id UUID        NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    role            STRING      NOT NULL CHECK (role IN ('user', 'assistant', 'system', 'tool')),
    content         JSONB       NOT NULL,
    -- clock_timestamp(), not now(): now() is the transaction timestamp, so two
    -- messages written in one transaction would otherwise get the same time.
    created_at      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    -- Load a conversation's history in order; id breaks ties for pagination.
    INDEX messages_conversation_idx (conversation_id, created_at, id)
);
