# Foodpanda Order Cancellation Analysis

Predicting food-delivery order cancellations from a Foodpanda-style transactions dataset, using logistic regression, a classification tree (CART), and a random forest — with an emphasis on **asymmetric cost** evaluation (a missed cancellation is treated as costlier than a false alarm).

## Overview

Food delivery platforms lose revenue and driver time on cancelled orders. This project builds a binary classifier — `cancelled` (1) vs. `not cancelled` (0) — from order, customer, and restaurant attributes, and compares three modeling approaches under a 5:1 false-negative-to-false-positive cost ratio.

## Dataset

`data/foodpanda_analysis_dataset.csv` — 6,000 rows, 20 columns.

| Column | Description |
|---|---|
| `customer_id`, `order_id` | Unique identifiers |
| `gender`, `age`, `city` | Customer demographics (`age`: Teenager / Adult / Senior) |
| `signup_date`, `last_order_date` | Customer lifecycle dates |
| `order_date` | Timestamp of the order |
| `restaurant_name`, `dish_name`, `category` | Order details (5 restaurants, 5 dishes, 5 cuisine categories) |
| `quantity`, `price` | Order size and value |
| `payment_method` | Card / Cash / Wallet |
| `order_frequency`, `loyalty_points` | Customer engagement metrics |
| `churned` | Active / Inactive customer flag |
| `rating`, `rating_date` | Post-order rating |
| `delivery_status` | Delivered / Delayed / **Cancelled** (target source) |

The target `cancelled` is derived from `delivery_status` (case-insensitive match on "cancelled/canceled/failed/rejected").

## Repository structure

```
.
├── analysis/
│   └── foodpanda_cancellation_analysis.R   # full pipeline: EDA -> models -> evaluation
├── data/
│   └── foodpanda_analysis_dataset.csv
├── outputs/                                # generated on run: EDA & model plots (PNG)
└── README.md
```

## Methodology

1. **Feature engineering** — parse dates, derive `hour` / `weekday` / `month` from `order_date`, convert categoricals to factors, median-impute missing numerics.
2. **EDA** — class balance, cancellation rate by payment method / weekday / city, price distribution by outcome, outlier counts (IQR rule).
3. **Train/test split** — 70/30.
4. **Models**
   - Logistic regression with stepwise (AIC) selection
   - CART (`rpart`), pruned to the minimum cross-validated error
   - Random forest (`randomForest`), 300 trees
5. **Evaluation** — ROC AUC, confusion matrices at cutoffs 0.9 / 0.5 / 0.2, plus an asymmetric-cost cutoff (`FN:FP = 5:1` → p = 1/6), and 5-fold CV for the logistic model.

## How to run

```bash
git clone <this-repo-url>
cd foodpanda-cancellation-analysis
Rscript analysis/foodpanda_cancellation_analysis.R
```

Requires R (≥ 4.0) with packages: `dplyr`, `pROC`, `rpart`, `rpart.plot`, `randomForest`, `boot` — the script installs any that are missing on first run. Plots are written to `outputs/`.

## Results

| Model | AUC (test) |
|---|---|
| Logistic regression (stepwise) | ~0.48 |
| CART (pruned) | 0.50 |
| Random forest | ~0.51 |

All three models perform at chance level (AUC ≈ 0.5). This is consistent with the underlying data: `delivery_status` and every categorical feature (`gender`, `age`, `city`, `category`, `payment_method`, ...) are close to uniformly distributed, indicating the dataset does not encode a real relationship between order/customer attributes and cancellation — likely because it is synthetically generated for practice purposes rather than sampled from real platform activity.

**Takeaway:** the pipeline (feature engineering, stepwise selection, cost-sensitive CART pruning, cross-validation) is built and validated end-to-end; applying it to real Foodpanda operational data would be the natural next step to obtain a model with genuine predictive lift.

## License

[MIT](LICENSE)
