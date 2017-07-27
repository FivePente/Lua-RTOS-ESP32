/*
 * Driver for Analog Devices ADXL345 accelerometer.
 *
 * Code based on BMP085 driver.
 */
#include "luartos.h"

#if CONFIG_LUA_RTOS_LUA_USE_ADXL345

#include "modules.h"
#include "lua.h"
#include "error.h"
#include "lauxlib.h"
#include "platform.h"
#include <stdlib.h>
#include <string.h>    

#define MEOW_FFT_IMPLEMENTAION
#include <meow_fft.h>

static int meow_real( lua_State* L ) {

	luaL_checktype(L, 1, LUA_TTABLE);
    int len = luaL_checkinteger(L, 2);

    float*            in  = malloc(sizeof(float) * len);
    Meow_FFT_Complex* out = malloc(sizeof(Meow_FFT_Complex) * len);

    int index = 1;
    while (index <= len) {
        lua_pushnumber(L, index);
        lua_gettable(L, -2);
        in[index - 1] = lua_tonumber(L, -1);
        index++;
    }

    size_t workset_bytes = meow_fft_generate_workset_real(N, NULL);
    Meow_FFT_Workset_Real* fft_real = (Meow_FFT_Workset_Real*) malloc(workset_bytes);
    meow_fft_generate_workset_real(N, fft_real);
    meow_fft_real(fft_real, in, out);

    free(fft_real);
    free(in);

    index = 1;
    while (index <= len) {
        lua_pushnumber(L, index);
        lua_gettable(L, -2);
        in[index - 1] = lua_tonumber(L, -1);
        lua_pop(L, 1); 
        index++;
    }

    lua_settop(L, 1)
    lua_newtable(L);

    for(i=0; i<len; ++i)  
    {  
        lua_pushnumber(L, i+1);  
        lua_pushnumber(L, out[i]);  
        lua_settable(L, -3);  
    } 

    free(out);
    return 1;
}

static const LUA_REG_TYPE meow_map[] = {
    { LSTRKEY( "real"    ),	 LFUNCVAL( meow_real ) },
	{ LNILKEY, LNILVAL }
};

int luaopen_meowFFT(lua_State* L) {
    return 0;
}

MODULE_REGISTER_MAPPED(MEOWFFT, meowFFT, meow_map, luaopen_meowFFT);

#endif