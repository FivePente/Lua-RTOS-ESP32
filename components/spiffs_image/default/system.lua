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

mqttConnectTry = 0
pppConnected = 0
watchTime = 0

mqttConnected = 0
updateCode = 0
sensorInited = 0
dogTime = 120
startup = 0
initConfigFlag = 0
useNet = 1

local useGSM = 1
local useWIFI = 0

function systemLed()
    local led_pin = pio.GPIO27
    pio.pin.setdir(pio.OUTPUT, led_pin)

    while true do
        if pppConnected == 0 then
            pio.pin.sethigh(led_pin)
            thread.sleepms(30)
            pio.pin.setlow(led_pin)
            thread.sleepms(500)
        elseif mqttConnected == 0 then
            pio.pin.sethigh(led_pin)
            thread.sleepms(30)
            pio.pin.setlow(led_pin)
            thread.sleepms(1000)
        elseif sensorInited == 0 then
            pio.pin.sethigh(led_pin)
            thread.sleepms(30)
            pio.pin.setlow(led_pin)
            thread.sleepms(2000)
        end
    end
end

function systemDog()
    while true do
        if os.clock() - watchTime > dogTime then
            print("system dog reboot...")
            os.exit(1)
        end
    end
end

function runDevice()
    print("empty autorun.lua")
end

function initConfig()
    print("initConfig function empty")
end

function initMainSubscribe(mqttClient)
    mqttClient:subscribe("code", mqtt.QOS2, function(len, message)
        local file2 = io.open("autorun.lua","w+")
        file2:write(message)
        file2:close()
        os.exit(0)
    end)
    mqttClient:subscribe("initConfig", mqtt.QOS2, function(len, message)
        --initConfig()
        initConfigFlag = 1
        if message ~= nil and message ~= "" then
            assert(load(message))()
        end
    end)
end

function sendData(topic , message , qos)
    if mqttConnected == 1 then
        client:publish(topic, message , qos)
        watchTime = os.clock()
    end
end

function startTask()
    print("start connection mqtt")
    local err = 0
    client = mqtt.client("esp32", "60.205.82.208", 1883, false)
    client:setLostCallback(function(msg)
        print(msg)
        mqttConnected = 0
    end)

    try(
        function()
            client:connect("","" , 30 , 0 , 1)
            mqttConnected = 1
            initMainSubscribe(client)

            if inited == 0 then
                inited = 1
                watchTime = os.clock()
            end
        end,
        function(where,line,error,message)
            print(message)
            mqttConnectTry = mqttConnectTry + 1
            if mqttConnectTry < 2 then
                print("connect fail , trying again...")
                thread.sleepms(3000)
                startTask()
            else
                print("connect fail , reboot...")
                thread.sleepms(1000)
                os.exit(1)
            end
        end
    )
end

function initNet()
    if useWIFI == 1 then
        net.wf.scan()
        net.wf.setup(net.wf.mode.STA, "wifi","password")
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
end

thread.start(systemLed)
thread.start(systemDog)

if useNet == 1 then
    initNet()
    while true do
        if pppConnected == 1 then
            net.service.sntp.start()
            --net.service.sntp.stop()
            startTask()
            break
        end
    end
end