gen <- odin::odin("reference/model.R")

case_compare <- function(state, observed, pars) {
  proportion_modelled <- state[["Ih"]]
  dbinom(x = observed$positive,
         size = observed$tested,
         prob = proportion_modelled,
         log = TRUE)
}

scale_log_weights <- function(log_weights) {
  log_weights[is.nan(log_weights)] <- -Inf
  max_log_weights <- max(log_weights)
  if (!is.finite(max_log_weights)) {
    ## if all log_weights at a time-step are -Inf, this should
    ## terminate the particle filter and output the marginal
    ## likelihood estimate as -Inf
    average <- -Inf
    weights <- rep(NaN, length(log_weights))
  } else {
    ## calculation of weights, there is some rescaling here to avoid
    ## issues where exp(log_weights) might give computationally zero
    ## values
    weights <- exp(log_weights - max_log_weights)
    average <- log(mean(weights)) + max_log_weights
  }
  list(weights = weights, average = average)
}

observed <- read.csv("casedata_monthly.csv")
## Very stripped down version of the mcstate::particle_filter_data
## logic
data <- cbind(t_start = observed$t[-nrow(observed)],
              t_end = observed$t[-1],
              observed[-1, -1])

n_particles <- 100

pars <- list(init_Ih = 0.8,
             init_Sv = 100,
             init_Iv = 1,
             nrates = 15,
             init_beta = -log(0.9)) # must match mu

beta_volatility <- 0.5

## Annoyingly there is really no good way of getting a named input
## vector out of odin (see mrc-3156), so there's a bit of a fight here
## to pull it off.
set.seed(1)
log_likelihood <- rep(0, 50)
for (s in seq_along(log_likelihood)) {
  mod <- gen$new(user = pars)
  idx <- seq_along(mod$initial(0)) + 1
  y0 <- mod$run(c(0, 1))[1,]
  state <- matrix(y0, length(y0), n_particles,
                  dimnames = list(names(y0), NULL))

  log_likelihood_step <- numeric(nrow(data))

  for (i in seq_len(nrow(data))) {
    d <- data[i,]

    log_weight <- numeric(n_particles)
    for (j in seq_len(n_particles)) {
      state[, j] <- mod$run(c(d$t_start, d$t_end), state[idx, j])[2,]
      log_weight[[j]] <- case_compare(state[, j], d, pars)
    }

    scaled_weight <- scale_log_weights(log_weight)
    log_likelihood_step[[i]] <- scaled_weight$average
    log_likelihood[[s]] <- log_likelihood[[s]] + scaled_weight$average

    kappa <- sample.int(n_particles, prob = scaled_weight$weights, replace = TRUE)
    state <- state[, kappa]
    state["beta",] <- state["beta",] * exp(rnorm(n_particles) * beta_volatility)
  }
}

mean(log_likelihood)
var(log_likelihood) ^ 0.5