MZBankLegacy = {}

local function tableExists(name)
  return tonumber(MySQL.scalar.await([[
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = ?
  ]], { name })) == 1
end

function MZBankLegacy.preview()
  local result = {
    bank_accounts = { exists = tableExists('bank_accounts'), rows = 0 },
    bank_transactions = { exists = tableExists('bank_transactions'), rows = 0 },
    matched = 0,
    divergent = 0,
    conflicts = 0,
    unmatched = 0
  }

  if result.bank_accounts.exists then
    result.bank_accounts.rows = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bank_accounts')) or 0
    local summary = MySQL.single.await([[
      SELECT
        SUM(CASE WHEN p.citizenid IS NOT NULL THEN 1 ELSE 0 END) AS matched,
        SUM(CASE WHEN p.citizenid IS NULL THEN 1 ELSE 0 END) AS unmatched,
        SUM(CASE WHEN p.citizenid IS NOT NULL AND ba.balance <> a.bank THEN 1 ELSE 0 END) AS divergent,
        SUM(CASE WHEN p.citizenid IS NOT NULL AND ba.balance <> a.bank AND a.bank <> 0 THEN 1 ELSE 0 END) AS conflicts
      FROM bank_accounts ba
      LEFT JOIN mz_players p ON p.citizenid = ba.identifier OR p.license = ba.identifier
      LEFT JOIN mz_player_accounts a ON a.citizenid = p.citizenid
    ]]) or {}
    result.matched = tonumber(summary.matched) or 0
    result.unmatched = tonumber(summary.unmatched) or 0
    result.divergent = tonumber(summary.divergent) or 0
    result.conflicts = tonumber(summary.conflicts) or 0
  end

  if result.bank_transactions.exists then
    result.bank_transactions.rows = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bank_transactions')) or 0
  end
  return result
end

local function printPreview(preview)
  print(('[mz_bank][legacy] bank_accounts exists=%s rows=%s matched=%s unmatched=%s divergent=%s conflicts=%s'):format(
    tostring(preview.bank_accounts.exists), preview.bank_accounts.rows, preview.matched,
    preview.unmatched, preview.divergent, preview.conflicts
  ))
  print(('[mz_bank][legacy] bank_transactions exists=%s rows=%s'):format(
    tostring(preview.bank_transactions.exists), preview.bank_transactions.rows
  ))
  print('[mz_bank][legacy] preview only; no legacy balance was imported or added')
end

RegisterCommand('mz_bank_legacy_preview', function(source)
  if source > 0 and not IsPlayerAceAllowed(source, Config.LegacyMigration.Ace) then return end
  local ok, preview = pcall(MZBankLegacy.preview)
  if not ok then
    print(('[mz_bank][legacy] preview failed: %s'):format(tostring(preview)))
    return
  end
  printPreview(preview)
end, false)

RegisterCommand('mz_bank_legacy_apply', function(source, args)
  if source > 0 and not IsPlayerAceAllowed(source, Config.LegacyMigration.Ace) then return end
  if Config.LegacyMigration.AllowApply ~= true then
    print('[mz_bank][legacy] apply disabled; review LEGACY_BANK_TABLES.md and set AllowApply=true deliberately')
    return
  end
  if tostring(args and args[1] or '') ~= 'CONFIRM' then
    print('[mz_bank][legacy] usage: mz_bank_legacy_apply CONFIRM')
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

  local preview = MZBankLegacy.preview()
  printPreview(preview)
  if not preview.bank_accounts.exists then return end

  local affected = MySQL.update.await([[
    UPDATE mz_player_accounts a
    JOIN mz_players p ON p.citizenid = a.citizenid
    JOIN bank_accounts ba ON ba.identifier = p.citizenid OR ba.identifier = p.license
    SET a.bank = ba.balance
    WHERE a.bank = 0 AND ba.balance >= 0
  ]])
  print(('[mz_bank][legacy] apply complete strategy=replace_if_official_zero affected=%s; legacy tables retained'):format(tostring(affected)))
end, false)
