/*
 * Driver for Analog Devices ADXL345 accelerometer.
 *
 * Code based on BMP085 driver.
 */
#include "luartos.h"

#if CONFIG_LUA_RTOS_LUA_USE_ADXL345

#include "modules.h"
#include "lua.h"
#include "i2c.h"
#include "driver/i2c.h"
#include <drivers/i2c.h>
#include "error.h"
#include "lauxlib.h"
#include "platform.h"
#include <stdlib.h>
#include <string.h>
#include "freertos/queue.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"


static const uint8_t adxl345_i2c_addr = 0x53;

typedef struct {
	int unit;
	int transaction;
    char *data;
} adxl345_user_data_t;

typedef struct {
	xQueueHandle msgQueue;
} x_queue_t;

typedef struct {
	float d;
    float x;
    float y;
    float w;
    uint t;
} x_queue_msg_t;

static int adxl345_init(lua_State* L) {

    driver_error_t *error;

    int id = luaL_checkinteger(L, 1);
    int mode = luaL_checkinteger(L, 2);
    int speed = luaL_checkinteger(L, 3);
    int sda = luaL_checkinteger(L, 4);
    int scl = luaL_checkinteger(L, 5);

    error = i2c_check(id);

    if (error != NULL){
        if ((error = i2c_setup(id, mode, speed, sda, scl, 0, 0))) {
            printf ("error 1\n");
            return luaL_driver_error(L, error);
        }
    }
    // Allocate userdata
    adxl345_user_data_t *user_data = (adxl345_user_data_t *)lua_newuserdata(L, sizeof(adxl345_user_data_t));
    if (!user_data) {
       	return luaL_exception(L, I2C_ERR_NOT_ENOUGH_MEMORY);
    }

    user_data->unit = id;
    user_data->transaction = I2C_TRANSACTION_INITIALIZER;
    user_data->data = (char*)malloc(6);

    luaL_getmetatable(L, "adxl345.trans");
    lua_setmetatable(L, -2);

    return 1;
}

static int adxl345_init_xQueue(lua_State* L){
    x_queue_t *user_data = (x_queue_t *)lua_newuserdata(L, sizeof(x_queue_t));
    user_data->msgQueue = xQueueCreate(3 , sizeof(x_queue_msg_t));  

    luaL_getmetatable(L, "adxl345.queue");
    lua_setmetatable(L, -2);

    return 1;
}

static int queue_send(lua_State* L){

	x_queue_t *user_data;
    x_queue_msg_t msg;

	// Get user data
	user_data = (x_queue_t *)luaL_checkudata(L, 1, "adxl345.queue");
    luaL_argcheck(L, user_data, 1, "adxl345 transaction expected");

    msg.d = luaL_checknumber(L, 2);
    msg.x = luaL_checknumber(L, 3);
    msg.y = luaL_checknumber(L, 4);
    msg.w = luaL_checknumber(L, 5);
    msg.t = luaL_checkinteger(L, 6);
    xQueueSend( user_data->msgQueue, &msg, 100/portTICK_RATE_MS );  
    return 0;
}

static int queue_receive(lua_State* L){

	x_queue_t *user_data;

	// Get user data
	user_data = (x_queue_t *)luaL_checkudata(L, 1, "adxl345.queue");
    luaL_argcheck(L, user_data, 1, "adxl345 transaction expected");

    x_queue_msg_t msg;

    if (xQueueReceive( user_data->msgQueue, &msg , 100/portTICK_RATE_MS ) == pdPASS){
        lua_pushnumber(L, msg.d);
        lua_pushnumber(L, msg.x);
        lua_pushnumber(L, msg.y);
        lua_pushnumber(L, msg.w);
        lua_pushinteger(L, msg.t);
    }else{
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
    }
    return 5;
}

static int adxl345_writeReg(lua_State* L) {

    driver_error_t *error;
	adxl345_user_data_t *user_data;

	// Get user data
	user_data = (adxl345_user_data_t *)luaL_checkudata(L, 1, "adxl345.trans");
    luaL_argcheck(L, user_data, 1, "adxl345 transaction expected");

    char reg_addr = (char)(luaL_checkinteger(L, 2) & 0xff);
    char value = (char)(luaL_checkinteger(L, 3) & 0xff);

    // Enable sensor
    if ((error = i2c_start(user_data->unit, &user_data->transaction))) {
    	return luaL_driver_error(L, error);
    }

	if ((error = i2c_write_address(user_data->unit, &user_data->transaction, adxl345_i2c_addr, false))) {
    	return luaL_driver_error(L, error);
    }

    if ((error = i2c_write(user_data->unit, &user_data->transaction, &reg_addr , sizeof(reg_addr)))) {
    	return luaL_driver_error(L, error);
    }
    if ((error = i2c_write(user_data->unit, &user_data->transaction, &value , sizeof(value)))) {
    	return luaL_driver_error(L, error);
    }

    if ((error = i2c_stop(user_data->unit, &user_data->transaction))) {
    	return luaL_driver_error(L, error);
    }
    return 0;
}



static int adxl345_read(lua_State* L) {

    driver_error_t *error;
	adxl345_user_data_t *user_data;

	// Get user data
	user_data = (adxl345_user_data_t *)luaL_checkudata(L, 1, "adxl345.trans");
    luaL_argcheck(L, user_data, 1, "adxl345 transaction expected");

    int x,y,z;
    char start_addr = 0x32;

    if ((error = i2c_start(user_data->unit, &user_data->transaction))) {
        printf("adxl345 read error 1\n");
    	return luaL_driver_error(L, error);
    }

	if ((error = i2c_write_address(user_data->unit, &user_data->transaction, adxl345_i2c_addr, false))) {
        printf("adxl345 read error 2\n");
    	return luaL_driver_error(L, error);
    }

    if ((error = i2c_write(user_data->unit, &user_data->transaction, &start_addr , sizeof(uint8_t)))) {
    	printf("adxl345 read error 3\n");
        return luaL_driver_error(L, error);
    }

    if ((error = i2c_start(user_data->unit, &user_data->transaction))) {
    	printf("adxl345 read error 4\n");
        return luaL_driver_error(L, error);
    }

	if ((error = i2c_write_address(user_data->unit, &user_data->transaction, adxl345_i2c_addr, true))) {
    	printf("adxl345 read error 5\n");
        return luaL_driver_error(L, error);
    }

    if ((error = i2c_read(user_data->unit, &user_data->transaction, user_data->data, 6))) {
        printf("adxl345 read error6\n");
    	return luaL_driver_error(L, error);
    }

    // We need to flush because we need to return reaad data now
    //if ((error = i2c_flush(user_data->unit, &user_data->transaction, 1))) {
        //return luaL_driver_error(L, error);
    ///}

    if ((error = i2c_stop(user_data->unit, &user_data->transaction))) {
        printf("adxl345 read error7\n");
    	return luaL_driver_error(L, error);
    }

    x = (int16_t) ((user_data->data[1] << 8) | user_data->data[0]);
    y = (int16_t) ((user_data->data[3] << 8) | user_data->data[2]);
    z = (int16_t) ((user_data->data[5] << 8) | user_data->data[4]);

    lua_pushinteger(L, x);
    lua_pushinteger(L, y);
    lua_pushinteger(L, z);

    return 3;
}

static int adxl345_close(lua_State* L) {
    driver_error_t *error;
	adxl345_user_data_t *user_data;

	// Get user data
	user_data = (adxl345_user_data_t *)luaL_checkudata(L, 1, "adxl345.trans");
    luaL_argcheck(L, user_data, 1, "adxl345 transaction expected");

    if ((error = i2c_close(user_data->unit))) {
    	return luaL_driver_error(L, error);
    }

    return 0;
}

static int adxl345_trans_gc (lua_State *L) {
	adxl345_user_data_t *user_data = NULL;

    user_data = (adxl345_user_data_t *)luaL_testudata(L, 1, "adxl345.trans");
    if (user_data) {
        free(user_data->data);
    }
    return 0;
}

static int adxl345_queue_gc (lua_State *L) {
	x_queue_t *user_data = NULL;

    user_data = (x_queue_t *)luaL_testudata(L, 1, "adxl345.queue");
    if (user_data) {
        free(user_data->msgQueue);
    }
    return 0;
}

//class map
//test
static const LUA_REG_TYPE adxl345_map[] = {
    { LSTRKEY( "init" ), LFUNCVAL( adxl345_init )},
    { LSTRKEY( "initQueue" ), LFUNCVAL( adxl345_init_xQueue )},
    { LNILKEY, LNILVAL }
};

//inst map
static const LUA_REG_TYPE adxl345_trans_map[] = {
    { LSTRKEY( "read" ),            LFUNCVAL( adxl345_read )},
    { LSTRKEY( "write" ),            LFUNCVAL( adxl345_writeReg )},
    { LSTRKEY( "close" ),            LFUNCVAL( adxl345_close )},
    { LSTRKEY( "__metatable" ),  	LROVAL  ( adxl345_trans_map ) },
	{ LSTRKEY( "__index"     ),   	LROVAL  ( adxl345_trans_map ) },
	{ LSTRKEY( "__gc"        ),   	LFUNCVAL  ( adxl345_trans_gc ) },
    { LNILKEY, LNILVAL}
};

//inst map
static const LUA_REG_TYPE adxl345_queue_map[] = {
    { LSTRKEY( "send" ),            LFUNCVAL( queue_send )},
    { LSTRKEY( "receive" ),            LFUNCVAL( queue_receive )},
    { LSTRKEY( "__metatable" ),  	LROVAL  ( adxl345_queue_map ) },
	{ LSTRKEY( "__index"     ),   	LROVAL  ( adxl345_queue_map ) },
	{ LSTRKEY( "__gc"        ),   	LFUNCVAL  ( adxl345_queue_gc ) },
    { LNILKEY, LNILVAL}
};


LUALIB_API int luaopen_adxl345( lua_State *L ) {
    luaL_newmetarotable(L,"adxl345.trans", (void *)adxl345_trans_map);
    luaL_newmetarotable(L,"adxl345.queue", (void *)adxl345_queue_map);
    return 0;
}
MODULE_REGISTER_MAPPED(ADXL345, adxl345, adxl345_map, luaopen_adxl345);
#endif