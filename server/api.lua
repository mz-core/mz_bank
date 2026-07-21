MZBankAPI = {}

local policy = type(Config.SharedAPI) == 'table' and Config.SharedAPI or {}
local API_VERSION = math.floor(tonumber(policy.Version) or 1)
local AllowedResources = type(policy.AllowedResources) == 'table' and policy.AllowedResources or {}
local ResourceChannels = type(policy.ResourceChannels) == 'table' and policy.ResourceChannels or {}
local CardReferences = {}

local FORBIDDEN_DTO_KEYS = {
  id = true,
  accountid = true,
  citizenid = true,
  sourcecitizenid = true,
  targetcitizenid = true,
  relatedcitizenid = true,
  license = true,
  license2 = true,
  source = true,
  targetsource = true,
  carduid = true,
  inventoryinstanceuid = true,
  metadata = true,
  metadatajson = true,
  pin = true,
  pinhash = true
}

local function sanitizeDto(value, seen)
  if type(value) ~= 'table' then return value end
  seen = seen or {}
  if seen[value] then return nil end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do
    local normalizedKey = tostring(key):lower():gsub('[^%w]', '')
    if FORBIDDEN_DTO_KEYS[normalizedKey] ~= true then
      out[key] = sanitizeDto(item, seen)
    end
  end
  seen[value] = nil
  return out
end

local function response(ok, errorCode, data, message)
  return {
    ok = ok == true,
    error = errorCode,
    message = message or (errorCode and (Config.Locale[errorCode] or Config.Locale.transaction_failed)) or nil,
    data = data,
    apiVersion = API_VERSION
  }
end

local function normalizeResult(result)
  if type(result) ~= 'table' then return response(false, 'transaction_failed') end
  local sanitized = sanitizeDto(result)
  sanitized.apiVersion = API_VERSION
  return sanitized
end

local function validateCaller(callerResource, context)
  callerResource = tostring(callerResource or '')
  if callerResource == '' or AllowedResources[callerResource] ~= true then
    return nil, 'api_forbidden'
  end
  context = type(context) == 'table' and context or {}
  if callerResource ~= 'mz_bank' then
    local requestedVersion = tonumber(context.apiVersion)
    if not requestedVersion then return nil, 'api_version_required' end
    if requestedVersion ~= API_VERSION then return nil, 'api_version_unsupported' end
  elseif context.apiVersion ~= nil and tonumber(context.apiVersion) ~= API_VERSION then
    return nil, 'api_version_unsupported'
  end
  return callerResource
end

local function authorize(source, callerResource, context)
  local caller, err = validateCaller(callerResource, context)
  if not caller then return nil, response(false, err) end
  local service = caller == 'mz_phone' and MZBankPhoneService or MZBankService
  if type(service) ~= 'table' or type(service.GetChannelCapabilities) ~= 'function' then
    return nil, response(false, 'bank_unavailable')
  end
  local capability = service.GetChannelCapabilities(source, context)
  if type(capability) ~= 'table' or capability.ok ~= true then
    return nil, normalizeResult(capability)
  end
  local channel = type(capability.data) == 'table' and tostring(capability.data.channel or '') or ''
  local allowedChannels = ResourceChannels[caller]
  if type(allowedChannels) ~= 'table' or allowedChannels[channel] ~= true then
    return nil, response(false, 'channel_forbidden')
  end
  return caller, nil, capability, service
end

local function phoneCommandForbidden(caller)
  return caller == 'mz_phone' and response(false, 'channel_forbidden') or nil
end

local function opaqueCardReference(source, sessionToken, index)
  return ('cardref_%x_%x_%x_%06d'):format(
    tonumber(source) or 0,
    os.time(),
    GetGameTimer(),
    math.random(0, 999999)
  ) .. '_' .. tostring(index)
end

local function safeCardDto(row, cardRef)
  local status = tostring(row.status or '')
  return {
    cardRef = cardRef,
    last4 = tostring(row.last4 or ''),
    status = status,
    canBlock = status == 'active',
    issuedAt = row.issued_at,
    updatedAt = row.updated_at,
    blockedAt = row.blocked_at
  }
end

local function clearCardReferences(source)
  CardReferences[tonumber(source) or source] = nil
end

function MZBankAPI.GetVersion()
  return {
    ok = true,
    apiVersion = API_VERSION,
    name = 'mz_bank',
    channels = { 'atm', 'branch', 'phone', 'admin' }
  }
end

function MZBankAPI.OpenPhoneSession(source, request, callerResource)
  local caller, err = validateCaller(callerResource, request)
  if not caller then return response(false, err) end
  if caller ~= 'mz_phone' then return response(false, 'channel_forbidden') end
  return normalizeResult(MZBankPhoneService.OpenSession(source, request))
end

function MZBankAPI.ClosePhoneSession(source, context, callerResource)
  local caller, err = validateCaller(callerResource, context)
  if not caller then return response(false, err) end
  if caller ~= 'mz_phone' then return response(false, 'channel_forbidden') end
  clearCardReferences(source)
  return normalizeResult(MZBankPhoneService.CloseSession(source, context, 'phone_resource_close'))
end

function MZBankAPI.GetAccountOverview(source, context, callerResource)
  local _, denied, _, service = authorize(source, callerResource, context)
  if denied then return denied end
  if service == MZBankPhoneService then
    return normalizeResult(service.Refresh(source, context))
  end
  return normalizeResult(service.Refresh(source, context and context.token))
end

function MZBankAPI.GetAccountStatement(source, filters, context, callerResource)
  local _, denied, _, service = authorize(source, callerResource, context)
  if denied then return denied end
  return normalizeResult(service.GetStatement(source, filters, context))
end

function MZBankAPI.GetPublicAccount(source, context, callerResource)
  local _, denied, _, service = authorize(source, callerResource, context)
  if denied then return denied end
  return normalizeResult(service.GetPublicAccount(source, context))
end

function MZBankAPI.ResolveTransferRecipient(source, route, context, callerResource)
  local _, denied, _, service = authorize(source, callerResource, context)
  if denied then return denied end
  return normalizeResult(service.ResolvePublicRecipient(source, route, context))
end

function MZBankAPI.Transfer(source, payload, context, callerResource)
  local _, denied, _, service = authorize(source, callerResource, context)
  if denied then return denied end
  payload = type(payload) == 'table' and payload or {}
  context = type(context) == 'table' and context or {}
  context.idempotencyKey = payload.idempotencyKey
  return normalizeResult(service.TransferByPublicAccount(
    source, payload.resolutionToken, payload.amount, context
  ))
end

function MZBankAPI.Withdraw(source, payload, context, callerResource)
  local caller, denied = authorize(source, callerResource, context)
  if denied then return denied end
  local forbidden = phoneCommandForbidden(caller)
  if forbidden then return forbidden end
  payload = type(payload) == 'table' and payload or {}
  return normalizeResult(MZBankService.Withdraw(
    source, context and context.token, payload.amount, payload.idempotencyKey
  ))
end

function MZBankAPI.Deposit(source, payload, context, callerResource)
  local caller, denied = authorize(source, callerResource, context)
  if denied then return denied end
  local forbidden = phoneCommandForbidden(caller)
  if forbidden then return forbidden end
  payload = type(payload) == 'table' and payload or {}
  return normalizeResult(MZBankService.Deposit(
    source, context and context.token, payload.amount, payload.idempotencyKey
  ))
end

function MZBankAPI.GetCards(source, context, callerResource)
  local _, denied, _, service = authorize(source, callerResource, context)
  if denied then return denied end
  local result = service.GetCards(source, context)
  if type(result) ~= 'table' or result.ok ~= true then return normalizeResult(result) end

  clearCardReferences(source)
  local sessionToken = tostring(type(context) == 'table' and context.token or '')
  local refs = {}
  local cards = {}
  for index, row in ipairs((result.data and result.data.cards) or {}) do
    local ref = opaqueCardReference(source, sessionToken, index)
    refs[ref] = { token = sessionToken, uid = tostring(row.card_uid or '') }
    cards[#cards + 1] = safeCardDto(row, ref)
  end
  CardReferences[tonumber(source) or source] = refs
  return response(true, nil, { cards = cards })
end

function MZBankAPI.IssueCard(source, context, callerResource)
  local caller, denied = authorize(source, callerResource, context)
  if denied then return denied end
  local forbidden = phoneCommandForbidden(caller)
  if forbidden then return forbidden end
  local result = MZBankService.IssueCard(source, context)
  if type(result) == 'table' and type(result.data) == 'table' then
    result.data.cardUid = nil
  end
  clearCardReferences(source)
  return normalizeResult(result)
end

function MZBankAPI.BlockCard(source, cardRef, context, callerResource)
  local _, denied, _, service = authorize(source, callerResource, context)
  if denied then return denied end
  local sourceRefs = CardReferences[tonumber(source) or source]
  local resolved = type(sourceRefs) == 'table' and sourceRefs[tostring(cardRef or '')] or nil
  if not resolved or resolved.token ~= tostring(type(context) == 'table' and context.token or '') then
    return response(false, 'card_invalid')
  end
  if type(service.BlockCard) ~= 'function' then return response(false, 'channel_forbidden') end
  local result = service.BlockCard(source, resolved.uid, context)
  clearCardReferences(source)
  return normalizeResult(result)
end

function MZBankAPI.ReplaceCard(source, context, callerResource)
  local caller, denied = authorize(source, callerResource, context)
  if denied then return denied end
  local forbidden = phoneCommandForbidden(caller)
  if forbidden then return forbidden end
  local result = MZBankService.RequestReplacementCard(source, context)
  if type(result) == 'table' and type(result.data) == 'table' then
    result.data.cardUid = nil
  end
  clearCardReferences(source)
  return normalizeResult(result)
end

function MZBankAPI.GetChannelCapabilities(source, context, callerResource)
  local _, denied, capability = authorize(source, callerResource, context)
  if denied then return denied end
  return normalizeResult(capability)
end

function MZBankAPI.GetOperationResult(source, request, context, callerResource)
  local _, denied = authorize(source, callerResource, context)
  if denied then return denied end

  request = type(request) == 'table' and request or {}
  local requestedOperation = tostring(request.operation or '')
  local coreOperations = {
    withdraw = 'transfer_between_accounts',
    deposit = 'transfer_between_accounts',
    transfer = 'bank_transfer'
  }
  local coreOperation = coreOperations[requestedOperation]
  if not coreOperation then return response(false, 'invalid_operation') end
  local result = MZBankBridge.GetOperationResult(
    source, request.idempotencyKey, coreOperation
  )
  if type(result) ~= 'table' or result.ok ~= true then return normalizeResult(result) end
  local stored = type(result.result) == 'table' and result.result or {}
  return response(true, nil, {
    found = true,
    operation = requestedOperation,
    correlationId = tostring(result.correlationId or stored.correlationId or stored.transactionRef or ''),
    confirmed = stored.ok ~= false,
    replayed = true,
    fee = tonumber(stored.fee) or 0
  })
end

function MZBankAPI.CleanupSource(source)
  clearCardReferences(source)
  if type(MZBankPhoneService) == 'table' and type(MZBankPhoneService.CleanupSource) == 'function' then
    MZBankPhoneService.CleanupSource(source)
  end
end
