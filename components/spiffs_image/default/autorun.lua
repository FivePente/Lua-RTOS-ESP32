local ver = 1.0

startX = 0
startY = 0
startDis = 0

disOut = 0
xOut = 0
yOut = 0

disAlarmExceed = 3
angleAlarmExceed = 3
tmpAlarmExceed = 3

disExceedCount = 0
angleXExceedCount = 0
angleYExceedCount = 0
tmpExceedCount = 0

hTmpAlarm = 60
lTmpAlarm = -20

hDisAlarm = 1
lDisAlarm = -1

hXAlarm = 1
lXAlarm = -1

hYAlarm = 1
lYAlarm = -1

temperature = 0

function initI2C() 
    cd = adxl345.init(i2c.I2C0 , i2c.MASTER , 400 , pio.GPIO18 , pio.GPIO19)
    cd:write(0x2D , 0x08)
    cd:write(0x31 , 0x2B)
    cd:write(0x2C , 0x08)
    ad = vl53l0x.init(i2c.I2C0 , i2c.MASTER , 400 , 0x29 , pio.GPIO18 , pio.GPIO19)
    ad:startRanging(2)

    --s1 = sensor.attach("DS1820", pio.GPIO21, 0x28ff900f, 0xb316041a)

    --Configure sensor resolution
    --s1:set("resolution", 10)
end

function saveConfig()
    local file2 = io.open("config.lua","w+")
    file2:write( "startDis="..startDis.." startX="..startX.." startY="..startY )
    file2:close()
    print("save config...")
end

function initConfig()
    checkAll()
    startDis = disOut
    startX = xOut
    startY = yOut
    saveConfig()
end

function checkDistance ()
    local ldis = {}
    local index = 0
    while true do
        ldis[index] = ad:getDistance()
        index = index + 1
        if index == 14 then

            local tdis = 0
            table.sort(ldis)
            print(table.concat(ldis, ", "))

            for i= 3, 12 do
                tdis = tdis + ldis[i]
            end

            disOut = tdis / 10.00
            if startDis == 0 then
                startDis = disOut
                saveConfig()
            end
            break
        end
    end
end

function checkAngle()
    local x , y , z
    local xt = 0
    local yt = 0
    local zt = 0
    local cont = 0
    local index = 0

    while true do

        x , y , z = cd:read()

        xt = xt + x
        yt = yt + y
        zt = zt + z

        index = index + 1

        if index == 10 then

            index = 0

            x = xt / 10
            y = yt / 10
            z = zt / 10

            xOut = getXAngle(x , y , z)
            yOut = getYAngle(x , y , z)

            if startX == 0 then
                startX = xOut
                startY = yOut
                saveConfig()
            end
            break
        end
    end
end

function checkAll()
    checkDistance()
    checkAngle()
    --temperature = s1:read("temperature")
    print(string.format("dis %0.2f, x %0.2f , y %0.2f , tmp %0.2f" , disOut - startDis , xOut - startX , yOut - startY , temperature))
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

function runDevice()

    local loadConfig = false

    local file , err = io.open("config.lua")
    if file ~= nil then
        loadConfig = true
        file:close()
    end

    if loadConfig then
        dofile("config.lua")
        print("load config.lua")
    end

    print("init data startDis:"..startDis.." startX:"..startX.." startY:"..startY)
    
    initI2C()
    tmr.delayms(1000)
    while true do
        if pppConnected == 1 then
            if mqttConnected == 1 then
                checkAll()
                try(
                    function()

                        local disOffset = disOut - startDis

                        if disOffset > hDisAlarm or disOffset < lDisAlarm then
                            disExceedCount = disExceedCount + 1
                        else
                            disExceedCount = 0
                        end

                        if disExceedCount >= disAlarmExceed then
                            sendData("alarm", string.format('{"type":1 , "d":%0.2f}' , disOffset) ,mqtt.QOS1)
                        end

                        local xAngleOffset = xOut - startX 

                        if xAngleOffset > hXAlarm or xAngleOffset < lXAlarm then
                            angleXExceedCount = angleXExceedCount + 1
                        else
                            angleXExceedCount = 0
                        end

                        if angleXExceedCount >= angleAlarmExceed then
                            sendData("alarm", string.format('{"type":2 , "x":%0.2f}' , xAngleOffset) ,mqtt.QOS1)
                        end                        

                        local yAngleOffset = yOut - startY

                        if yAngleOffset > hYAlarm or yAngleOffset < lYAlarm then
                            angleYExceedCount = angleYExceedCount + 1
                        else
                            angleYExceedCount = 0
                        end

                        if angleYExceedCount >= angleAlarmExceed then
                            sendData("alarm", string.format('{"type":3 , "y":%0.2f}' , xAngleOffset) ,mqtt.QOS1)
                        end  

                        if temperature > hTmpAlarm or temperature < lTmpAlarm then
                            tmpExceedCount = tmpExceedCount + 1
                        else
                            tmpExceedCount = 0
                        end

                        if tmpExceedCount >= tmpAlarmExceed then
                            sendData("alarm", string.format('{"type":4 , "tmp":%0.2f}' , temperature) ,mqtt.QOS1)
                        end

                        sendData("data", string.format('{"dis":%0.2f, "x":%0.2f , "y":%0.2f , "tmp":%0.2f}' , disOffset , xAngleOffset , yAngleOffset , temperature) ,mqtt.QOS0)
                        tmr.delayms(10000)
                    end,

                    function(where,line,error,message)
                        print(message)
                        mqttConnected = 0
                    end
                )

            else
                --client:disconnect()
                tmr.delayms(1000)
                startTask()
            end
        else
            print("Network Disconnected...")
            tmr.delayms(3000)
        end
    end
end

thread.start(runDevice)