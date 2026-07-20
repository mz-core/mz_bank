if GetConvarInt('mz_bank_p4_runtime_runner', 0) ~= 1 then return end

local COMMAND = 'mz_bank_p4_runtime_test'

local function resultError(result)
  return type(result) == 'table' and tostring(result.error or '') or ''
end

local function hasForbiddenKey(value, seen)
  if type(value) ~= 'table' then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true
  local forbidden = {
    id = true, accountid = true, citizenid = true, sourcecitizenid = true,
    targetcitizenid = true, relatedcitizenid = true, license = true,
    license2 = true, source = true, targetsource = true, carduid = true,
    inventoryinstanceuid = true, metadata = true, metadatajson = true,
    pin = true, pinhash = true
  }
  for key, item in pairs(value) do
    local normalized = tostring(key):lower():gsub('[^%w]', '')
    if forbidden[normalized] or hasForbiddenKey(item, seen) then return true end
  end
  return false
end

local function emit(ok, testId, detail)
  print(('[mz_bank][p4-runner] %s %s detail=%s'):format(
    ok and 'PASS' or 'FAIL', testId, tostring(detail or 'none')
  ))
  return ok
end

RegisterCommand(COMMAND, function(source)
  if tonumber(source) ~= 0 then
    print('[mz_bank][p4-runner] DENIED source=player console_only=true')
    return
  end

  print('[mz_bank][p4-runner] START fixtures=memory sql_writes=0 balance_writes=0 client_input=false')
  local original = {
    capabilities = MZBankService.GetChannelCapabilities,
    refresh = MZBankService.Refresh,
    cards = MZBankService.GetCards,
    block = MZBankService.BlockCard,
    transfer = MZBankService.TransferByPublicAccount,
    operation = MZBankBridge.GetOperationResult
  }
  local executed, passed = 0, 0

  local function run(testId, handler)
    executed = executed + 1
    local ok, result, detail = pcall(handler)
    local approved = ok and result == true
    if emit(approved, testId, ok and detail or result) then passed = passed + 1 end
  end

  local restored = false
  local function restore()
    if restored then return end
    restored = true
    MZBankService.GetChannelCapabilities = original.capabilities
    MZBankService.Refresh = original.refresh
    MZBankService.GetCards = original.cards
    MZBankService.BlockCard = original.block
    MZBankService.TransferByPublicAccount = original.transfer
    MZBankBridge.GetOperationResult = original.operation
    MZBankAPI.CleanupSource(9001)
  end

  local suiteOk, suiteError = pcall(function()
    MZBankService.GetChannelCapabilities = function()
      return { ok = true, data = { channel = 'branch', capabilities = { overview = true, cards = true } } }
    end

    run('P4-SEC-01', function()
      local version = MZBankAPI.GetVersion()
      local missing = MZBankAPI.GetAccountOverview(9001, {}, 'mz_phone')
      local wrong = MZBankAPI.GetAccountOverview(9001, { apiVersion = 99 }, 'mz_phone')
      local forbidden = MZBankAPI.GetAccountOverview(9001, { apiVersion = 1 }, 'unknown_resource')
      local ok = version.apiVersion == 1
        and resultError(missing) == 'api_version_required'
        and resultError(wrong) == 'api_version_unsupported'
        and resultError(forbidden) == 'api_forbidden'
      return ok, 'version=1 caller_allowlist=true errors=stable'
    end)

    run('P4-SEC-02', function()
      MZBankService.GetChannelCapabilities = function()
        return { ok = true, data = { channel = 'atm', capabilities = { overview = true } } }
      end
      local result = MZBankAPI.GetChannelCapabilities(
        9001, { apiVersion = 1, token = 'physical_fixture' }, 'mz_phone'
      )
      MZBankService.GetChannelCapabilities = function()
        return { ok = true, data = { channel = 'branch', capabilities = { overview = true, cards = true } } }
      end
      return resultError(result) == 'channel_forbidden', 'phone_cannot_reuse_atm_or_branch=true'
    end)

    run('P4-DTO-01', function()
      MZBankService.Refresh = function()
        return {
          ok = true,
          data = {
            balance = 10, cash = 2, name = 'Cliente', account = '0001 / ********-0',
            citizenid = 'INTERNAL', license = 'INTERNAL', id = 77,
            publicAccount = { branch = '0001', accountNumber = '12345678', checkDigit = '7', accountId = 77 },
            statement = { { amount = 1, citizenid = 'INTERNAL' } }
          }
        }
      end
      local result = MZBankAPI.GetAccountOverview(9001, { token = 'fixture' }, 'mz_bank')
      return result.ok == true and result.apiVersion == 1 and not hasForbiddenKey(result),
        'overview_sanitized=true api_version=1'
    end)

    run('P4-CARD-01', function()
      MZBankService.GetCards = function()
        return { ok = true, data = { cards = { {
          card_uid = 'SECRET_CARD_UID', citizenid = 'INTERNAL', id = 1,
          last4 = '4321', status = 'active', metadata_json = '{}'
        } } } }
      end
      local blockedUid
      MZBankService.BlockCard = function(_, uid)
        blockedUid = uid
        return { ok = true }
      end
      local listed = MZBankAPI.GetCards(9001, { token = 'fixture' }, 'mz_bank')
      local card = listed.data and listed.data.cards and listed.data.cards[1]
      local blocked = card and MZBankAPI.BlockCard(9001, card.cardRef, { token = 'fixture' }, 'mz_bank')
      local fake = MZBankAPI.BlockCard(9001, 'fake_ref', { token = 'fixture' }, 'mz_bank')
      local ok = listed.ok == true and card and card.last4 == '4321'
        and not hasForbiddenKey(listed) and blocked and blocked.ok == true
        and blockedUid == 'SECRET_CARD_UID' and resultError(fake) == 'card_invalid'
      return ok, 'card_uid=internal card_ref=bound fake_ref=denied'
    end)

    run('P4-RESULT-01', function()
      MZBankBridge.GetOperationResult = function()
        return {
          ok = true, operation = 'bank_transfer', correlationId = 'corr_fixture',
          result = { ok = true, fee = 0, targetCitizenId = 'INTERNAL', targetSource = 22 }
        }
      end
      local result = MZBankAPI.GetOperationResult(9001, {
        operation = 'transfer', idempotencyKey = 'p4_fixture_key_1234'
      }, { token = 'fixture' }, 'mz_bank')
      return result.ok == true and result.data and result.data.correlationId == 'corr_fixture'
        and result.data.replayed == true and not hasForbiddenKey(result),
        'read_only=true correlation=set internal_target=false'
    end)

    run('P4-REPLAY-01', function()
      local calls = {}
      MZBankService.TransferByPublicAccount = function(_, token, amount, context)
        calls[#calls + 1] = {
          token = token, amount = amount, key = context and context.idempotencyKey
        }
        return {
          ok = true, confirmed = true, correlationId = 'corr_replay_fixture',
          replayed = #calls > 1,
          data = { confirmed = true, correlationId = 'corr_replay_fixture', replayed = #calls > 1 }
        }
      end
      local payload = {
        resolutionToken = 'resolution_fixture', amount = 1,
        idempotencyKey = 'p4_replay_key_1234'
      }
      local first = MZBankAPI.Transfer(9001, payload, { token = 'fixture' }, 'mz_bank')
      local replay = MZBankAPI.Transfer(9001, payload, { token = 'fixture' }, 'mz_bank')
      local forwarded = #calls == 2 and calls[1].key == payload.idempotencyKey
        and calls[2].key == payload.idempotencyKey
      return first.ok == true and replay.ok == true and replay.replayed == true
        and replay.correlationId == first.correlationId and forwarded,
        'idempotency_key=stable correlation=stable adapter_duplicate=false'
    end)
  end)

  restore()
  if not suiteOk then
    print(('[mz_bank][p4-runner] ERROR detail=%s'):format(tostring(suiteError)))
  end
  print(('[mz_bank][p4-runner] SUMMARY executed=%d passed=%d failed=%d sql_writes=0 balance_writes=0'):format(
    executed, passed, executed - passed
  ))
  print('[mz_bank][p4-runner] END dependencies=restored disable_convar_and_restart=true')
end, false)

print(('[mz_bank][p4-runner] enabled staging_only=true command=%s source=console fixtures=memory'):format(COMMAND))
