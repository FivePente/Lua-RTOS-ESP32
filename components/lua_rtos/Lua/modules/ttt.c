#include "luartos.h"

#if CONFIG_LUA_RTOS_LUA_USE_TMR

#include "lua.h"
#include "lauxlib.h"
#include "modules.h"

#include <unistd.h>
#include <sys/delay.h>

static int ttt_sleep_us( lua_State* L ) {
    unsigned long long period;

    period = luaL_checkinteger( L, 1 );
    usleep(period);
    
    return 0;
}

static const LUA_REG_TYPE ttt_map[] = {
    { LSTRKEY( "delay" ),			LFUNCVAL( ttt_sleep_us ) },
    { LNILKEY, LNILVAL }
};

LUALIB_API int luaopen_ttt( lua_State *L ) {
#if !LUA_USE_ROTABLE
    luaL_newlib(L, ttt_map);

    return 1;
#else
	return 0;
#endif
}

MODULE_REGISTER_MAPPED(TTT, ttt, ttt_map, luaopen_ttt);

#endif
