fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_bank'
author 'Mazus'
description 'ATM e agencia sobre as contas oficiais do mz_core'
version '2.0.0'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua'
}

client_scripts {
  'client/main.lua',
  'client/interact.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/account_rng.js',
  'bridge/server.lua',
  'server/account_identity.lua',
  'server/migrations.lua',
  'server/repository.lua',
  'server/account_service.lua',
  'server/account_resolution.lua',
  'server/account_backfill.lua',
  'server/service.lua',
  'server/legacy.lua',
  'server/main.lua',
  'server/p2b_runtime_runner.lua',
  'server/p2d_runtime_runner.lua',
  'server/p2e_runtime_runner.lua',
  'server/p2f_runtime_runner.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/script.js',
  'sql/*.sql'
}

dependencies {
  'oxmysql',
  'ox_lib',
  'mz_core',
  'mz_inventory'
}
