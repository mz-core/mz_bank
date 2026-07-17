MZBankAccountService = {}

local policy = type(Config.PublicAccount) == 'table' and Config.PublicAccount or {}
local DEFAULT_BRANCH = tostring(policy.DefaultBranch or '')
local ACCOUNT_TYPE = tostring(policy.AccountType or '')
local ACCOUNT_NUMBER_MAX = 99999999
local RANDOM_SPACE = 4294967296
local ALLOCATION_ATTEMPTS = tonumber(policy.AllocationAttempts) or 0
local RANDOM_DRAW_ATTEMPTS = tonumber(policy.RandomDrawAttempts) or 0
local METADATA_VERSION = tonumber(policy.MetadataVersion) or 0
local REJECTION_LIMIT = math.floor(RANDOM_SPACE / ACCOUNT_NUMBER_MAX) * ACCOUNT_NUMBER_MAX

local runtime = {
  enabled = false,
  ready = false,
  error = 'feature_disabled',
  randomSource = 'not_checked'
}

local STATE_CAPABILITIES = {
  active = { read = true, deposit = true, withdraw = true, transfer = true, receive = true },
  blocked = { read = true, deposit = true, withdraw = false, transfer = false, receive = true },
  frozen = { read = true, deposit = false, withdraw = false, transfer = false, receive = false },
  closed = { read = false, deposit = false, withdraw = false, transfer = false, receive = false }
}

local function copyRuntime()
  return {
    enabled = runtime.enabled == true,
    ready = runtime.ready == true,
    error = runtime.error,
    randomSource = runtime.randomSource
  }
end

local function trim(value)
  if type(value) ~= 'string' then return nil end
  local normalized = value:gsub('^%s+', ''):gsub('%s+$', '')
  if normalized == '' or normalized ~= value or #normalized > 32 then return nil end
  return normalized
end

local function featureEnabled()
  if policy.Enabled == true then return true end
  local convar = tostring(policy.StagingEnableConvar or '')
  return convar ~= '' and GetConvarInt(convar, 0) == 1
end

local function validRandomHex(value)
  return type(value) == 'string' and #value == 8 and value:match('^[0-9a-fA-F]+$') ~= nil
end

local function drawAccountNumber()
  for _ = 1, RANDOM_DRAW_ATTEMPTS do
    local callOk, randomHex, randomSource = pcall(MZBankRepository.getSecureAccountRandomHex)
    if not callOk or not validRandomHex(randomHex) then
      return nil, 'secure_random_unavailable'
    end
    local raw = tonumber(randomHex, 16)
    if raw and raw < REJECTION_LIMIT then
      local number = (raw % ACCOUNT_NUMBER_MAX) + 1
      return ('%08d'):format(number), nil, randomSource
    end
  end
  return nil, 'secure_random_rejection_limit'
end

local function validateStoredAccount(row, expectedCitizenId)
  if type(row) ~= 'table' then return nil, 'account_not_found' end
  if tostring(row.citizenid or '') ~= expectedCitizenId then
    return nil, 'account_owner_mismatch'
  end
  if tostring(row.account_type or '') ~= ACCOUNT_TYPE then
    return nil, 'account_record_invalid'
  end
  local status = tostring(row.status or '')
  if MZBankAccountIdentity.IsValidStatus(status) ~= true then
    return nil, 'account_record_invalid'
  end
  local branch = tostring(row.branch or '')
  local accountNumber = tostring(row.account_number or '')
  local checkDigit = tostring(row.check_digit or '')
  if MZBankAccountIdentity.ValidateRoute(branch, accountNumber, checkDigit) ~= true then
    return nil, 'account_record_invalid'
  end
  if status == 'closed' and row.closed_at == nil then
    return nil, 'account_record_invalid'
  end
  if status ~= 'closed' and row.closed_at ~= nil then
    return nil, 'account_record_invalid'
  end
  return {
    branch = branch,
    accountNumber = accountNumber,
    checkDigit = checkDigit,
    formatted = ('%s / %s-%s'):format(branch, accountNumber, checkDigit),
    accountType = ACCOUNT_TYPE,
    accountTypeLabel = 'Conta pessoal',
    status = status
  }
end

local function existingResult(citizenid)
  local row, lookupError = MZBankRepository.getPublicAccountByOwner(citizenid)
  if lookupError then return nil, lookupError end
  if not row then return nil end
  local dto, dtoError = validateStoredAccount(row, citizenid)
  if not dto then return nil, dtoError end
  return { ok = true, created = false, account = dto }
end

function MZBankAccountService.IsEnabled()
  return featureEnabled()
end

function MZBankAccountService.GetRuntimeStatus()
  return copyRuntime()
end

function MZBankAccountService.CanAccountPerform(status, capability)
  local allowed = STATE_CAPABILITIES[tostring(status or '')]
  return type(allowed) == 'table' and allowed[tostring(capability or '')] == true
end

function MZBankAccountService.ValidateRuntime()
  runtime.enabled = featureEnabled()
  runtime.ready = false
  runtime.error = runtime.enabled and 'checking' or 'feature_disabled'
  if not runtime.enabled then return true, copyRuntime() end

  if type(MZBankRepository) ~= 'table'
    or type(MZBankRepository.getSecureAccountRandomHex) ~= 'function'
    or type(MZBankRepository.insertPersonalAccount) ~= 'function' then
    runtime.error = 'account_repository_unavailable'
    return false, copyRuntime()
  end

  local candidate, randomError, randomSource = drawAccountNumber()
  if not candidate then
    runtime.error = randomError or 'secure_random_unavailable'
    return false, copyRuntime()
  end
  local checkDigit, digitError = MZBankAccountIdentity.CalculateCheckDigit(DEFAULT_BRANCH, candidate)
  if not checkDigit then
    runtime.error = digitError or 'check_digit_unavailable'
    return false, copyRuntime()
  end

  runtime.ready = true
  runtime.error = nil
  runtime.randomSource = randomSource or 'unknown'
  return true, copyRuntime()
end

function MZBankAccountService.EnsurePersonalAccount(internalIdentity)
  if not featureEnabled() then return { ok = false, error = 'feature_disabled' } end
  if runtime.ready ~= true then return { ok = false, error = runtime.error or 'public_account_unavailable' } end

  local citizenid = type(internalIdentity) == 'table' and trim(internalIdentity.citizenid) or nil
  if not citizenid then return { ok = false, error = 'invalid_internal_identity' } end
  local origin = internalIdentity.origin == 'p2d_backfill'
    and 'p2d_backfill' or 'lazy_authenticated_overview'

  local existing, existingError = existingResult(citizenid)
  if existing then return existing end
  if existingError then return { ok = false, error = existingError } end

  local collisionsRecovered = 0
  for _ = 1, ALLOCATION_ATTEMPTS do
    local accountNumber, randomError = drawAccountNumber()
    if not accountNumber then return { ok = false, error = randomError or 'secure_random_unavailable' } end
    local checkDigit, digitError = MZBankAccountIdentity.CalculateCheckDigit(DEFAULT_BRANCH, accountNumber)
    if not checkDigit then return { ok = false, error = digitError or 'check_digit_unavailable' } end

    local metadataJson = json.encode({
      version = METADATA_VERSION,
      origin = origin
    })
    local insertOk, committed = pcall(MZBankRepository.insertPersonalAccount, {
      citizenid = citizenid,
      branch = DEFAULT_BRANCH,
      accountNumber = accountNumber,
      checkDigit = checkDigit,
      metadataJson = metadataJson
    })

    if insertOk and committed == true then
      local createdRow, createdError = existingResult(citizenid)
      if not createdRow then return { ok = false, error = createdError or 'account_create_failed' } end
      createdRow.created = true
      createdRow.collisionsRecovered = collisionsRecovered
      return createdRow
    end

    -- A constraint de titular resolve a corrida. Qualquer mensagem/índice SQL
    -- permanece interno; o chamador recebe somente erros estáveis.
    local concurrent, concurrentError = existingResult(citizenid)
    if concurrent then
      concurrent.collisionsRecovered = collisionsRecovered
      return concurrent
    end
    if concurrentError then return { ok = false, error = concurrentError } end

    -- Sem conta do titular, uma rota agora existente classifica a falha como
    -- colisão e permite novo candidato. Outros erros falham fechado.
    local route = MZBankRepository.getPublicAccountByRoute(DEFAULT_BRANCH, accountNumber, checkDigit)
    if not route then return { ok = false, error = 'account_create_failed' } end
    collisionsRecovered = collisionsRecovered + 1
  end

  return { ok = false, error = 'account_number_allocation_failed' }
end
