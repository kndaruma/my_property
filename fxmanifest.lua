fx_version 'cerulean'
game 'gta5'

description 'Advanced Property System (Refactored & Optimized)'

-- โหลด Config ก่อนเสมอเพื่อให้ใช้งานได้ทั้ง Server และ Client
shared_scripts {
    'config.lua'
}

-- ไฟล์ฝั่งเซิร์ฟเวอร์
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

-- ไฟล์ฝั่งผู้เล่น
client_scripts {
    'RageUI/src/RMenu.lua',
    'RageUI/src/menu/RageUI.lua',
    'RageUI/src/menu/Menu.lua',
    'RageUI/src/menu/MenuController.lua',
    'RageUI/src/components/*.lua',
    'RageUI/src/menu/elements/*.lua',
    'RageUI/src/menu/items/*.lua',
    'RageUI/src/menu/panels/*.lua',
    'RageUI/src/menu/windows/*.lua',

    'client/placement.lua',     -- โหลดระบบจัดวางก่อน
    'client/client.lua',        -- โหลดระบบ UI หลัก
    'client/client_pedit.lua',  -- ระบบบินจัดบ้าน
    'client/client_lift.lua'    -- ระบบลิฟต์มิติซ้อน
}