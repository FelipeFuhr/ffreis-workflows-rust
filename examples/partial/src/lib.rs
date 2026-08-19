//! Fixture crate for `self-test.yml`'s mutation-harness check.
//!
//! Half of this crate is tested and half is deliberately NOT, so a working
//! mutation harness must report a score strictly between 0 and 100.
//!
//! WHY THIS EXISTS
//! ---------------
//! `rust-mutation.yml` spent months reporting a clean 100% on every consumer
//! repo without ever measuring anything: `cargo mutants --output mutants.out`
//! nests results at `mutants.out/mutants.out/`, the scorer read
//! `mutants.out/`, every count came back 0, and the "no viable mutants ->
//! pass" branch turned that into a green check. `examples/hello` could not
//! catch it — a fully-tested crate scores 100 whether the harness works or
//! not, so the passing result looked identical either way.
//!
//! This crate makes the two cases distinguishable. Do NOT add tests for
//! `shrink_to_fit_len` or the fixture stops discriminating: see the
//! `assert-mutation-not-vacuous` job in `.github/workflows/self-test.yml`.

/// Clamps `value` into `[min, max]`.
///
/// Fully covered by the tests below, so mutants here are expected to be caught.
pub fn clamp_between(value: i64, min: i64, max: i64) -> i64 {
    if value < min {
        return min;
    }
    if value > max {
        return max;
    }
    value
}

/// Returns how many items survive a cap.
///
/// DELIBERATELY UNTESTED — this is the half that produces surviving mutants.
/// Adding tests here defeats the fixture's only purpose.
pub fn shrink_to_fit_len(len: usize, cap: usize) -> usize {
    if len > cap {
        cap
    } else {
        len
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamp_returns_value_when_inside_range() {
        assert_eq!(clamp_between(5, 0, 10), 5);
    }

    #[test]
    fn clamp_raises_value_below_min() {
        assert_eq!(clamp_between(-4, 0, 10), 0);
    }

    #[test]
    fn clamp_lowers_value_above_max() {
        assert_eq!(clamp_between(99, 0, 10), 10);
    }

    #[test]
    fn clamp_keeps_the_boundaries_themselves() {
        assert_eq!(clamp_between(0, 0, 10), 0);
        assert_eq!(clamp_between(10, 0, 10), 10);
    }
}
