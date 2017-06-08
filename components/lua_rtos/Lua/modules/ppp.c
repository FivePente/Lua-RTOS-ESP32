#include "luartos.h"

#include "lua.h"
#include "lauxlib.h"
#include "modules.h"

#include <unistd.h>
#include <sys/delay.h>

static int pppos_step( lua_State* L ) {
    return 0;
}

static const LUA_REG_TYPE ppp_map[] = {
    { LSTRKEY( "step" ),			LFUNCVAL( pppos_step ) },
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