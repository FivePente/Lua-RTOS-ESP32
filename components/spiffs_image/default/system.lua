os.loglevel(os.LOG_INFO)   -- Log level to info
os.logcons(true)           -- Enable/disable sys log messages to console
os.shell(true)             -- Enable/disable shell
os.history(false)          -- Enable/disable history

netConnected = 0
mqttConnected = 0
sensorInited = 0
initFlag = 0

msgQueue = adxl345.initQueue()

--0 wifi  1 uart DTU 2 lora
local netMode = 0

led_pin = pio.GPIO27
pio.pin.setdir(pio.OUTPUT, led_pin)

function systemLed()

    while true do
        if netConnected == 0 then
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
    mqttClient:subscribe("initConfig", mqtt.QOS2, function(len , message)
        initFlag = 1
        if message ~= nil and message ~= "" then
            assert(load(message))()
        end
    end)
end

function sendData()
    if mqttConnected == 1 then
        local d , x , y , w , t = msgQueue:receive()
        if t ~= 0 then
            print("send....")
            local str = string.format('{"d":%0.2f, "x":%0.2f , "y":%0.2f , "w":%0.2f , "t":%d}' , d , x , y , w ,t)
            client:publish("/free/test", str , 0)
        end
    end
end

function startupMqtt()
    while true do
        if netConnected == 1 then
            net.service.sntp.start()
            print("start connection mqtt")
            client = mqtt.client("esp32", "60.205.82.208", 1883, false)
            client:setLostCallback(function(msg)
                print(msg)
                mqttConnected = 0
                startupMqtt()
            end)

            try(
                function()
                    client:connect("","" , 30 , 0 , 1)
                    mqttConnected = 1
                    initMainSubscribe(client)
                end,
                function(where,line,error,message)
                    print("connect fail reboot...")
                    os.exit(1)
                end
            )
            break
        end
    end

    while true do
        sendData()
    end
end

thread.start(systemLed)

if netMode == 0 then
    net.wf.scan()
    net.wf.setup(net.wf.mode.STA, "HiWiFi_3B0F16","Freedom0806")
    net.wf.start()
    netConnected = 1
    net.service.sntp.start()

elseif netMode == 1 then
    ppp.setCallback(function (err_code , message)
        print("ppp state: " , message)
        if err_code == 0 then
            netConnected = 1
        else
            netConnected = 0
        end
    end)
    ppp.setupXTask()
end

thread.start(startupMqtt)