# Foodpanda Order Cancellation Analysis

A cancellation-risk diagnostic: do order, customer, and restaurant attributes actually predict which orders get cancelled? Tested with logistic regression, a classification tree (CART), and a random forest — evaluated under an **asymmetric cost** assumption (missing a real cancellation costs more than a false alarm).

## The Business Question

**North Star metric:** order cancellation rate.

Every cancelled order costs a delivery platform the order value, driver time already spent, and customer trust. If a small set of order/customer/restaurant attributes could flag high-risk orders before they cancel, that's a lever ops teams could act on — reroute a driver, prioritize support outreach, or hold a second confirmation. This project tests that directly: can `cancelled` (1 vs. 0) be predicted from order, customer, and restaurant attributes on held-out data?

Because a missed cancellation (driver already en route) is more expensive than a false alarm (an unnecessary check-in), the models are evaluated at a 5:1 false-negative-to-false-positive cost ratio, not just a plain 50/50 cutoff — that's the cutoff a real ops team would actually use.

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
   - CART (`rpart`), pruned via cross-validation (minimum-xerror cp, not a hand-picked value) — so if it does find a split, it's one that generalizes, not noise
   - Random forest (`randomForest`), 300 trees
5. **Evaluation** — ROC AUC, confusion matrices at cutoffs 0.9 / 0.5 / 0.2, plus the asymmetric-cost cutoff (`FN:FP = 5:1` → p = 1/6) that reflects the real operational cost, and 5-fold CV for the logistic model.

## Findings

| Model | AUC (test) |
|---|---|
| Logistic regression (stepwise) | ~0.48 |
| CART (cross-validated pruning) | 0.50 |
| Random forest | ~0.51 |

**All three land at chance level (AUC ≈ 0.5) — including the cross-validated CART, which is the tell.** Cross-validated pruning picks the tree that generalizes best; when that process settles on "no split beats the baseline," it's a strong signal there's genuinely nothing here to find, not that the model needs more tuning. Digging into why: `delivery_status` and every categorical feature (`gender`, `age`, `city`, `category`, `payment_method`, ...) are close to uniformly distributed in this dataset — consistent with it being synthetically generated for practice rather than sampled from real platform activity, where cancellations are rarely that evenly spread across every segment.

**What this means for root-cause diagnosis:** on real operational data, a cancellation-rate spike almost always traces back to *something* — a specific restaurant, payment method, or time window. The absence of any such pattern here is itself informative: it means this exercise validates the *pipeline* (feature engineering, stepwise selection, cost-sensitive cutoff selection, cross-validation) rather than producing a deployable risk score. The natural next step is running the same pipeline against real Foodpanda operational data, where the cost-weighted evaluation would actually matter.

## How to run

```bash
git clone <this-repo-url>
cd foodpanda-cancellation-analysis
Rscript analysis/foodpanda_cancellation_analysis.R
```

Requires R (≥ 4.0) with packages: `dplyr`, `pROC`, `rpart`, `rpart.plot`, `randomForest`, `boot` — the script installs any that are missing on first run. Plots are written to `outputs/`.

## License

[MIT](LICENSE)
