#include "luartos.h"

#include "lua.h"
#include "lauxlib.h"
#include "modules.h"

typedef struct {
	int uart_num;
} ppp_user_data_t;

static int pppos_step( lua_State* L ) {

    driver_error_t *error;
    // Allocate userdata
    ppp_user_data_t *user_data = (ppp_user_data_t *)lua_newuserdata(L, sizeof(ppp_user_data_t));
    if (!user_data) {
       	return luaL_exception(L, 1);
    }

    user_data->uart_num = 2;

    luaL_getmetatable(L, "ppp.trans");
    lua_setmetatable(L, -2);

    return 1;
}

// Destructor
static int pppos_trans_gc (lua_State *L) {
	ppp_user_data_t *user_data = NULL;

    user_data = (ppp_user_data_t *)luaL_testudata(L, 1, "ppp.trans");
    if (user_data) {
    }

    return 0;
}

static const LUA_REG_TYPE pppos_map[] = {
    { LSTRKEY( "step" ), LFUNCVAL( pppos_step ) },
    { LNILKEY, LNILVAL }
};


//inst map
static const LUA_REG_TYPE pppos_trans_map[] = {
    { LSTRKEY( "__metatable" ),  	LROVAL  ( pppos_trans_map ) },
	{ LSTRKEY( "__index"     ),   	LROVAL  ( pppos_trans_map ) },
	{ LSTRKEY( "__gc"        ),   	LFUNCVAL  ( pppos_trans_gc ) },
    { LNILKEY, LNILVAL}
};

LUALIB_API int luaopen_ppp( lua_State *L ) {
    luaL_newmetarotable(L,"ppp.trans", (void *)pppos_trans_map);
    return 0;
}

MODULE_REGISTER_MAPPED(PPP, ppp, pppos_map, luaopen_ppp);