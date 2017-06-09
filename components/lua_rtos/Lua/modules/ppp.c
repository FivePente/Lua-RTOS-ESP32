#include "luartos.h"

//#if CONFIG_LUA_RTOS_LUA_USE_PPP

#include "lua.h"
#include "lauxlib.h"
#include "modules.h"
#include <unistd.h>

static int ppp_step( lua_State* L ) {
    return 0;
}

static const LUA_REG_TYPE ppp_map[] = {
    { LSTRKEY( "step" ), LFUNCVAL( ppp_step ) },
    { LNILKEY, LNILVAL }
};

LUALIB_API int luaopen_ppp( lua_State *L ) {
#if !LUA_USE_ROTABLE
    luaL_newlib(L, ppp_map);

    return 1;
#else
	return 0;
#endif
}

MODULE_REGISTER_MAPPED(PPP, ppp, ppp_map, luaopen_ppp);
/*#endif


for key, value in pairs(_G) do      
    print(key)
end*/