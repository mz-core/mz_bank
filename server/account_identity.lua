MZBankAccountIdentity = {}

local policy = type(Config.PublicAccount) == 'table' and Config.PublicAccount or {}
local DEFAULT_BRANCH = policy.DefaultBranch
local ACCOUNT_NUMBER_LENGTH = tonumber(policy.AccountNumberLength)
local ACCOUNT_TYPE = policy.AccountType
local CHECK_DIGIT_ALGORITHM = policy.CheckDigitAlgorithm
local ALLOWED_STATUSES = type(policy.AllowedStatuses) == 'table' and policy.AllowedStatuses or {}

local function isExactDigits(value, length)
  return type(value) == 'string'
    and #value == length
    and value:match('^%d+$') ~= nil
end

function MZBankAccountIdentity.ValidateConfiguration()
  if DEFAULT_BRANCH ~= '0001' then return false, 'invalid_default_branch' end
  if ACCOUNT_NUMBER_LENGTH ~= 8 then return false, 'invalid_account_number_length' end
  if ACCOUNT_TYPE ~= 'personal' then return false, 'invalid_account_type' end
  if CHECK_DIGIT_ALGORITHM ~= 'mod11' then return false, 'invalid_check_digit_algorithm' end
  if type(policy.Enabled) ~= 'boolean' then return false, 'invalid_public_account_enabled' end
  if type(policy.StagingEnableConvar) ~= 'string' or policy.StagingEnableConvar == '' then
    return false, 'invalid_public_account_staging_convar'
  end
  if tonumber(policy.SecureRandomBytes) ~= 4 then return false, 'invalid_secure_random_bytes' end
  if tonumber(policy.SecureRandomTimeoutMs) ~= 1500 then return false, 'invalid_secure_random_timeout' end
  if tonumber(policy.AllocationAttempts) ~= 10 then return false, 'invalid_allocation_attempts' end
  if tonumber(policy.RandomDrawAttempts) ~= 16 then return false, 'invalid_random_draw_attempts' end
  if tonumber(policy.MetadataVersion) ~= 1 then return false, 'invalid_metadata_version' end
  local requiredStatuses = { active = true, blocked = true, frozen = true, closed = true }
  for status in pairs(requiredStatuses) do
    if ALLOWED_STATUSES[status] ~= true then
      return false, ('missing_account_status:%s'):format(status)
    end
  end
  for status, enabled in pairs(ALLOWED_STATUSES) do
    if enabled == true and requiredStatuses[status] ~= true then
      return false, ('unexpected_account_status:%s'):format(tostring(status))
    end
  end
  return true
end

function MZBankAccountIdentity.GetDefaultBranch()
  return DEFAULT_BRANCH
end

function MZBankAccountIdentity.IsValidStatus(status)
  return type(status) == 'string' and ALLOWED_STATUSES[status] == true
end

function MZBankAccountIdentity.CalculateCheckDigit(branch, accountNumber)
  if branch == nil then branch = DEFAULT_BRANCH end
  if not isExactDigits(branch, 4) then return nil, 'invalid_branch' end
  if not isExactDigits(accountNumber, ACCOUNT_NUMBER_LENGTH) then
    return nil, 'invalid_account_number'
  end
  if accountNumber == string.rep('0', ACCOUNT_NUMBER_LENGTH) then
    return nil, 'reserved_account_number'
  end

  local digits = branch .. accountNumber
  local weights = { 2, 3, 4, 5, 6, 7, 8, 9 }
  local sum = 0
  local weightIndex = 1
  for index = #digits, 1, -1 do
    sum = sum + (tonumber(digits:sub(index, index)) * weights[weightIndex])
    weightIndex = weightIndex == #weights and 1 or weightIndex + 1
  end

  local candidate = 11 - (sum % 11)
  if candidate == 10 or candidate == 11 then candidate = 0 end
  return tostring(candidate)
end

function MZBankAccountIdentity.ValidateRoute(branch, accountNumber, checkDigit)
  local expected, err = MZBankAccountIdentity.CalculateCheckDigit(branch, accountNumber)
  if not expected then return false, err end
  if not isExactDigits(checkDigit, 1) or checkDigit ~= expected then
    return false, 'invalid_check_digit'
  end
  return true
end
