-- Course 1, Lab 2 solution: index the JSONB message content so containment
-- queries (content @> '{...}') use an inverted index instead of a full scan.
CREATE INVERTED INDEX IF NOT EXISTS messages_content_idx ON messages (content);
