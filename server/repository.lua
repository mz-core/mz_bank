MZBankRepository = {}

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

function MZBankRepository.insertLegacyReport(report)
  local id = MySQL.insert.await([[
    INSERT INTO mz_bank_legacy_reports (
      report_uid, status, actor, environment, backup_ref, authorization_ref,
      strategy, snapshot_fingerprint, preview_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    report.reportUid, report.status, report.actor, report.environment,
    report.backupRef, report.authorizationRef, report.strategy,
    report.snapshotFingerprint, report.previewJson
  })
  return id ~= nil and tonumber(id) ~= 0
end

function MZBankRepository.getLegacyReport(reportUid)
  return MySQL.single.await([[
    SELECT report_uid, status, actor, environment, backup_ref, authorization_ref,
           strategy, snapshot_fingerprint, preview_json, affected_rows,
           error_code, created_at, applied_at,
           TIMESTAMPDIFF(SECOND, created_at, CURRENT_TIMESTAMP) AS age_seconds
    FROM mz_bank_legacy_reports
    WHERE report_uid = ?
    LIMIT 1
  ]], { reportUid })
end

function MZBankRepository.finishLegacyReport(reportUid, statusValue, affectedRows, errorCode)
  local affected = MySQL.update.await([[
    UPDATE mz_bank_legacy_reports
    SET status = ?, affected_rows = ?, error_code = ?,
        applied_at = CASE WHEN ? = 'applied' THEN CURRENT_TIMESTAMP ELSE applied_at END
    WHERE report_uid = ? AND status IN ('preview_ready', 'applying')
  ]], { statusValue, affectedRows, errorCode, statusValue, reportUid })
  return tonumber(affected) == 1
end

function MZBankRepository.claimLegacyReport(reportUid)
  local affected = MySQL.update.await([[
    UPDATE mz_bank_legacy_reports
    SET status = 'applying'
    WHERE report_uid = ? AND status = 'preview_ready'
  ]], { reportUid })
  return tonumber(affected) == 1
end
