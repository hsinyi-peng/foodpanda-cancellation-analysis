-- Relational schema for the Foodpanda cancellation dataset.
-- The raw data ships as one flat CSV (data/foodpanda_analysis_dataset.csv);
-- this normalizes it into customers / restaurants / orders so that
-- customer and restaurant attributes aren't repeated on every order row,
-- and so city/restaurant-level analysis requires a real JOIN.

CREATE TABLE customers (
    customer_id     TEXT PRIMARY KEY,
    gender          TEXT,
    age             TEXT,       -- Teenager / Adult / Senior
    city            TEXT,
    signup_date     TEXT,
    order_frequency INTEGER,
    last_order_date TEXT,
    loyalty_points  INTEGER,
    churned         TEXT        -- Active / Inactive
);

CREATE TABLE restaurants (
    restaurant_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    restaurant_name TEXT UNIQUE NOT NULL
);

CREATE TABLE orders (
    order_id        TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL REFERENCES customers(customer_id),
    restaurant_id   INTEGER NOT NULL REFERENCES restaurants(restaurant_id),
    dish_name       TEXT,
    category        TEXT,
    order_date      TEXT,
    quantity        INTEGER,
    price           REAL,
    payment_method  TEXT,
    rating          REAL,
    rating_date     TEXT,
    delivery_status TEXT        -- Delivered / Delayed / Cancelled / ...
);

CREATE INDEX idx_orders_customer   ON orders(customer_id);
CREATE INDEX idx_orders_restaurant ON orders(restaurant_id);
