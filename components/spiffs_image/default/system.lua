-- system.lua
--
-- This script is executed after a system boot or a system reset and is intended
-- for setup the system.

---------------------------------------------------
-- Main setups
---------------------------------------------------
os.loglevel(os.LOG_INFO)   -- Log level to info
os.logcons(true)           -- Enable/disable sys log messages to console
os.shell(true)             -- Enable/disable shell
os.history(false)          -- Enable/disable history

local useGSM = 1
local useWIFI = 0
local mqttConnectTry = 0
local pppConnected = 0

if useWIFI == 1 then
    net.wf.scan()
    net.wf.setup(net.wf.mode.STA, "HiWiFi_3B0F16","Freedom0806")
    net.wf.start();
end

if useGSM == 1 then
    ppp.setCallback(function (err_code , message)
        print("ppp state: " , message)
        if err_code == 0 then
            pppConnected = 1
        else
            pppConnected = 0;
        end
    end)
    ppp.setupXTask()
end

function initMainSubscribe(mqttClient)
    mqttClient:subscribe("message", mqtt.QOS0, function(len, message)
        print(message)
    end)

    mqttClient:subscribe("code", mqtt.QOS0, function(len, message)
        local file2 = io.open("autorun.lua","w+")
        file2:write(message)
        file2:close()
        os.exit()
    end)  
end

function startTask()
    print("start connection mqtt")
    local err = 0
    client = mqtt.client("esp32", "60.205.82.208", 1883, false)
    client:setLostCallback(function(msg) 
        client:disconnect()
        print(msg)
        tmr.delayms(1000)
        startTask()
    end)

    err = client:connect("","" , 30 , 0 , 1)

    if err == nil then
        initMainSubscribe(client)
    else
        mqttConnectTry = mqttConnectTry + 1
        if mqttConnectTry < 4 then
            print("connect fail , trying again...")
            tmr.delayms(3000)
            client:disconnect()
            startTask()
        else
            print("connect fail , reboot...")
            tmr.delayms(1000)
            os.exit(1)
        end
    end
end




--[[
thread.start(function()
   ppp.step()
end)
