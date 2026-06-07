-- v1.0.227 — granular pipeline progress for Smart Purchase jobs.
--
-- Adds a `progress_stage` column to smart_purchase_jobs so the worker can
-- record which extraction / matching stage the job is currently in. The
-- Flutter poll loop reads this and surfaces a user-friendly hint
-- ("Reading Bill via Textract…", "Reading Gate-pass via Claude…",
-- "Matching brands…", "Building Purcha confirmation…") instead of a
-- generic "Processing…".
--
-- Idempotent: re-running the migration is a no-op.
-- Pre-existing rows (NULL) render as the legacy "Processing…" hint.

ALTER TABLE smart_purchase_jobs
  ADD COLUMN IF NOT EXISTS progress_stage VARCHAR(32);

-- No backfill — terminal-state rows (done / failed / canceled) already
-- have status set; only in-flight rows benefit from the column, and the
-- worker writes it on every checkpoint going forward.
