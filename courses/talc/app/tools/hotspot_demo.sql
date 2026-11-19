-- Lab 1: why Talc uses random UUID primary keys.
-- Compare the keys that two id strategies generate for the same 10 inserts.

CREATE TABLE IF NOT EXISTS demo_serial_ids (id INT8 NOT NULL DEFAULT unique_rowid() PRIMARY KEY, n INT8);
CREATE TABLE IF NOT EXISTS demo_uuid_ids   (id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY, n INT8);

INSERT INTO demo_serial_ids (n) SELECT generate_series(1, 10);
INSERT INTO demo_uuid_ids   (n) SELECT generate_series(1, 10);

-- Sequential: every new key is larger than the last, so every insert lands at the
-- end of the key space: on one range, on one leaseholder (a hotspot).
SELECT n AS insert_order, id FROM demo_serial_ids ORDER BY id;

-- Random: consecutive inserts land all over the key space, so writes spread
-- across ranges (and nodes) as the table grows.
SELECT n AS insert_order, id FROM demo_uuid_ids ORDER BY id;
