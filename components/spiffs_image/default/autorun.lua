startDis = 0
startX = 0
startY = 0

disOut = 0
xOut = 0
yOut = 0

xOutCount = 0
yOutCount = 0
indexA = 1

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

collectionMax = 30
collectionTotal = 100
angleStarted = 0


local ver = 1.0

function initI2C() 

    ad = vl53l0x.init(i2c.I2C0 , i2c.MASTER , 400 , 0x29 , pio.GPIO18 , pio.GPIO19)
    ad:startRanging(2)
    tmr.delayms(10)

    cd = adxl345.init(i2c.I2C0 , i2c.MASTER , 400 , pio.GPIO18 , pio.GPIO19)
    cd:write(0x2D , 0x08)
    cd:write(0x31 , 0x28)
    cd:write(0x2C , 0x0C)

    s1 = sensor.attach("DS1820", pio.GPIO21, 0x28ff900f, 0xb316041a)
    s1:set("resolution", 10)

    tmr.delayms(10)

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
    local index = 1
    local tDis = 0
    while true do
        tDis = ad:getDistance()

        if tDis == -1 then
            print("distance error")
            return
        end

        ldis[index] = tDis
        index = index + 1
        
        if index > 14 then

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

    try(
        function()
            x, y , z  = cd:read()
        end,
        function(where, line, error, message)
            print(message)
            print("read error init I2C")
            sensorInited = 0
            initI2C()
        end
    )

    if err ~= nil then
        print("adxl345 read "..err)
        return
    end

    tX = getXAngle(x , y , z)
    tY = getYAngle(x , y , z)

    xList[indexA] = tX
    yList[indexA] = tY

    indexA = indexA + 1

    if indexA > collectionMax then
    
        table.sort(xList)
        table.sort(yList)

        tX = 0
        tY = 0

        for i= 3, collectionMax - 2 do
            tX = tX + xList[i]
            tY = tY + yList[i]
        end

        xOutCount = xOutCount + tX / (collectionMax - 4)
        yOutCount = yOutCount + tY / (collectionMax - 4)

        indexCount = indexCount + (collectionMax - 4)
        indexA = 1
    end
end

function checkAngleP()
    if indexCount == 0 then return end

    xOut = xOutCount / indexCount
    yOut = yOutCount / indexCount

    print("angle count "..indexCount.."  "..xOut)

    indexA = 0
    xOutCount = 0
    yOutCount = 0
    indexCount = 0

    if startX == 0 or startX == nan then
        startX = xOut
        startY = yOut
        saveConfig()
    end
end

function checkAll()
    temperature = s1:read("temperature")
    if temperature < maxTemp or temperature > minTemp then
        checkAngleP()
        --checkDistance()
    else
       print("temperature limitation")
    end
    print(string.format("dis %0.2f, x %0.4f , y %0.4f , tmp %0.2f" , disOut - startDis , xOut - startX , yOut - startY , temperature))
end

function getXAngle(x , y , z)
    local tmp = x / math.sqrt(y*y + z*z)
    local res = math.atan(tmp)
    return math.deg(res)
end

function getYAngle(x , y , z)
    local tmp = y / math.sqrt(x*x + z*z)
    local res = math.atan(tmp)
    return math.deg(res)
end

function cutNumber(v)
    local x,y = math.modf(v * 1000)
    print("y....."..math.abs(y))
    if math.abs(y) > 0.75 then
        if x >= 0 then
            x = x + 1
        elseif x < 0 then
            x = x - 1
        end
    end

    return x / 1000
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

    startX = 0
    startY = 0

    print("init data startDis:"..startDis.." startX:"..startX.." startY:"..startY)
    
    initI2C()
    tmr.delayms(100)

    local timer = os.clock()
    watchTime = timer
    while true do
        if pppConnected == 1 then
            if mqttConnected == 1 and sensorInited == 1 then
                checkAngle()
                if indexCount >= collectionTotal then
                    checkAll()

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
                        --sendData("alarm" , tAlarm..string.format('"t":%d}', os.time()) , mqtt.QOS1)
                        --alarm = tAlarm..string.format('"t":%d}', os.time())
                    end

                    watchTime = os.clock()

                    --sendData("data", string.format('{"d":%0.2f, "x":%0.2f , "y":%0.2f , "w":%0.2f , "t":%d}' , disOffset , cutNumber(xAngleOffset) , cutNumber(yAngleOffset) , temperature, os.time()) ,mqtt.QOS0)
                    --data = string.format('{"d":%0.2f, "x":%0.3f , "y":%0.3f , "w":%0.2f , "t":%d}' , disOffset , cutNumber(xAngleOffset) , cutNumber(yAngleOffset) , temperature, os.time())
                    --pio.pin.sethigh(led_pin)
                    --tmr.delayms(30)
                    --pio.pin.setlow(led_pin)
                end

            else
                --print("mqtt disconnected...")
                --tmr.delayms(1000)
                --startTask()
            end
        else
            --print("Network disconnected...")
            --tmr.delayms(3000)
        end
    end
end

pppConnected = 1 
mqttConnected = 1 
sensorInited = 1

runDevice()