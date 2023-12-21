#load packages
library(fpp3)
library(stringr)

## ++++++++++++++++++ LOAD DATA ++++++++++++++++++++++++++++
#load data
data_path <- "../data/"

# train data
sales_train <- read.csv(paste(data_path,"sales_train_validation_afcs2023.csv", sep=""))

# test data
sales_test <- read.csv(paste(data_path,"sales_test_validation_afcs2022.csv", sep=""))

# calendar data
calendar_df <- read.csv(paste(data_path,"calendar_afcs2023.csv", sep=""))

# price data
price_df <- read.csv(paste(data_path,"sell_prices_afcs2023.csv", sep=""))


## ++++++++++++++++++ PREPARE DATA SETS ++++++++++++++++++++++++++++

# 1) Calendar data
# convert to Date object
calendar_df$Date <- as.Date(calendar_df$date, format = "%m/%d/%Y")

# create id column to merge with sales data, everything else is disregarded
calendar_df <- calendar_df %>% select(-date) %>% arrange(Date) %>% mutate(id_day = row_number(), day = paste("d_", id_day, sep=""))

# save id mapping for maybe later use
cal_ids <- calendar_df %>% select(Date, id_day, day)

# dummy if weekend
calendar_df <- calendar_df %>% mutate(is_weekend = if_else(wday<=2, 1,0))

# day of month
calendar_df <- calendar_df %>% mutate(day_of_month = day(Date))

# dummy of is event (only event 1)
calendar_df <- calendar_df %>%
  mutate(event = if_else(!is.na(event_name_1), 1, 0))



# 2) Sales train data

# Create id column in order for easier handling (product name is too annoying)
df_sales_train <- df_sales_train %>% arrange(id) %>% mutate(product_id = row_number()) %>% select(id, product_id, everything())
ids <- df_sales_train %>% select(product_id, id)

# pivot to prepare to merge with data
sales_pivot <- df_sales_train %>% pivot_longer(cols=starts_with("d_"), names_to="Day", values_to="Sales") %>% rename(Product = id) %>% arrange(Day, Product)


# 3) Merge sales with calendar data
sales_train_ts <- sales_pivot %>%
  left_join(calendar_df, by=join_by(Day==day)) %>%
  as_tsibble(index=Date, key=product_id)


# 4) Add price data
sales_train_ts <- sales_train_ts %>%
  mutate(extracted_id = str_extract(Product, "FOODS_\\d+_\\d+")) %>%
  left_join(price_df, by=c("extracted_id" = "item_id", "wm_yr_wk"="wm_yr_wk"))

# fill na price values with last price
sales_train_ts <- sales_train_ts %>%
  arrange(product_id, Date) %>%
  fill(sell_price)


# 5) select relevant columns
sales_train <- sales_train_ts %>%
  select(Date, product_id,  Sales, wday, month, snap_TX, is_weekend, day_of_month, event, sell_price)


# 6) ++++++++++ Additional feature engineering ++++++++++++++++++
# ---- add product age-----
first_dates_with_sale <- sales_train %>%
  as_tibble() %>%
  filter(Sales > 0) %>%
  group_by(product_id) %>%
  summarize(first_date_with_sales = min(Date)) 

days <- length(calendar_df$Date)

first_dates_with_sale <-first_dates_with_sale %>% 
  left_join(cal_ids, by=c("first_date_with_sales" ="Date")) 

first_dates_with_sale <- first_dates_with_sale %>%
  mutate(product_age = days - id_day)

product_age <- first_dates_with_sale %>%
  select(product_id, product_age)

sales_train <- sales_train %>%
  left_join(product_age, by="product_id")

#---------new product---------
first_dates_with_sale <- first_dates_with_sale %>%
  mutate(new_product = 1)

new_products <- first_dates_with_sale %>%
  select(product_id, first_date_with_sales, new_product) %>%
  rename(Date = first_date_with_sales)

sales_train <- sales_train %>%
  left_join(new_products, by=c("product_id", "Date")) %>%
  mutate(new_product = replace_na(new_product, 0))


# ----------- lags and leads -------------------
sales_train <- sales_train %>%
  as_tibble %>%
  group_by(product_id) %>%
  mutate(sell_price_lag_7 = lag(sell_price, 7, default=first(sell_price))) %>% 
  ungroup() %>%
  as_tsibble(index=Date, key=product_id)

event_lag_1 <- calendar_df %>% 
  mutate(event_lag_1 = lag(event, 1, default=first(event))) %>%
  select(Date, event_lag_1)

event_lag_2 <- calendar_df %>% 
  mutate(event_lag_2 = lag(event, 2, default=first(event))) %>%
  select(Date, event_lag_2)

event_lag_3 <- calendar_df %>% 
  mutate(event_lag_3 = lag(event, 3, default=first(event))) %>%
  select(Date, event_lag_3)

event_lead_1 <- calendar_df %>%
  mutate(event_lead_1 = lead(event, 1, default=last(event))) %>%
  select(Date, event_lead_1)

event_lead_2 <- calendar_df %>%
  mutate(event_lead_2 = lead(event, 2, default=last(event))) %>%
  select(Date, event_lead_2)

event_lead_3 <- calendar_df %>%
  mutate(event_lead_3 = lead(event, 3, default=last(event))) %>%
  select(Date, event_lead_3)


sales_train <- sales_train %>%
  left_join(event_lag_1, by="Date") %>%
  left_join(event_lead_1, by="Date") %>%
  left_join(event_lead_2, by="Date") %>%
  left_join(event_lead_3, by="Date")


# 7) test data + Generate new data
# pivot to prepare to merge with data
sales_test <- sales_test %>% arrange(id) %>% mutate(product_id = row_number()) %>% select(id, product_id, everything())
sales_test_pivot <- sales_test %>% pivot_longer(cols=starts_with("d_"), names_to="Day", values_to="Sales") %>% rename(Product = id) %>% arrange(Day, Product) 

# Merge data and create tsibble
sales_test_ts <- sales_test_pivot %>%
  left_join(calendar_df, by=c("Day" = "day")) %>%
  select(Date, product_id, Sales) %>% 
  as_tsibble(index=Date, key=product_id)

# dates of test data
dates_test_data <- sales_test_ts %>% distinct(Date)

# create "empty" new data for test horizon
new_data <- new_data(sales_train, 28)

# extract calendar information for forcast horizon
cal_new <- calendar_df %>%
  filter(Date %in% dates_test_data$Date) %>%
  select(Date, wday, snap_TX, is_weekend, day_of_month, event)

# get last price before forecast
last_price <- sales_train %>%
  as_tibble() %>%
  group_by(product_id) %>% slice(n()) %>% 
  select(product_id, sell_price)

lagged_last_price <- sales_train %>%
  as_tibble() %>%
  group_by(product_id) %>% slice(n()-8) %>% 
  select(product_id, sell_price) %>%
  mutate(sell_price_lag_7 = sell_price) %>%
  select(-sell_price)

# generate new data for forecast horizon
new_data <- new_data %>%
  left_join(cal_new, by="Date") %>%
  left_join(last_price, by="product_id") %>%
  left_join(lagged_last_price, by="product_id")

new_data <- new_data %>%
  left_join(event_lag_1, by="Date") %>%
  left_join(event_lead_1, by="Date") %>%
  left_join(event_lead_2, by="Date") %>%
  left_join(event_lead_3, by="Date")

new_data <- new_data %>%
  as_tsibble(index=Date, key=product_id)

month <- calendar_df %>%
  select(Date, month)

new_data <- new_data %>%
  left_join(month, by="Date") %>%
  select(-is_weekend)

## ++++++++++++++++++ DYNAMIC REGRESSION +++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------

## ++++++++++++++++++ Sales ~ with lag +++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------

#test <- sales_train %>% filter(product_id<20)

dynamic_reg_lag <- sales_train %>%
  model(ARIMA(Sales ~ sell_price + snap_TX + wday + month + day_of_month + event +
                sell_price_lag_7 + event_lag_1 + event_lead_1 + event_lead_2 + event_lead_3))

fc_dynam_lag <-  forecast(dynamic_reg_lag,  new_data) 


## ++++++++++++++++++ Evaluate ++++++++++

accuracy <- fc_dynam_lag %>% accuracy(sales_test_ts, measures = list(rmse = RMSE))
rmse <- mean(accuracy$rmse, na.rm=TRUE)
print(rmse)


## ++++++++++++++++++ Create Submission File +++++++++

submission_dynamic_3 <- fc_dynam_lag %>% as_tibble() %>% 
  select(product_id, Date, `.mean`) %>% 
  rename(fc = `.mean`) %>%
  mutate(across(fc, round))%>% 
  left_join(ids, by="product_id") %>%
  left_join(calendar_df, by="Date") %>%
  select(id, day, fc) %>%
  pivot_wider(names_from = day, values_from = fc)

write.csv(submission_dynamic_3, "../forecasts/fc_dynamic_3.csv")


## ++++++++++++++++++ Dynamic 4 +++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------

#test <- sales_train %>% filter(product_id<20)

dynamic_reg_4<- sales_train %>%
  model(ARIMA(Sales ~ sell_price + snap_TX + event_lead_1 + event_lead_2 + event_lead_3))

fc_dynam_4 <-  forecast(dynamic_reg_4,  new_data) 


## ++++++++++++++++++ Evaluate ++++++++++

accuracy <- fc_dynam_4 %>% accuracy(sales_test_ts, measures = list(rmse = RMSE))
rmse <- mean(accuracy$rmse, na.rm=TRUE)
print(rmse)


## ++++++++++++++++++ Create Submission File +++++++++

submission_dynamic_4 <- fc_dynam_4 %>% as_tibble() %>% 
  select(product_id, Date, `.mean`) %>% 
  rename(fc = `.mean`) %>%
  mutate(across(fc, round))%>% 
  left_join(ids, by="product_id") %>%
  left_join(calendar_df, by="Date") %>%
  select(id, day, fc) %>%
  pivot_wider(names_from = day, values_from = fc)

write.csv(submission_dynamic_4, "../forecasts/fc_dynamic_4.csv")

