local ver = 1.0

startX = 0
startY = 0
startDis = 0

disOut = 0
xOut = 0
yOut = 0

xOutCount = 0
yOutCount = 0
indexA = 0

disAlarmExceed = 3
angleAlarmExceed = 6
tmpAlarmExceed = 3

disExceedCount = 0
angleXExceedCount = 0
angleYExceedCount = 0
tmpExceedCount = 0

hTmpAlarm = 60
lTmpAlarm = -20

hDisAlarm = 1
lDisAlarm = -1

hXAlarm = 0.3
lXAlarm = -0.3

hYAlarm = 0.3
lYAlarm = -0.3

temperature = 0
maxTemp = 50
minTemp = -15

function initI2C() 
    cd = adxl345.init(i2c.I2C0 , i2c.MASTER , 400 , pio.GPIO18 , pio.GPIO19)
    cd:write(0x2D , 0x08)
    cd:write(0x31 , 0x28)
    cd:write(0x2C , 0x0C)
    ad = vl53l0x.init(i2c.I2C0 , i2c.MASTER , 400 , 0x29 , pio.GPIO18 , pio.GPIO19)
    ad:startRanging(2)

    s1 = sensor.attach("DS1820", pio.GPIO21, 0x28ff900f, 0xb316041a)

    --Configure sensor resolution
    s1:set("resolution", 10)

    sensorInited = 1
end

function saveConfig()
    local file2 = io.open("config.lua","w+")
    file2:write( "startDis="..startDis.." startX="..startX.." startY="..startY.." tmp="..temperature )
    file2:close()
    print("save config...")
end

function initConfig()
    --checkAll()
    startDis = disOut
    startX = xOut
    startY = yOut
    saveConfig()
end

function checkDistance()

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

xList = {}
yList = {}
indexCount = 0

function checkAngle()
    local x = 0
    local y = 0
    local z = 0
    local FILTER_A = 0.01
    local tX = 0
    local tY = 0

    x, y , z = cd:read()

    tX = getXAngle(x , y , z)
    tY = getYAngle(x , y , z)

    xList[indexA] = tX
    yList[indexA] = tY

    indexA = indexA + 1

    if indexA == 14 then
    
        table.sort(xList)
        table.sort(yList)

        --print(table.concat(xList, ", "))

        tX = 0
        tY = 0

        for i= 3, 12 do
            tX = tX + xList[i]
            tY = tY + yList[i]
        end

        xOutCount = xOutCount + tX / 10.00
        yOutCount = yOutCount + tY / 10.00

        --print(xOutCount)

        indexCount = indexCount + 10
        indexA = 0
        --print(indexCount)
    end


    -- 一阶滞后滤波法
    --xOut = tX * FILTER_A + (1.0 - FILTER_A) * xOut
    --yOut = tY * FILTER_A + (1.0 - FILTER_A) * yOut

    --xOutCount = xOutCount + xOut
    --yOutCount = yOutCount + yOut  
end

function checkAngleP()
    xOut = xOutCount / indexCount
    yOut = yOutCount / indexCount

    indexA = 0
    xOutCount = 0
    yOutCount = 0
    indexCount = 0

    if startX == 0 then
        startX = xOut
        startY = yOut
        saveConfig()
    end
end

function checkAll()
    temperature = s1:read("temperature")
    if temperature > maxTemp or temperature < minTemp then
        sendData("alarm", string.format('{"type":5 , "tmp":%0.2f}' , temperature) ,mqtt.QOS1)
        return
    else
        checkAngleP()
        checkDistance()
    end
    
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
        xOut = startX
        yOut = startY
        print("load config.lua")
    end

    print("init data startDis:"..startDis.." startX:"..startX.." startY:"..startY)
    
    initI2C()
    tmr.delayms(1000)

    local timer = 0
    watchTime = os.clock()
    while true do
        if pppConnected == 1 then
            if mqttConnected == 1 then
                checkAngle()
                if timer == 0 or os.clock() - timer >= 10 then
                    timer = os.clock()
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

                            pio.pin.sethigh(led_pin)
                            tmr.delayms(30)
                            pio.pin.setlow(led_pin)
                            watchTime = os.clock()
                        end,

                        function(where,line,error,message)
                            print(message)
                            mqttConnected = 0
                        end
                    )
                end

            else
                print("mqtt disconnected...")
                --client:disconnect()
                tmr.delayms(1000)
                startTask()
            end
        else
            print("Network disconnected...")
            tmr.delayms(3000)
        end
    end
end

thread.start(runDevice)