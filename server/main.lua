CreateThread(function()
  local ok, err = pcall(MZBankRepository.prepare)
  if not ok then
    print(('[mz_bank] card schema prepare failed: %s'):format(tostring(err)))
    MZBankService.SetReady(false)
    return
  end

  MZBankService.SetReady(true)
  print('[mz_bank] ready; balances are provided exclusively by mz_core')

  local previewOk, preview = pcall(MZBankLegacy.preview)
  if previewOk and (preview.bank_accounts.exists or preview.bank_transactions.exists) then
    print(('[mz_bank][legacy] detected accounts_rows=%s transactions_rows=%s; run mz_bank_legacy_preview; no migration applied'):format(
      preview.bank_accounts.rows, preview.bank_transactions.rows
    ))
  end

  pcall(function()
    exports['mz_core']:RegisterItemUseHandler(Config.Card.ItemName, function(source)
      MZBankBridge.Notify(source, 'Use o cartao em um caixa eletronico ou agencia.', 'info')
      return { ok = true, consume = false }
    end)
  end)
end)

local function safeServiceCall(handler, ...)
  local ok, result = pcall(handler, ...)
  if ok and type(result) == 'table' then return result end
  if not ok then print(('[mz_bank] service call failed: %s'):format(tostring(result))) end
  return { ok = false, error = 'transaction_failed', message = Config.Locale.transaction_failed }
end

lib.callback.register('mz_bank:server:openSession', function(source, payload)
  return safeServiceCall(MZBankService.OpenSession, source, payload)
end)

lib.callback.register('mz_bank:server:authenticate', function(source, token)
  return safeServiceCall(MZBankService.Authenticate, source, token)
end)

lib.callback.register('mz_bank:server:overview', function(source, token, channel)
  return safeServiceCall(MZBankService.Refresh, source, token, channel)
end)

lib.callback.register('mz_bank:server:withdraw', function(source, token, amount)
  return safeServiceCall(MZBankService.Withdraw, source, token, amount)
end)

lib.callback.register('mz_bank:server:deposit', function(source, token, amount)
  return safeServiceCall(MZBankService.Deposit, source, token, amount)
end)

lib.callback.register('mz_bank:server:transfer', function(source, token, payload)
  payload = type(payload) == 'table' and payload or {}
  return safeServiceCall(MZBankService.Transfer, source, {
    type = payload.recipientType,
    value = payload.recipientValue
  }, payload.amount, { token = token, channel = payload.channel })
end)

RegisterNetEvent('mz_bank:server:closeSession', function(token, reason)
  pcall(MZBankService.CloseSession, source, token, reason)
end)

AddEventHandler('playerDropped', function()
  MZBankService.CleanupSource(source)
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  for _, playerId in ipairs(GetPlayers()) do
    MZBankService.CleanupSource(tonumber(playerId))
  end
end)

exports('GetAccountOverview', function(source, context)
  return safeServiceCall(MZBankService.GetAccountOverview, source, context)
end)

exports('GetStatement', function(source, filters, context)
  return safeServiceCall(MZBankService.GetStatement, source, filters, context)
end)

exports('ResolveRecipient', function(source, recipientType, recipientValue)
  return safeServiceCall(MZBankService.ResolveRecipient, source, recipientType, recipientValue)
end)

exports('Transfer', function(source, recipient, amount, context)
  return safeServiceCall(MZBankService.Transfer, source, recipient, amount, context)
end)

exports('GetCards', function(source)
  return safeServiceCall(MZBankService.GetCards, source)
end)

exports('BlockCard', function(source, cardUid)
  return safeServiceCall(MZBankService.BlockCard, source, cardUid)
end)

exports('RequestReplacementCard', function(source, context)
  return safeServiceCall(MZBankService.RequestReplacementCard, source, context)
end)
