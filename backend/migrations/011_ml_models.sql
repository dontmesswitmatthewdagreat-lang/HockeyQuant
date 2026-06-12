-- 011_ml_models.sql
-- Lets a trained machine-learned model live in user_models and compete on the
-- models leaderboard alongside hand-tuned weighted models.

ALTER TABLE user_models
    ADD COLUMN IF NOT EXISTS model_type text NOT NULL DEFAULT 'weighted',
    ADD COLUMN IF NOT EXISTS ml_meta jsonb;

-- Existing rows are weighted models; the default covers them.
COMMENT ON COLUMN user_models.model_type IS 'weighted | ml';
COMMENT ON COLUMN user_models.ml_meta IS 'For ml models: {features, kind, mu, sd, w, b | stumps}';
