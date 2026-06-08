getgenv().vex_key = "KEYLESS"

local VexSDK = loadstring(game:HttpGet("https://vexbin.lol/vexlytics/sdk/main.lua"))()
VexSDK.script_id = "e61cab62"

local status = VexSDK.check_key(getgenv().vex_key)
if status.code == "KEY_VALID" then
    print("Welcome! Executions: " .. status.data.total_executions)
    VexSDK.load_script()
else
    game.Players.LocalPlayer:Kick(status.message)
end
