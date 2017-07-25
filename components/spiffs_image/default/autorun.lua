startDis = 0
startX = 0
startY = 0

disOut = 0
xOut = 0
yOut = 0
zOut = 0

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

collectionMax = 20
collectionTotal = 200
angleStarted = 0

local ver = 1.0

function initI2C() 
    cd = adxl345.init(i2c.I2C0 , i2c.MASTER , 400 , pio.GPIO18 , pio.GPIO19)
    tmr.delayms(2)
    cd:write(0x2D , 0x00)
    tmr.delayms(2)
    cd:write(0x31 , 0x28) --28
    cd:write(0x2C , 0x0C)
    --cd:write(0x38 , 0xA0)
    cd:write(0x2E , 0x00)
    cd:write(0x2D , 0x28)

    tmr.delayms(10)

    ad = vl53l0x.init(i2c.I2C0 , i2c.MASTER , 400 , 0x29 , pio.GPIO18 , pio.GPIO19)
    tmr.delayms(10)
    ad:startRanging(2)

    s1 = sensor.attach("DS1820", pio.GPIO21, 0x28ff900f, 0xb316041a)
    s1:set("resolution", 10)

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
    file2:write( "startDis="..startDis.." startX="..startX.." startY="..startY)
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
            print("vl5310x get distance error init I2C")
            sensorInited = 0
            ad:stopRanging()
            ad:close()
            tmr.delayms(500)
            initI2C()
            return
        else
            ldis[index] = tDis
            index = index + 1
            
            if index > 14 then

                local tdis = 0
                table.sort(ldis)
                print(table.concat(ldis, ", "))

                for i= 2, 13 do
                    tdis = tdis + ldis[i] * ldis[i]
                end

                disOut = math.sqrt(tdis / 12)
                if startDis == 0 then
                    startDis = disOut
                    --saveConfig()
                end
                break
            end
        end
    end
end

xList = {}
yList = {}
indexCount = 0
FILTER_A = 0.001
lastX = 0
lastY = 0
lastZ = 0
maxX = 0
minX = 0
maxY = 0
minY = 0

function checkAngle()
    local x = 0
    local y = 0
    local z = 0
    local tX = 0
    local tY = 0

    try(
        function()
            x, y , z = cd:read()

            if x > maxX then
                maxX = x
            elseif x < minX then
                minX = x
            end

            if y > maxY then
                maxY = y
            elseif y < minY then
                minY = y
            end
        end,
        function(where, line, error, message)
            print("read error init I2C:"..message)
            sensorInited = 0
            cd:close()
            tmr.delayms(10)
            initI2C()
        end
    )

    tX = getXAngle(x , y , z)
    tY = getYAngle(x , y , z)

    --print(tX.."  "..tY)
    
    xList[indexA] = tX - startX                                     
    yList[indexA] = tY - startY

    indexA = indexA + 1

    if indexA > collectionMax then
    
        table.sort(xList)
        table.sort(yList)

        for i= 4, collectionMax - 3 do
            tX = tX + xList[i]
            tY = tY + yList[i]
        end

        tX = tX / (collectionMax - 6)
        tY = tY / (collectionMax - 6)

        xOutCount = xOutCount + tX
        yOutCount = yOutCount + tY

        indexCount = indexCount + 1
        indexA = 1
    end
end

function checkAngleP()
    if indexCount == 0 then return end

    xOut = xOutCount / indexCount
    yOut = yOutCount / indexCount

    print("angle count "..indexCount.."  "..xOut.."  "..yOut.."  "..(maxX - minX).."  "..(maxY - minY))

    indexA = 0
    xOutCount = 0
    yOutCount = 0
    indexCount = 0

    maxX = 0
    minX = 0
    maxY = 0
    minY = 0

    lastX = 0
    lastY = 0
    lastZ = 0

    if startX == 0 or startX == nan then
        startX = xOut
        startY = yOut
        saveConfig()
    end
end

function checkAll()
    temperature = s1:read("temperature")
    if temperature < maxTemp or temperature > minTemp then
        tmr.delayms(2)
        checkDistance()
        checkAngleP()
    else
       print("temperature limitation")
    end
    local tC = collectgarbage("count")
    print("mem: "..tC)
    print(string.format("dis %0.2f, x %0.2f , y %0.2f , tmp %0.2f" , disOut - startDis , cutNumber(xOut) , cutNumber(yOut) , temperature))
end

function getXAngle(x , y , z)
    --local tmp = x / math.sqrt(y*y + z*z)
    --local res = math.atan(tmp)
    res = math.atan(x , math.sqrt(y*y + z*z))
    return math.deg(res)
end

function getYAngle(x , y , z)
    --local tmp = y / math.sqrt(x*x + z*z)
    --local res = math.atan(tmp)
    local res = math.atan(y , math.sqrt(x*x + z*z))
    return math.deg(res)
end

function cutNumber(v)
    local x,y = math.modf(v * 100)
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
        print("load config.lua")
    end
    
    initI2C()
    tmr.delayms(100)

    local timer = os.clock()
    watchTime = timer
    while true do
        if initConfigFlag == 1 then
            initConfig()
            initConfigFlag = 0
        end
        if pppConnected == 1 then
            if mqttConnected == 1 then
                if sensorInited == 1 then
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
                            tAlarm = tAlarm..string.format('"x":%0.2f , ', cutNumber(xAngleOffset))
                        end                        

                        local yAngleOffset = yOut - startY

                        if yAngleOffset > hYAlarm or yAngleOffset < lYAlarm then
                            angleYExceedCount = angleYExceedCount + 1
                        else
                            angleYExceedCount = 0
                        end

                        if angleYExceedCount >= angleAlarmExceed then
                            tAlarm = tAlarm..string.format('"y":%0.2f , ', cutNumber(yAngleOffset))
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
                        --watchTime = os.clock()
                        sendData("data", string.format('{"d":%0.2f, "x":%0.2f , "y":%0.2f , "w":%0.2f , "t":%d}' , disOffset , cutNumber(xAngleOffset) , cutNumber(yAngleOffset) , temperature, os.time()) ,mqtt.QOS0)
                        pio.pin.sethigh(led_pin)
                        tmr.delayms(30)
                        pio.pin.setlow(led_pin)
                    end
                end
            else
                --print("mqtt disconnected...")
                --tmr.delayms(3000)
            end
        else
            --print("Network disconnected...")
            --tmr.delayms(3000)
        end
    end
end

runDevice()