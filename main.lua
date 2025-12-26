-- Remote Renamer by Calling Script Path
-- Переименовывает ремоуты в последний элемент пути callingscript

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- Хук для отслеживания вызовов ремоутов
local remoteCallers = {} -- {remoteInstance = {lastPathElement, callCount}}
local originalNamecall
local originalEventFire
local originalFunctionInvoke

-- Конфигурация
local CONFIG = {
    MONITOR_TIME = 15, -- Время мониторинга вызовов в секундах
    MIN_CALLS = 1, -- Минимальное количество вызовов для анализа
    RENAME_ENABLED = true,
    DEBUG_MODE = true,
    SEND_TO_WEBHOOK = false,
    WEBHOOK_URL = "https://discord.com/api/webhooks/1434181472423776277/wrgeevBbOT05meDtUawJvTomccDgrCn8qml8x2Y18fRhAswj_fOPE3LLM13-R3bCkC7g",
    USE_HOOKFUNCTION = true -- Использовать hookfunction вместо namecall
}

-- Функции логирования
local function log(message, ...)
    if CONFIG.DEBUG_MODE then
        print(string.format("[PathRenamer] " .. message, ...))
    end
end

local function errorLog(message, ...)
    warn(string.format("[PathRenamer ERROR] " .. message, ...))
end

-- Основная функция: извлечь последний элемент пути из callingscript
local function getLastPathElement(scriptInstance)
    if not scriptInstance or typeof(scriptInstance) ~= "Instance" then
        return nil
    end
    
    -- Получаем полный путь как в SimpleSpy (v2s функция)
    local function v2s(obj)
        if typeof(obj) == "Instance" then
            -- Упрощенная версия для получения пути
            local path = {}
            local current = obj
            
            while current and current ~= game do
                local name = current.Name
                -- Если имя содержит спецсимволы, добавляем кавычки
                if name:match("[^%w_]") then
                    name = string.format(':WaitForChild("%s")', name)
                else
                    name = "." .. name
                end
                table.insert(path, 1, name)
                current = current.Parent
            end
            
            if #path > 0 then
                return "game" .. table.concat(path)
            end
            return "game"
        end
        return tostring(obj)
    end
    
    local success, pathString = pcall(v2s, scriptInstance)
    if not success or not pathString then
        return scriptInstance.Name
    end
    
    log("Полный путь скрипта: %s", pathString)
    
    -- Извлекаем последний элемент пути
    local lastElement = nil
    
    -- Вариант 1: Ищем последний элемент после последней точки
    local lastDot = pathString:reverse():find("%.")
    if lastDot then
        lastElement = pathString:sub(-lastDot + 2)
        -- Убираем возможные :WaitForChild("...")
        lastElement = lastElement:gsub(':WaitForChild%(?"', ''):gsub('"%)?', '')
    else
        -- Вариант 2: Берем просто имя скрипта
        lastElement = scriptInstance.Name
    end
    
    -- Очищаем имя
    if lastElement then
        lastElement = lastElement
            :gsub("%s+", "_")
            :gsub("[^%w_]", "")
            :gsub("^%d+", "")
        
        -- Если после очистки имя слишком короткое, используем оригинальное имя
        if #lastElement < 2 then
            lastElement = scriptInstance.Name:gsub("%s+", "_"):gsub("[^%w_]", "")
        end
    end
    
    return lastElement or scriptInstance.Name
end

-- Улучшенная функция получения callingscript (как в SimpleSpy)
local function getCallingScript()
    -- Пытаемся получить скрипт через debug.info
    local success, callingScript = pcall(function()
        -- Вариант 1: Через getcallingscript (если доступен)
        if getcallingscript then
            local script = getcallingscript()
            if script and typeof(script) == "Instance" then
                return script
            end
        end
        
        -- Вариант 2: Через debug.info и поиск по окружению
        for i = 3, 10 do -- Проверяем несколько уровней стека
            local func = debug.info(i, "f")
            if func and func ~= 0 then
                local env = getfenv and getfenv(func)
                if env then
                    local script = rawget(env, "script")
                    if script and typeof(script) == "Instance" then
                        return script
                    end
                end
            end
        end
        
        return nil
    end)
    
    if success and callingScript then
        log("Найден calling script: %s", callingScript:GetFullName())
        return callingScript
    end
    
    -- Альтернативный метод: через стек вызовов
    local stack = debug.traceback()
    for line in stack:gmatch("[^\n]+") do
        -- Ищем упоминания скриптов
        if line:find("Script") and not line:find("Remote") then
            -- Пытаемся извлечь путь
            local pathMatch = line:match("([%w%.]+Script)")
            if pathMatch then
                -- Пытаемся найти экземпляр
                local instance = game
                for part in pathMatch:gmatch("[^%.]+") do
                    local child = instance:FindFirstChild(part)
                    if child then
                        instance = child
                    else
                        break
                    end
                end
                
                if instance ~= game then
                    log("Найден скрипт из стека: %s", instance:GetFullName())
                    return instance
                end
            end
        end
    end
    
    return nil
end

-- Хук для FireServer
local function hookFireServer()
    if not CONFIG.USE_HOOKFUNCTION then return end
    
    local remoteEvent = Instance.new("RemoteEvent")
    local original = remoteEvent.FireServer
    
    if hookfunction then
        originalEventFire = hookfunction(remoteEvent.FireServer, function(self, ...)
            local callingScript = getCallingScript()
            if callingScript then
                local lastPathElement = getLastPathElement(callingScript)
                
                if not remoteCallers[self] then
                    remoteCallers[self] = {
                        lastPath = lastPathElement,
                        callCount = 1,
                        callingScript = callingScript,
                        originalName = self.Name
                    }
                else
                    remoteCallers[self].callCount = remoteCallers[self].callCount + 1
                    remoteCallers[self].lastPath = lastPathElement
                    remoteCallers[self].callingScript = callingScript
                end
                
                log("FireServer: %s -> %s (вызовов: %d)", 
                    self.Name, lastPathElement, remoteCallers[self].callCount)
            end
            
            return original(self, ...)
        end)
        
        log("Хук FireServer установлен")
    end
end

-- Хук для InvokeServer
local function hookInvokeServer()
    if not CONFIG.USE_HOOKFUNCTION then return end
    
    local remoteFunction = Instance.new("RemoteFunction")
    local original = remoteFunction.InvokeServer
    
    if hookfunction then
        originalFunctionInvoke = hookfunction(remoteFunction.InvokeServer, function(self, ...)
            local callingScript = getCallingScript()
            if callingScript then
                local lastPathElement = getLastPathElement(callingScript)
                
                if not remoteCallers[self] then
                    remoteCallers[self] = {
                        lastPath = lastPathElement,
                        callCount = 1,
                        callingScript = callingScript,
                        originalName = self.Name
                    }
                else
                    remoteCallers[self].callCount = remoteCallers[self].callCount + 1
                    remoteCallers[self].lastPath = lastPathElement
                    remoteCallers[self].callingScript = callingScript
                end
                
                log("InvokeServer: %s -> %s (вызовов: %d)", 
                    self.Name, lastPathElement, remoteCallers[self].callCount)
            end
            
            return original(self, ...)
        end)
        
        log("Хук InvokeServer установлен")
    end
end

-- Хук для namecall (альтернативный метод)
local function hookNamecall()
    if CONFIG.USE_HOOKFUNCTION then return end
    
    if getrawmetatable then
        local mt = getrawmetatable(game)
        if mt then
            originalNamecall = mt.__namecall
            
            local function newNamecall(self, ...)
                local method = getnamecallmethod()
                
                if method and (method == "FireServer" or method == "InvokeServer") then
                    if self and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent")) then
                        local callingScript = getCallingScript()
                        if callingScript then
                            local lastPathElement = getLastPathElement(callingScript)
                            
                            if not remoteCallers[self] then
                                remoteCallers[self] = {
                                    lastPath = lastPathElement,
                                    callCount = 1,
                                    callingScript = callingScript,
                                    originalName = self.Name
                                }
                            else
                                remoteCallers[self].callCount = remoteCallers[self].callCount + 1
                                remoteCallers[self].lastPath = lastPathElement
                                remoteCallers[self].callingScript = callingScript
                            end
                            
                            log("%s: %s -> %s (вызовов: %d)", 
                                method, self.Name, lastPathElement, remoteCallers[self].callCount)
                        end
                    end
                end
                
                return originalNamecall(self, ...)
            end
            
            if setreadonly then setreadonly(mt, false) end
            mt.__namecall = newcclosure(newNamecall)
            if setreadonly then setreadonly(mt, true) end
            
            log("Хук namecall установлен")
        end
    end
end

-- Функция переименования ремоута
local function renameRemote(remote, newName)
    if not remote or remote.Name == newName then
        return false, "Already has correct name"
    end
    
    local originalName = remote.Name
    
    -- Стандартный метод
    local success, result = pcall(function()
        remote.Name = newName
        return true
    end)
    
    if success then
        log("✓ Переименовано: %s -> %s", originalName, newName)
        return true
    else
        -- Агрессивный метод через rawset
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
            log("✓ Агрессивно переименовано: %s -> %s", originalName, newName)
            return true
        end
        
        errorLog("✗ Ошибка переименования %s: %s", originalName, result)
        return false, result
    end
end

-- Основная функция переименования
local function renameByLastPath()
    log("=== ПЕРЕИМЕНОВАНИЕ ПО ПОСЛЕДНЕМУ ЭЛЕМЕНТУ ПУТИ ===")
    
    local renameResults = {
        success = 0,
        failed = 0,
        skipped = 0,
        details = {}
    }
    
    local generatedScript = "-- Remote Rename by Last Path Element\n-- Generated at: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n"
    local renameCommands = {}
    
    -- Обрабатываем все зафиксированные ремоуты
    for remote, callerInfo in pairs(remoteCallers) do
        if callerInfo.callCount >= CONFIG.MIN_CALLS then
            if remote and remote.Parent then
                local newName = callerInfo.lastPath
                
                if not newName or newName == "" then
                    newName = callerInfo.originalName .. "_Renamed"
                end
                
                -- Проверяем уникальность имени
                local counter = 1
                local finalName = newName
                while remote.Parent:FindFirstChild(finalName) and finalName ~= remote.Name do
                    counter = counter + 1
                    finalName = newName .. "_" .. counter
                end
                
                if remote.Name == finalName then
                    log("⏭️ Пропуск: %s уже имеет имя %s", remote.Name, finalName)
                    renameResults.skipped = renameResults.skipped + 1
                    
                    table.insert(renameResults.details, {
                        status = "skipped",
                        original = callerInfo.originalName,
                        new = finalName,
                        lastPath = callerInfo.lastPath,
                        calls = callerInfo.callCount,
                        path = remote:GetFullName(),
                        reason = "Already has correct name"
                    })
                else
                    -- Создаем команду переименования
                    local command = string.format([[
-- Remote: %s
-- Calling Script: %s
-- Last Path Element: %s
-- Calls: %d
local remote = game:GetService("ReplicatedStorage"):FindFirstChild("%s", true)
if remote then
    remote.Name = "%s"
    print("Renamed: %s -> %s (from: %s)")
end]],
                        callerInfo.originalName,
                        callerInfo.callingScript and callerInfo.callingScript:GetFullName() or "Unknown",
                        callerInfo.lastPath,
                        callerInfo.callCount,
                        callerInfo.originalName,
                        finalName,
                        callerInfo.originalName,
                        finalName,
                        callerInfo.lastPath
                    )
                    
                    table.insert(renameCommands, command)
                    
                    -- Пытаемся переименовать
                    if CONFIG.RENAME_ENABLED then
                        local success, errorMsg = renameRemote(remote, finalName)
                        
                        if success then
                            renameResults.success = renameResults.success + 1
                            log("✓ Успех: %s -> %s (путь: %s, вызовов: %d)", 
                                callerInfo.originalName, finalName, callerInfo.lastPath, callerInfo.callCount)
                        else
                            renameResults.failed = renameResults.failed + 1
                            errorLog("✗ Ошибка: %s -> %s: %s", callerInfo.originalName, finalName, errorMsg)
                        end
                        
                        table.insert(renameResults.details, {
                            status = success and "success" or "failed",
                            original = callerInfo.originalName,
                            new = finalName,
                            lastPath = callerInfo.lastPath,
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
                            lastPath = callerInfo.lastPath,
                            calls = callerInfo.callCount,
                            path = remote:GetFullName(),
                            error = "RENAME_ENABLED = false"
                        })
                    end
                end
            end
        end
    end
    
    -- Если команд нет, генерируем общий скрипт
    if #renameCommands == 0 then
        generatedScript = generatedScript .. "-- No remotes found during monitoring\n"
        generatedScript = generatedScript .. "-- Try playing the game and monitoring again\n"
    else
        generatedScript = generatedScript .. table.concat(renameCommands, "\n\n")
        generatedScript = generatedScript .. string.format("\n\nprint('Renamed %d remotes by last path element!')", #renameCommands)
    end
    
    -- Копируем в буфер обмена
    if setclipboard then
        setclipboard(generatedScript)
        log("📋 Скрипт скопирован в буфер обмена")
    else
        log("⚠️ setclipboard не доступен")
    end
    
    -- Отчет
    log("=== РЕЗУЛЬТАТЫ ===")
    log("Найдено ремоутов: %d", table.count(remoteCallers))
    log("Успешно переименовано: %d", renameResults.success)
    log("Пропущено: %d", renameResults.skipped)
    log("Ошибок: %d", renameResults.failed)
    log("Всего команд: %d", #renameCommands)
    
    -- Показываем детали
    if CONFIG.DEBUG_MODE then
        print("\n" .. string.rep("=", 60))
        print("DETAILED REMOTE RENAME REPORT")
        print(string.rep("=", 60))
        
        for _, detail in ipairs(renameResults.details) do
            local statusIcon = detail.status == "success" and "✅" or 
                             detail.status == "failed" and "❌" or "⏭️"
            
            print(string.format("%s %s -> %s", statusIcon, detail.original, detail.new))
            print(string.format("   Path Element: %s | Calls: %d", detail.lastPath, detail.calls))
            if detail.error then
                print(string.format("   Error: %s", detail.error))
            end
            print(string.rep("-", 40))
        end
    end
    
    return renameResults, generatedScript
end

-- Функция мониторинга
local function startMonitoring()
    log("🚀 Начинаем мониторинг на %d секунд...", CONFIG.MONITOR_TIME)
    log("📝 Играйте в игру как обычно. Скрипт отслеживает вызовы ремоутов.")
    
    -- Устанавливаем хуки
    if CONFIG.USE_HOOKFUNCTION and hookfunction then
        hookFireServer()
        hookInvokeServer()
    else
        hookNamecall()
    end
    
    -- Ждем указанное время
    local startTime = tick()
    local lastUpdate = 0
    
    while tick() - startTime < CONFIG.MONITOR_TIME do
        local elapsed = tick() - startTime
        local remaining = CONFIG.MONITOR_TIME - elapsed
        
        -- Обновляем статус каждые 5 секунд
        if elapsed - lastUpdate >= 5 then
            log("⏱️ Мониторинг... %d сек осталось (ремоутов: %d)", 
                math.floor(remaining), table.count(remoteCallers))
            lastUpdate = elapsed
        end
        
        task.wait(1)
    end
    
    log("✅ Мониторинг завершен! Найдено %d ремоутов", table.count(remoteCallers))
    
    -- Выводим статистику
    if CONFIG.DEBUG_MODE and table.count(remoteCallers) > 0 then
        print("\n" .. string.rep("=", 50))
        print("REMOTE CALL STATISTICS")
        print(string.rep("=", 50))
        
        for remote, info in pairs(remoteCallers) do
            if info.callCount >= CONFIG.MIN_CALLS then
                print(string.format("%s: %d вызовов -> %s", 
                    info.originalName, info.callCount, info.lastPath))
            end
        end
    end
    
    return remoteCallers
end

-- Создание простого интерфейса
local function createSimpleUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "PathRenamerUI"
    screenGui.ResetOnSpawn = false
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 400, 0, 300)
    mainFrame.Position = UDim2.new(0.5, -200, 0.5, -150)
    mainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    -- Заголовок
    local title = Instance.new("TextLabel")
    title.Text = "Path Renamer v2.0"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 20
    title.Parent = mainFrame
    
    -- Статус
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "Status"
    statusLabel.Text = "Готов к работе\n\nМониторит последний элемент пути callingscript\nПример: game.Players.LocalPlayer.Pets → 'Pets'"
    statusLabel.Size = UDim2.new(1, -20, 0, 100)
    statusLabel.Position = UDim2.new(0, 10, 0, 50)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextSize = 14
    statusLabel.TextWrapped = true
    statusLabel.Parent = mainFrame
    
    -- Прогресс
    local progressFrame = Instance.new("Frame")
    progressFrame.Name = "ProgressFrame"
    progressFrame.Size = UDim2.new(1, -20, 0, 20)
    progressFrame.Position = UDim2.new(0, 10, 0, 160)
    progressFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    progressFrame.BorderSizePixel = 0
    progressFrame.Visible = false
    progressFrame.Parent = mainFrame
    
    local progressBar = Instance.new("Frame")
    progressBar.Name = "ProgressBar"
    progressBar.Size = UDim2.new(0, 0, 1, 0)
    progressBar.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    progressBar.BorderSizePixel = 0
    progressBar.Parent = progressFrame
    
    local progressText = Instance.new("TextLabel")
    progressText.Name = "ProgressText"
    progressText.Text = "0%"
    progressText.Size = UDim2.new(1, 0, 1, 0)
    progressText.BackgroundTransparency = 1
    progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
    progressText.Font = Enum.Font.SourceSansBold
    progressText.TextSize = 14
    progressText.Parent = progressFrame
    
    -- Кнопки
    local monitorBtn = Instance.new("TextButton")
    monitorBtn.Text = "🔄 Мониторить (" .. CONFIG.MONITOR_TIME .. "с)"
    monitorBtn.Size = UDim2.new(0.48, -5, 0, 40)
    monitorBtn.Position = UDim2.new(0.01, 0, 0, 190)
    monitorBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    monitorBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    monitorBtn.Font = Enum.Font.SourceSansBold
    monitorBtn.TextSize = 16
    monitorBtn.Parent = mainFrame
    
    local renameBtn = Instance.new("TextButton")
    renameBtn.Text = "✏️ Переименовать"
    renameBtn.Size = UDim2.new(0.48, -5, 0, 40)
    renameBtn.Position = UDim2.new(0.51, 0, 0, 190)
    renameBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
    renameBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    renameBtn.Font = Enum.Font.SourceSansBold
    renameBtn.TextSize = 16
    renameBtn.Parent = mainFrame
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Text = "❌ Закрыть"
    closeBtn.Size = UDim2.new(1, -20, 0, 35)
    closeBtn.Position = UDim2.new(0, 10, 0, 240)
    closeBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Font = Enum.Font.SourceSans
    closeBtn.TextSize = 14
    closeBtn.Parent = mainFrame
    
    -- Примеры
    local examples = Instance.new("TextLabel")
    examples.Text = "Примеры:\ngame.PlayerGui.Scripts.Inventory → 'Inventory'\nworkspace.Monitors.Security → 'Security'\nReplicatedStorage.RemoteEvents.Damage → 'Damage'"
    examples.Size = UDim2.new(1, -20, 0, 60)
    examples.Position = UDim2.new(0, 10, 0, 280)
    examples.BackgroundTransparency = 1
    examples.TextColor3 = Color3.fromRGB(180, 180, 180)
    examples.Font = Enum.Font.SourceSans
    examples.TextSize = 12
    examples.TextWrapped = true
    examples.Visible = false
    examples.Parent = mainFrame
    
    -- Обработчики событий
    monitorBtn.MouseButton1Click:Connect(function()
        monitorBtn.Active = false
        renameBtn.Active = false
        
        -- Показываем прогресс
        progressFrame.Visible = true
        statusLabel.Text = "Мониторинг запущен...\nИграйте в игру как обычно\nОтслеживаем вызовы ремоутов"
        
        -- Запускаем мониторинг в отдельном потоке
        task.spawn(function()
            local startTime = tick()
            
            -- Запускаем мониторинг
            startMonitoring()
            
            -- Скрываем прогресс
            progressFrame.Visible = false
            
            -- Обновляем статус
            local remoteCount = table.count(remoteCallers)
            statusLabel.Text = string.format(
                "✅ Мониторинг завершен!\n" ..
                "Найдено ремоутов: %d\n" ..
                "Готово к переименованию.",
                remoteCount
            )
            
            -- Показываем примеры
            examples.Visible = true
            
            monitorBtn.Active = true
            renameBtn.Active = true
        end)
        
        -- Анимация прогресса
        task.spawn(function()
            local startTime = tick()
            while tick() - startTime < CONFIG.MONITOR_TIME do
                local progress = (tick() - startTime) / CONFIG.MONITOR_TIME
                progressBar.Size = UDim2.new(progress, 0, 1, 0)
                progressText.Text = string.format("%d%%", math.floor(progress * 100))
                task.wait(0.1)
            end
        end)
    end)
    
    renameBtn.MouseButton1Click:Connect(function()
        if table.count(remoteCallers) == 0 then
            statusLabel.Text = "Сначала проведите мониторинг!\nНажмите кнопку мониторинга"
            return
        end
        
        monitorBtn.Active = false
        renameBtn.Active = false
        
        statusLabel.Text = "Выполняется переименование...\nПожалуйста, подождите"
        
        local results, script = renameByLastPath()
        
        statusLabel.Text = string.format(
            "🎉 Переименование завершено!\n" ..
            "✅ Успешно: %d\n" ..
            "❌ Ошибок: %d\n" ..
            "⏭️ Пропущено: %d\n\n" ..
            "📋 Скрипт скопирован в буфер!",
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
    log("=== PATH RENAMER v2.0 ===")
    log("Переименовывает ремоуты в последний элемент пути callingscript")
    log("Пример: game.Players.LocalPlayer.Pets → 'Pets'")
    
    local ui = createSimpleUI()
    
    -- Автоматически начинаем через 3 секунды
    task.wait(3)
    
    log("Автоматический запуск через 2 секунды...")
    task.wait(2)
    
    -- Запускаем автоматически
    local startBtn = ui:FindFirstChild("PathRenamerUI") and 
                     ui.PathRenamerUI.MainFrame:FindFirstChild("MonitorBtn")
    
    if startBtn then
        startBtn.Active = false
        local status = ui.PathRenamerUI.MainFrame.Status
        status.Text = "🔄 Автоматический запуск мониторинга..."
        
        task.spawn(function()
            task.wait(1)
            
            -- Имитируем клик по кнопке мониторинга
            local remoteCount = startMonitoring()
            
            status.Text = string.format(
                "✅ Автоматический мониторинг завершен!\n" ..
                "Найдено ремоутов: %d\n" ..
                "Нажмите 'Переименовать' для завершения.",
                table.count(remoteCount)
            )
            
            -- Автоматически переименовываем через 2 секунды
            task.wait(2)
            
            local renameBtn = ui.PathRenamerUI.MainFrame:FindFirstChild("RenameBtn")
            if renameBtn and table.count(remoteCallers) > 0 then
                status.Text = "⚡ Автоматическое переименование..."
                
                local results, script = renameByLastPath()
                
                status.Text = string.format(
                    "🎉 Автоматическое переименование завершено!\n" ..
                    "✅ Успешно: %d\n" ..
                    "❌ Ошибок: %d\n" ..
                    "⏭️ Пропущено: %d",
                    results.success,
                    results.failed,
                    results.skipped
                )
            end
            
            startBtn.Active = true
        end)
    end
    
    log("=== СИСТЕМА ГОТОВА ===")
end

-- Запуск
local success, err = pcall(autoStart)
if not success then
    errorLog("Ошибка запуска: %s", err)
    
    -- Пытаемся запустить без интерфейса
    pcall(function()
        log("Запуск в режиме командной строки...")
        startMonitoring()
        renameByLastPath()
    end)
end

-- Экспорт функций для ручного использования
getgenv().PathRenamer = {
    StartMonitoring = startMonitoring,
    RenameAll = renameByLastPath,
    GetRemoteCallers = function() return remoteCallers end,
    GetLastPathElement = getLastPathElement,
    
    -- Быстрая функция для ручного переименования
    QuickRename = function()
        log("Быстрое переименование...")
        startMonitoring()
        task.wait(CONFIG.MONITOR_TIME + 1)
        return renameByLastPath()
    end
}

-- Инструкция
print("\n" .. string.rep("=", 60))
print("PATH RENAMER v2.0")
print("Переименовывает RemoteEvents/RemoteFunctions в последний элемент пути")
print("Пример: game.Players.LocalPlayer.Pets → 'Pets'")
print(string.rep("=", 60))
print("Использование:")
print("1. Запустите скрипт")
print("2. Играйте в игру как обычно 15 секунд")
print("3. Ремоуты автоматически переименуются")
print("4. Или используйте PathRenamer.QuickRename() в консоли")
print(string.rep("=", 60))
