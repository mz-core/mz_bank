CREATE TABLE IF NOT EXISTS mz_bank_accounts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(32) NOT NULL,
  branch CHAR(4) NOT NULL DEFAULT '0001',
  account_number CHAR(8) NOT NULL,
  check_digit CHAR(1) NOT NULL,
  account_type VARCHAR(24) NOT NULL DEFAULT 'personal',
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  closed_at TIMESTAMP NULL,
  metadata_json LONGTEXT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mz_bank_accounts_owner_type (citizenid, account_type),
  UNIQUE KEY uq_mz_bank_accounts_route (branch, account_number),
  KEY idx_mz_bank_accounts_route_lookup (branch, account_number, check_digit, account_type),
  KEY idx_mz_bank_accounts_owner_status (citizenid, status),
  KEY idx_mz_bank_accounts_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
