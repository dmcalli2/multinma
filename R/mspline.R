#' Distribution functions for M-spline baseline hazards
#'
#' Density, distribution, quantile, hazard, cumulative hazard, and restricted
#' mean survival time functions for the M-spline baseline hazards model.
#'
#' @param x,q Vector of quantiles
#' @param basis M-spline basis produced by [splines2::mSpline()]
#' @param scoef Vector (or matrix) of spline coefficients with length (or number
#'   of columns) equal to the dimension of `basis`
#' @param rate Vector of rate parameters
#' @param log,log.p Logical; if `TRUE`, probabilities `p` are given as
#'   \eqn{\log(p)}
#' @param lower.tail Logical; if `TRUE` (the default), probabilities are
#'   \eqn{P(X \le x)}, otherwise \eqn{P(X > x)}
#' @param p Vector of probabilities
#' @param t Vector of times to which the restricted mean survival time is
#'   calculated
#' @param start Optional left-truncation time or times. The returned restricted
#'   mean survival will be conditioned on survival up to this time
#'
#' @details Survival models with a flexible M-spline on the baseline hazard are
#'   described by \insertCite{Brilleman2020;textual}{multinma}.
#'   Piecewise-exponential baseline hazards are a special case where the degree
#'   of the M-spline polynomial is 0.
#'
#'   The d/p/h/H functions are calculated from their definitions. `qmspline()`
#'   uses numerical inversion via [flexsurv::qgeneric()]. `rmst_mspline()`uses
#'   numerical integration via [flexsurv::rmst_generic()], except for the
#'   special case of the piecewise-exponential hazard (i.e. degree 0 M-splines)
#'   which uses the explicit formula from
#'   \insertCite{Royston2013;textual}{multinma}.
#'
#'   Beyond the boundary knots, the hazard is assumed to be constant. (This
#'   differs from the approach in [splines2::mSpline()] that extrapolates the
#'   polynomial basis functions, which is numerically unstable and highly
#'   dependent on the data just before the boundary knots.) As with all
#'   extrapolation, care should be taken when evaluating the splines at times
#'   beyond the boundary knots (either directly through the d/p/h/H/rmst
#'   functions, or indirectly by requesting quantiles with `qmspline()` that
#'   correspond to times beyond the boundary knots). For this reason evaluating
#'   the (unrestricted) mean survival time is not generally recommended as this
#'   requires integrating over an infinite time horizon (i.e. `rmst_mspline()`
#'   with `t = Inf`).
#'
#' @return `dmspline()` gives the density, `pmspline()` gives the distribution
#'   function (CDF), `qmspline()` gives the quantile function (inverse-CDF),
#'   `hmspline()` gives the hazard function, `Hmspline()` gives the cumulative
#'   hazard function, and `rmst_mspline()` gives restricted mean survival times.
#'
#' @rdname mspline
#' @export
#'
#' @references
#'   \insertAllCited{}
#'
dmspline <- function(x, basis, scoef, rate, log = FALSE) {
  if (!is_mspline(basis)) abort("`basis` must be an M-spline basis produced by splines2::mSpline()")
  if (!rlang::is_bool(log)) abort("`log` must be a logical value (TRUE or FALSE).")

  if (missing(x)) out <- hmspline(basis = basis, scoef = scoef, rate = rate) * pmspline(basis = basis, scoef = scoef, rate = rate, lower.tail = FALSE)
  else out <- hmspline(x, basis = basis, scoef = scoef, rate = rate) * pmspline(q = x, basis = basis, scoef = scoef, rate = rate, lower.tail = FALSE)

  if (log) out <- log(out)

  return(out)
}

#' @rdname mspline
#' @export
pmspline <- function(q, basis, scoef, rate, lower.tail = TRUE, log.p = FALSE) {
  if (!is_mspline(basis)) abort("`basis` must be an M-spline basis produced by splines2::mSpline()")
  if (!rlang::is_bool(lower.tail)) abort("`lower.tail` must be a logical value (TRUE or FALSE).")
  if (!rlang::is_bool(log.p)) abort("`log.p` must be a logical value (TRUE or FALSE).")

  if (missing(q)) out <- exp(-Hmspline(basis = basis, scoef = scoef, rate = rate))
  else  out <- exp(-Hmspline(x = q, basis = basis, scoef = scoef, rate = rate))

  if (lower.tail) out <- 1 - out
  if (log.p) out <- log(out)

  return(out)
}

#' @rdname mspline
#' @export
qmspline <- function(p, basis, scoef, rate, lower.tail = TRUE, log.p = FALSE) {
  if (!is.numeric(p)) abort("`p` must be a numeric vector of quantiles.")
  require_pkg("flexsurv")

  flexsurv::qgeneric(pmspline, p = p,
                     scalarargs = "basis", matargs = "scoef",
                     basis = basis, scoef = scoef, rate = rate,
                     lower.tail = lower.tail, log.p = log.p,
                     lbound = 0)
}

#' @rdname mspline
#' @export
hmspline <- function(x, basis, scoef, rate, log = FALSE) {
  require_pkg("splines2")
  if (!is_mspline(basis)) abort("`basis` must be an M-spline basis produced by splines2::mSpline()")
  if (!rlang::is_bool(log)) abort("`log` must be a logical value (TRUE or FALSE).")

  # Extrapolate with constant hazard beyond boundary knots
  if (!missing(x)) {
    x <- pmax(x, attr(basis, "Boundary.knots")[1])
    x <- pmin(x, attr(basis, "Boundary.knots")[2])
  }

  xb <- if (missing(x)) update(basis, integral = FALSE)
  else update(basis, x = x, integral = FALSE)

  if (!is.matrix(scoef)) scoef <- matrix(scoef, nrow = 1)

  if (is.matrix(scoef) && nrow(scoef) == nrow(xb)) {
    out <- rowSums(xb * scoef) * rate
  } else if (nrow(xb) == 1) {
    out <- scoef %*% xb[1,] * rate
  } else if (is.matrix(scoef) && nrow(scoef) == 1) {
    out <- xb %*% scoef[1,] * rate
  } else {
    out <- xb %*% scoef * rate
  }

  # Return 0 for x < 0
  lt0 <- x < 0
  out[lt0] <- 0

  if (log) out <- log(out)

  return(drop(out))
}

#' @rdname mspline
#' @export
Hmspline <- function(x, basis, scoef, rate, log = FALSE) {
  require_pkg("splines2")
  if (!is_mspline(basis)) abort("`basis` must be an M-spline basis produced by splines2::mSpline()")
  if (!rlang::is_bool(log)) abort("`log` must be a logical value (TRUE or FALSE).")

  # Extrapolate with constant hazard beyond boundary knots
  if (!missing(x)) {
    lower <- attr(basis, "Boundary.knots")[1]
    upper <- attr(basis, "Boundary.knots")[2]

    ex_lo <- x < lower & x > 0
    ex_up <- x > upper

    ex_time_lo <- x[ex_lo]
    ex_time_up <- x[ex_up] - upper

    xorig <- x
    x <- pmax(x, lower)
    x <- pmin(x, upper)
  } else {
    ex_lo <- ex_up <- FALSE
  }

  xb <- if (missing(x)) update(basis, integral = TRUE)
        else update(basis, x = x, integral = TRUE)

  if (!is.matrix(scoef)) scoef <- matrix(scoef, nrow = 1)

  if (is.matrix(scoef) && nrow(scoef) == nrow(xb)) {
    out <- rowSums(xb * scoef) * rate
  } else if (nrow(xb) == 1) {
    out <- scoef %*% xb[1,] * rate
  } else if (is.matrix(scoef) && nrow(scoef) == 1) {
    out <- xb %*% scoef[1,] * rate
  } else {
    out <- xb %*% scoef * rate
  }

  if (any(ex_up)) {
    ex_up_rate <- if (length(rate) == 1) rate else rate[ex_up]
    ex_up_scoef <- if (nrow(scoef) == 1) scoef else scoef[ex_up, , drop = FALSE]
    h_up <- hmspline(xorig[ex_up], basis = basis, scoef = ex_up_scoef, rate = ex_up_rate)
    out[ex_up] <- out[ex_up] + h_up * ex_time_up
  }

  if (any(ex_lo)) {
    ex_lo_rate <- if (length(rate) == 1) rate else rate[ex_lo]
    ex_lo_scoef <- if (nrow(scoef) == 1) scoef else scoef[ex_lo, , drop = FALSE]
    h_lo <- hmspline(xorig[ex_lo], basis = basis, scoef = ex_lo_scoef, rate = ex_lo_rate)
    out[ex_lo] <- h_lo * ex_time_lo
  }

  # Return 0 for x < 0
  lt0 <- x < 0
  out[lt0] <- 0

  if (log) out <- log(out)

  return(drop(out))
}

#' @rdname mspline
#' @export
rmst_mspline <- function(t, basis, scoef, rate, start = 0) {
  if (attr(basis, "degree") == 0) {
    # Piecewise exponential has explicit formula (Royston and Parmar 2013)
    nr <- max(length(t), if (is.matrix(scoef)) nrow(scoef) else 1, length(rate))

    knots <- c(attr(basis, "Boundary.knots")[1], attr(basis, "knots"))
    knots <- matrix(knots, nrow = nr, ncol = length(knots), byrow = TRUE)

    h <- apply(knots, 2, hmspline, basis = basis, scoef = scoef, rate = rate)

    delta <- t(apply(pmax(pmin(cbind(knots, Inf), t) - start, 0), 1, diff))

    hd <- h * delta

    H <- t(apply(cbind(0, hd[, -ncol(knots), drop = FALSE]), 1, cumsum))

    rowSums(exp(-H) / h * (1 - exp(-hd)))

  } else {
    # General M-splines require numerical integration
    require_pkg("flexsurv")
    flexsurv::rmst_generic(pmspline, t, start = start,
                           basis = basis, scoef = scoef, rate = rate,
                           scalarargs = "basis", matargs = "scoef")
  }
}

# Don't export mean_mspline - this is a bad idea in general
#' @noRd
mean_mspline <- function(basis, scoef, rate, ...) {
  rmst_mspline(t = Inf, basis, scoef, rate)
}

# Function to check for mspline/ispline objects
is_mspline <- function(x) {
  inherits(x, "MSpline")
}
