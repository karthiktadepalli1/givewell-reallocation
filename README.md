# GiveWell reallocation analysis

This repository analyzes the value of reallocating money between GiveWell's top charities. It is laid out as follows:

* `givewell_ce` contains the downloaded Excel spreadsheets for GiveWell's cost-effectiveness analyses. I use these to efficiently extract bottom-line cost-effectiveness estimates for each charity, re-evaluated each time GiveWell does a new analysis.
* `allocations` contains the Top Charities Fund allocations. I created this by hand, mostly copy-pasting the [table on GiveWell's page](https://www.givewell.org/top-charities-fund) and formatting it so that each row is a charity-year.
* `clean_data` contains the cleaned cost-effectiveness estimates, which are created in `make_ce.R`.
* `output` contains the figures and tables used in the analysis, which are created in `reallocations.R`.

The analysis document is `entry.md`.