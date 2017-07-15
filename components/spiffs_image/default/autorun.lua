local ver = 1.0

nan = 0

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
angleAlarmExceed = 3
tmpAlarmExceed = 3

disAlarmOn = 0
angleAlarmOn = 0
tmpAlarmOn = 0

disExceedCount = 0
angleXExceedCount = 0
angleYExceedCount = 0
tmpExceedCount = 0

hTmpAlarm = 60
lTmpAlarm = -20

hDisAlarm = 1
lDisAlarm = -1

hXAlarm = 0.03
lXAlarm = -0.03

hYAlarm = 0.03
lYAlarm = -0.03

temperature = 0
maxTemp = 50
minTemp = -15

function initI2C() 

    s1 = sensor.attach("DS1820", pio.GPIO21, 0x28ff900f, 0xb316041a)
    s1:set("resolution", 10)

    cd = adxl345.init(i2c.I2C0 , i2c.MASTER , 100 , pio.GPIO18 , pio.GPIO19)
    cd:write(0x2D , 0x08)
    cd:write(0x31 , 0x28)
    cd:write(0x2C , 0x0C)

    ad = vl53l0x.init(i2c.I2C0 , i2c.MASTER , 100 , 0x29 , pio.GPIO18 , pio.GPIO19)
    ad:startRanging(2)

    sensorInited = 1
end

function restart()
    if ad ~= nil then
        ad:stopRanging()
    end
    os.exit(1)
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

            for i= 2, 13 do
                tdis = tdis + ldis[i]
            end

            disOut = tdis / 12
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

        tX = 0
        tY = 0

        for i= 3, 12 do
            tX = tX + xList[i]
            tY = tY + yList[i]
        end

        xOutCount = xOutCount + tX / 10
        yOutCount = yOutCount + tY / 10

        indexCount = indexCount + 10
        indexA = 0
    end
end

function checkAngleP()
    xOut = xOutCount / indexCount
    yOut = yOutCount / indexCount

    print("angle count "..indexCount)

    indexA = 0
    xOutCount = 0
    yOutCount = 0
    indexCount = 0

    if startX == 0 or startX == nil then
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
    
    print(string.format("dis %0.2f, x %0.3f , y %0.3f , tmp %0.2f" , disOut - startDis , xOut - startX , yOut - startY , temperature))
end

function getXAngle(x , y , z)
    local tmp = x / math.sqrt(y*y + z*z)
    local res = math.atan(tmp)
    return res * 180 / 3.1415926
end

function getYAngle(x , y , z)
    local tmp = y / math.sqrt(x*x + z*z)
    local res = math.atan(tmp)
    return res * 180 / 3.1415926
end

function cutNumber(v)
    local x,y = math.modf(v * 100)
    print("y....."..math.abs(y))
    if math.abs(y) > 0.75 then
        if x >= 0 then
            x = x + 1
        elseif x < 0 then
            x = x - 1
        end
    end

    return x / 100
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

    local timer = os.clock()
    watchTime = timer
    while true do
        if pppConnected == 1 then
            if mqttConnected == 1 then
                checkAngle()
                if os.clock() - timer >= 10 then
                    checkAll()
                    timer = os.clock()
                    try(
                        function()

                            local disOffset = disOut - startDis
                            local tAlarm = '{'

                            if disOffset > hDisAlarm or disOffset < lDisAlarm then
                                disExceedCount = disExceedCount + 1
                            else
                                disExceedCount = 0
                            end

                            if disExceedCount >= disAlarmExceed then
                                tAlarm = tAlarm..string.format('"d":%0.2f , ', disOffset)
                            end

                            local xAngleOffset = xOut - startX

                            if xAngleOffset > hXAlarm or xAngleOffset < lXAlarm then
                                angleXExceedCount = angleXExceedCount + 1
                            else
                                angleXExceedCount = 0
                            end

                            if angleXExceedCount >= angleAlarmExceed then
                                tAlarm = tAlarm..string.format('"x":%0.2f , ', xAngleOffset)
                            end                        

                            local yAngleOffset = yOut - startY

                            if yAngleOffset > hYAlarm or yAngleOffset < lYAlarm then
                                angleYExceedCount = angleYExceedCount + 1
                            else
                                angleYExceedCount = 0
                            end

                            if angleYExceedCount >= angleAlarmExceed then
                                tAlarm = tAlarm..string.format('"y":%0.2f , ', yAngleOffset)
                            end  

                            if temperature > hTmpAlarm or temperature < lTmpAlarm then
                                tmpExceedCount = tmpExceedCount + 1
                            else
                                tmpExceedCount = 0
                            end

                            if tmpExceedCount >= tmpAlarmExceed then
                                tAlarm = tAlarm..string.format('"w":%0.2f , ', temperature)
                            end

                            if #tAlarm > 2 then
                                sendData("alarm" , tAlarm..string.format('"t":%d}', os.time()) , mqtt.QOS1)
                            end

                            print(xAngleOffset.."   "..yAngleOffset)

                            sendData("data", string.format('{"d":%0.2f, "x":%0.2f , "y":%0.2f , "w":%0.2f , "t":%d}' , disOffset , cutNumber(xAngleOffset) , cutNumber(yAngleOffset) , temperature, os.time()) ,mqtt.QOS0)

                            pio.pin.sethigh(led_pin)
                            tmr.delayms(30)
                            pio.pin.setlow(led_pin)
                            watchTime = os.clock()
                        end,

                        function(where,line,error,message)
                            print("error "..message.." line:"..line)
                            --mqttConnected = 0
                            restart()
                        end
                    )
                end

            else
                print("mqtt disconnected...")
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