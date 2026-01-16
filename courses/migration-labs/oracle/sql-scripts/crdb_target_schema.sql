-- CockroachDB Target Schema Creation Script
-- Creates target database and schema for migrated Oracle data

-- Create target database
CREATE DATABASE IF NOT EXISTS target;

USE target;

-- Create sequences (starting higher to avoid conflicts)
CREATE SEQUENCE IF NOT EXISTS public.orders_seq START 1000000;
CREATE SEQUENCE IF NOT EXISTS public.order_fills_seq START 10000000;

-- Create orders table
CREATE TABLE IF NOT EXISTS public.orders (
    account_id INT8 NOT NULL,
    order_id INT8 NOT NULL DEFAULT nextval('public.orders_seq'::REGCLASS),
    symbol VARCHAR(2000) NOT NULL,
    order_started TIMESTAMP(6) NOT NULL,
    order_completed TIMESTAMP(0) NULL,
    total_shares_purchased DECIMAL NULL,
    total_cost_of_order DECIMAL(10,2) NULL,
    CONSTRAINT orders_pkey PRIMARY KEY (order_id ASC)
);

-- Create indexes for orders table
CREATE INDEX IF NOT EXISTS orders_account_id ON public.orders(account_id);
CREATE INDEX IF NOT EXISTS orders_symbol ON public.orders(symbol);

-- Create order_fills table
CREATE TABLE IF NOT EXISTS public.order_fills (
    fill_id INT8 NOT NULL DEFAULT nextval('public.order_fills_seq'::REGCLASS),
    order_id INT8 NOT NULL,
    account_id INT8 NOT NULL,
    symbol VARCHAR(2000) NOT NULL,
    fill_time TIMESTAMP(6) NOT NULL,
    shares_filled DECIMAL NULL,
    total_cost_of_fill DECIMAL(10,2) NULL,
    price_at_time_of_fill DECIMAL(10,2) NULL,
    CONSTRAINT order_fills_pkey PRIMARY KEY (fill_id ASC)
);

-- Create indexes for order_fills table
CREATE INDEX IF NOT EXISTS order_fills_order_id ON public.order_fills(order_id);
CREATE INDEX IF NOT EXISTS order_fills_account_id ON public.order_fills(account_id);

-- Create view (same as Oracle)
CREATE OR REPLACE VIEW public.orcl_order_fills_view
AS
  SELECT o.order_id, o.order_started, f.fill_id, f.shares_filled, f.fill_time
    FROM public.orders o JOIN public.order_fills f ON f.order_id = o.order_id
   WHERE o.symbol = 'ORCL';

-- Display schema
SHOW TABLES;
