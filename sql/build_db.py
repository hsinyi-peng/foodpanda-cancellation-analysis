"""
Build sql/foodpanda.db from data/foodpanda_analysis_dataset.csv.

Normalizes the flat CSV into customers / restaurants / orders
(see schema.sql) so that queries.sql can JOIN across them.

Run from the project root:
    python3 sql/build_db.py
"""
import csv
import os
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "data", "foodpanda_analysis_dataset.csv")
DB = os.path.join(HERE, "foodpanda.db")
SCHEMA = os.path.join(HERE, "schema.sql")

if os.path.exists(DB):
    os.remove(DB)

conn = sqlite3.connect(DB)
cur = conn.cursor()
cur.executescript(open(SCHEMA).read())

rows = list(csv.DictReader(open(SRC)))
customers_seen = set()
restaurants = {}

for r in rows:
    if r["customer_id"] not in customers_seen:
        cur.execute(
            "INSERT INTO customers VALUES (?,?,?,?,?,?,?,?,?)",
            (r["customer_id"], r["gender"], r["age"], r["city"], r["signup_date"],
             int(r["order_frequency"]), r["last_order_date"], int(r["loyalty_points"]), r["churned"])
        )
        customers_seen.add(r["customer_id"])

    if r["restaurant_name"] not in restaurants:
        cur.execute("INSERT INTO restaurants (restaurant_name) VALUES (?)", (r["restaurant_name"],))
        restaurants[r["restaurant_name"]] = cur.lastrowid

    cur.execute(
        "INSERT INTO orders VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        (r["order_id"], r["customer_id"], restaurants[r["restaurant_name"]],
         r["dish_name"], r["category"], r["order_date"],
         int(r["quantity"]), float(r["price"]), r["payment_method"],
         float(r["rating"]) if r["rating"] not in ("", "NA") else None,
         r["rating_date"], r["delivery_status"])
    )

conn.commit()
for t in ("customers", "restaurants", "orders"):
    print(t, cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0])
conn.close()
print("Built", DB)
