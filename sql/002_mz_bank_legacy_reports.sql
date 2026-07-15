CREATE TABLE IF NOT EXISTS mz_bank_legacy_reports (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  report_uid VARCHAR(64) NOT NULL,
  status VARCHAR(32) NOT NULL,
  actor VARCHAR(64) NOT NULL,
  environment VARCHAR(16) NOT NULL,
  backup_ref VARCHAR(128) NOT NULL,
  authorization_ref VARCHAR(128) NOT NULL,
  strategy VARCHAR(64) NOT NULL,
  snapshot_fingerprint VARCHAR(128) NOT NULL,
  preview_json LONGTEXT NOT NULL,
  affected_rows INT UNSIGNED NULL,
  error_code VARCHAR(64) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  applied_at TIMESTAMP NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mz_bank_legacy_reports_uid (report_uid),
  KEY idx_mz_bank_legacy_reports_status_created (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
