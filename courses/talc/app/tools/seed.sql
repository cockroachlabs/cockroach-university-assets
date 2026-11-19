-- Lab 2 sample data: two users, 400 conversations, about 40,000 messages,
-- plus one long conversation (2,000 messages) for pagination tests.
-- Assistant messages carry tool calls and model metadata inside JSONB.

INSERT INTO users (id, email, display_name) VALUES
  ('a0000000-0000-4000-8000-000000000001', 'ada@example.com',   'Ada'),
  ('a0000000-0000-4000-8000-000000000002', 'grace@example.com', 'Grace')
ON CONFLICT (email) DO NOTHING;

INSERT INTO conversations (id, user_id, title, created_at, updated_at)
SELECT gen_random_uuid(),
       IF(i % 2 = 0, 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002')::UUID,
       'Seeded conversation ' || i::STRING,
       now() - (i::STRING || ' hours')::INTERVAL,
       now() - (i::STRING || ' hours')::INTERVAL
FROM generate_series(1, 400) AS g(i);

-- 100 messages per seeded conversation, alternating user / assistant.
INSERT INTO messages (conversation_id, role, content, created_at)
SELECT c.id,
       IF(m % 2 = 1, 'user', 'assistant'),
       IF(m % 2 = 1,
          json_build_object('text', 'Question ' || m::STRING),
          json_build_object(
            'text', 'Answer ' || m::STRING,
            'tool_calls', CASE m % 10
                            WHEN 2 THEN json_build_array(json_build_object('name', 'search_docs', 'args', json_build_object('query', 'changefeeds')))
                            WHEN 4 THEN json_build_array(json_build_object('name', 'issue_search', 'args', json_build_object('query', 'open bugs')))
                            WHEN 6 THEN json_build_array(json_build_object('name', 'memory_create', 'args', json_build_object('content', 'prefers Python')))
                            ELSE json_build_array() END,
            'metadata', json_build_object(
              'model', IF(m % 20 = 0, 'large-model', 'talc-stub'),
              'tokens', json_build_object('input', 50 + m, 'output', 20 + m % 30))))::JSONB,
       c.created_at + (m::STRING || ' seconds')::INTERVAL
FROM conversations AS c, generate_series(1, 100) AS g(m)
WHERE c.title LIKE 'Seeded conversation %';

-- One long conversation for Ada.
INSERT INTO conversations (id, user_id, title, updated_at)
VALUES ('c0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Long conversation (2,000 messages)', now());

INSERT INTO messages (conversation_id, role, content, created_at)
SELECT 'c0000000-0000-4000-8000-000000000001',
       IF(m % 2 = 1, 'user', 'assistant'),
       json_build_object('text', 'Message ' || m::STRING, 'tool_calls', json_build_array(),
                         'metadata', json_build_object('model', 'talc-stub'))::JSONB,
       now() - '1 day'::INTERVAL + (m::STRING || ' seconds')::INTERVAL
FROM generate_series(1, 2000) AS g(m);
