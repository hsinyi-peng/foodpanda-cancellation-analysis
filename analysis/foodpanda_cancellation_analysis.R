# ===============================
# Foodpanda Order Cancellation Analysis
# Predicting order cancellations with logistic regression, CART, and random forest
# ===============================
#
# Run from the project root, e.g.:
#   Rscript analysis/foodpanda_cancellation_analysis.R
#
# Reads:  data/foodpanda_analysis_dataset.csv
# Writes: outputs/*.png

# --------- 0) Setup ---------
# If a package is missing, install it once, then run again.
pkg_needed <- c("dplyr","pROC","rpart","rpart.plot","randomForest","boot")
pkg_to_install <- pkg_needed[!(pkg_needed %in% installed.packages()[,"Package"])]
if (length(pkg_to_install) > 0) install.packages(pkg_to_install, dependencies = TRUE)

library(dplyr)
library(pROC)
library(rpart)
library(rpart.plot)
library(randomForest)
library(boot)

set.seed(42)

dir.create("outputs", showWarnings = FALSE)

# --------- 1) Load Data ---------
df <- read.csv("data/foodpanda_analysis_dataset.csv", stringsAsFactors = FALSE)

# Quick peek
cat("Rows x Cols:", nrow(df), "x", ncol(df), "\n")
cat("Columns:", paste(colnames(df), collapse = ", "), "\n\n")

# --------- 2) Target Creation: cancelled (1) vs not (0) ---------
# The proposal defines cancelled if delivery_status contains any of:
# "cancelled/canceled/failed/rejected"
if (!"delivery_status" %in% names(df)) stop("Column 'delivery_status' not found.")
df$cancelled <- grepl("cancelled|canceled|failed|rejected",
                      tolower(df$delivery_status))
df$cancelled <- as.integer(df$cancelled)

# --------- 3) Basic Cleaning & Feature Engineering ---------
# Parse dates that are present
to_date <- function(x) suppressWarnings(as.POSIXct(x, format = "%m/%d/%Y", tz = "UTC"))
date_cols <- intersect(c("order_date","signup_date","last_order_date","rating_date"), names(df))
for (v in date_cols) df[[v]] <- to_date(df[[v]])

# Derive time features from order_date if available
if ("order_date" %in% names(df)) {
  df$hour    <- as.integer(format(df$order_date, "%H"))
  df$weekday <- factor(weekdays(df$order_date),
                       levels = c("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"))
  df$month   <- factor(format(df$order_date, "%b"), levels = month.abb)
} else {
  df$hour <- NA_integer_; df$weekday <- NA; df$month <- NA
}

# Categorical -> factors (with Unknown for NAs)
fac_cols <- intersect(c("gender","city","restaurant_name","category",
                        "payment_method","weekday","month"),
                      names(df))
for (v in fac_cols) {
  df[[v]][is.na(df[[v]])] <- "Unknown"
  df[[v]] <- as.factor(df[[v]])
}

# Simple numeric imputation (median) to avoid losing rows
num_cols <- intersect(c("age","quantity","price","order_frequency",
                        "loyalty_points","rating","hour"),
                      names(df))
for (v in num_cols) {
  if (all(is.na(df[[v]]))) next
  df[[v]][is.na(df[[v]])] <- median(df[[v]], na.rm = TRUE)
}

# --------- 4) Exploratory Data Analysis (EDA) ---------
cat("== Class balance (cancelled) ==\n")
print(table(df$cancelled))
print(round(prop.table(table(df$cancelled)), 3))

# Cancellation rate by payment method (numeric proof)
if ("payment_method" %in% names(df)) {
  cat("\n== Cancellation rate by payment_method ==\n")
  tab_pm  <- with(df, table(payment_method, cancelled))
  rate_pm <- prop.table(tab_pm, 1)[, "1"]
  print(round(rate_pm, 3))
  # Bar plot
  png("outputs/plot_cancel_by_payment.png", width = 900, height = 600)
  barplot(rate_pm, ylim=c(0, max(rate_pm, na.rm=TRUE)*1.25),
          main="Cancellation Rate by Payment Method",
          ylab="Rate (proportion)", xlab="Payment Method", las=2, cex.names=.9)
  text(x = seq_along(rate_pm), y = rate_pm, labels = sprintf("%.1f%%", 100*rate_pm),
       pos = 3, cex = .9)
  dev.off()
}

# Cancellation rate by weekday (if available)
if ("weekday" %in% names(df)) {
  cat("\n== Cancellation rate by weekday ==\n")
  tab_wd  <- with(df, table(weekday, cancelled))
  rate_wd <- prop.table(tab_wd, 1)[, "1"]
  print(round(rate_wd, 3))
  png("outputs/plot_cancel_by_weekday.png", width = 900, height = 600)
  barplot(rate_wd, ylim=c(0, max(rate_wd, na.rm=TRUE)*1.25),
          main="Cancellation Rate by Weekday", ylab="Rate (proportion)",
          xlab="Weekday", las=2)
  text(x = seq_along(rate_wd), y = rate_wd, labels = sprintf("%.1f%%", 100*rate_wd),
       pos = 3, cex = .9)
  dev.off()
}

# Boxplots + outliers for price
if ("price" %in% names(df)) {
  png("outputs/plot_price_by_cancel.png", width = 900, height = 600)
  boxplot(price ~ cancelled, data=df, xlab="Cancelled (0=no, 1=yes)",
          ylab="Price", main="Order Value by Cancellation")
  dev.off()
  cat("\n== Price summaries by cancelled ==\n")
  print(by(df$price, df$cancelled, summary))
  outlier_counts <- by(df$price, df$cancelled, function(x){
    q <- quantile(x, c(.25,.75), na.rm=TRUE); iqr <- q[2]-q[1]
    sum(x < q[1]-1.5*iqr | x > q[2]+1.5*iqr, na.rm=TRUE)
  })
  cat("Outlier counts (IQR rule):\n"); print(outlier_counts)
}

# Risky cities (min 50 orders)
if ("city" %in% names(df)) {
  cat("\n== Highest cancellation rate by city (n>=50) ==\n")
  risky_city <- df %>%
    count(city, cancelled) %>%
    group_by(city) %>%
    mutate(rate = n / sum(n)) %>%
    filter(cancelled == 1, sum(n) >= 50) %>%
    arrange(desc(rate))
  print(head(risky_city, 10))
}

# --------- 5) Train/Test Split ---------
set.seed(1)
idx <- sample.int(nrow(df), floor(0.7 * nrow(df)))
train <- df[idx, ]
test  <- df[-idx, ]

# --------- 6) Logistic Regression ---------
# Keep a manageable set of predictors (avoid ultra-high-cardinality at first)
log_formula <- as.formula(cancelled ~ payment_method + weekday + month + city +
                            category + price + quantity + order_frequency +
                            loyalty_points + rating + hour + gender)

# Remove terms not present
terms_present <- all.vars(log_formula)[-1]
terms_present <- terms_present[terms_present %in% names(train)]
log_formula <- as.formula(paste("cancelled ~", paste(terms_present, collapse = " + ")))

cat("\nLogistic formula used:\n")
print(log_formula)

log_mod <- glm(log_formula, data=train, family=binomial())

# Stepwise by AIC (optional)
log_step <- step(log_mod, trace = 0)

# Predictions & AUC
phat <- predict(log_step, newdata=test, type="response")
auc_val <- auc(test$cancelled, phat)
cat("\nAUC (logistic, stepwise):", as.numeric(auc_val), "\n")

# Function: confusion matrix at arbitrary cutoff
conf_mat <- function(y_true, p, p_cut = 0.5) {
  pred <- as.integer(p >= p_cut)
  cm <- table(Pred = pred, True = y_true)
  mr <- mean(pred != y_true)
  list(cm = cm, misclass_rate = mr)
}

# Evaluate at requested cutoffs 0.9 / 0.5 / 0.2
cuts <- c(0.9, 0.5, 0.2)
for (c0 in cuts) {
  res <- conf_mat(test$cancelled, phat, c0)
  cat("\n--- Logistic at cutoff", c0, "---\n")
  print(res$cm); cat("Misclassification rate:", round(res$misclass_rate, 4), "\n")
}

# Asymmetric cost FN:FP = 5:1 -> p_cut = 1/(1+5) = 1/6
p_cut_asym <- 1/6
res_asym <- conf_mat(test$cancelled, phat, p_cut_asym)
cat("\n--- Logistic at asymmetric cutoff (1/6) ---\n")
print(res_asym$cm); cat("Misclassification rate:", round(res_asym$misclass_rate, 4), "\n")

# --------- 7) CART (Classification Tree) ---------
tree_formula <- log_formula  # reuse terms
tree_fit <- rpart(tree_formula, data=train, method="class",
                  control = rpart.control(cp = 0.001, xval = 10))
printcp(tree_fit)   # complexity parameter table

# Choose cp with lowest xerror (1-SE rule could be used here)
cp_min <- tree_fit$cptable[which.min(tree_fit$cptable[,"xerror"]), "CP"]
tree_pruned <- prune(tree_fit, cp = cp_min)
png("outputs/plot_cart_tree.png", width = 1000, height = 700)
rpart.plot(tree_pruned, main="Pruned CART Tree")
dev.off()

# Predict + AUC + confusion at same cutoffs (need class probs)
tp <- predict(tree_pruned, newdata=test, type="prob")[, "1"]
auc_tree <- auc(test$cancelled, tp)
cat("\nAUC (CART):", as.numeric(auc_tree), "\n")
for (c0 in cuts) {
  res <- conf_mat(test$cancelled, tp, c0)
  cat("\n--- CART at cutoff", c0, "---\n")
  print(res$cm); cat("Misclassification rate:", round(res$misclass_rate, 4), "\n")
}
res_asym_tree <- conf_mat(test$cancelled, tp, p_cut_asym)
cat("\n--- CART at asymmetric cutoff (1/6) ---\n")
print(res_asym_tree$cm); cat("Misclassification rate:", round(res_asym_tree$misclass_rate, 4), "\n")

# --------- 8) Random Forest ---------
# randomForest only runs classification if the response is a factor;
# a numeric 0/1 column would silently be treated as regression.
train$cancelled_factor <- factor(train$cancelled, levels = c(0, 1))
test$cancelled_factor  <- factor(test$cancelled,  levels = c(0, 1))
rf_formula <- as.formula(paste("cancelled_factor ~", paste(terms_present, collapse = " + ")))

# For speed, limit mtry and ntree; tune as needed
rf_fit <- randomForest(rf_formula, data=train, ntree=300, mtry = max(2, floor(sqrt(sum(sapply(train[terms_present], function(x) is.numeric(x)))))),
                       na.action = na.roughfix, importance = TRUE)

# Variable importance plot
png("outputs/plot_rf_varimp.png", width = 900, height = 600)
varImpPlot(rf_fit, main="Random Forest Variable Importance")
dev.off()

# Predict + AUC + confusion
rp <- predict(rf_fit, newdata=test, type="prob")[, "1"]
auc_rf <- auc(test$cancelled, rp)
cat("\nAUC (Random Forest):", as.numeric(auc_rf), "\n")
for (c0 in cuts) {
  res <- conf_mat(test$cancelled, rp, c0)
  cat("\n--- Random Forest at cutoff", c0, "---\n")
  print(res$cm); cat("Misclassification rate:", round(res$misclass_rate, 4), "\n")
}
res_asym_rf <- conf_mat(test$cancelled, rp, p_cut_asym)
cat("\n--- Random Forest at asymmetric cutoff (1/6) ---\n")
print(res_asym_rf$cm); cat("Misclassification rate:", round(res_asym_rf$misclass_rate, 4), "\n")

# --------- 9) Cross-Validation (Logistic) ---------
# 5-fold CV using boot::cv.glm on a simpler numeric-focused model to keep runtime reasonable
simple_vars <- intersect(c("price","quantity","order_frequency","loyalty_points","rating","hour"), names(train))
if (length(simple_vars) >= 2) {
  f_cv <- as.formula(paste("cancelled ~", paste(simple_vars, collapse = " + ")))
  glm_cv <- glm(f_cv, data=train, family=binomial())
  set.seed(123)
  cv5 <- cv.glm(data=train[, c(simple_vars, "cancelled")], glmfit=glm_cv, K=5)
  cat("\n5-fold CV (logistic, simple numeric model) - raw delta (LOOCV approx, K=5):\n")
  print(cv5$delta)
}

cat("\nAll done. Figures saved to outputs/.\n")
