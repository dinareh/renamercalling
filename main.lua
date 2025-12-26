-- Remote Renamer by Calling Script
-- Переименовывает ремоуты в имена скриптов, которые их вызывают

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- Хук для отслеживания вызовов ремоутов
local remoteCallers = {} -- {remoteDebugId = {scriptName, callCount}}
local originalNamecall

-- Конфигурация
local CONFIG = {
    MONITOR_TIME = 10, -- Время мониторинга вызовов в секундах
    MIN_CALLS = 1, -- Минимальное количество вызовов для анализа
    RENAME_ENABLED = true,
    DEBUG_MODE = true,
    SEND_TO_WEBHOOK = true,
    WEBHOOK_URL = "https://discord.com/api/webhooks/1434181472423776277/wrgeevBbOT05meDtUawJvTomccDgrCn8qml8x2Y18fRhAswj_fOPE3LLM13-R3bCkC7g"
}

-- Функции логирования
local function log(message, ...)
    if CONFIG.DEBUG_MODE then
        print(string.format("[RemoteRenamer] " .. message, ...))
    end
end

local function errorLog(message, ...)
    warn(string.format("[RemoteRenamer ERROR] " .. message, ...))
end

-- Функция для получения информации о calling script
local function getCallingScriptInfo()
    -- Получаем стек вызовов
    local stack = debug.traceback()
    
    -- Ищем скрипты в стеке
    for line in stack:gmatch("[^\n]+") do
        -- Ищем пути к скриптам
        if line:find("Script") and not line:find("Remote") then
            -- Извлекаем путь к скрипту
            local scriptPath = line:match("(%w+%.?)+Script")
            if scriptPath then
                -- Пробуем найти экземпляр скрипта
                local success, script = pcall(function()
                    local pathParts = {}
                    for part in scriptPath:gmatch("[^%.]+") do
                        table.insert(pathParts, part)
                    end
                    
                    -- Ищем скрипт в иерархии
                    local current = game
                    for i, part in ipairs(pathParts) do
                        local child = current:FindFirstChild(part)
                        if child then
                            current = child
                        else
                            return nil
                        end
                    end
                    
                    return current
                end)
                
                if success and script then
                    return {
                        Instance = script,
                        Name = script.Name,
                        ClassName = script.ClassName,
                        Path = script:GetFullName()
                    }
                end
            end
        end
    end
    
    return nil
end

-- Хук для отслеживания вызовов RemoteEvents/RemoteFunctions
local function setupRemoteHook()
    log("Установка хука для отслеживания вызовов ремоутов...")
    
    local function getNamecallHook(...)
        local method = getnamecallmethod()
        
        if method and (method == "FireServer" or method == "InvokeServer") then
            local remote = ...
            if remote and typeof(remote) == "Instance" then
                if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") or remote:IsA("UnreliableRemoteEvent") then
                    -- Получаем calling script
                    local callingScript = getCallingScriptInfo()
                    
                    if callingScript then
                        local debugId = game.GetDebugId(remote)
                        
                        if not remoteCallers[debugId] then
                            remoteCallers[debugId] = {
                                scriptName = callingScript.Name,
                                scriptPath = callingScript.Path,
                                callCount = 1,
                                remoteInstance = remote,
                                className = remote.ClassName,
                                originalName = remote.Name
                            }
                        else
                            remoteCallers[debugId].callCount = remoteCallers[debugId].callCount + 1
                            
                            -- Если нашли другой скрипт, выбираем тот, который чаще вызывает
                            if remoteCallers[debugId].callCount > 2 then
                                remoteCallers[debugId].scriptName = callingScript.Name
                                remoteCallers[debugId].scriptPath = callingScript.Path
                            end
                        end
                        
                        log("Зафиксирован вызов: %s -> %s (вызовов: %d)", 
                            remote.Name, callingScript.Name, remoteCallers[debugId].callCount)
                    end
                end
            end
        end
        
        return originalNamecall(...)
    end
    
    -- Сохраняем оригинальный namecall
    if getrawmetatable then
        local mt = getrawmetatable(game)
        if mt then
            originalNamecall = mt.__namecall
            if setreadonly then
                setreadonly(mt, false)
            end
            mt.__namecall = newcclosure(getNamecallHook)
            if setreadonly then
                setreadonly(mt, true)
            end
            log("Хук успешно установлен")
        end
    end
end

-- Функция для получения чистого имени скрипта
local function getCleanScriptName(scriptName, remoteName)
    if not scriptName or scriptName == "" then
        return remoteName .. "_Renamed"
    end
    
    -- Очищаем имя от нежелательных символов
    local cleanName = scriptName
        :gsub("%s+", "_")
        :gsub("[^%w_]", "")
        :gsub("^%d+", "")
        :sub(1, 50)
    
    -- Проверяем, не является ли имя слишком коротким
    if #cleanName < 3 then
        return remoteName .. "_Renamed"
    end
    
    return cleanName
end

-- Функция переименования ремоута
local function renameRemote(remote, newName)
    if not remote or remote.Name == newName then
        return false, "Already has correct name"
    end
    
    local originalName = remote.Name
    
    local success, result = pcall(function()
        remote.Name = newName
        return true
    end)
    
    if success then
        log("Переименовано: %s -> %s", originalName, newName)
        return true
    else
        -- Пробуем агрессивный метод
        local aggressiveSuccess = pcall(function()
            local rawMeta = getrawmetatable(remote)
            if rawMeta then
                local wasReadonly = isreadonly and isreadonly(rawMeta)
                if wasReadonly and makewritable then
                    makewritable(rawMeta)
                end
                
                rawset(remote, "Name", newName)
                
                if wasReadonly and makereadonly then
                    makereadonly(rawMeta)
                end
                return true
            end
            return false
        end)
        
        if aggressiveSuccess then
            log("Агрессивно переименовано: %s -> %s", originalName, newName)
            return true
        end
        
        errorLog("Ошибка переименования %s: %s", originalName, result)
        return false, result
    end
end

-- Основная функция переименования на основе calling script
local function renameByCallingScript()
    log("=== ПЕРЕИМЕНОВАНИЕ ПО CALLING SCRIPT ===")
    
    local renameResults = {
        success = 0,
        failed = 0,
        skipped = 0,
        details = {}
    }
    
    local generatedScript = "-- Remote Rename by Calling Script\n-- Generated at: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n"
    local renameCommands = {}
    
    -- Обрабатываем все зафиксированные ремоуты
    for debugId, callerInfo in pairs(remoteCallers) do
        if callerInfo.callCount >= CONFIG.MIN_CALLS then
            local remote = callerInfo.remoteInstance
            
            if remote and remote.Parent then
                local newName = getCleanScriptName(callerInfo.scriptName, callerInfo.originalName)
                
                -- Проверяем уникальность имени
                local counter = 1
                local finalName = newName
                while remote.Parent:FindFirstChild(finalName) and finalName ~= remote.Name do
                    counter = counter + 1
                    finalName = newName .. "_" .. counter
                end
                
                if remote.Name == finalName then
                    log("Пропуск: %s уже имеет имя %s", remote.Name, finalName)
                    renameResults.skipped = renameResults.skipped + 1
                else
                    -- Создаем команду переименования
                    local command = string.format([[
-- Remote: %s (calls: %d, caller: %s)
local remote = %s:FindFirstChild("%s", true)
if remote then
    remote.Name = "%s"
    print("Renamed: %s -> %s")
end]],
                        callerInfo.originalName,
                        callerInfo.callCount,
                        callerInfo.scriptName,
                        "game",
                        callerInfo.originalName,
                        finalName,
                        callerInfo.originalName,
                        finalName
                    )
                    
                    table.insert(renameCommands, command)
                    
                    -- Пытаемся переименовать сразу
                    if CONFIG.RENAME_ENABLED then
                        local success, errorMsg = renameRemote(remote, finalName)
                        
                        if success then
                            renameResults.success = renameResults.success + 1
                            log("✓ Успех: %s -> %s (вызывал: %s, раз: %d)", 
                                callerInfo.originalName, finalName, callerInfo.scriptName, callerInfo.callCount)
                        else
                            renameResults.failed = renameResults.failed + 1
                            errorLog("✗ Ошибка: %s -> %s: %s", callerInfo.originalName, finalName, errorMsg)
                        end
                        
                        table.insert(renameResults.details, {
                            status = success and "success" or "failed",
                            original = callerInfo.originalName,
                            new = finalName,
                            caller = callerInfo.scriptName,
                            calls = callerInfo.callCount,
                            path = remote:GetFullName(),
                            error = errorMsg
                        })
                    else
                        renameResults.skipped = renameResults.skipped + 1
                        table.insert(renameResults.details, {
                            status = "skipped",
                            original = callerInfo.originalName,
                            new = finalName,
                            caller = callerInfo.scriptName,
                            calls = callerInfo.callCount,
                            path = remote:GetFullName(),
                            error = "RENAME_ENABLED = false"
                        })
                    end
                end
            end
        end
    end
    
    -- Собираем скрипт
    generatedScript = generatedScript .. table.concat(renameCommands, "\n\n")
    generatedScript = generatedScript .. string.format("\n\nprint('Renamed %d remotes!')", #renameCommands)
    
    -- Копируем в буфер обмена
    if setclipboard then
        setclipboard(generatedScript)
        log("Скрипт скопирован в буфер обмена")
    end
    
    -- Отчет
    log("=== РЕЗУЛЬТАТЫ ===")
    log("Найдено ремоутов: %d", #renameCommands)
    log("Успешно: %d", renameResults.success)
    log("Пропущено: %d", renameResults.skipped)
    log("Ошибок: %d", renameResults.failed)
    
    -- Отправка в Discord
    if CONFIG.SEND_TO_WEBHOOK and #renameCommands > 0 then
        local function sendToWebhook()
            local summary = string.format(
                "**Remote Rename by Calling Script**\n" ..
                "⏱️ Monitor time: %d seconds\n" ..
                "📊 Found remotes: %d\n" ..
                "✅ Success: %d\n" ..
                "❌ Failed: %d\n" ..
                "⏭️ Skipped: %d",
                CONFIG.MONITOR_TIME,
                #renameCommands,
                renameResults.success,
                renameResults.failed,
                renameResults.skipped
            )
            
            local detailsText = "```\n"
            for i, detail in ipairs(renameResults.details) do
                if i <= 10 then
                    detailsText = detailsText .. string.format("%s: %s -> %s\n  Caller: %s (calls: %d)\n",
                        detail.status:upper(),
                        detail.original,
                        detail.new,
                        detail.caller,
                        detail.calls)
                end
            end
            detailsText = detailsText .. "```"
            
            local payload = {
                embeds = {{
                    title = "Calling Script Renamer Report",
                    description = summary,
                    color = 0x00FF00,
                    fields = {
                        {
                            name = "Remote Details",
                            value = detailsText,
                            inline = false
                        },
                        {
                            name = "Generated Script",
                            value = "```lua\n" .. generatedScript:sub(1, 1000) .. "\n```",
                            inline = false
                        }
                    },
                    footer = {
                        text = "Executed by Calling Script Renamer"
                    },
                    timestamp = DateTime.now():ToIsoDate()
                }},
                username = "Calling Script Renamer"
            }
            
            local jsonPayload = HttpService:JSONEncode(payload)
            
            local requestFunc = syn and syn.request or request
            if requestFunc then
                local response = requestFunc({
                    Url = CONFIG.WEBHOOK_URL,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = jsonPayload
                })
                return response.Success
            end
            return false
        end
        
        local success, err = pcall(sendToWebhook)
        if success then
            log("Отчет отправлен в Discord")
        else
            errorLog("Ошибка отправки в Discord: %s", err)
        end
    end
    
    return renameResults, generatedScript
end

-- Альтернативный метод: поиск всех ремоутов и их анализ
local function findAllRemotesAndAnalyze()
    log("Поиск всех ремоутов в игре...")
    
    local allRemotes = {}
    local function searchInContainer(container)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") or child:IsA("UnreliableRemoteEvent") then
                table.insert(allRemotes, {
                    Instance = child,
                    Path = child:GetFullName(),
                    Parent = child.Parent,
                    ClassName = child.ClassName,
                    OriginalName = child.Name
                })
            end
            searchInContainer(child)
        end
    end
    
    searchInContainer(game)
    log("Найдено %d ремоутов", #allRemotes)
    
    -- Анализируем, какие скрипты находятся рядом с ремоутами
    for _, remoteInfo in ipairs(allRemotes) do
        local remote = remoteInfo.Instance
        
        -- Ищем скрипты в родительской цепочке
        local foundScript = nil
        local current = remote.Parent
        
        while current and current ~= game do
            for _, child in ipairs(current:GetChildren()) do
                if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
                    foundScript = child
                    break
                end
            end
            if foundScript then break end
            current = current.Parent
        end
        
        if foundScript then
            local debugId = game.GetDebugId(remote)
            remoteCallers[debugId] = {
                scriptName = foundScript.Name,
                scriptPath = foundScript:GetFullName(),
                callCount = 1,
                remoteInstance = remote,
                className = remote.ClassName,
                originalName = remote.Name
            }
            log("Найден ремоут %s рядом со скриптом %s", remote.Name, foundScript.Name)
        end
    end
end

-- Функция мониторинга в реальном времени
local function startMonitoring()
    log("Начинаем мониторинг вызовов ремоутов на %d секунд...", CONFIG.MONITOR_TIME)
    
    setupRemoteHook()
    
    -- Ждем, пока накопится статистика
    local startTime = tick()
    local monitoredCalls = 0
    
    while tick() - startTime < CONFIG.MONITOR_TIME do
        task.wait(1)
        
        -- Показываем прогресс
        local elapsed = tick() - startTime
        local remaining = CONFIG.MONITOR_TIME - elapsed
        
        if math.floor(elapsed) % 5 == 0 then
            log("Мониторинг... %d секунд осталось (найдено ремоутов: %d)", 
                math.floor(remaining), table.count(remoteCallers))
        end
    end
    
    log("Мониторинг завершен. Найдено %d ремоутов", table.count(remoteCallers))
    
    -- Если ремоутов мало, ищем все
    if table.count(remoteCallers) < 5 then
        log("Слишком мало данных. Ищем все ремоуты в игре...")
        findAllRemotesAndAnalyze()
    end
    
    return remoteCallers
end

-- Создание интерфейса
local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CallingScriptRenamerUI"
    screenGui.ResetOnSpawn = false
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 350, 0, 250)
    mainFrame.Position = UDim2.new(0.5, -175, 0.5, -125)
    mainFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    -- Заголовок
    local title = Instance.new("TextLabel")
    title.Text = "Calling Script Renamer"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 18
    title.Parent = mainFrame
    
    -- Статус
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Text = "Готов к работе"
    statusLabel.Size = UDim2.new(1, -20, 0, 80)
    statusLabel.Position = UDim2.new(0, 10, 0, 50)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextSize = 14
    statusLabel.TextWrapped = true
    statusLabel.Parent = mainFrame
    
    -- Кнопки
    local monitorBtn = Instance.new("TextButton")
    monitorBtn.Text = "Мониторить вызовы"
    monitorBtn.Size = UDim2.new(0.45, -5, 0, 40)
    monitorBtn.Position = UDim2.new(0.025, 0, 0, 140)
    monitorBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    monitorBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    monitorBtn.Font = Enum.Font.SourceSansBold
    monitorBtn.TextSize = 14
    monitorBtn.Parent = mainFrame
    
    local renameBtn = Instance.new("TextButton")
    renameBtn.Text = "Переименовать"
    renameBtn.Size = UDim2.new(0.45, -5, 0, 40)
    renameBtn.Position = UDim2.new(0.525, 0, 0, 140)
    renameBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
    renameBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    renameBtn.Font = Enum.Font.SourceSansBold
    renameBtn.TextSize = 14
    renameBtn.Parent = mainFrame
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "Закрыть"
    closeBtn.Size = UDim2.new(1, -20, 0, 35)
    closeBtn.Position = UDim2.new(0, 10, 0, 200)
    closeBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Font = Enum.Font.SourceSans
    closeBtn.TextSize = 14
    closeBtn.Parent = mainFrame
    
    -- Обработчики
    monitorBtn.MouseButton1Click:Connect(function()
        monitorBtn.Active = false
        renameBtn.Active = false
        
        statusLabel.Text = "Мониторинг вызовов...\nПожалуйста, играйте в игру.\nВремя: " .. CONFIG.MONITOR_TIME .. " сек"
        
        startMonitoring()
        
        statusLabel.Text = string.format(
            "Мониторинг завершен!\n" ..
            "Найдено ремоутов: %d\n" ..
            "Готово к переименованию.",
            table.count(remoteCallers)
        )
        
        monitorBtn.Active = true
        renameBtn.Active = true
    end)
    
    renameBtn.MouseButton1Click:Connect(function()
        if table.count(remoteCallers) == 0 then
            statusLabel.Text = "Сначала проведите мониторинг!"
            return
        end
        
        monitorBtn.Active = false
        renameBtn.Active = false
        
        statusLabel.Text = "Выполняется переименование..."
        
        local results, script = renameByCallingScript()
        
        statusLabel.Text = string.format(
            "Переименование завершено!\n" ..
            "Успешно: %d\n" ..
            "Ошибок: %d\n" ..
            "Пропущено: %d\n\n" ..
            "Скрипт скопирован!",
            results.success,
            results.failed,
            results.skipped
        )
        
        monitorBtn.Active = true
        renameBtn.Active = true
    end)
    
    closeBtn.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)
    
    -- Делаем окно перемещаемым
    local dragging = false
    local dragInput, dragStart, startPos
    
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    title.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)
    
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            mainFrame.Position = startPos + UDim2.new(0, delta.X, 0, delta.Y)
        end
    end)
    
    -- Добавляем в игру
    if gethui then
        screenGui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(screenGui)
        screenGui.Parent = game:GetService("CoreGui")
    else
        screenGui.Parent = game:GetService("CoreGui")
    end
    
    return screenGui
end

-- Автоматический запуск
local function autoStart()
    log("=== CALLING SCRIPT RENAMER === ")
    log("Запуск автоматического режима...")
    
    local ui = createUI()
    
    -- Автоматически начинаем мониторинг
    task.wait(2)
    
    log("Автоматический мониторинг через 5 секунд...")
    for i = 5, 1, -1 do
        if ui and ui:FindFirstChild("CallingScriptRenamerUI") then
            local status = ui.CallingScriptRenamerUI.MainFrame.Status
            if status then
                status.Text = string.format("Автоматический запуск через %d...", i)
            end
        end
        task.wait(1)
    end
    
    -- Запускаем мониторинг
    startMonitoring()
    
    -- Автоматически переименовываем
    task.wait(2)
    
    if table.count(remoteCallers) > 0 then
        log("Начинаем автоматическое переименование...")
        
        local results, script = renameByCallingScript()
        
        if ui and ui:FindFirstChild("CallingScriptRenamerUI") then
            local status = ui.CallingScriptRenamerUI.MainFrame.Status
            if status then
                status.Text = string.format(
                    "Автоматическое переименование завершено!\n" ..
                    "Успешно: %d\n" ..
                    "Ошибок: %d\n" ..
                    "Пропущено: %d\n\n" ..
                    "Скрипт скопирован!",
                    results.success,
                    results.failed,
                    results.skipped
                )
            end
        end
    else
        log("Не найдено ремоутов для переименования")
    end
    
    log("=== ВЫПОЛНЕНИЕ ЗАВЕРШЕНО ===")
end

-- Запуск
pcall(autoStart)

-- Экспорт функций
getgenv().CallingScriptRenamer = {
    StartMonitoring = startMonitoring,
    RenameAll = renameByCallingScript,
    GetRemoteCallers = function() return remoteCallers end,
    FindAllRemotes = findAllRemotesAndAnalyze
}
