--[[
    Independent Remote Renamer Script
    Renames all RemoteEvents, RemoteFunctions, and UnreliableRemoteEvents in ReplicatedStorage to indices 1-500
    No dependencies, works standalone
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Main function to rename all remotes
local function renameAllRemotes()
    -- Collect all remotes in ReplicatedStorage (direct children only, not in subfolders)
    local remotes = {}
    local renameCommands = {}
    
    -- Find all remote instances
    for _, child in ipairs(ReplicatedStorage:GetChildren()) do
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") or child:IsA("UnreliableRemoteEvent") then
            table.insert(remotes, {
                instance = child,
                originalName = child.Name,
                className = child.ClassName
            })
        end
    end
    
    -- Create rename commands
    for index, remoteData in ipairs(remotes) do
        local newNumber = index
        if newNumber > 500 then
            newNumber = 500
        end
        
        -- Create rename command using rawset to bypass protection
        local command = string.format([[
            local remote = game:GetService("ReplicatedStorage"):FindFirstChild("%s")
            if remote then
                local rawmeta = getrawmetatable(remote)
                if rawmeta then
                    local wasReadonly
                    if isreadonly then
                        wasReadonly = isreadonly(rawmeta)
                    elseif table.isfrozen then
                        wasReadonly = table.isfrozen(rawmeta)
                    end
                    
                    if wasReadonly then
                        if makewritable then
                            makewritable(rawmeta)
                        elseif not table.isfrozen then
                            setreadonly(rawmeta, false)
                        end
                    end
                    
                    rawset(remote, "Name", "%d")
                    
                    if wasReadonly then
                        if makereadonly then
                            makereadonly(rawmeta)
                        elseif table.isfrozen then
                            setreadonly(rawmeta, true)
                        end
                    end
                else
                    remote.Name = "%d"
                end
            end
        ]], remoteData.originalName, newNumber, newNumber)
        
        table.insert(renameCommands, {
            command = command,
            originalName = remoteData.originalName,
            newName = tostring(newNumber),
            className = remoteData.className,
            index = index
        })
    end
    
    -- Create the full script
    local scriptText = "-- REMOTE RENAMER SCRIPT\n"
    scriptText = scriptText .. "-- Renames all remotes in ReplicatedStorage to numbers 1-500\n\n"
    scriptText = scriptText .. "-- Auto-generated at " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n"
    
    -- Add individual rename commands
    for _, cmdData in ipairs(renameCommands) do
        scriptText = scriptText .. "-- " .. cmdData.originalName .. " → " .. cmdData.newName .. " (" .. cmdData.className .. ")\n"
        scriptText = scriptText .. cmdData.command .. "\n"
        scriptText = scriptText .. 'print("Renamed: ' .. cmdData.originalName .. ' → ' .. cmdData.newName .. '")\n\n'
    end
    
    scriptText = scriptText .. string.format('print("=== RENAMING COMPLETE ===\\nTotal remotes renamed: %d")', #renameCommands)
    
    -- Execute the rename commands
    for _, cmdData in ipairs(renameCommands) do
        pcall(loadstring(cmdData.command))
    end
    
    -- Copy to clipboard
    if setclipboard then
        setclipboard(scriptText)
    elseif writeclipboard then
        writeclipboard(scriptText)
    end
    
    -- Create summary message
    local summary = string.format("=== REMOTE RENAMING SUMMARY ===\n\n")
    summary = summary .. string.format("Total remotes found: %d\n", #renameCommands)
    summary = summary .. string.format("Renamed to: 1-%d\n\n", math.min(#renameCommands, 500))
    summary = summary .. "Renamed remotes:\n"
    
    for _, cmdData in ipairs(renameCommands) do
        if cmdData.index <= 20 then  -- Show first 20
            summary = summary .. string.format("%d. %s (%s) → %s\n", 
                cmdData.index, 
                cmdData.originalName, 
                cmdData.className, 
                cmdData.newName)
        elseif cmdData.index == 21 then
            summary = summary .. "... and " .. (#renameCommands - 20) .. " more\n"
        end
    end
    
    -- Print summary
    print("\n" .. string.rep("=", 50))
    print(summary)
    
    if #renameCommands > 0 then
        print("✓ Script copied to clipboard!")
    else
        print("⚠ No remotes found in ReplicatedStorage")
    end
    print(string.rep("=", 50) .. "\n")
    
    -- Return results for potential webhook integration
    return {
        success = true,
        totalRemotes = #renameCommands,
        scriptText = scriptText,
        summary = summary,
        renamedList = renameCommands
    }
end

-- Optional: Webhook integration function
local function sendToWebhook(results)
    if not results or results.totalRemotes == 0 then
        return false, "No remotes to report"
    end
    
    local success, err = pcall(function()
        -- Format Discord message
        local message = string.format("**Remote Renaming Complete**\n\n")
        message = message .. string.format("**Total Remotes:** %d\n", results.totalRemotes)
        message = message .. string.format("**Renamed to:** 1-%d\n\n", math.min(results.totalRemotes, 500))
        message = message .. "**First 10 renamed:**\n"
        
        for i = 1, math.min(10, #results.renamedList) do
            local r = results.renamedList[i]
            message = message .. string.format("%d. `%s` (%s) → `%s`\n", 
                i, r.originalName, r.className, r.newName)
        end
        
        if results.totalRemotes > 10 then
            message = message .. string.format("\n... and %d more", results.totalRemotes - 10)
        end
        
        -- Create payload
        local payload = {
            content = message,
            username = "Remote Renamer",
            embeds = {{
                title = "Remote Renaming Script",
                description = string.format("Successfully renamed **%d** remotes", results.totalRemotes),
                color = 0x00FF00,
                timestamp = DateTime.now():ToIsoDate()
            }}
        }
        
        -- Send to webhook
        local jsonPayload = HttpService:JSONEncode(payload)
        
        -- Try different request methods
        local requestFunc = syn and syn.request or request or http_request
        if requestFunc then
            local response = requestFunc({
                Url = "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL_HERE",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
            return true
        end
        
        return false, "No request function available"
    end)
    
    return success, err
end

-- Main execution
local function main()
    print("Starting Remote Renamer...")
    
    local results = renameAllRemotes()
    
    -- Optional: Uncomment to send to webhook
    -- local webhookSuccess, webhookError = sendToWebhook(results)
    -- if webhookSuccess then
    --     print("✓ Results sent to Discord webhook")
    -- else
    --     print("⚠ Webhook failed: " .. tostring(webhookError))
    -- end
    
    return results
end

-- Execute immediately when loaded
main()

-- Also expose as a global function for manual calling
getgenv().RenameAllRemotes = renameAllRemotes

print("\nRemote Renamer loaded! Call 'RenameAllRemotes()' to execute again.")
