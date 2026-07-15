MZBankLegacy = {}
local MAX_SAFE_INTEGER = 9007199254740991

local function tableExists(name)
  return tonumber(MySQL.scalar.await([[
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = ?
  ]], { name })) == 1
end

local function hasColumns(tableName, required)
  local rows = MySQL.query.await([[
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = ?
  ]], { tableName }) or {}
  local found = {}
  for _, row in ipairs(rows) do found[tostring(row.column_name)] = true end
  for _, columnName in ipairs(required) do
    if not found[columnName] then return false, columnName end
  end
  return true
end

local function normalizeReference(value)
  value = tostring(value or '')
  if #value < 6 or #value > 128 or not value:match('^[%w%._:%-]+$') then return nil end
  return value
end

local function hasRequiredAce(source)
  local ace = tostring(Config.LegacyMigration.Ace or '')
  if ace == '' then
    print('[mz_bank][legacy] denied: legacy ACE is not configured')
    return false
  end
  local ok, allowed = pcall(IsPlayerAceAllowed, source, ace)
  local normalized = tostring(allowed):lower()
  if ok and (allowed == true or allowed == 1 or normalized == '1' or normalized == 'true') then return true end
  print(('[mz_bank][legacy] denied source=%s missing_ace=%s'):format(
    tostring(source), tostring(Config.LegacyMigration.Ace)
  ))
  return false
end

local function actorFor(source)
  if tonumber(source) == 0 then return 'console' end
  return ('source:%s'):format(tostring(source))
end

local function fingerprintRows(rows)
  local hash = 17
  local length = 0
  for _, row in ipairs(rows) do
    local canonical = table.concat({
      tostring(row.identifier or ''), tostring(row.balance or ''),
      tostring(row.citizen_match or ''), tostring(row.license_match or ''),
      tostring(row.resolved_citizenid or ''), tostring(row.official_bank or '')
    }, '|') .. '\n'
    length = length + #canonical
    for index = 1, #canonical do
      hash = (hash * 131 + canonical:byte(index)) % 2147483647
    end
  end
  return ('v1:%s:%s:%s'):format(#rows, length, hash)
end

local function makeReportUid()
  return ('legacy-%s-%s-%06d'):format(os.time(), GetGameTimer(), math.random(0, 999999))
end

local function emptyPreview()
  return {
    bank_accounts = { exists = false, rows = 0 },
    bank_transactions = { exists = false, rows = 0 },
    matched = 0,
    unmatched = 0,
    divergent = 0,
    conflicts = 0,
    duplicate_identifiers = 0,
    duplicate_identifier_rows = 0,
    multiple_rows_same_account = 0,
    ambiguous_identifiers = 0,
    negative_balances = 0,
    invalid_balances = 0,
    candidates = 0,
    blockers = {},
    safeToApply = false,
    snapshotFingerprint = 'v1:0:0:0',
    _candidates = {}
  }
end

local function addBlocker(result, code)
  result.blockers[#result.blockers + 1] = code
end

local function collectPreview()
  local result = emptyPreview()
  result.bank_accounts.exists = tableExists('bank_accounts')
  result.bank_transactions.exists = tableExists('bank_transactions')
  if result.bank_transactions.exists then
    result.bank_transactions.rows = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bank_transactions')) or 0
  end

  if not result.bank_accounts.exists then
    addBlocker(result, 'legacy_accounts_missing')
    return result
  end

  local validSchema, missingColumn = hasColumns('bank_accounts', { 'identifier', 'balance' })
  if not validSchema then
    addBlocker(result, ('legacy_schema_missing_column:%s'):format(tostring(missingColumn)))
    return result
  end

  local rows = MySQL.query.await([[
    SELECT ba.identifier, ba.balance,
           pc.citizenid AS citizen_match,
           pl.citizenid AS license_match,
           CASE
             WHEN pc.citizenid IS NOT NULL AND pl.citizenid IS NOT NULL
                  AND pc.citizenid <> pl.citizenid THEN NULL
             ELSE COALESCE(pc.citizenid, pl.citizenid)
           END AS resolved_citizenid,
           a.bank AS official_bank
    FROM bank_accounts ba
    LEFT JOIN mz_players pc ON pc.citizenid = ba.identifier
    LEFT JOIN mz_players pl ON pl.license = ba.identifier
    LEFT JOIN mz_player_accounts a ON a.citizenid = CASE
      WHEN pc.citizenid IS NOT NULL AND pl.citizenid IS NOT NULL
           AND pc.citizenid <> pl.citizenid THEN NULL
      ELSE COALESCE(pc.citizenid, pl.citizenid)
    END
    ORDER BY CAST(ba.identifier AS CHAR), CAST(ba.balance AS CHAR)
  ]]) or {}

  result.bank_accounts.rows = #rows
  result.snapshotFingerprint = fingerprintRows(rows)
  local identifierCounts = {}
  local accountCounts = {}

  for _, row in ipairs(rows) do
    local identifier = tostring(row.identifier or '')
    identifierCounts[identifier] = (identifierCounts[identifier] or 0) + 1
    local citizenMatch = row.citizen_match and tostring(row.citizen_match) or nil
    local licenseMatch = row.license_match and tostring(row.license_match) or nil
    local resolved = row.resolved_citizenid and tostring(row.resolved_citizenid) or nil
    if citizenMatch and licenseMatch and citizenMatch ~= licenseMatch then
      result.ambiguous_identifiers = result.ambiguous_identifiers + 1
    elseif resolved then
      accountCounts[resolved] = (accountCounts[resolved] or 0) + 1
    end
  end

  for _, count in pairs(identifierCounts) do
    if count > 1 then
      result.duplicate_identifiers = result.duplicate_identifiers + 1
      result.duplicate_identifier_rows = result.duplicate_identifier_rows + count
    end
  end
  for _, count in pairs(accountCounts) do
    if count > 1 then result.multiple_rows_same_account = result.multiple_rows_same_account + 1 end
  end

  for _, row in ipairs(rows) do
    local citizenMatch = row.citizen_match and tostring(row.citizen_match) or nil
    local licenseMatch = row.license_match and tostring(row.license_match) or nil
    local ambiguous = citizenMatch and licenseMatch and citizenMatch ~= licenseMatch
    local resolved = not ambiguous and row.resolved_citizenid and tostring(row.resolved_citizenid) or nil
    local legacyBalance = tonumber(row.balance)
    local officialBalance = tonumber(row.official_bank)
    local validBalance = legacyBalance ~= nil and legacyBalance == legacyBalance
      and legacyBalance ~= math.huge and legacyBalance ~= -math.huge
      and legacyBalance % 1 == 0 and math.abs(legacyBalance) <= MAX_SAFE_INTEGER

    if not validBalance then
      result.invalid_balances = result.invalid_balances + 1
    elseif legacyBalance < 0 then
      result.negative_balances = result.negative_balances + 1
    end

    if not resolved or officialBalance == nil then
      result.unmatched = result.unmatched + 1
    else
      result.matched = result.matched + 1
      if validBalance and legacyBalance ~= officialBalance then
        result.divergent = result.divergent + 1
        if officialBalance ~= 0 then
          result.conflicts = result.conflicts + 1
        elseif legacyBalance >= 0 then
          result._candidates[#result._candidates + 1] = {
            citizenid = resolved,
            balance = legacyBalance
          }
        end
      end
    end
  end

  result.candidates = #result._candidates
  if result.bank_accounts.rows == 0 then addBlocker(result, 'legacy_accounts_empty') end
  if result.duplicate_identifiers > 0 then addBlocker(result, 'duplicate_identifiers') end
  if result.multiple_rows_same_account > 0 then addBlocker(result, 'multiple_rows_same_account') end
  if result.ambiguous_identifiers > 0 then addBlocker(result, 'ambiguous_identifiers') end
  if result.negative_balances > 0 then addBlocker(result, 'negative_balances') end
  if result.invalid_balances > 0 then addBlocker(result, 'invalid_balances') end
  if result.conflicts > 0 then addBlocker(result, 'official_balance_conflicts') end
  if result.unmatched > 0 then addBlocker(result, 'unmatched_legacy_accounts') end
  result.safeToApply = #result.blockers == 0
  return result
end

local function publicPreview(result)
  return {
    bank_accounts = result.bank_accounts,
    bank_transactions = result.bank_transactions,
    matched = result.matched,
    unmatched = result.unmatched,
    divergent = result.divergent,
    conflicts = result.conflicts,
    duplicate_identifiers = result.duplicate_identifiers,
    duplicate_identifier_rows = result.duplicate_identifier_rows,
    multiple_rows_same_account = result.multiple_rows_same_account,
    ambiguous_identifiers = result.ambiguous_identifiers,
    negative_balances = result.negative_balances,
    invalid_balances = result.invalid_balances,
    candidates = result.candidates,
    blockers = result.blockers,
    safeToApply = result.safeToApply,
    snapshotFingerprint = result.snapshotFingerprint
  }
end

local function printPreview(preview)
  print(('[mz_bank][legacy] accounts exists=%s rows=%s matched=%s unmatched=%s candidates=%s'):format(
    tostring(preview.bank_accounts.exists), preview.bank_accounts.rows, preview.matched,
    preview.unmatched, preview.candidates
  ))
  print(('[mz_bank][legacy] duplicate_identifiers=%s duplicate_rows=%s multiple_rows_same_account=%s ambiguous=%s'):format(
    preview.duplicate_identifiers, preview.duplicate_identifier_rows,
    preview.multiple_rows_same_account, preview.ambiguous_identifiers
  ))
  print(('[mz_bank][legacy] negative=%s invalid=%s divergent=%s conflicts=%s blockers=%s'):format(
    preview.negative_balances, preview.invalid_balances, preview.divergent,
    preview.conflicts, table.concat(preview.blockers, ',')
  ))
  print(('[mz_bank][legacy] transactions exists=%s rows=%s; history is never imported automatically'):format(
    tostring(preview.bank_transactions.exists), preview.bank_transactions.rows
  ))
  print('[mz_bank][legacy] preview only; no legacy balance was imported, added or deleted')
end

function MZBankLegacy.preview(context)
  local result = collectPreview()
  if type(context) ~= 'table' or context.persist ~= true then return result end

  local reportUid = makeReportUid()
  local persisted = MZBankRepository.insertLegacyReport({
    reportUid = reportUid,
    status = result.safeToApply and 'preview_ready' or 'blocked',
    actor = context.actor,
    environment = context.environment,
    backupRef = context.backupRef,
    authorizationRef = context.authorizationRef,
    strategy = Config.LegacyMigration.Strategy,
    snapshotFingerprint = result.snapshotFingerprint,
    previewJson = json.encode(publicPreview(result))
  })
  if not persisted then error('legacy_report_persist_failed') end
  result.reportUid = reportUid
  return result
end

RegisterCommand('mz_bank_legacy_preview', function(source, args)
  if not hasRequiredAce(source) then return end
  local backupRef = normalizeReference(args and args[1])
  local authorizationRef = normalizeReference(args and args[2])
  local environment = tostring(args and args[3] or ''):lower()
  if not backupRef or not authorizationRef or environment ~= Config.LegacyMigration.RequiredEnvironment then
    print(('[mz_bank][legacy] usage: mz_bank_legacy_preview <backup_ref> <authorization_ref> %s'):format(
      tostring(Config.LegacyMigration.RequiredEnvironment):upper()
    ))
    return
  end

  local ok, preview = pcall(MZBankLegacy.preview, {
    persist = true,
    actor = actorFor(source),
    environment = environment,
    backupRef = backupRef,
    authorizationRef = authorizationRef
  })
  if not ok then
    print(('[mz_bank][legacy] preview failed: %s'):format(tostring(preview)))
    return
  end
  printPreview(preview)
  print(('[mz_bank][legacy] persistent_report=%s status=%s'):format(
    preview.reportUid, preview.safeToApply and 'preview_ready' or 'blocked'
  ))
end, false)

RegisterCommand('mz_bank_legacy_apply', function(source, args)
  if not hasRequiredAce(source) then return end
  if Config.LegacyMigration.AllowApply ~= true then
    print('[mz_bank][legacy] apply disabled; review LEGACY_BANK_TABLES.md and set AllowApply=true deliberately')
    return
  end

  local phrase = tostring(args and args[1] or '')
  local reportUid = normalizeReference(args and args[2])
  local backupRef = normalizeReference(args and args[3])
  local authorizationRef = normalizeReference(args and args[4])
  local environment = tostring(args and args[5] or ''):lower()
  if phrase ~= Config.LegacyMigration.ConfirmationPhrase or not reportUid or not backupRef
      or not authorizationRef or environment ~= Config.LegacyMigration.RequiredEnvironment then
    print(('[mz_bank][legacy] usage: mz_bank_legacy_apply %s <report_uid> <backup_ref> <authorization_ref> %s'):format(
      Config.LegacyMigration.ConfirmationPhrase,
      tostring(Config.LegacyMigration.RequiredEnvironment):upper()
    ))
    return
  end
  if #GetPlayers() > 0 then
    print('[mz_bank][legacy] apply refused while players are connected; this protects mz_core caches')
    return
  end
  if Config.LegacyMigration.Strategy ~= 'replace_if_official_zero' then
    print('[mz_bank][legacy] unsupported strategy')
    return
  end

  local report = MZBankRepository.getLegacyReport(reportUid)
  if not report or tostring(report.status) ~= 'preview_ready' then
    print('[mz_bank][legacy] apply refused: report_missing_or_not_ready')
    return
  end
  if tostring(report.environment) ~= environment or tostring(report.backup_ref) ~= backupRef
      or tostring(report.authorization_ref) ~= authorizationRef
      or tostring(report.strategy) ~= Config.LegacyMigration.Strategy then
    print('[mz_bank][legacy] apply refused: confirmation_does_not_match_report')
    return
  end
  if (tonumber(report.age_seconds) or math.huge) > Config.LegacyMigration.PreviewMaxAgeSeconds then
    pcall(MZBankRepository.finishLegacyReport, reportUid, 'expired', nil, 'preview_expired')
    print('[mz_bank][legacy] apply refused: preview_expired; create a new preview')
    return
  end

  local ok, current = pcall(collectPreview)
  if not ok then
    print(('[mz_bank][legacy] apply refused: preview_recheck_failed:%s'):format(tostring(current)))
    return
  end
  printPreview(current)
  if not current.safeToApply or current.snapshotFingerprint ~= tostring(report.snapshot_fingerprint) then
    pcall(MZBankRepository.finishLegacyReport, reportUid, 'invalidated', nil, 'snapshot_changed_or_blocked')
    print('[mz_bank][legacy] apply refused: snapshot_changed_or_blocked; create a new preview')
    return
  end
  if not MZBankRepository.claimLegacyReport(reportUid) then
    print('[mz_bank][legacy] apply refused: report_already_claimed')
    return
  end

  local statements = {}
  for _, candidate in ipairs(current._candidates) do
    statements[#statements + 1] = {
      query = 'UPDATE mz_player_accounts SET bank = ? WHERE citizenid = ? AND bank = 0',
      parameters = { candidate.balance, candidate.citizenid }
    }
  end
  statements[#statements + 1] = {
    query = [[
      UPDATE mz_bank_legacy_reports
      SET status = 'applied', affected_rows = ?, error_code = NULL, applied_at = CURRENT_TIMESTAMP
      WHERE report_uid = ? AND status = 'applying'
    ]],
    parameters = { #current._candidates, reportUid }
  }

  local transactionOk, committed = pcall(MySQL.transaction.await, statements)
  if not transactionOk or committed ~= true then
    pcall(MZBankRepository.finishLegacyReport, reportUid, 'failed', nil, 'transaction_failed')
    print(('[mz_bank][legacy] apply failed report=%s error=%s'):format(reportUid, tostring(committed)))
    return
  end
  print(('[mz_bank][legacy] apply complete report=%s strategy=replace_if_official_zero affected=%s; legacy tables retained'):format(
    reportUid, #current._candidates
  ))
end, false)
