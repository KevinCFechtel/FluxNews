//! Core timestamp parsing and durable UTC encodings.
//!
//! Publication keys use whole seconds with `Z`. Operational timestamps retain
//! `+00:00` and 0/3/6/9 fractional digits, so changing the date library does not
//! change persisted values, native DTOs, or retention's existing text cutoffs.

use time::{OffsetDateTime, UtcOffset, format_description::well_known::Rfc3339};

pub(crate) fn parse_rfc3339(value: &str) -> Result<OffsetDateTime, time::error::Parse> {
    OffsetDateTime::parse(value, &Rfc3339)
}

fn utc_seconds(value: OffsetDateTime) -> String {
    let value = value.to_offset(UtcOffset::UTC);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
        value.year(),
        value.month() as u8,
        value.day(),
        value.hour(),
        value.minute(),
        value.second(),
    )
}

pub(crate) fn publication_time(value: &str) -> Result<String, time::error::Parse> {
    let mut text = utc_seconds(parse_rfc3339(value)?);
    // `time` represents a leap second by the preceding nanosecond. Keep the
    // publisher's leap-second spelling in the existing second-precision key.
    if value.as_bytes().get(17..19) == Some(b"60") {
        text.replace_range(17..19, "60");
    }
    text.push('Z');
    Ok(text)
}

pub(crate) fn format_utc(value: OffsetDateTime) -> String {
    let mut text = utc_seconds(value);
    let nanos = value.nanosecond();
    if nanos != 0 {
        let (fraction, width) = if nanos.is_multiple_of(1_000_000) {
            (nanos / 1_000_000, 3)
        } else if nanos.is_multiple_of(1_000) {
            (nanos / 1_000, 6)
        } else {
            (nanos, 9)
        };
        text.push_str(&format!(".{fraction:0width$}"));
    }
    text.push_str("+00:00");
    text
}

pub(crate) fn now_rfc3339() -> String {
    format_utc(OffsetDateTime::now_utc())
}

#[cfg(test)]
mod tests {
    use super::*;
    use time::Duration;

    #[test]
    fn publication_keys_keep_utc_seconds_across_offsets_and_fractions() {
        for (input, expected) in [
            (
                "2026-11-28T01:30:45.123456789+02:00",
                "2026-11-27T23:30:45Z",
            ),
            ("2026-11-28T23:30:45-02:00", "2026-11-29T01:30:45Z"),
            ("2026-11-28t12:30:45z", "2026-11-28T12:30:45Z"),
            ("2016-12-31T23:59:60Z", "2016-12-31T23:59:60Z"),
            ("2017-01-01T00:59:60+01:00", "2016-12-31T23:59:60Z"),
        ] {
            assert_eq!(publication_time(input).unwrap(), expected);
        }
    }

    #[test]
    fn operational_timestamps_preserve_precision_and_numeric_utc_offset() {
        for (input, expected) in [
            ("2026-11-28T12:30:45Z", "2026-11-28T12:30:45+00:00"),
            ("2026-11-28T12:30:45.12Z", "2026-11-28T12:30:45.120+00:00"),
            (
                "2026-11-28T12:30:45.1234Z",
                "2026-11-28T12:30:45.123400+00:00",
            ),
            (
                "2026-11-28T12:30:45.1234567Z",
                "2026-11-28T12:30:45.123456700+00:00",
            ),
            (
                "2026-11-28T12:30:45.001+01:00",
                "2026-11-28T11:30:45.001+00:00",
            ),
        ] {
            assert_eq!(format_utc(parse_rfc3339(input).unwrap()), expected);
        }
    }

    #[test]
    fn epoch_and_retention_use_instants_and_fixed_day_durations() {
        assert_eq!(
            parse_rfc3339("1970-01-01T00:00:00Z")
                .unwrap()
                .unix_timestamp(),
            0
        );
        assert_eq!(
            parse_rfc3339("1969-12-31T23:59:59.5Z")
                .unwrap()
                .unix_timestamp(),
            -1
        );
        let now = parse_rfc3339("2026-11-01T01:00:00-05:00").unwrap();
        let cutoff = now - Duration::days(30);
        assert_eq!(format_utc(cutoff), "2026-10-02T06:00:00+00:00");
        assert!(parse_rfc3339("2026-10-02T08:00:00+02:00").unwrap() <= cutoff);
        assert!(parse_rfc3339("2026-10-02T06:00:00.001Z").unwrap() > cutoff);
    }

    #[test]
    fn invalid_remote_timestamps_remain_errors() {
        for input in [
            "",
            "not a date",
            "2026-02-30T12:00:00Z",
            "2026-11-28T12:00:00",
        ] {
            assert!(parse_rfc3339(input).is_err(), "{input}");
            assert!(publication_time(input).is_err(), "{input}");
        }
    }
}
