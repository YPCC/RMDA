#' Calculate decision curves
#'
#'Decision curves are a useful tool to evaluate the population impact of adopting a risk prediction instrument into clinical practice. Given one or more instruments (risk models) that predict the probability of a binary outcome, this package calculates and plots decision curves, which display estimates of the standardized net benefit by the probabilty threshold used to categorize observations as 'high risk.'  Bootstrap confidence intervals are displayed as well. This package is a companion to the manuscript '(put ref here.)'.
#'
#' @param formula an object of class 'formula' of the form outcome ~ predictors, giving the prediction model to be fitted using glm.
#' @param data data.frame containing outcome and predictors. Missing data on any of the predictors will cause the entire observation to be removed.
#' @param family a description of the error distribution and link function to pass to 'glm' used for model fitting. Defaults to binomial(link = "logit") for logistic regression.
#' @param fitted.risk logical (default FALSE) indicating whether the predictor provided are estimated risks from an already established model. If set to TRUE, no model fitting will be done and all estimates will be conditional on the risks provided.  Risks must fall between 0 and 1.
#' @param thresholds Numeric vector of high risk thresholds to use when plotting and calculating net benefit values.
#' @param confidence.intervals Numeric (default 0.95 for 95\% confidence bands) level of bootstrap confidence intervals to plot. Set as NA or 'none' to remove confidence intervals. See details for more information.
#' @param bootstraps Number of bootstrap replicates to use to calculate confidence intervals (default 500).
#' @details  Confidence intervals for (standardized) net benefit are calculated pointwise at each risk threshold. Bootstrap sampling is done without stratifying on outcome, so disease prevalence varies within bootstrap samples.
#' @return List with components
#' \itemize{
#'   \item derived.data: A data frame in long form showing the following for each predictor and each 'threshold', 'FPR':false positive rate, 'TPR': true positive rate, 'NB': net benefit, 'sNB': standardized net benefit, 'rho': outcome prevalence, 'DP': detection probability, 'model': name of prediction model, 'xx_lower', 'xx_upper': the lower and upper confidence bands for TPF, FPF, rho, DP, NB and sNB.
#'   \item confidence.intervals: Level of confidence intervals returned.
#'   \item call: matched function call.
#' }
#'
#' @seealso \code{\link{summary.decision.curve}},  \code{\link{Add_CostBenefit_Axis}}
#' @examples
#'#helper function
#' expit <- function(xx) exp(xx)/ (1+exp(xx))
#'
#'#load simulated data
#'data(dcaData)
#'baseline.model <- decision_curve(Cancer~Age + Female + Smokes,
#'                                 data = dcaData,
#'                                 thresholds = seq(0, .4, by = .001),# calculate thresholds from 0-0.4 at every 0.001 increment.
#'                                 bootstraps = 25) #number of bootstraps should be higher
#'
#'full.model <- decision_curve(Cancer~Age + Female + Smokes + Marker1 + Marker2,
#'                             data = dcaData,
#'                             thresholds = seq(0, .4, by = .001),# calculate thresholds from 0-0.4 at every 0.001 increment.
#'                             bootstraps = 25)
#'
#'
#' @export

decision_curve <- function(formula,
                          data,
                          family = binomial(link = "logit"),
                          fitted.risk = FALSE,
                          thresholds = seq(0, 1, by = .01),
                          confidence.intervals = 0.95,
                          bootstraps = 500){
 call <- match.call()

  #check vars are in data
  if(any( names.check <- !is.element(all.vars(formula), names(data)))) stop(paste("variable(s)", paste( all.vars(formula)[names.check], collapse = ", ") , "not found in 'data'"))

 #throw out missing data
  data <- data[,all.vars(formula)]
  #complete case indicator
  cc.ind <- complete.cases(data)

  if(sum(cc.ind) < nrow(data)) warning(paste(sum(1-cc.ind), "observation(s) with missing data removed"))

  data <- data[cc.ind,]

  #retreive outcome
  outcome <- data[[all.vars(formula[[2]])]]
  ## check inputs
   #if fitted risks are provided, then there can only be one term on the rhs of formula
   #and the provided risks must be
  if(fitted.risk){
    message("Fitted risks are provided, no model fitting will be done by DecisionCurve. Bootstrap confidence intervals are conditional on the model used to fit risks.")
    if(length(all.vars(formula[[3]])) > 1) stop("When fitted.risk = TRUE, there can only be one term  (denoting the fitted risks) on the right hand side of the formula provided.")

    provided.risks <-  data[[Reduce(paste, deparse(formula[[3]]))]] #get the name of the fitted risk variable from formula.
    if(min(provided.risks) < 0 | max(provided.risks) > 1) stop("When fitted.risks = TRUE, all risks provided must be between 0 and 1.")

  }
  #...

  #calculate curves
  #first we fit the model

  #extract the model name from formula
  predictors <- c(Reduce(paste, deparse(formula[[3]])), "All", "None")
  predictor.names <- c(Reduce(paste, deparse(formula)), "All", "None")

  #indicate whether we are fitting a model with a formula or not
  #the last two are FALSE since they correspond to 'all' and 'none'
  formula.ind <- c(ifelse(fitted.risk, FALSE, TRUE), FALSE, FALSE)

  data[["All"]] <- 1
  data[["None"]] <- 0

  n.preds <- length(predictors) #should always be three

  n.out <- length(predictors)*length(thresholds)
  dc.data <- data.frame("thresholds" = numeric(n.out),
                    "FPR" = numeric(n.out),"TPR" = numeric(n.out),
                    "NB" = numeric(n.out), "sNB" = numeric(n.out),
                    "rho" = numeric(n.out),"prob.high.risk" = numeric(n.out),
                    "DP" = numeric(n.out),
                    "model"= numeric(n.out))

  #if ci's
  #set up vars for bootstrap ci's and first calculate bootstrap indices
  if(is.numeric(confidence.intervals))  {

    #bootstrap sampling indices
    B.ind <- matrix(nrow = nrow(data), ncol = bootstraps)
    for(b in 1:bootstraps) B.ind[,b] <- sample.int(nrow(data), replace = TRUE)
    dc.data <- add.ci.columns(dc.data)
  }

  index = 1
  n.pred = 1
  for(i in 1:n.preds){

    tmpNBdata <- calculate.nb(d = outcome,
                              y = data[[predictors[[i]]]],
                              rH = thresholds,
                              formula = formula,
                              family = family,
                              data = data,
                              formula.ind = formula.ind[i])

    tmpNBdata$model <- predictor.names[[i]]

    if(is.numeric(confidence.intervals)){
      #calculate measures in each bootstrap
      boot.data <- apply(B.ind, 2, function(x){

      calculate.nb(d = outcome[x],
                   y = data[[predictors[[i]] ]][x],
                   rH = thresholds,
                   formula = formula,
                   family = family,
                   data = data[x,],
                   formula.ind = formula.ind[i])})

      alpha = 1- confidence.intervals
      #go through each measure and get the quantiles from the bootstrap distribution at each threshold
      for(rtn in names(boot.data[[1]][-1])){
        #collate the data from the measure estimates across bootstrap replicates
        #so I can call apply next.
        tmpdat <- sapply(boot.data, function(xx) xx[,rtn])

        tmpNBdata[[paste(rtn, "_lower", sep = "")]] <- apply(tmpdat, 1, quantile, probs = alpha/2, type = 1, na.rm = TRUE)
        tmpNBdata[[paste(rtn, "_upper", sep = "")]] <- apply(tmpdat, 1, quantile, probs = 1-alpha/2, type = 1, na.rm = TRUE)
      }
    }


    dc.data[index:(length(thresholds)*n.pred),] <-  tmpNBdata
    index = index + length(thresholds)
    n.pred = n.pred + 1
  }


  dc.data$cost.benefit.ratio <- as.character(fractions(threshold_to_costbenefit(dc.data$thresholds)))
  #find indices without a fraction and make them "xx/1"
  add.dash1 <-  which(!is.element(1:nrow(dc.data), grep("/", dc.data$cost.benefit.ratio)))
  dc.data$cost.benefit.ratio[add.dash1] <- paste(dc.data$cost.benefit.ratio[add.dash1], "/1", sep = "")
  dc.data$cost.benefit.ratio <- gsub("/", ":", dc.data$cost.benefit.ratio)



  #return list of elements
  out <- list("derived.data"  = dc.data,
              "confidence.intervals" = confidence.intervals,
              "call" = call)
  class(out) = "decision_curve"
  invisible(out)

}


