// -*- indent-tabs-mode: nil; -*-
// Simple and fast atof (ascii to float) function.
//
// - Executes about 5x faster than standard MSCRT library atof().
// - An attractive alternative if the number of calls is in the millions.
// - Assumes input is a proper integer, fraction, or scientific format.
// - Matches library atof() to 15 digits (except at extreme exponents).
// - Follows atof() precedent of essentially no error checking.
//
// 09-May-2009 Tom Van Baak (tvb) www.LeapSecond.com
//

//#define white_space(c) ((c) == ' ' || (c) == '\t')
fn white_space(c: u8) -> bool { c == ' ' || c == '\t' }

//#define valid_digit(c) ((c) >= '0' && (c) <= '9')
fn valid_digit(c: u8) -> bool { (c >= '0' && c <= '9') }

pub error BadFloatString;

pub fn zatod(p: []const u8) -> %f64 {
    var frac: i32 = 0;
    var sign: f64 = 1.0;
    var value: f64 = 0.0;
    var scale: f64 = 1.0;
    var idx: usize = 0;
    const end = p.len;

    // Skip leading white space, if any.
    while ((idx < end) && white_space(p[idx]); idx += 1 ) {}
    if ((idx == end) || (p[idx] == 0)) return value; // or possibly an error

    // Get sign, if any.
    if (p[idx] == '-') {
        sign = -1.0;
        idx += 1;
    } else if (p[idx] == '+') {
        idx += 1;
    }

    // Get digits before decimal point or exponent, if any.
    while ((idx < end) && (valid_digit(p[idx])); idx += 1) {
       value = value * 10.0 + f64(p[idx] - '0');
    }

    // Get digits after decimal point, if any.
    if (p[idx] == '.') {
        var pow10: f64 = 10.0;
        idx += 1;
        while ((idx < end) && (valid_digit(p[idx])); idx += 1) {
            value += f64(p[idx] - '0') / pow10;
            pow10 *= 10.0;
        }
    }

    if (idx < end) {
        // Handle exponent, if any.
        if ((p[idx] == 'e') || (p[idx] == 'E')) {
            var expon: u64 = 0;

            // Get sign of exponent, if any.
            idx += 1;
            if (idx < end) {
                if (p[idx] == '-') {
                    frac = 1;
                    idx += 1;

                } else if (p[idx] == '+') {
                    idx += 1;
                }

                // Get digits of exponent, if any.
                while ((idx < end) && (valid_digit(p[idx])); idx += 1) {
                    expon = expon * 10 + @typeOf(expon)(p[idx] - '0');
                }
            }
            if (expon > 308) expon = 308;

            // Calculate scaling factor.
            while (expon >= 50) { scale *= 1E50; expon -= 50; }
            while (expon >=  8) { scale *= 1E8;  expon -=  8; }
            while (expon >   0) { scale *= 10.0; expon -=  1; }
        }
    }

    // Return signed and scaled floating point result.
    return sign * if (frac == 1) (value / scale) else (value * scale);
}
