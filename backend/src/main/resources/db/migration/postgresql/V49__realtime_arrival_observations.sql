CREATE TABLE realtime_arrival_observations (
  id BIGSERIAL PRIMARY KEY,
  provider_id VARCHAR(80) NOT NULL,
  station_id VARCHAR(120) NOT NULL,
  line_id VARCHAR(80) NOT NULL,
  provider_line_id VARCHAR(80) NOT NULL,
  provider_station_id VARCHAR(80) NOT NULL,
  train_no VARCHAR(80) NOT NULL,
  provider_observed_at TIMESTAMPTZ NOT NULL,
  backend_received_at TIMESTAMPTZ NOT NULL,
  raw_eta_seconds INTEGER,
  adjusted_eta_seconds INTEGER,
  raw_direction VARCHAR(120),
  raw_destination VARCHAR(120),
  retained_until TIMESTAMPTZ NOT NULL,
  CONSTRAINT chk_realtime_arrival_retention
    CHECK (retained_until > backend_received_at)
);

CREATE INDEX idx_realtime_arrival_provider_train_time
  ON realtime_arrival_observations (provider_id, train_no, provider_observed_at);

CREATE INDEX idx_realtime_arrival_retained_until
  ON realtime_arrival_observations (retained_until);
