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
local mqttConnected = 0
local inited = 0

dis = 0
x = 0
y = 0
z = 0
xAngle = 0
yAngle = 0

--distance threshold
dTH = 0.00

--x angle threshold
xATH = 0.00

--y angle threshold
yATH = 0.00

dOut = 0
xOut = 0
yOut = 0

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
        mqttConnected = 0
        client:disconnect()
        print(msg)
        tmr.delayms(1000)
        startTask()
    end)

    err = client:connect("","" , 30 , 0 , 1)

    if err == nil then
        mqttConnected = 1
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

function initI2C() 

end

check = function()
        --[[
        cd = adxl345.init(i2c.I2C0 , i2c.MASTER , 400 , pio.GPIO18 , pio.GPIO19)
        cd:write(0x2D , 0x08)
        cd:write(0x31 , 0x2B)
        cd:write(0x2C , 0x08)
        ad = vl53l0x.init(i2c.I2C0 , i2c.MASTER , 400 , 0x29 , pio.GPIO18 , pio.GPIO19)
        ad:startRanging(2)

        tmr.delayms(500)
        
        t = 0
        c = 0
        m = 1

        local xt = 0
        local yt = 0
        local zt = 0
        local odis = 0
        local ldis = {}
        local tdis = 0

        while(true) do]]
                if t > 30 then
                        t = 0
                        ldis[m] = ad:getDistance()

                        m = m + 1
                        if m == 14 then
                           m = 1
                           table.sort(ldis)
                           print(table.concat(ldis, ", "))

                           for i= 3, 12 do
                              tdis = tdis + ldis[i]
                           end

                           odis = tdis / 10.00
                           if dis == 0 then
                                dis = odis
                           end
                           tdis = 0
                        end
                end

                t = t + 1
                x ,y , z = cd:read()

                xt = xt + x
                yt = yt + y
                zt = zt + z

                c = c + 1

                if c == 10 then

                        c = 0

                        x = xt / 10
                        y = yt / 10
                        z = zt / 10

                        xt = 0
                        yt = 0
                        zt = 0

                        local ox = getXAngle(x , y , z)
                        local oy = getYAngle(x , y , z)

                        if xAngle == 0 then
                                xAngle = ox
                                yAngle = oy
                        end

                        if math.abs(xAngle - ox) >= xATH then
                                xOut = xAngle - ox
                        else
                                xOut = 0
                        end

                        if math.abs(yAngle - oy) >= yATH then
                                yOut = yAngle - oy
                        else
                                yOut = 0
                        end  

                        if math.abs(odis - dis) >= dTH then
                                dOut = odis - dis
                        else
                                dOut = 0
                        end  

                        print(string.format("dis %0.2f, x %0.2f , y %0.2f" , odis - dis , xOut , yOut))
                end
        --end
end

function getXAngle(x , y , z)
        local tmp = x / math.sqrt(y*y + z*z)
        local res = math.atan(tmp)
        return math.deg(res)-- * 180 / 3.1415926
end

function getYAngle(x , y , z)
        local tmp = y / math.sqrt(x*x + z*z)
        local res = math.atan(tmp)
        return math.deg(res) --res * 180 / 3.1415926
end

t = 0
c = 0
m = 1

xt = 0
yt = 0
zt = 0
odis = 0
ldis = {}
tdis = 0

while true do
    if pppConnected == 1 then
        if inited == 0 then
            inited = 1

            cd = adxl345.init(i2c.I2C0 , i2c.MASTER , 400 , pio.GPIO18 , pio.GPIO19)
            cd:write(0x2D , 0x08)
            cd:write(0x31 , 0x2B)
            cd:write(0x2C , 0x08)
            ad = vl53l0x.init(i2c.I2C0 , i2c.MASTER , 400 , 0x29 , pio.GPIO18 , pio.GPIO19)
            ad:startRanging(2)

            tmr.delayms(500)

            thread.start(check)
            startTask()
        end

        if mqttConnected == 1 then
                if t > 30 then
                        t = 0
                        ldis[m] = ad:getDistance()

                        m = m + 1
                        if m == 14 then
                           m = 1
                           table.sort(ldis)
                           print(table.concat(ldis, ", "))

                           for i= 3, 12 do
                              tdis = tdis + ldis[i]
                           end

                           odis = tdis / 10.00
                           if dis == 0 then
                                dis = odis
                           end
                           tdis = 0
                        end
                end

                t = t + 1
                x ,y , z = cd:read()

                xt = xt + x
                yt = yt + y
                zt = zt + z

                c = c + 1

                if c == 10 then

                        c = 0

                        x = xt / 10
                        y = yt / 10
                        z = zt / 10

                        xt = 0
                        yt = 0
                        zt = 0

                        local ox = getXAngle(x , y , z)
                        local oy = getYAngle(x , y , z)

                        if xAngle == 0 then
                                xAngle = ox
                                yAngle = oy
                        end

                        if math.abs(xAngle - ox) >= xATH then
                                xOut = xAngle - ox
                        else
                                xOut = 0
                        end

                        if math.abs(yAngle - oy) >= yATH then
                                yOut = yAngle - oy
                        else
                                yOut = 0
                        end  

                        if math.abs(odis - dis) >= dTH then
                                dOut = odis - dis
                        else
                                dOut = 0
                        end  

                        print(string.format("dis %0.2f, x %0.2f , y %0.2f" , odis - dis , xOut , yOut))
                end
            client:publish("data", string.format('{"dis":%0.2f, "x":%0.2f , "y":%0.2f}' , dOut , xOut , yOut) ,mqtt.QOS0) 
            tmr.delayms(10000)
        end
    end
end