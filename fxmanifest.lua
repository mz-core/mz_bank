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
  'bridge/server.lua',
  'server/repository.lua',
  'server/service.lua',
  'server/legacy.lua',
  'server/main.lua'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/script.js'
}

dependencies {
  'oxmysql',
  'ox_lib',
  'mz_core'
}
