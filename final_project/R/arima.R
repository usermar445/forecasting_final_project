#load packages
library(fpp3)


## ++++++++++++++++++ LOAD DATA ++++++++++++++++++++++++++++
#load data
data_path <- "../data/"

# train data
sales_train <- read.csv(paste(data_path,"sales_train_validation_afcs2023.csv", sep=""))

# test data
sales_test <- read.csv(paste(data_path,"sales_test_validation_afcs2022.csv", sep=""))

# calendar data
calendar <- read.csv(paste(data_path,"calendar_afcs2023.csv", sep=""))


## ++++++++++++++++++ PREPARE DATA SETS ++++++++++++++++++++++++++++

# 1) Calendar data
# convert to Date object
calendar$date_new <- as.Date(calendar$date, format = "%m/%d/%Y")

# create id column to merge with sales data, everything else is disregarded
calendar <- calendar %>% select(date_new) %>% arrange(date_new) %>% mutate(id = row_number(), day = paste("d_", id, sep=""))

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


## ++++++++++++++++++ RUN TEST PREDICTION ++++++++++++++++++++++++++++

#test <- sales_ts %>% 
#  filter(product_id <= 100)


arima_fit <- sales_ts %>%
  model(ARIMA(Sales))

fc <- arima_fit %>% forecast(h=28) 


## ++++++++++++++++++ EVALUATE ++++++++++++++++++++++++++++


accuracy <- fc %>% accuracy(sales_test_ts, measures = list(rmse = RMSE))


rmse <- mean(accuracy$rmse)
print(rmse)






