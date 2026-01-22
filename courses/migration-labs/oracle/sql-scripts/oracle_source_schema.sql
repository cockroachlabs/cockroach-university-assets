-- Oracle Source Schema Creation Script
-- Creates APP_USER schema with orders and order_fills tables
-- Includes sequences, triggers, and initial data

-- Switch to pluggable database
ALTER SESSION SET CONTAINER = FREEPDB1;
SHOW CON_NAME;

-- Create the application user/schema
CREATE USER APP_USER IDENTIFIED BY apppass;
ALTER USER APP_USER QUOTA UNLIMITED ON USERS;
GRANT CONNECT, RESOURCE TO APP_USER;
GRANT CREATE SESSION TO APP_USER;
GRANT CREATE TABLE TO APP_USER;
GRANT CREATE SEQUENCE TO APP_USER;
GRANT CREATE TRIGGER TO APP_USER;
GRANT CREATE VIEW TO APP_USER;

-- Create orders table
CREATE TABLE APP_USER.orders (
    account_id NUMBER NOT NULL,
    order_id NUMBER PRIMARY KEY,
    symbol VARCHAR2(2000) NOT NULL,
    order_started TIMESTAMP(6) NOT NULL,
    order_completed DATE,
    total_shares_purchased NUMBER,
    total_cost_of_order NUMBER(10,2)
);

-- Create indexes for orders table
CREATE INDEX APP_USER.orders_account_id ON APP_USER.orders (account_id);
CREATE INDEX APP_USER.orders_symbol ON APP_USER.orders (symbol);

-- Create order_fills table
CREATE TABLE APP_USER.order_fills (
    fill_id NUMBER PRIMARY KEY,
    order_id NUMBER NOT NULL,
    account_id NUMBER NOT NULL,
    symbol VARCHAR2(2000) NOT NULL,
    fill_time TIMESTAMP(6) NOT NULL,
    shares_filled NUMBER,
    total_cost_of_fill NUMBER(10,2),
    price_at_time_of_fill NUMBER(10,2)
);

-- Create indexes for order_fills table
CREATE INDEX APP_USER.order_fills_order_id ON APP_USER.order_fills (order_id);
CREATE INDEX APP_USER.order_fills_account_id ON APP_USER.order_fills (account_id);

-- Create sequences for auto-incrementing primary keys
CREATE SEQUENCE APP_USER.order_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE APP_USER.order_fill_seq START WITH 1 INCREMENT BY 1;

-- Create trigger for orders table to auto-populate order_id
CREATE OR REPLACE TRIGGER APP_USER.order_set_id
BEFORE INSERT ON APP_USER.orders
FOR EACH ROW
BEGIN
  IF :new.order_id IS NULL THEN
    SELECT APP_USER.order_seq.NEXTVAL
    INTO   :new.order_id
    FROM   dual;
  END IF;
END;
/

-- Create trigger for order_fills table to auto-populate fill_id
CREATE OR REPLACE TRIGGER APP_USER.order_fill_set_id
BEFORE INSERT ON APP_USER.order_fills
FOR EACH ROW
BEGIN
  IF :new.fill_id IS NULL THEN
    SELECT APP_USER.order_fill_seq.NEXTVAL
    INTO   :new.fill_id
    FROM   dual;
  END IF;
END;
/

-- Create view for Oracle orders
CREATE OR REPLACE VIEW APP_USER.orcl_order_fills_view
AS
  SELECT o.order_id, o.order_started, f.fill_id, f.shares_filled, f.fill_time
    FROM APP_USER.orders o, APP_USER.order_fills f
   WHERE f.order_id = o.order_id
     AND o.symbol = 'ORCL';

-- Create replicator sentinel table (required for MOLT Replicator)
CREATE TABLE APP_USER.replicator_sentinel (
  keycol NUMBER PRIMARY KEY,
  lastSCN NUMBER
);

-- Verify schema creation
SELECT 'Schema created successfully' AS status FROM dual;

EXIT;
