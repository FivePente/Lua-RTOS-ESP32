#include "luartos.h"

#if CONFIG_LUA_RTOS_LUA_USE_PPP

#include "lua.h"
#include "error.h"
#include "lauxlib.h"
#include "modules.h"
#include "platform.h"
#include <stdlib.h>
#include <string.h>
#include "uart.h"

#include <stdio.h>
#include <assert.h>
#include <signal.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event_loop.h"
#include "esp_log.h"
#include "nvs_flash.h"

#include "driver/uart.h"
#include <drivers/uart.h>

#include "netif/ppp/pppos.h"
#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "lwip/netdb.h"
#include "lwip/dns.h"
#include "lwip/pppapi.h"

#include <sys/status.h>

static uint8_t conn_ok = 0;

/* The examples use simple GSM configuration that you can set via
   'make menuconfig'.
 */
#define BUF_SIZE (1024)
// *** If not using hw flow control, set it to 38400
#define UART_BDRATE 115200

#define GSM_OK_Str "OK"


const char *PPP_User = "";
const char *PPP_Pass = "";

// UART
#define UART_GPIO_TX 17
#define UART_GPIO_RX 16

static int uart_num = 2;

// The PPP control block
ppp_pcb *ppp;

// The PPP IP interface
struct netif ppp_netif;

static TaskHandle_t xHandle = NULL;

static lua_State *luaState;

static const char *TAG = "[PPPOS CLIENT]";

static int status_callback_index = -1;

struct mtx callback_mtx;

typedef struct
{
	char *cmd;
	uint16_t cmdSize;
	char *cmdResponseOnOk;
	uint32_t timeoutMs;
	uint32_t delayMs;
}GSM_Cmd;

//--------------------------
GSM_Cmd GSM_MGR_InitCmds[] =
{
		{
				.cmd = "AT\r\n",
				.cmdSize = sizeof("AT\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str,
				.timeoutMs = 300,
		},
		{
				.cmd = "ATZ\r\n",
				.cmdSize = sizeof("ATZ\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str,
				.timeoutMs = 3000,
		},
		{
				.cmd = "ATE0\r\n",
				.cmdSize = sizeof("ATE0\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str,
				.timeoutMs = 300,
		},
		{
				.cmd = "AT+CCID\r\n",
				.cmdSize = sizeof("AT+CCID\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str,
				.timeoutMs = 3000,
		},
		/*
		{
				.cmd = "AT+CFUN=4\r\n",
				.cmdSize = sizeof("ATCFUN=4\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str,
				.timeoutMs = 10000,
		},
		{
				.cmd = "AT+CFUN=1\r\n",
				.cmdSize = sizeof("ATCFUN=1,0\r\n")-1,
				.cmdResponseOnOk = "CINIT: 1, 0, 0",
				.timeoutMs = 10000,
		},*/
		{
				.cmd = "AT+CGCLASS=\"B\"\r\n",
				.cmdSize = sizeof("AT+CGCLASS=\"B\"\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str,
				.timeoutMs = 10000,
		},
		{
				.cmd = "AT+CPIN?\r\n",
				.cmdSize = sizeof("AT+CPIN?\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str, //"CPIN: READY",
				.timeoutMs = 10000,
		},
		{
				.cmd = "AT+CREG?\r\n",
				.cmdSize = sizeof("AT+CREG?\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str, //"CREG: 0,1",
				.timeoutMs = 10000,
		},
		{
				.cmd = "AT+CGDCONT=1,\"IP\",\"cmnet\"\r\n", //playmetric , CMMTM
				.cmdSize = sizeof("AT+CGDCONT=1,\"IP\",\"cmnet\"\r\n")-1,
				.cmdResponseOnOk = GSM_OK_Str,
				.timeoutMs = 10000,
		},
		{
				//.cmd = "AT+CGDATA=\"PPP\",1\r\n",
				//.cmdSize = sizeof("AT+CGDATA=\"PPP\",1\r\n")-1,
				.cmd = "ATDT*99***1#\r\n",
				.cmdSize = sizeof("ATDT*99***1#\r\n")-1,
				//.cmd = "ATD*99***1#\r\n",
				//.cmdSize = sizeof("ATD*99***1#\r\n")-1,
				.cmdResponseOnOk = "CONNECT",
				.timeoutMs = 30000,
		}
};

#define GSM_MGR_InitCmdsSize  (sizeof(GSM_MGR_InitCmds)/sizeof(GSM_Cmd))

void sendStatus(int err_code , char* msg)
{ 
    if(status_callback_index != -1){
		mtx_lock(&callback_mtx);

        lua_rawgeti(luaState, LUA_REGISTRYINDEX, status_callback_index);
        lua_pushinteger(luaState, err_code);
		lua_pushstring(luaState, msg);
        lua_call(luaState, 2, 0);

		mtx_unlock(&callback_mtx);
    }
}


// PPP status callback
//----------------------------------------------------------------
static void ppp_status_cb(ppp_pcb *pcb, int err_code, void *ctx) {
	struct netif *pppif = ppp_netif(pcb);
	LWIP_UNUSED_ARG(ctx);

	switch(err_code) {
	case PPPERR_NONE: {
		ESP_LOGI(TAG,"status_cb: Connected\n");
#if PPP_IPV4_SUPPORT
		ESP_LOGI(TAG,"   ipaddr    = %s\n", ipaddr_ntoa(&pppif->ip_addr));
		ESP_LOGI(TAG,"   gateway   = %s\n", ipaddr_ntoa(&pppif->gw));
		ESP_LOGI(TAG,"   netmask   = %s\n", ipaddr_ntoa(&pppif->netmask));
#endif

#if PPP_IPV6_SUPPORT
		ESP_LOGI(TAG,"   ip6addr   = %s\n", ip6addr_ntoa(netif_ip6_addr(pppif, 0)));
#endif
		conn_ok = 1;
		status_set(STATUS_PPP_CONNECTED);
		sendStatus(err_code , "connected");
		printf("freedom: Connected ipaddr = %s\n" , ipaddr_ntoa(&pppif->ip_addr));
		break;
	}
	case PPPERR_PARAM: {
		sendStatus(err_code , "Invalid parameter");
		ESP_LOGE(TAG,"status_cb: Invalid parameter\n");
		break;
	}
	case PPPERR_OPEN: {
		sendStatus(err_code , "Unable to open PPP session");
		ESP_LOGE(TAG,"status_cb: Unable to open PPP session\n");
		break;
	}
	case PPPERR_DEVICE: {
		sendStatus(err_code , "Invalid I/O device for PPP");
		ESP_LOGE(TAG,"status_cb: Invalid I/O device for PPP\n");
		break;
	}
	case PPPERR_ALLOC: {
		sendStatus(err_code , "Unable to allocate resources");
		ESP_LOGE(TAG,"status_cb: Unable to allocate resources\n");
		break;
	}
	case PPPERR_USER: {
		sendStatus(err_code , "User interrupt");
		ESP_LOGE(TAG,"status_cb: User interrupt\n");
		break;
	}
	case PPPERR_CONNECT: {
		sendStatus(err_code , "Connection lost");
		ESP_LOGE(TAG,"status_cb: Connection lost\n");
		conn_ok = 0;
		status_clear(STATUS_PPP_CONNECTED);
		break;
	}
	case PPPERR_AUTHFAIL: {
		sendStatus(err_code , "Failed authentication challenge");
		ESP_LOGE(TAG,"status_cb: Failed authentication challenge\n");
		break;
	}
	case PPPERR_PROTOCOL: {
		sendStatus(err_code , "Failed to meet protocol");
		ESP_LOGE(TAG,"status_cb: Failed to meet protocol\n");
		break;
	}
	case PPPERR_PEERDEAD: {
		sendStatus(err_code , "Connection timeout");
		ESP_LOGE(TAG,"status_cb: Connection timeout\n");
		break;
	}
	case PPPERR_IDLETIMEOUT: {
		sendStatus(err_code , "Idle Timeout");
		ESP_LOGE(TAG,"status_cb: Idle Timeout\n");
		break;
	}
	case PPPERR_CONNECTTIME: {
		sendStatus(err_code , "Max connect time reached");
		ESP_LOGE(TAG,"status_cb: Max connect time reached\n");
		break;
	}
	case PPPERR_LOOPBACK: {
		sendStatus(err_code , "Loopback detected");
		ESP_LOGE(TAG,"status_cb: Loopback detected\n");
		break;
	}
	default: {
		sendStatus(err_code , "Unknown error code");
		ESP_LOGE(TAG,"status_cb: Unknown error code %d\n", err_code);
		break;
	}
	}

	/*
	 * This should be in the switch case, this is put outside of the switch
	 * case for example readability.
	 */

	if (err_code == PPPERR_NONE) {
		return;
	}

	/* ppp_close() was previously called, don't reconnect */
	if (err_code == PPPERR_USER) {
		/* ppp_free(); -- can be called here */
		return;
	}
}

//--------------------------------------------------------------------------------
static u32_t ppp_output_callback(ppp_pcb *pcb, u8_t *data, u32_t len, void *ctx) {
	// *** Handle sending to GSM modem ***
	uint32_t ret = uart_write_bytes(uart_num, (const char*)data, len);
    uart_wait_tx_done(uart_num, 10 / portTICK_RATE_MS);
    return ret;
}

//-----------------------------
static void pppos_client_task()
{
	uint8_t init_ok = 1;
	int pass = 0;
	char sresp[256] = {'\0'};

    char* data = (char*) malloc(BUF_SIZE);
	
	uart_config_t uart_config = {
			.baud_rate = UART_BDRATE,
			.data_bits = UART_DATA_8_BITS,
			.parity = UART_PARITY_DISABLE,
			.stop_bits = UART_STOP_BITS_1,
			.flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
            .rx_flow_ctrl_thresh = 122,
	};
	//Configure UART1 parameters
	uart_param_config(uart_num, &uart_config);
	//Set UART1 pins(TX, RX, RTS, CTS)
	uart_set_pin(uart_num, UART_GPIO_TX, UART_GPIO_RX, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
	uart_driver_install(uart_num, BUF_SIZE * 2, BUF_SIZE * 2, 0, NULL, 0);

	ESP_LOGI(TAG,"Gsm init start");

	// *** Disconnect if connected ***
	vTaskDelay(1000 / portTICK_PERIOD_MS);
	while (uart_read_bytes(uart_num, (uint8_t*)data, BUF_SIZE, 100 / portTICK_RATE_MS)) {
		vTaskDelay(100 / portTICK_PERIOD_MS);
	}
	uart_write_bytes(uart_num, "+++", 3);
    uart_wait_tx_done(uart_num, 10 / portTICK_RATE_MS);
	vTaskDelay(1000 / portTICK_PERIOD_MS);
    
	conn_ok = 98;
	while(1)
	{
		init_ok = 1;
		// Init gsm
		int gsmCmdIter = 0;
		while(1)
		{
			// ** Send command to GSM
			memset(sresp, 0, 256);
			for (int i=0; i<255;i++) {
				if ((GSM_MGR_InitCmds[gsmCmdIter].cmd[i] >= 0x20) && (GSM_MGR_InitCmds[gsmCmdIter].cmd[i] < 0x80)) {
					sresp[i] = GSM_MGR_InitCmds[gsmCmdIter].cmd[i];
					sresp[i+1] = 0;
				}
				if (GSM_MGR_InitCmds[gsmCmdIter].cmd[i] == 0) break;
			}
			printf("[GSM INIT] >Cmd: [%s]\r\n", sresp);
			vTaskDelay(100 / portTICK_PERIOD_MS);
            
			while (uart_read_bytes(uart_num, (uint8_t*)data, BUF_SIZE, 100 / portTICK_RATE_MS)) {
				vTaskDelay(100 / portTICK_PERIOD_MS);
			}
			uart_write_bytes(uart_num, (const char*)GSM_MGR_InitCmds[gsmCmdIter].cmd,
					GSM_MGR_InitCmds[gsmCmdIter].cmdSize);
            uart_wait_tx_done(uart_num, 10 / portTICK_RATE_MS);

            // ** Wait for and check the response
            int timeoutCnt = 0;
			memset(sresp, 0, 256);
			int idx = 0;
			int tot = 0;
			while(1)
			{
				memset(data, 0, BUF_SIZE);
				int len = 0;
				len = uart_read_bytes(uart_num, (uint8_t*)data, BUF_SIZE, 10 / portTICK_RATE_MS);
				if (len > 0) {
					for (int i=0; i<len;i++) {
						if (idx < 255) {
							if ((data[i] >= 0x20) && (data[i] < 0x80)) {
								sresp[idx++] = data[i];
							}
							else sresp[idx++] = 0x2e;
							sresp[idx] = 0;
						}
					}
					tot += len;
				}
				else {
					if (tot > 0) {
						printf("[GSM INIT] <Resp: [%s], %d\r\n", sresp, tot);
						if (strstr(sresp, GSM_MGR_InitCmds[gsmCmdIter].cmdResponseOnOk) != NULL) {
							break;
						}
						else {
							printf("           Wrong response, expected [%s]\r\n", GSM_MGR_InitCmds[gsmCmdIter].cmdResponseOnOk);
							init_ok = 0;
							break;
						}
					}
				}
				timeoutCnt += 10;

				if (timeoutCnt > GSM_MGR_InitCmds[gsmCmdIter].timeoutMs)
				{
					printf("[GSM INIT] No response, Gsm Init Error\r\n");
					init_ok = 0;
					break;
				}
			}
			if (init_ok == 0) {
				// No response or not as expected
				vTaskDelay(5000 / portTICK_PERIOD_MS);
				init_ok = 1;
				gsmCmdIter = 0;
				continue;
			}

			if (gsmCmdIter == 2) vTaskDelay(500 / portTICK_PERIOD_MS);
			if (gsmCmdIter == 3) vTaskDelay(1500 / portTICK_PERIOD_MS);
			gsmCmdIter++;
			if (gsmCmdIter >= GSM_MGR_InitCmdsSize) break; // All init commands sent
			if ((pass) && (gsmCmdIter == 2)) gsmCmdIter = 4;
			if (gsmCmdIter == 6) pass++;
		}

		ESP_LOGI(TAG,"Gsm init end");

		if (conn_ok == 98) {
			// After first successful initialization
			ppp = pppapi_pppos_create(&ppp_netif,
					ppp_output_callback, ppp_status_cb, NULL);

			ESP_LOGI(TAG,"After pppapi_pppos_create");

			if(ppp == NULL)	{
				ESP_LOGE(TAG, "Error init pppos");
				return;
			}
		}
		conn_ok = 99;
		pppapi_set_default(ppp);
		//pppapi_set_auth(ppp, PPPAUTHTYPE_PAP, PPP_User, PPP_Pass);
		pppapi_set_auth(ppp, PPPAUTHTYPE_NONE, PPP_User, PPP_Pass);
		pppapi_connect(ppp, 0);

		// *** Handle GSM modem responses ***
		while(1) {
			memset(data, 0, BUF_SIZE);
			int len = uart_read_bytes(uart_num, (uint8_t*)data, BUF_SIZE, 30 / portTICK_RATE_MS);
			if(len > 0)	{
				pppos_input_tcpip(ppp, (u8_t*)data, len);
			}
			// Check if disconnected
			if (conn_ok == 0) {
				ESP_LOGE(TAG, "Disconnected, trying again...");
				pppapi_close(ppp, 0);
				gsmCmdIter = 0;
				conn_ok = 89;
				vTaskDelay(1000 / portTICK_PERIOD_MS);
				break;
			}
		}
	}
}

static int ppp_callback(lua_State* L ){
    
    luaL_checktype(L, 1 , LUA_TFUNCTION);
    lua_pushvalue(L, 1); 
    status_callback_index = luaL_ref(L, LUA_REGISTRYINDEX);

    return 0;
}

static int ppp_task_setup(lua_State* L){
	mtx_init(&callback_mtx, NULL, NULL, 0);
    tcpip_adapter_init();
    xTaskCreate(&pppos_client_task, "pppos_client_task", 2048, NULL, 5, &xHandle); 
    return 0;
}

static int ppp_setup(lua_State* L){
    tcpip_adapter_init();
    pppos_client_task();
    return 0;
}

//class map
static const LUA_REG_TYPE ppp_map[] = {
    { LSTRKEY( "setupXTask" ),  LFUNCVAL( ppp_task_setup )},
    { LSTRKEY( "setup" ),  LFUNCVAL( ppp_setup )},
    { LSTRKEY( "setCallback" ),  LFUNCVAL( ppp_callback )},
    { LNILKEY, LNILVAL }
};


LUALIB_API int luaopen_ppp( lua_State *L ) {
	luaState = L;
#if !LUA_USE_ROTABLE
    luaL_newlib(L, ppp_map);
    return 1;
#else
	return 0;
#endif
}

MODULE_REGISTER_MAPPED(PPP, ppp, ppp_map, luaopen_ppp)

#endif