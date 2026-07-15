CREATE TABLE IF NOT EXISTS mz_bank_cards (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  card_uid VARCHAR(64) NOT NULL,
  citizenid VARCHAR(64) NOT NULL,
  last4 CHAR(4) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  pin_hash VARCHAR(255) NULL,
  issued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  blocked_at TIMESTAMP NULL,
  metadata_json LONGTEXT NULL,
  UNIQUE KEY uq_mz_bank_cards_uid (card_uid),
  KEY idx_mz_bank_cards_owner_status (citizenid, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
