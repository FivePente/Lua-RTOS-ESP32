/*
 * pppos
 */
#include "luartos.h"

//#if CONFIG_LUA_RTOS_LUA_USE_PPP

#include "lua.h"
#include "error.h"
#include "lauxlib.h"
#include "modules.h"
#include "platform.h"
#include <stdlib.h>
#include <string.h>
#include "uart.h"


static int pppos_task_step(lua_State* L){
    //tcpip_adapter_init();
    //xTaskCreate(&pppos_client_task, "pppos_client_task", 2048, NULL, 5, NULL); 
    return 0;
}

//class map
static const LUA_REG_TYPE pppos_map[] = {
    { LSTRKEY( "step" ),  LFUNCVAL( pppos_task_step )},
    { LNILKEY, LNILVAL }
};


LUALIB_API int luaopen_pppos( lua_State *L ) {
#if !LUA_USE_ROTABLE
    luaL_newlib(L, pppos_map);
    return 1;
#else
	return 0;
#endif
}

MODULE_REGISTER_MAPPED(PPPOS, pppos, pppos_map, luaopen_pppos);
//#endif