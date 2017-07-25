
#include "luartos.h"

#if CONFIG_LUA_RTOS_LUA_USE_ADXL345

#include "modules.h"
#include "lua.h"
#include "error.h"
#include "lauxlib.h"
#include "platform.h"
#include <stdlib.h>
#include <string.h>
#include "freertos/queue.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

typedef struct {
	xQueueHandle msgQueue;
} x_queue_t;

static int init_xQueue(lua_State* L){
    x_queue_t *user_data = (x_queue_t *)lua_newuserdata(L, sizeof(x_queue_t));
    user_data->msgQueue = xQueueCreate(3 , sizeof(char) * 50);  

    luaL_getmetatable(L, "queue.tran");
    lua_setmetatable(L, -2);

    return 1;
}

static int queue_send(lua_State* L){

	x_queue_t *user_data;

	// Get user data
	user_data = (x_queue_t *)luaL_checkudata(L, 1, "queue.tran");
    luaL_argcheck(L, user_data, 1, "queue transaction expected");

    const char *msg = luaL_checkstring( L, 2 );
    xQueueSend( user_data->msgQueue, msg, 0 );  
    return 0;
}

static int queue_receive(lua_State* L){

	x_queue_t *user_data;

	// Get user data
	user_data = (x_queue_t *)luaL_checkudata(L, 1, "queue.tran");
    luaL_argcheck(L, user_data, 1, "queue transaction expected");

    char luaMsg;

    if (xQueueReceive( user_data->msgQueue, &luaMsg , 100/portTICK_RATE_MS ) == pdPASS){
        lua_pushstring(L, &luaMsg);
    }else{
        lua_pushnil(L);
    }
    return 1;
}

static int queue_gc (lua_State *L) {
	x_queue_t *user_data = NULL;

    user_data = (x_queue_t *)luaL_testudata(L, 1, "queue.tran");
    if (user_data) {
        free(user_data->msgQueue);
    }
    return 0;
}

//class map
static const LUA_REG_TYPE queue_map[] = {
    { LSTRKEY( "init" ), LFUNCVAL( init_xQueue )},
    { LNILKEY, LNILVAL }
};

//inst map
static const LUA_REG_TYPE queue_trans_map[] = {
    { LSTRKEY( "send" ),            LFUNCVAL( queue_send )},
    { LSTRKEY( "receive" ),            LFUNCVAL( queue_receive )},
    { LSTRKEY( "__metatable" ),  	LROVAL  ( queue_trans_map ) },
	{ LSTRKEY( "__index"     ),   	LROVAL  ( queue_trans_map ) },
	{ LSTRKEY( "__gc"        ),   	LFUNCVAL  ( queue_gc ) },
    { LNILKEY, LNILVAL}
};


LUALIB_API int luaopen_queue( lua_State *L ) {
    luaL_newmetarotable(L,"queue.tran", (void *)queue_map);
    return 0;
}
MODULE_REGISTER_MAPPED(QUEUE, queue, queue_map, luaopen_queue);
#endif