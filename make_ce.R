# Purpose: Compile cost-effectiveness results for GiveWell charities
# Author: Karthik Tadepalli

#---------------SETUP------------------

# load packages, install if not present
if (!require("pacman")) install.packages("pacman")
pacman::p_load(tidyverse, janitor, lubridate, readxl, glue)

#-----------2017---------------

ce17_1 <- read_xlsx("givewell_ce/2017-05-20.xlsx", sheet = "Results", n_max = 7) %>%
  clean_names() %>%
  select(charity = results_sheet, ce = median_result) %>%
  filter(!grepl("Charity", charity)) %>%
  mutate(charity = sub(" vs Cash", "", charity),
         date = "2017-05-20")

ce17_2 <- read_xlsx("givewell_ce/2017-08-16.xlsx", sheet = "Results", n_max = 7) %>%
  clean_names() %>%
  select(charity = results_sheet, ce = median_result) %>%
  filter(!grepl("Charity", charity)) %>%
  mutate(charity = sub(" vs Cash", "", charity),
         date = "2017-08-16")

ce17_3 <- read_xlsx("givewell_ce/2017-11-27.xlsx", sheet = "Results", n_max = 9) %>%
  clean_names() %>%
  select(charity = results, ce = median_result) %>%
  filter(!grepl("Charity", charity)) %>%
  mutate(charity = sub(" vs Cash", "", charity),
         date = "2017-11-27")

#---------------2018-----------------

ce18 <- read_xlsx("givewell_ce/2018-11-27.xlsx", sheet = "Results", n_max = 10) %>%
  clean_names() %>%
  select(charity = results, ce = median_result) %>%
  filter(row_number() > 2) %>%
  mutate(charity = sub(" vs Cash", "", charity),
         date = "2018-11-27")

#---------------2019-----------------

ce19 <- read_xlsx("givewell_ce/2019-11-25.xlsx", sheet = "Results", n_max = 26) %>%
  clean_names() %>%
  select(charity = results, ce = x2) %>%
  filter(row_number() > 18) %>%
  mutate(charity = sub(" vs Cash", "", charity),
         date = "2019-11-25")

#---------------2020--------------------

ce20_1 <- read_xlsx("givewell_ce/2020-09-11.xlsx", sheet = "Results", n_max = 26) %>%
  clean_names() %>%
  select(charity = results, ce = x2) %>%
  filter(row_number() > 17) %>%
  mutate(charity = sub(" vs Cash", "", charity),
         date = "2020-09-11")

ce20_2 <- read_xlsx("givewell_ce/2020-11-19.xlsx", sheet = "Results", n_max = 26) %>%
  clean_names() %>%
  select(charity = results, ce = x2) %>%
  filter(row_number() > 17) %>%
  mutate(charity = sub(" vs Cash", "", charity),
         date = "2020-11-19")

#-------------COMPILE UNTIL 2021------------

ce_till_2021 <- do.call('rbind', 
                      list(ce17_1, ce17_2, ce17_3, ce18, ce19, ce20_1, ce20_2)) %>%
  mutate(charity = sub("Schistosomiasis Control Initiative", "SCI Foundation", charity),
         charity = sub("Against Malaria Foundation", "AMF", charity),
         date = as_date(date),
         ce = as.numeric(ce)) %>%
  filter(charity != "GiveDirectly")
  
#------------2021 and 2022 (broken down by country)---------------

charities <- c("AMF", "Deworm the World", "END Fund", "SCI Foundation", 
               "Sightsavers", "Malaria Consortium", "Helen Keller International", 
               "New Incentives")

read_ce <- function(date_str) {
  ce_df <- data.frame()
  for (charity in charities) {
    df <- read_xlsx(glue("givewell_ce/{date_str}.xlsx"), sheet = charity) 
    names(df)[1] <- "x1"
    
    ce_est <- df %>%
      # select final CE estimate
      filter(grepl("Cost-effectiveness", x1)) %>%
      tail(1) %>%
      select(-x1)
    
    funding <- df %>%
      filter(grepl("Percentage of funding to be allocated", x1)) %>%
      select(-x1)
    
    # later CEs don't have funding fractions - infer from "Total spending" row
    if (nrow(funding) == 0) {
      funding <- df %>%
        filter(grepl("Total (.*) by all contributors", x1)) %>%
        select(-x1) %>%
        flatten_chr()
    } else {
      funding <- funding %>%
        flatten_chr()
    } 
    # ensure funding weights are fractions
    funding <- as.numeric(funding)
    funding <- funding/sum(funding)

    # match country names and CEs
    countries <- colnames(ce_est)
    ce <- ce_est[1,] %>% flatten_chr()
    ce <- as.numeric(ce)
    
    df <- data.frame(charity = charity, country = countries, ce = ce,
                     funding = funding, date = date_str)
    ce_df <- bind_rows(ce_df, df)
  }
  
  return(ce_df)
}

ce21_1 <- read_ce("2021-05-05")
ce21_2 <- read_ce("2021-07-06")
ce21_3 <- read_ce("2021-09-28")
ce22_1 <- read_ce("2022-03-29")
ce22_2 <- read_ce("2022-08-04")

ce_post_2021 <- do.call('rbind', list(ce21_1, ce21_2, ce21_3, ce22_1, ce22_2)) %>%
  mutate(date = as_date(date),
         ce = as.numeric(ce),
         funding = as.numeric(funding))

# make overall CEs for non-SCI, non-New Incentives charities
ce_overall <- ce_post_2021 %>%
  filter(!charity %in% c("SCI Foundation", "New Incentives")) %>%
  group_by(charity, date) %>%
  summarise(ce = weighted.mean(ce, funding)) %>%
  ungroup()

# where there is overall CE, use it
ce_overall <- ce_post_2021 %>%
  filter(country == "Overall") %>%
  select(charity, date, ce) %>%
  mutate(ce = as.numeric(ce),
         date = as_date(date)) %>%
  # merge with pre-2021 CEs
  bind_rows(ce_till_2021) %>% 
  # merge with weighted CEs post-2021
  bind_rows(ce_overall) %>%
  arrange(date) %>%
  # merge names 
  mutate(charity = sub("The END Fund", "END Fund", charity))

#----------ADJUSTMENTS-------------

read_adjustments <- function(date_str) {
  adj_df <- data.frame()
  for (charity in charities) {
    df <- read_xlsx(glue("givewell_ce/{date_str}.xlsx"), sheet = charity) 
    names(df)[1] <- "x1"
    
    adj <- df %>%
      # select total adjustment factor
      filter(grepl("Total adjustment factor", x1)) %>%
      tail(1) %>%
      select(-x1) %>%
      flatten_chr() %>%
      as.numeric()

    countries <- colnames(df)[2:length(df)]
    
    df <- data.frame(charity = charity, country = countries, adjustment = adj,
                     date = date_str)
    adj_df <- bind_rows(adj_df, df)
  }
  
  return(adj_df)
}

adj21_1 <- read_adjustments("2021-05-05")
adj21_2 <- read_adjustments("2021-07-06")
adj21_3 <- read_adjustments("2021-09-28")
adj22_1 <- read_adjustments("2022-03-29")
adj22_2 <- read_adjustments("2022-08-04")

adj_post_2021 <- do.call('rbind', list(adj21_1, adj21_2, adj21_3, adj22_1, adj22_2)) %>%
  mutate(date = as_date(date),
         adjustment = as.numeric(adjustment))

#----------OUTPUT-------------

write.csv(ce_overall, "clean_data/overall_ce.csv", row.names = F)
write.csv(ce_post_2021, "clean_data/ce_post_2021.csv", row.names = F)  
write.csv(adj_post_2021, "clean_data/adjustments_post_2021.csv", row.names = F)  