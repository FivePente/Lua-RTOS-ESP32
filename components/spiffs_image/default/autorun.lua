t = 0
c = 0
m = 1

xt = 0
yt = 0
zt = 0
odis = 0
ldis = {}
tdis = 0

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

function initI2C() 
    cd = adxl345.init(i2c.I2C0 , i2c.MASTER , 400 , pio.GPIO18 , pio.GPIO19)
    cd:write(0x2D , 0x08)
    cd:write(0x31 , 0x2B)
    cd:write(0x2C , 0x08)
    ad = vl53l0x.init(i2c.I2C0 , i2c.MASTER , 400 , 0x29 , pio.GPIO18 , pio.GPIO19)
    ad:startRanging(2)
end

function check ()
    while true do
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
            break
        end

        tmr.delayms(500)
    end

    while true do

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
            break
        end
    end
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
    initI2C()
    tmr.delayms(1000)
    while true do
        if pppConnected == 1 then
            if mqttConnected == 1 then
                check()
                try(
                    function()
                        client:publish("data", string.format('{"dis":%0.2f, "x":%0.2f , "y":%0.2f}' , dOut , xOut , yOut) ,mqtt.QOS0) 
                        tmr.delayms(10000)
                    end,

                    function(where,line,error,message)
                        print(message)
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

runDevice()