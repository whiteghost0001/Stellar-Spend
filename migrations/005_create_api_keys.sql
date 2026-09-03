-- Migration: 005_create_api_keys
-- Adds programmatic API key management, usage tracking, and per-key rate limits.
-- Idempotent: safe to run multiple times.

CREATE TABLE IF NOT EXISTS api_keys (
  id                       TEXT PRIMARY KEY,
  name                     TEXT NOT NULL,
  key_prefix               TEXT NOT NULL,
  key_hash                 TEXT NOT NULL UNIQUE,
  status                   TEXT NOT NULL,
  rate_limit_max_requests  INTEGER NOT NULL DEFAULT 60,
  rate_limit_window_ms     INTEGER NOT NULL DEFAULT 60000,
  usage_count              BIGINT NOT NULL DEFAULT 0,
  last_used_at             BIGINT,
  last_rotated_at          BIGINT,
  revoked_at               BIGINT,
  revoked_reason           TEXT,
  expires_at               BIGINT,
  rotated_from_key_id      TEXT,
  created_at               BIGINT NOT NULL,
  updated_at               BIGINT NOT NULL,
  CONSTRAINT api_keys_status_check CHECK (status IN ('active', 'rotated', 'revoked'))
);

CREATE INDEX IF NOT EXISTS idx_api_keys_status
  ON api_keys (status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_keys_key_prefix
  ON api_keys (key_prefix);

CREATE TABLE IF NOT EXISTS api_key_usage_events (
  id            TEXT PRIMARY KEY,
  api_key_id    TEXT NOT NULL,
  method        TEXT NOT NULL,
  path          TEXT NOT NULL,
  status_code   INTEGER NOT NULL,
  limited       BOOLEAN NOT NULL DEFAULT FALSE,
  ip_address    TEXT,
  used_at       BIGINT NOT NULL,
  metadata      JSONB
);

CREATE INDEX IF NOT EXISTS idx_api_key_usage_events_api_key_id
  ON api_key_usage_events (api_key_id, used_at DESC);
