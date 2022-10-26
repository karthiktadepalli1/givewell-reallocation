# Purpose: Analyze cleaned cost-effectiveness data for GiveWell charities
# Author: Karthik Tadepalli

#---------------SETUP------------------

# load packages, install if not present
if (!require("pacman")) install.packages("pacman")
pacman::p_load(tidyverse, ggthemes, lubridate, stringr, scales,
               knitr, kableExtra, magick)

theme_set(theme_bw())

# read data
ce_overall <- read_csv("clean_data/overall_ce.csv")

#---------------READ ALLOCATIONS----------------

alloc <- read_csv("allocations/MIF_allocations.csv") %>%
  mutate(yr = as.numeric(str_sub(date, -4, -1)),
         amount = sub(" million", "", amount),
         amount = sub("$", "", amount, fixed = T),
         amount = as.numeric(amount) * 1000000)

# combine yearly allocations
yearly <- alloc %>%
  filter(yr > 2014) %>%
  group_by(yr, charity) %>%
  summarise(yearly_allocation = sum(amount)) %>%
  ungroup()

# include non-allocation as zeros
yearly <- yearly %>% 
  expand(yr, charity) %>%
  left_join(yearly) %>%
  mutate(yearly_allocation = replace_na(yearly_allocation, 0)) 

#-------------ALLOCATIONS AND COST-EFFECTIVENESS----------------

# change names for merge
yearly <- yearly %>%
  mutate(charity = sub("Against Malaria Foundation", "AMF", charity),
         charity = sub("Schistosomiasis Control Initiative", "SCI Foundation", charity),
         charity = sub("Seasonal Malaria Chemoprevention", "Malaria Consortium", charity))

# make a unique CE for each year
ce_yearly <- read_csv("clean_data/overall_ce.csv") %>%
  mutate(yr = year(date)) %>%
  group_by(charity, yr) %>%
  summarise(ce = mean(ce)) %>%
  # make CE from previous year
  mutate(lagged_ce = lag(ce)) %>%
  ungroup()

# merge 
merged <- yearly %>%
  inner_join(ce_yearly) %>%
  mutate(received_money = as.numeric(yearly_allocation > 0))

#----------------HOW MUCH COULD WE GET FROM REALLOCATION?---------------------

# baseline - create yearly value estimates of GiveWell's portfolio 
baseline <- merged %>%
  group_by(yr) %>%
  summarise(total_value = sum(yearly_allocation * ce))

# assume you can only reallocate between charities that received any money at all 
# impact of reallocating X% of funding from the least effective one to the most effective
conservative_reallocation <- function(reallocation_frac) {
  comparison <- merged %>%
    filter(yearly_allocation > 0) %>%
    group_by(yr) %>%
    mutate(worst = (ce == min(ce)),
           best = (ce == max(ce)))
  
  # identify worst charities and calculate how much to reduce from their allocation
  reduction <- comparison %>%
    filter(worst) %>%
    mutate(reallocation = reallocation_frac * yearly_allocation,
           value_lost = reallocation * ce) %>%
    select(yr, taken_from = charity, reallocation, value_lost)
  
  # merge back to best charities, estimate value from reallocating to best charities
  increase <- comparison %>%
    filter(best) %>%
    left_join(reduction) %>%
    mutate(reallocation_frac = reallocation_frac, 
           value_created = reallocation * ce - value_lost) %>%
    select(yr, given_to = charity, taken_from, initial_budget = yearly_allocation,
           reallocation, reallocation_frac, value_created)
  
  return(increase)
}

# make estimates of value created, both absolute and as fraction of GiveWell's portfolio
final <- conservative_reallocation(reallocation_frac = 0.1) %>%
  left_join(baseline) %>%
  mutate(frac_givewell = value_created/total_value)

# yearly bar plot of value created by reallocation (absolute)
p <- ggplot(final, aes(x = as.factor(yr), y = value_created)) + 
  geom_bar(stat = 'identity', position = 'dodge') +
  scale_y_continuous(labels = dollar_format(scale = 0.000001, suffix = 'M')) + 
  labs(x = "", y = "",
       title = "Reallocating funding is equivalent to a GiveDirectly donation of...",
       caption = paste0("Estimate derived from reducing yearly funding to least-effective ",
                        "charity by 10% and reallocating to \n most-effective charity ",
                        "that received any funding that year. Evaluated by ",
                        "CE estimates from that year.")) + 
  theme(plot.title = element_text(hjust=0.5),
        plot.caption = element_text(size=10))
p
ggsave("output/ce_reallocation.png", p, width = 8, height = 5)

# yearly bar plot of value created by reallocation (fraction of GiveWell value)
p <- ggplot(final, aes(x = as.factor(yr), y = frac_givewell)) + 
  geom_bar(stat = 'identity') +
  scale_y_continuous(labels = percent) + 
  labs(x = "", y = "",
       title = "Reallocating funding increases GiveWell's total value created by...",
       caption = paste0("Estimate derived from reducing yearly funding to least-effective ",
                        "charity by 10% and reallocating to \n most-effective charity ",
                        "that received any funding that year. Evaluated by ",
                        "CE estimates from that year.\nGiveWell value created is the ",
                        "sum of (cost-effectiveness x money allocated) across charities.")) + 
  theme(plot.title = element_text(hjust=0.5),
        plot.caption = element_text(size=10))
p
ggsave("output/ce_reallocation_frac.png", p, width = 8, height = 5)

#-----------VALUE INCREASE AS A FUNCTION OF REALLOCATION RATE------------

possible_reallocations <- seq(0.1, 0.4, 0.01)
curve <- data.frame()
for (realloc in possible_reallocations) {
  curve <- bind_rows(curve, conservative_reallocation(reallocation_frac = realloc))
}

curve <- curve %>%
  # combine years to get average value created
  group_by(reallocation_frac) %>%
  summarise(value_created = mean(value_created)) %>%
  ungroup()

p <- ggplot(curve, aes(x = reallocation_frac, y = value_created)) + 
  geom_line() + 
  scale_y_continuous(labels = dollar_format(scale = 0.000001, suffix = "M")) + 
  scale_x_continuous(labels = percent) + 
  labs(x = "% of funding reallocated from least-effective to most-effective",
       y = "", title = "Reallocating funding is equivalent to a GiveDirectly donation of...",
       caption = "Averaged over 2017-2022.") + 
  theme(plot.title = element_text(hjust=0.5))
p
ggsave("output/reallocation_fraction.png", p, width = 8, height = 5)

#---------------COMPARING REALLOCATION TO BUDGET---------------

tab <- final %>%
  mutate(pct_increase = round(100 * reallocation/initial_budget, 0),
         pct_increase = paste0(pct_increase, "%"), 
         initial_budget = paste0("$", initial_budget/1000000, "M"),
         reallocation = paste0("$", reallocation/1000000, "M")) %>%
  select(year = yr, given_to, initial_budget, reallocation, pct_increase)

tab %>%
  kbl() %>%
  kable_paper() %>%
  save_kable("output/reallocation_table.png")

#---------------COMPARING CE OF ORGANIZATIONS----------------

# identify most/least effective orgs that got money in a year
comparison <- merged %>%
  filter(yearly_allocation > 0) %>%
  group_by(yr) %>%
  mutate(worst = (ce == min(ce)),
         best = (ce == max(ce))) %>%
  filter(worst | best)

worst <- comparison %>%
  filter(worst) %>%
  select(yr, least_ce = charity, min_ce = ce)

best <- comparison %>%
  filter(best) %>%
  select(yr, most_ce = charity, max_ce = ce)

# merge them, make the cost-effectiveness ratio
tab <- worst %>% 
  inner_join(best) %>%
  mutate(ce_increase = round(100 * max_ce/min_ce, 0),
         ce_increase = paste0(ce_increase, "%"))

# print table
tab %>%
  kbl() %>%
  kable_paper() %>%
  save_kable("output/ce_increase.png")
