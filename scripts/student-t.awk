# Student-t quantiles using the regularized incomplete beta representation of
# the CDF. This keeps benchmark analysis self-contained on the pinned build
# host instead of depending on a statistics package.
function aco_log_gamma(value,    shifted, series) {
    # Lanczos approximation for positive arguments. Student-t analysis only
    # calls this with half-integers greater than or equal to one half.
    shifted = value - 1
    series = 0.99999999999980993 \
        + 676.5203681218851 / (shifted + 1) \
        - 1259.1392167224028 / (shifted + 2) \
        + 771.32342877765313 / (shifted + 3) \
        - 176.61502916214059 / (shifted + 4) \
        + 12.507343278686905 / (shifted + 5) \
        - 0.13857109526572012 / (shifted + 6) \
        + 0.000009984369578019572 / (shifted + 7) \
        + 0.00000015056327351493116 / (shifted + 8)
    return 0.9189385332046727 + (shifted + 0.5) * log(shifted + 7.5) \
        - (shifted + 7.5) + log(series)
}

function aco_beta_continued_fraction(a, b, x,    qab, qap, qam, c, d, h, m, m2, aa, delta) {
    qab = a + b
    qap = a + 1
    qam = a - 1
    c = 1
    d = 1 - qab * x / qap
    if (d < 1e-30 && d > -1e-30)
        d = 1e-30
    d = 1 / d
    h = d
    for (m = 1; m <= 200; m++) {
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1 + aa * d
        if (d < 1e-30 && d > -1e-30)
            d = 1e-30
        c = 1 + aa / c
        if (c < 1e-30 && c > -1e-30)
            c = 1e-30
        d = 1 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1 + aa * d
        if (d < 1e-30 && d > -1e-30)
            d = 1e-30
        c = 1 + aa / c
        if (c < 1e-30 && c > -1e-30)
            c = 1e-30
        d = 1 / d
        delta = d * c
        h *= delta
        if (delta > 0.999999999999 && delta < 1.000000000001)
            return h
    }
    return h
}

function aco_regularized_beta(x, a, b,    factor) {
    if (x <= 0)
        return 0
    if (x >= 1)
        return 1
    factor = exp(aco_log_gamma(a + b) - aco_log_gamma(a) - aco_log_gamma(b) \
        + a * log(x) + b * log(1 - x))
    if (x < (a + 1) / (a + b + 2))
        return factor * aco_beta_continued_fraction(a, b, x) / a
    return 1 - factor * aco_beta_continued_fraction(b, a, 1 - x) / b
}

function aco_student_t_cdf(value, degrees,    beta) {
    beta = aco_regularized_beta(degrees / (degrees + value * value), degrees / 2, 0.5)
    return value >= 0 ? 1 - beta / 2 : beta / 2
}

function aco_student_t_critical(probability, degrees,    low, high, middle, iteration) {
    if (probability <= 0.5 || probability >= 1 || degrees < 1)
        return 0
    low = 0
    high = 1
    while (aco_student_t_cdf(high, degrees) < probability)
        high *= 2
    for (iteration = 0; iteration < 100; iteration++) {
        middle = (low + high) / 2
        if (aco_student_t_cdf(middle, degrees) < probability)
            low = middle
        else
            high = middle
    }
    return (low + high) / 2
}
