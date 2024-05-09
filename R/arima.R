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
calendar$date_new <- as.Date(calendar$date, format = "%m/%d/%Y")

# create id column to merge with sales data, everything else is disregarded
calendar <- calendar_df %>% select(date_new) %>% arrange(date_new) %>% mutate(id = row_number(), day = paste("d_", id, sep=""))

# 2) Sales train data

# Create id column in order for easier handling (product name is too annoying)
sales_train <- sales_train %>% arrange(id) %>% mutate(id_numeric = row_number()) %>% select(id, id_numeric, everything())
ids <- sales_train %>% select(id_numeric, id)

# pivot to prepare to merge with data
sales_pivot <- sales_train %>% pivot_longer(cols=starts_with("d_"), names_to="Day", values_to="Sales") %>% rename(Product = id) %>% arrange(Day, Product) %>% select(-Product)

# Merge data and create tsibble
sales_train_ts <- merge(sales_pivot, calendar, by.x="Day", by.y="day") %>% 
  select(date_new, id_numeric, Sales) %>% 
  rename(Date = date_new, product_id = id_numeric) %>% 
  as_tsibble(index=Date, key=product_id)

# 3) Sales test data
# pivot to prepare to merge with data
sales_test <- sales_test %>% arrange(id) %>% mutate(id_numeric = row_number()) %>% select(id, id_numeric, everything())
sales_test_pivot <- sales_test %>% pivot_longer(cols=starts_with("d_"), names_to="Day", values_to="Sales") %>% rename(Product = id) %>% arrange(Day, Product) %>% select(-Product)

# Merge data and create tsibble
sales_test_ts <- merge(sales_test_pivot, calendar, by.x="Day", by.y="day") %>% 
  select(date_new, id_numeric, Sales) %>% 
  rename(Date = date_new, product_id = id_numeric) %>% 
  as_tsibble(index=Date, key=product_id)


## ++++++++++++++++++ ARIMA BASELINE ++++++++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------

#test <- sales_ts %>% 
#  filter(product_id <= 100)


arima_fit <- sales_ts %>%
  model(ARIMA(Sales))

fc <- arima_fit %>% forecast(h=28) 


## ++++++++++++++++++ Evaluate ++++++++++


accuracy <- fc %>% accuracy(sales_test_ts, measures = list(rmse = RMSE))


rmse <- mean(accuracy$rmse)
print(rmse)


## ++++++++++++++++++ Create Submission File +++++++++


fc_arima <- fc %>% as_tibble() %>% 
  select(product_id, Date, `.mean`) %>% 
  rename(fc = `.mean`) %>%
  mutate(across(fc, round)) %>% 
  left_join(ids, by=c("product_id" = "id_numeric")) %>%
  left_join(calendar, by=c('Date' = "date_new")) %>%
  rename(product=id.x) %>%
  select(product, day, fc) %>%
  pivot_wider(names_from = day, values_from = fc)

write.csv(fc_arima, "../forecasts/fc_arima_baseline.csv")



## ++++++++++++++++++ Naive Methods ++++++++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------

#test <- sales_ts %>% 
#  filter(product_id <= 100)


fit_baseline <- sales_ts %>%
  model(
    Mean = MEAN(Sales),
    `Naïve` = NAIVE(Sales),
    Drift = NAIVE(Sales ~ drift()),
    `Seasonal naïve` = SNAIVE(Sales)
  )


fc_baseline <- fit_baseline %>% forecast(h=28) 


## ++++++++++++++++++ Evaluate ++++++++++


accuracy_baseline <- fc_baseline %>% accuracy(sales_test_ts, measures = list(rmse = RMSE))


rmse_baseline <- accuracy_baseline %>% group_by(`.model`) %>% summarise(mean(rmse))
print(rmse_baseline)

print(rmse)

## ++++++++++++++++++ Create Submission File +++++++++

baseline_models <- rmse_baseline %>% 
  distinct(`.model`) %>% 
  pull(`.model`) %>%
  as.list()

for(model in baseline_models){
  print(model)
  fc_base <- fc_baseline %>% as_tibble() %>% 
    mutate(Model = `.model`) %>%
    filter(Model== model) %>% 
    select(product_id, Date, `.mean`) %>% 
    rename(fc = `.mean`) %>%
    mutate(across(fc, round)) %>% 
    left_join(ids, by=c("product_id" = "id_numeric")) %>%
    left_join(calendar, by=c('Date' = "date_new")) %>%
    rename(product=id.x) %>%
    select(product, day, fc) %>%
    pivot_wider(names_from = day, values_from = fc)
  
  file_name <- paste("fc_", model, ".csv",sep="")
  write.csv(fc_base, paste("../forecasts/", file_name, sep=""))
  
}

## ++++++++++++++++++ ETS BASELINE ++++++++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------

# test <- sales_ts %>% 
#   filter(product_id <= 20)


ets_fit <- sales_ts %>%
  model(ETS(Sales))

fc_ets <- ets_fit %>% forecast(h=28) 


## ++++++++++++++++++ Evaluate ++++++++++


accuracy_ets <- fc_ets %>% accuracy(sales_test_ts, measures = list(rmse = RMSE))


rmse_ets <- accuracy_ets %>% group_by(`.model`) %>% summarise(mean(rmse))
print(rmse_ets)


## ++++++++++++++++++ Create Submission File +++++++++

submission_ets <- fc_ets %>% as_tibble() %>% 
  select(product_id, Date, `.mean`) %>% 
  rename(fc = `.mean`) %>%
  mutate(across(fc, round)) %>% 
  left_join(ids, by=c("product_id" = "id_numeric")) %>%
  left_join(calendar, by=c('Date' = "date_new")) %>%
  rename(product=id.x) %>%
  select(product, day, fc) %>%
  pivot_wider(names_from = day, values_from = fc)

write.csv(submission_ets, "../forecasts/fc_ets_baseline.csv")



## ++++++++++++++++++ DYNAMIC REGRESSION +++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------

##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------
calendar_df$Date <- as.Date(calendar_df$date, format = "%m/%d/%Y")

calendar_df <- calendar_df %>% arrange(Date)

# dummy if weekend
cal <- calendar_df %>% mutate(is_weekend = if_else(wday<=2, 1,0))

# 
cal <- cal %>% mutate(day_of_month = day(Date))

cal %>% filter(event_name_1 =="Thanksgiving")

# Create a tibble for black_friday and rename the column to "dat"
black_friday <- cal %>%
  filter(event_name_1 == "Thanksgiving") %>%
  mutate(dat = Date + days(1)) %>% 
  select(dat)

# Convert the tibble to a data frame
black_friday <- as.data.frame(black_friday)

# Extract the vector using pull
black_friday_vector <- pull(black_friday, dat)

# Initialize the "black_friday" column in the original dataframe
cal$black_friday <- 0

# Update the "black_friday" column based on the conditions
cal <- cal %>%
  mutate(event_new = if_else(Date %in% black_friday_vector, 1, 0)) %>%
  rename(b_friday = event_new)

cal <- cal %>%
  mutate(event = if_else(!is.na(event_name_1), 1, 0))


thankgsgivings <- cal %>%
  filter(event_name_1 == "Thanksgiving") %>%
  select(Date)

christmas <- cal %>%
  filter(event_name_1 == "Christmas") %>%
  select(Date)

Map(function(x,y){
  print(x)
  print(y)
}, thankgsgivings, christmas)


cal_df <- cal %>%
  select(wm_yr_wk, wday, month, snap_TX, Date, is_weekend, day_of_month, event) 


joined <- sales_ts %>% 
  left_join(cal_df, by="Date") 

ids <- ids %>%
  rename(product_id = id_numeric)
  
joined <- joined %>%
  left_join(ids, by="product_id")

joined <- joined %>%
  mutate(extracted_id = str_extract(id, "FOODS_\\d+_\\d+"))

joined <- joined %>%
  rename(item_id = extracted_id) %>% 
  left_join(price_df, by=c("item_id", "wm_yr_wk"))

joined %>% 
  filter(is.na(sell_price))

joined <- joined %>% 
  arrange(product_id, Date) %>%
  fill(sell_price)

joined <- joined %>%
  select(Date, product_id, id, Sales, wday, month, snap_TX, is_weekend, day_of_month, b_friday, event, sell_price)


## ++++++++++++++++++ Sales ~ snap_TX +++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------
#test <-  joined %>%
#  filter(product_id <= 20)


dynamic_reg <- joined %>%
  model(ARIMA(Sales ~ snap_TX))


fc_horizon_dates <- sales_test_ts %>% distinct(Date) %>%
  mutate(shift_date = Date - years(1))

new_snap_data <- joined %>% filter(Date %in% fc_horizon_dates$shift_date) %>%
  select(Date, product_id, snap_TX) %>%
  mutate(Date = Date + years(1)) %>% 
  as_tsibble()

fc_dynam <-  forecast(dynamic_reg,  new_snap_data) 


## ++++++++++++++++++ Evaluate ++++++++++

accuracy <- fc_dynam %>% accuracy(sales_test_ts, measures = list(rmse = RMSE))

test_fc <- fc_dynam %>%
  as_tibble() %>%
  mutate(across('.mean', round))
  
acc <- accuracy(test_fc, sales_test_ts)
rmse <- mean(acc$RMSE)
print(RMSE)


rmse <- mean(accuracy$rmse)
print(rmse)

## ++++++++++++++++++ Create Submission File +++++++++

submission_dynamic <- fc_dynam %>% as_tibble() %>% 
  select(product_id, Date, `.mean`) %>% 
  rename(fc = `.mean`) %>%
  mutate(across(fc, round)) %>% 
  left_join(ids, by="product_id") %>%
  left_join(calendar, by=c('Date' = "date_new")) %>%
  rename(product=id.x) %>%
  select(product, day, fc) %>%
  pivot_wider(names_from = day, values_from = fc)

write.csv(submission_dynamic, "../forecasts/fc_dynamic_1.csv")

## ++++++++++++++++++ no-lags +++++++++++++++++++++++
##--------------------------------------------------------------
##--------------------------------------------------------------
##--------------------------------------------------------------

dynamic_reg_2 <- joined %>%
  select(-id) %>% 
  model(ARIMA(Sales ~ sell_price + snap_TX + wday + month + day_of_month + event))


fc_horizon_dates <- sales_test_ts %>% distinct(Date) 

fc_horizon_dates <- cal %>% filter(Date %in% fc_horizon_dates$Date) %>%
  select(Date, wday, month, day_of_month, event)

last_price <- joined %>%
  as_tibble() %>%
  group_by(product_id) %>% slice(n()) %>% 
  select(product_id, sell_price)

shifted_dates <- sales_test_ts %>% distinct(Date) %>%
  mutate(shift_date = Date - years(1))

snap_data <- joined %>% filter(Date %in% shifted_dates$shift_date) %>%
  select(Date, product_id, snap_TX) %>%
  mutate(Date = Date + years(1)) %>% 
  as_tsibble()


new_snap_data <- fc_horizon_dates %>%
  left_join(sales_test_ts, by="Date") %>%
  select(-Sales) %>%
  arrange(product_id, Date) %>%
  left_join(last_price, by="product_id") %>%
  left_join(snap_data, by=c("product_id", "Date")) %>%
  as_tsibble(index=Date, key=product_id)
  
fc_dynam_2 <-  forecast(dynamic_reg_2,  new_snap_data) 


## ++++++++++++++++++ Evaluate ++++++++++

accuracy <- fc_dynam_2 %>% accuracy(sales_test_ts, measures = list(rmse = RMSE))
rmse <- mean(accuracy$rmse)
print(RMSE)

test_fc <- fc_dynam %>%
  as_tibble() %>%
  mutate(across('.mean', round))

acc <- accuracy(test_fc, sales_test_ts)
rmse <- mean(acc$RMSE)
print(RMSE)


rmse <- mean(accuracy$rmse)
print(rmse)

## ++++++++++++++++++ Create Submission File +++++++++

submission_dynamic <- fc_dynam %>% as_tibble() %>% 
  select(product_id, Date, `.mean`) %>% 
  rename(fc = `.mean`) %>%
  mutate(across(fc, round)) %>% 
  left_join(ids, by="product_id") %>%
  left_join(calendar, by=c('Date' = "date_new")) %>%
  rename(product=id.x) %>%
  select(product, day, fc) %>%
  pivot_wider(names_from = day, values_from = fc)

write.csv(submission_dynamic, "../forecasts/fc_dynamic_1.csv")







## ++++++++++++++++++
## ++++++++++++++++++
## ++++++++++++++++++
## ++++++++++++++++++
## ++++++++++++++++++
## ++++++++++++++++++
## ++++++++++++++++++

joined %>% filter(product_id == 89) %>% autoplot(Sales)

mean_price %>% price_df


prod_freq <- joined %>% select(Date, product_id, Sales) %>%
  mutate_all(~replace(., . == 0, NA)) %>%
  as.data.frame() %>%
  group_by(product_id) %>%
  summarise(mean(Sales, na.rm=TRUE))



