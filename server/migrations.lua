MZBankMigrations = {}

local EXPECTED_VERSION = 3
local status = {
  ready = false,
  currentVersion = 0,
  expectedVersion = EXPECTED_VERSION,
  error = 'not_started'
}

local migrations = {
  { version = 1, name = 'mz_bank_cards', file = 'sql/001_mz_bank_cards.sql' },
  { version = 2, name = 'mz_bank_legacy_reports', file = 'sql/002_mz_bank_legacy_reports.sql' },
  { version = 3, name = 'mz_bank_accounts', file = 'sql/003_mz_bank_accounts.sql' }
}

-- Contrato de readiness somente leitura. A definição/evolução executável das
-- tabelas continua exclusivamente nos arquivos SQL versionados.
local expectedSchemas = {
  mz_bank_schema_migrations = {
    columns = { version = 'int', name = 'varchar', applied_at = 'timestamp' },
    lengths = { name = 96 },
    indexes = { PRIMARY = 'version' }
  },
  mz_bank_cards = {
    columns = {
      id = 'bigint', card_uid = 'varchar', citizenid = 'varchar', last4 = 'char',
      status = 'varchar', pin_hash = 'varchar', issued_at = 'timestamp',
      updated_at = 'timestamp', blocked_at = 'timestamp', metadata_json = 'longtext'
    },
    lengths = { card_uid = 64, citizenid = 64, last4 = 4, status = 16, pin_hash = 255 },
    autoIncrement = 'id',
    indexes = {
      PRIMARY = 'id',
      uq_mz_bank_cards_uid = 'card_uid',
      idx_mz_bank_cards_owner_status = 'citizenid,status'
    }
  },
  mz_bank_legacy_reports = {
    columns = {
      id = 'bigint', report_uid = 'varchar', status = 'varchar', actor = 'varchar',
      environment = 'varchar', backup_ref = 'varchar', authorization_ref = 'varchar',
      strategy = 'varchar', snapshot_fingerprint = 'varchar', preview_json = 'longtext',
      affected_rows = 'int', error_code = 'varchar', created_at = 'timestamp',
      applied_at = 'timestamp'
    },
    lengths = {
      report_uid = 64, status = 32, actor = 64, environment = 16,
      backup_ref = 128, authorization_ref = 128, strategy = 64,
      snapshot_fingerprint = 128, error_code = 64
    },
    autoIncrement = 'id',
    indexes = {
      PRIMARY = 'id',
      uq_mz_bank_legacy_reports_uid = 'report_uid',
      idx_mz_bank_legacy_reports_status_created = 'status,created_at'
    }
  },
  mz_bank_accounts = {
    charset = 'utf8mb4',
    columns = {
      id = 'bigint', citizenid = 'varchar', branch = 'char', account_number = 'char',
      check_digit = 'char', account_type = 'varchar', status = 'varchar',
      created_at = 'timestamp', updated_at = 'timestamp', closed_at = 'timestamp',
      metadata_json = 'longtext'
    },
    lengths = {
      citizenid = 32, branch = 4, account_number = 8, check_digit = 1,
      account_type = 24, status = 16
    },
    nullable = {
      id = false, citizenid = false, branch = false, account_number = false,
      check_digit = false, account_type = false, status = false,
      created_at = false, updated_at = false, closed_at = true, metadata_json = true
    },
    defaults = {
      branch = '0001', account_type = 'personal', status = 'active'
    },
    unsigned = { id = true },
    extraContains = { updated_at = 'on update current_timestamp' },
    autoIncrement = 'id',
    indexes = {
      PRIMARY = 'id',
      uq_mz_bank_accounts_owner_type = 'citizenid,account_type',
      uq_mz_bank_accounts_route = 'branch,account_number',
      idx_mz_bank_accounts_route_lookup = 'branch,account_number,check_digit,account_type',
      idx_mz_bank_accounts_owner_status = 'citizenid,status',
      idx_mz_bank_accounts_status = 'status'
    }
  }
}

local function copyStatus()
  return {
    ready = status.ready,
    currentVersion = status.currentVersion,
    expectedVersion = status.expectedVersion,
    error = status.error
  }
end

local function fail(code)
  status.ready = false
  status.error = code
  return false, copyStatus()
end

local function loadSql(path)
  local sql = LoadResourceFile(GetCurrentResourceName(), path)
  if type(sql) ~= 'string' or not sql:match('%S') then
    error(('migration_file_unavailable:%s'):format(path))
  end
  return sql
end

local function normalizeColumnDefault(value)
  if value == nil then return nil end

  local normalized = tostring(value)
  local first = normalized:sub(1, 1)
  local last = normalized:sub(-1)
  if #normalized >= 2
    and ((first == "'" and last == "'") or (first == '"' and last == '"')) then
    normalized = normalized:sub(2, -2)
    normalized = first == "'"
      and normalized:gsub("''", "'")
      or normalized:gsub('""', '"')
  end
  return normalized
end

local function verifyTable(tableName)
  local definition = expectedSchemas[tableName]
  local tableRow = MySQL.single.await([[
    SELECT ENGINE AS engine, TABLE_COLLATION AS table_collation
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = ?
    LIMIT 1
  ]], { tableName })
  if not tableRow or tostring(tableRow.engine or ''):lower() ~= 'innodb' then
    return false, ('schema_invalid:%s:engine'):format(tableName)
  end
  if definition.charset then
    local actualCharset = tostring(tableRow.table_collation or ''):lower():match('^([^_]+)')
    if actualCharset ~= definition.charset then
      return false, ('schema_invalid:%s:charset'):format(tableName)
    end
  end

  local columns = MySQL.query.await([[
    SELECT column_name, data_type, column_type, character_maximum_length,
           is_nullable, column_default, extra
    FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = ?
  ]], { tableName }) or {}
  local actualColumns = {}
  for _, row in ipairs(columns) do
    actualColumns[tostring(row.column_name)] = {
      dataType = tostring(row.data_type):lower(),
      columnType = tostring(row.column_type or ''):lower(),
      length = tonumber(row.character_maximum_length),
      nullable = tostring(row.is_nullable or ''):upper() == 'YES',
      default = row.column_default,
      extra = tostring(row.extra or ''):lower()
    }
  end
  for columnName, dataType in pairs(definition.columns) do
    local actual = actualColumns[columnName]
    if not actual or actual.dataType ~= dataType then
      return false, ('schema_invalid:%s:column:%s'):format(tableName, columnName)
    end
    local expectedLength = definition.lengths and definition.lengths[columnName]
    if expectedLength and actual.length ~= expectedLength then
      return false, ('schema_invalid:%s:column_length:%s'):format(tableName, columnName)
    end
    local expectedNullable = definition.nullable and definition.nullable[columnName]
    if expectedNullable ~= nil and actual.nullable ~= expectedNullable then
      return false, ('schema_invalid:%s:nullable:%s'):format(tableName, columnName)
    end
    local expectedDefault = definition.defaults and definition.defaults[columnName]
    if expectedDefault ~= nil
      and normalizeColumnDefault(actual.default) ~= normalizeColumnDefault(expectedDefault) then
      return false, ('schema_invalid:%s:default:%s'):format(tableName, columnName)
    end
    if definition.unsigned and definition.unsigned[columnName]
      and not actual.columnType:find('unsigned', 1, true) then
      return false, ('schema_invalid:%s:unsigned:%s'):format(tableName, columnName)
    end
    local expectedExtra = definition.extraContains and definition.extraContains[columnName]
    if expectedExtra and not actual.extra:find(expectedExtra, 1, true) then
      return false, ('schema_invalid:%s:extra:%s'):format(tableName, columnName)
    end
  end
  if definition.autoIncrement then
    local actual = actualColumns[definition.autoIncrement]
    if not actual or not actual.extra:find('auto_increment', 1, true) then
      return false, ('schema_invalid:%s:auto_increment:%s'):format(tableName, definition.autoIncrement)
    end
  end

  local indexes = MySQL.query.await([[
    SELECT index_name, non_unique,
           GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ',') AS column_list
    FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = ?
    GROUP BY index_name, non_unique
  ]], { tableName }) or {}
  local actualIndexes = {}
  for _, row in ipairs(indexes) do
    actualIndexes[tostring(row.index_name)] = {
      columns = tostring(row.column_list or ''),
      unique = tonumber(row.non_unique) == 0
    }
  end
  for indexName, columnList in pairs(definition.indexes) do
    local actual = actualIndexes[indexName]
    if not actual or actual.columns ~= columnList then
      return false, ('schema_invalid:%s:index:%s'):format(tableName, indexName)
    end
    if (indexName == 'PRIMARY' or indexName:sub(1, 3) == 'uq_') and not actual.unique then
      return false, ('schema_invalid:%s:index_not_unique:%s'):format(tableName, indexName)
    end
  end
  return true
end

function MZBankMigrations.run()
  status.ready = false
  status.error = 'running'

  if type(MZBankAccountIdentity) ~= 'table'
    or type(MZBankAccountIdentity.ValidateConfiguration) ~= 'function' then
    return fail('public_account_identity_unavailable')
  end
  local configValid, configError = MZBankAccountIdentity.ValidateConfiguration()
  if configValid ~= true then
    return fail(('public_account_config_invalid:%s'):format(tostring(configError or 'unknown')))
  end

  MySQL.query.await(loadSql('sql/000_mz_bank_schema_migrations.sql'))
  local registryValid, registryError = verifyTable('mz_bank_schema_migrations')
  if not registryValid then return fail(registryError) end
  local newest = tonumber(MySQL.scalar.await('SELECT MAX(version) FROM mz_bank_schema_migrations')) or 0
  status.currentVersion = newest
  if newest > EXPECTED_VERSION then
    return fail(('schema_newer_than_resource:%s'):format(newest))
  end

  for _, migration in ipairs(migrations) do
    local applied = MySQL.single.await([[
      SELECT version, name FROM mz_bank_schema_migrations WHERE version = ? LIMIT 1
    ]], { migration.version })
    if applied and tostring(applied.name) ~= migration.name then
      return fail(('migration_version_conflict:%s'):format(migration.version))
    end

    if not applied then
      MySQL.query.await(loadSql(migration.file))
      local valid, validationError = verifyTable(migration.name)
      if not valid then return fail(validationError) end

      local inserted = MySQL.update.await([[
        INSERT IGNORE INTO mz_bank_schema_migrations (version, name) VALUES (?, ?)
      ]], { migration.version, migration.name })
      if tonumber(inserted) ~= 1 then
        local concurrent = MySQL.single.await([[
          SELECT name FROM mz_bank_schema_migrations WHERE version = ? LIMIT 1
        ]], { migration.version })
        if not concurrent or tostring(concurrent.name) ~= migration.name then
          return fail(('migration_registry_write_failed:%s'):format(migration.version))
        end
      end
    else
      local valid, validationError = verifyTable(migration.name)
      if not valid then return fail(validationError) end
    end
    status.currentVersion = migration.version
  end

  local finalVersion = tonumber(MySQL.scalar.await('SELECT MAX(version) FROM mz_bank_schema_migrations')) or 0
  if finalVersion ~= EXPECTED_VERSION then
    return fail(('migration_version_mismatch:%s:%s'):format(finalVersion, EXPECTED_VERSION))
  end

  status.ready = true
  status.currentVersion = finalVersion
  status.error = nil
  return true, copyStatus()
end

function MZBankMigrations.getStatus()
  return copyStatus()
end
