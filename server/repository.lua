MZBankRepository = {}

local publicAccountPolicy = type(Config.PublicAccount) == 'table' and Config.PublicAccount or {}
local PERSONAL_ACCOUNT_TYPE = tostring(publicAccountPolicy.AccountType or '')
local SECURE_RANDOM_BYTES = tonumber(publicAccountPolicy.SecureRandomBytes) or 0
local SECURE_RANDOM_TIMEOUT_MS = tonumber(publicAccountPolicy.SecureRandomTimeoutMs) or 0
local SECURE_RANDOM_EVENT = 'mz_bank:internal:accountRandomBytes'
local secureRandomSource

local function normalizeInternalCitizenId(value)
  if type(value) ~= 'string' then return nil end
  local normalized = value:gsub('^%s+', ''):gsub('%s+$', '')
  if normalized == '' or normalized ~= value or #normalized > 32 then return nil end
  return normalized
end

function MZBankRepository.getPublicAccountByOwner(citizenid)
  citizenid = normalizeInternalCitizenId(citizenid)
  if not citizenid then return nil, 'invalid_citizenid' end
  if PERSONAL_ACCOUNT_TYPE ~= 'personal' then return nil, 'invalid_account_type' end

  return MySQL.single.await([[
    SELECT id, citizenid, branch, account_number, check_digit, account_type,
           status, created_at, updated_at, closed_at
    FROM mz_bank_accounts
    WHERE citizenid = ? AND account_type = ?
    LIMIT 1
  ]], { citizenid, PERSONAL_ACCOUNT_TYPE })
end

function MZBankRepository.getPublicAccountByRoute(branch, accountNumber, checkDigit)
  if type(branch) ~= 'string' then return nil, 'invalid_branch' end
  if PERSONAL_ACCOUNT_TYPE ~= 'personal' then return nil, 'invalid_account_type' end
  if type(MZBankAccountIdentity) ~= 'table'
    or type(MZBankAccountIdentity.ValidateRoute) ~= 'function' then
    return nil, 'account_identity_unavailable'
  end

  local valid, validationError = MZBankAccountIdentity.ValidateRoute(branch, accountNumber, checkDigit)
  if valid ~= true then return nil, validationError or 'invalid_route' end

  return MySQL.single.await([[
    SELECT id, citizenid, branch, account_number, check_digit, account_type,
           status, created_at, updated_at, closed_at
    FROM mz_bank_accounts
    WHERE branch = ? AND account_number = ? AND check_digit = ? AND account_type = ?
    LIMIT 1
  ]], { branch, accountNumber, checkDigit, PERSONAL_ACCOUNT_TYPE })
end

function MZBankRepository.listPublicAccountBackfillRows(afterPlayerId, limit)
  afterPlayerId = tonumber(afterPlayerId)
  limit = tonumber(limit)
  if not afterPlayerId or afterPlayerId < 0 or afterPlayerId ~= math.floor(afterPlayerId) then
    return nil, 'invalid_after_player_id'
  end
  if not limit or limit < 1 or limit > 501 or limit ~= math.floor(limit) then
    return nil, 'invalid_backfill_limit'
  end

  local sql = ([[
    SELECT p.id AS player_id, p.citizenid, a.status AS account_status
    FROM mz_players p
    LEFT JOIN mz_bank_accounts a
      ON a.citizenid = p.citizenid AND a.account_type = ?
    WHERE p.id > ?
    ORDER BY p.id ASC
    LIMIT %d
  ]]):format(limit)
  return MySQL.query.await(sql, { PERSONAL_ACCOUNT_TYPE, afterPlayerId }) or {}
end

local function validRandomHex(value)
  return type(value) == 'string'
    and #value == (SECURE_RANDOM_BYTES * 2)
    and value:match('^[0-9a-fA-F]+$') ~= nil
end

local function getNodeSecureRandomHex()
  if type(promise) ~= 'table' or type(promise.new) ~= 'function'
    or type(Citizen) ~= 'table' or type(Citizen.Await) ~= 'function'
    or type(SetTimeout) ~= 'function' then
    return nil
  end

  local deferred = promise.new()
  local settled = false
  local function settle(payload)
    if settled then return end
    settled = true
    deferred:resolve(payload)
  end

  TriggerEvent(SECURE_RANDOM_EVENT, SECURE_RANDOM_BYTES, function(randomHex, errorCode)
    settle({ value = randomHex, error = errorCode })
  end)
  SetTimeout(SECURE_RANDOM_TIMEOUT_MS, function()
    settle({ error = 'node_crypto_timeout' })
  end)

  local result = Citizen.Await(deferred)
  if type(result) ~= 'table' or not validRandomHex(result.value) then return nil end
  return result.value:upper()
end

-- Prefer the SQL engine's SSL-backed source. Older MariaDB deployments do not
-- provide RANDOM_BYTES(), so a server-only Node crypto provider is used as the
-- secure compatibility path. There is no RAND()/math.random fallback.
function MZBankRepository.getSecureAccountRandomHex()
  if secureRandomSource ~= 'node_crypto_random_bytes' then
    local sqlOk, sqlValue = pcall(MySQL.scalar.await, 'SELECT HEX(RANDOM_BYTES(4))')
    if sqlOk and validRandomHex(sqlValue) then
      secureRandomSource = 'sql_random_bytes'
      return sqlValue:upper(), secureRandomSource
    end
    secureRandomSource = 'node_crypto_random_bytes'
  end

  local nodeValue = getNodeSecureRandomHex()
  if not nodeValue then return nil, 'secure_random_unavailable' end
  return nodeValue, secureRandomSource
end

function MZBankRepository.insertPersonalAccount(account)
  if type(account) ~= 'table' then return false end
  return MySQL.transaction.await({
    {
      query = [[
        INSERT INTO mz_bank_accounts (
          citizenid, branch, account_number, check_digit,
          account_type, status, metadata_json
        ) VALUES (?, ?, ?, ?, ?, 'active', ?)
      ]],
      parameters = {
        account.citizenid,
        account.branch,
        account.accountNumber,
        account.checkDigit,
        PERSONAL_ACCOUNT_TYPE,
        account.metadataJson
      }
    }
  }) == true
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
