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
watchTime = 0
mqttConnectTry = 0
pppConnected = 0

mqttConnected = 0
updateCode = 0
sensorInited = 0

led_pin = pio.GPIO27
pio.pin.setdir(pio.OUTPUT, led_pin)

function systemDog()
    while true do
        if pppConnected == 0 then
            pio.pin.sethigh(led_pin)
            tmr.delayms(30)
            pio.pin.setlow(led_pin)
            tmr.delayms(500)
        elseif mqttConnected == 0 then
            pio.pin.sethigh(led_pin)
            tmr.delayms(30)
            pio.pin.setlow(led_pin)
            tmr.delayms(1000)
        elseif sensorInited == 0 then
            pio.pin.sethigh(led_pin)
            tmr.delayms(30)
            pio.pin.setlow(led_pin)
            tmr.delayms(2000)
        end
        
        --[[
        if os.clock() - watchTime > 60 then
            print("system dog reboot...")
            os.exit(1)
        end]]
    end
end

thread.start(systemDog)

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
            pppConnected = 0
        end
    end)
    ppp.setupXTask()
end

function runDevice()
    print("empty autorun.lua")
end

function initConfig()
    print("initConfig function empty")
end

function initMainSubscribe(mqttClient)
    mqttClient:subscribe("message", mqtt.QOS0, function(len, message)
        print(message)
    end)

    mqttClient:subscribe("code", mqtt.QOS0, function(len, message)
        updateCode = 1
        tmr.delayms(10)
        local file2 = io.open("autorun.lua","w+")
        file2:write(message)
        file2:close()
        os.exit(0)
    end)
    mqttClient:subscribe("initConfig", mqtt.QOS0, function(len, message)
        updateCode = 1
        initConfig()
        if message ~= nil and message ~= "" then
            assert(load(message))()
        end
    end)  
end

function sendData(topic , message , qos)
    watchTime = os.clock()
    client:publish(topic, message , qos)
end

function startTask()
    print("start connection mqtt")
    local err = 0
    client = mqtt.client("esp32", "60.205.82.208", 1883, false)
    client:setLostCallback(function(msg)
        print(msg)
        mqttConnected = 0
        --client:disconnect()
        --tmr.delayms(1000)
        --startTask()
    end)

    try(
        function()
            client:connect("","" , 30 , 0 , 1)

            mqttConnected = 1
            initMainSubscribe(client)

            if inited == 0 then
                inited = 1
                --runDevice()
            end
        end,
        function(where,line,error,message)
            print(message)
            mqttConnectTry = mqttConnectTry + 1
            if mqttConnectTry < 4 then
                print("connect fail , trying again...")
                tmr.delayms(3000)
                startTask()
            else
                print("connect fail , reboot...")
                tmr.delayms(1000)
                os.exit(1)
            end
        end
    )
end

while true do
    if pppConnected == 1 then
        startTask()
        break
    end
end