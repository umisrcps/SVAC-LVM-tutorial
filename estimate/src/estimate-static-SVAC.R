## Authors:      CJF, Ju
## Maintainers:  Ju
##
## ---------------------------------
## Purpose: calculate static SVAC model
## ---------------------------------

library(argparse)
library(yaml)
library(rstan)
library(parallel)

rm(list=ls())

## declare arguments if working with Makefile
parser    <- ArgumentParser()
parser$add_argument("--inputfile", type='character')
parser$add_argument("--STANcode", type='character')
parser$add_argument("--CONSTANTS", type='character')
parser$add_argument("--model_functions", type='character')
parser$add_argument("--outputfile", type='character')
arguments <- parser$parse_args()

## declare arguments if not working with Makefile
# setwd("<fill in your personal path>/SVAC-LVM-tutorial/")
# arguments <- list(inputfile='import/output/SVAC_main.csv',
#                   STANcode='estimate/src/SVAC_static.stan',
#                   model_functions='estimate/src/model-functions.R',
#                   CONSTANTS='estimate/hand/CONSTANTS.yaml',
#                   outputfile='estimate/output/SVAC_static_est.csv')

#the CONSTANTS in the yaml file will declare some additional STAN parameters 
CONSTANTS <- yaml.load_file(arguments$CONSTANTS)

# let's read in some additional functions that will help us plot different model aspects
source(arguments$model_functions)

data <- read.csv(arguments$inputfile, header=TRUE, sep='|', stringsAsFactors = FALSE)

## adding +1 because STAN wants categorical data to start at 1 
state <- data$state_prev + 1
ai    <- data$ai_prev + 1
hrw   <- data$hrw_prev + 1

## STAN deals w missing data (NA observations in the prevalence vectors) differently, 
##  we keep track of missing data by setting them relative to the full index:
##  i.e., we index the observed values only when they are not missing (e.g., index_state)
##  while also keeping track of the original index positions with: index_all
index_all   <- 1:nrow(data)
index_state <- index_all[!is.na(state)]
index_ai    <- index_all[!is.na(ai)]
index_hrw   <- index_all[!is.na(hrw)]

## ensure that the observed vars are of the same length as their indices; 
##  these are the vectors entering the model
state <- state[!is.na(state)]
ai    <- ai[!is.na(ai)]
hrw   <- hrw[!is.na(hrw)]

## create scalars, i.e., the total number of observed values; 
## in STAN, we declare the length of each of the vectors, 
## so the program knows how long they are before entering them in model
n_state <- length(state)
n_ai    <- length(ai)
n_hrw   <- length(hrw)
n_all   <- nrow(data)

## create a list of all things created so far, to be processed in STAN
stan.data <- list(
  n_state = n_state,
  n_ai    = n_ai,
  n_hrw   = n_hrw,
  n_all   = n_all,
  
  index_state = index_state,
  index_ai    = index_ai,
  index_hrw   = index_hrw,
  
  state = state,
  ai    = ai,
  hrw   = hrw
)

## for the sampling procedure, we want to reproduce the exact same results 
##   every time we run this model
##   this way, journals and others are able to reproduce our findings
##   you can pick a seed at random, set it in the CONSTANTS file
set.seed(CONSTANTS$random_seed)

## The parallel packages helps us detect the number of cores available on our machine for
##   executing the chains in parallel. In Rstan, the default setting is 1.
## The recommendation is to set the cores option to as many processors 
##   as the hardware and RAM allow 
##   but not higher than the number of chains we are running.
avail.cores <- detectCores(logical = FALSE)

## STAN passes the simulated values back to R in the form of a list, 
##   putting all the chains into separate arrays
static.stan.fit <- stan(
  file=arguments$STANcode,
  data=stan.data,
  ## iter: number of times simulations will happen, the first half are used for 
  ##   burning in the model and get thrown out, the second half are used for 
  ##  inference and get saved. 
  ##   To know we have enough iterations, we will calculate the R-hat statistic 
  ##   (Gelman-Rubin statistic) 
  ##   --> the Rhat statistic has to be as close to 1 as possible to ensure 
  ##   that the model has converged
  iter=CONSTANTS$static_STAN_iter,
  ## chains: designate the number of independent simulations happening at the same time, 
  ## each simulation gets computed in parallel by one processor
  chains=CONSTANTS$static_STAN_chains,
  ## set the number of cores in the CONSTANTS file based on the technical 
  ##  specifications of your machine, 
  ##  i.e., do not exceed the number of cores you have available
  cores=avail.cores
)

## if you like, you can save this stan object like so: (just fyi, it is usually quite big)
# saveRDS(static.stan.fit, file='estimate/output/full-stan-fit.rds')

## we use the Rhat plot function to check if the model converged, the Rhat's have to be below 1.1
make_Rhat_plot(static.stan.fit, 'static')

## here we extract just the parameters that are interesting to us
##   staticstanout gives us a list of model parameters, 
##   i.e., theta, beta and the alpha difficulty cut points
staticstanout <- extract(static.stan.fit)

## let's plot the cut points that the model estimated
##  using a function we read in earlier
plot_cutpoints_by_source(staticstanout, 'static')

## theta is the latent variable, we want its mean, std, upper and lower bounds for plotting later
data$theta       <- apply(staticstanout$theta, 2, mean)
data$theta_sd    <- apply(staticstanout$theta, 2, sd)
#CREDIBLE intervals (CI)
data$theta_upper <- apply(staticstanout$theta, 2, quantile, 0.975)
data$theta_low   <- apply(staticstanout$theta, 2, quantile, 0.025)

write.table(data, arguments$outputfile, sep="|", row.names = FALSE)
##end of Rscript.