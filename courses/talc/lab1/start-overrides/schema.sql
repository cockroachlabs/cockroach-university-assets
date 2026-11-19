-- Talc schema: Course 1, Lab 1 starting point.
-- users is done for you. Finish conversations and messages (see the TODOs),
-- then load the file with:  cockroach sql ... -d talc -f schema.sql

-- One row per person who uses the app.
CREATE TABLE IF NOT EXISTS users (
    id           UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    email        STRING      NOT NULL UNIQUE,
    display_name STRING      NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- TODO: conversations, one row per chat thread.
--   id          UUID primary key with a random default (not a sequence: why?)
--   user_id     UUID, required, references users(id), delete with the user
--   title       STRING, required, default 'New conversation'
--   model       STRING, required, default 'talc-stub'
--   created_at  TIMESTAMPTZ, required, default now()
--   updated_at  TIMESTAMPTZ, required, default now()
--   An index named conversations_user_recent_idx that serves:
--     SELECT ... WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 50


-- TODO: messages, one row per chat turn.
--   id               UUID primary key with a random default
--   conversation_id  UUID, required, references conversations(id), delete with the conversation
--   role             STRING, required, one of 'user', 'assistant', 'system', 'tool'
--   content          JSONB, required
--   created_at       TIMESTAMPTZ, required, default clock_timestamp()
--                    (not now(): now() is the transaction timestamp, so two messages
--                    written in one transaction would get the same time)
--   An index named messages_conversation_idx that serves:
--     SELECT ... WHERE conversation_id = $1 ORDER BY created_at, id
