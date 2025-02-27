# Group Scholar Referral Tracker

A Zig CLI for logging partner referrals into Group Scholar and generating quick summaries for outreach follow-ups.

## Features
- Initialize and seed the production Postgres schema.
- Log referrals with partner metadata and notes.
- List recent referrals and export tab-delimited output.
- Generate partner-level referral summaries with optional date filters.
- Review partner health snapshots with last referral activity.
- Flag partners with stale or missing referral activity.

## Tech
- Zig
- Postgres (psql)

## Setup
1. Install Zig and psql.
2. Export the production database connection string:

```bash
export DATABASE_URL="postgresql://USER:PASSWORD@HOST:PORT/postgres"
```

## Usage
```bash
zig build run -- init-db
zig build run -- add-referral --partner "Northside Scholars Network" --scholar "Tara Singh" --channel "Warm intro" --date "2026-02-01" --sector "Nonprofit" --region "Midwest" --notes "Referred after alumni event."
zig build run -- list-referrals --limit 10
zig build run -- summary --since "2025-11-01"
zig build run -- partner-health --since "2025-11-01" --status "active" --limit 15
zig build run -- partner-alerts --stale-days 45 --status "active" --as-of "2026-02-01" --limit 10
```

## Tests
```bash
zig build test
```

## Notes
- The CLI shells out to `psql`, so ensure it is on your PATH.
- Tables live in the `gs_referral_tracker` schema.
