-- Migration: 010_create_transaction_disputes
-- Creates the transaction_disputes table for handling failed transaction disputes.

CREATE TABLE IF NOT EXISTS transaction_disputes (
  id                    TEXT PRIMARY KEY,
  transaction_id        TEXT NOT NULL,
  user_address          TEXT NOT NULL,
  reason                TEXT NOT NULL,
  description           TEXT,
  status                TEXT NOT NULL DEFAULT 'open',
  created_at            BIGINT NOT NULL,
  updated_at            BIGINT NOT NULL,
  resolved_at           BIGINT,
  resolution_notes      TEXT,
  CONSTRAINT disputes_status_check CHECK (status IN ('open', 'in_review', 'resolved', 'rejected')),
  FOREIGN KEY (transaction_id) REFERENCES transactions(id)
);

CREATE INDEX IF NOT EXISTS idx_disputes_transaction_id
  ON transaction_disputes (transaction_id);

CREATE INDEX IF NOT EXISTS idx_disputes_user_address
  ON transaction_disputes (user_address);

CREATE INDEX IF NOT EXISTS idx_disputes_status
  ON transaction_disputes (status);
