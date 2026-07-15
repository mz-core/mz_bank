MZBankRepository = {}

function MZBankRepository.prepare()
  MySQL.query.await([[
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  ]])
  return true
end

function MZBankRepository.getCard(cardUid)
  return MySQL.single.await([[
    SELECT id, card_uid, citizenid, last4, status, issued_at, updated_at, blocked_at
    FROM mz_bank_cards WHERE card_uid = ? LIMIT 1
  ]], { cardUid })
end

function MZBankRepository.listCards(citizenid)
  return MySQL.query.await([[
    SELECT card_uid, last4, status, issued_at, updated_at, blocked_at
    FROM mz_bank_cards
    WHERE citizenid = ?
    ORDER BY issued_at DESC, id DESC
  ]], { citizenid }) or {}
end

function MZBankRepository.countActiveCards(citizenid)
  return tonumber(MySQL.scalar.await([[
    SELECT COUNT(*) FROM mz_bank_cards WHERE citizenid = ? AND status = 'active'
  ]], { citizenid })) or 0
end

function MZBankRepository.insertCard(cardUid, citizenid, last4, metadata)
  local metadataJson = json.encode(type(metadata) == 'table' and metadata or {})
  local id = MySQL.insert.await([[
    INSERT INTO mz_bank_cards (card_uid, citizenid, last4, status, metadata_json)
    VALUES (?, ?, ?, 'active', ?)
  ]], { cardUid, citizenid, last4, metadataJson })
  return id ~= nil and tonumber(id) ~= 0
end

function MZBankRepository.revokeActiveCards(citizenid)
  MySQL.update.await([[
    UPDATE mz_bank_cards
    SET status = 'revoked', blocked_at = CURRENT_TIMESTAMP
    WHERE citizenid = ? AND status = 'active'
  ]], { citizenid })
  return true
end

function MZBankRepository.revokeActiveCardsExcept(citizenid, cardUid)
  MySQL.update.await([[
    UPDATE mz_bank_cards
    SET status = 'revoked', blocked_at = CURRENT_TIMESTAMP
    WHERE citizenid = ? AND status = 'active' AND card_uid <> ?
  ]], { citizenid, cardUid })
  return true
end

function MZBankRepository.blockCard(citizenid, cardUid)
  local affected = MySQL.update.await([[
    UPDATE mz_bank_cards
    SET status = 'blocked', blocked_at = CURRENT_TIMESTAMP
    WHERE citizenid = ? AND card_uid = ? AND status = 'active'
  ]], { citizenid, cardUid })
  return tonumber(affected) == 1
end

function MZBankRepository.revokeCard(cardUid)
  MySQL.update.await([[
    UPDATE mz_bank_cards
    SET status = 'revoked', blocked_at = CURRENT_TIMESTAMP
    WHERE card_uid = ? AND status = 'active'
  ]], { cardUid })
end
