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

--net.wf.scan()
--net.wf.setup(net.wf.mode.STA, "HiWiFi_3B0F16","Freedom0806")
--net.wf.start();

--[[
thread.start(function()
   ppp.step()
end)

client:publish("test", "{name:device1000xksjshj , speed:1726.3826 , type:1 , bool:true , ttt:1927373626 ,test:928282}", mqtt.QOS0)

client = mqtt.client("esp32", "60.205.82.208", 1883, false)
client:setLostCallback(function(mes) print(mes) end)
client:connect("","" , 30 , 0 , 1)

client:subscribe("code", mqtt.QOS0, function(len, message)
    --local file2 = io.open("autorun.lua","w+")
    --file2:write(message)
    --file2:close()
    --os.exit(1)
    print(message)
end)]]