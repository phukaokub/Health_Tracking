# Huawei normalization contract (v1)

This Step 4 vertical slice accepts a sanitized Huawei JSON object containing a
`records` array. The streaming parser recognizes only `heart_rate`, `steps`,
`distance`, and `active_duration` scalar records. Every accepted record requires
a synthetic/source record identifier, RFC 3339 timestamp, approved unit, and a
numeric scalar value.

The parser emits canonical samples with only a SHA-256 source-record hash and a
versioned deterministic dedupe key. The key is derived from source family/type,
source-record hash, UTC time range, unit, and canonical value. Replays and
overlapping batches therefore address the same `(user_id, dedupe_key)` row.

Owner-visible import responses may include `normalization` with a normalized
record count and stable warning codes. They never expose raw JSON, source paths,
identifiers, values, ECG/RRI samples, GPS coordinates, credentials, or emails.

ECG, route, and unknown record types are discarded and represented, at most, by
safe warning codes. Malformed input returns a stable safe code such as
`json_truncated`, `source_schema_unsupported`, `timestamp_invalid`, or
`json_token_too_large`; no payload excerpt is included.
