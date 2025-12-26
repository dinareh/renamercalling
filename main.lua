-- Remote Renamer Script
-- Автоматически переименовывает RemoteEvents/RemoteFunctions в имена их скриптов-источников

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- Конфигурация
local CONFIG = {
    DEBUG_MODE = true,
    SEND_TO_WEBHOOK = true,
    WEBHOOK_URL = "https://discord.com/api/webhooks/1434181472423776277/wrgeevBbOT05meDtUawJvTomccDgrCn8qml8x2Y18fRhAswj_fOPE3LLM13-R3bCkC7g",
    RENAME_IN_GAME = true, -- Автоматически переименовывать в игре
    USE_RAW_METHOD = false -- Использовать rawset для обхода защиты
}

-- Глобальные переменные
local renameHistory = {}
local remoteStats = {}
local lastExecutionTime = tick()

-- Функции логирования
local function log(message, ...)
    if CONFIG.DEBUG_MODE then
        print(string.format("[RemoteRenamer] " .. message, ...))
    end
end

local function errorLog(message, ...)
    warn(string.format("[RemoteRenamer ERROR] " .. message, ...))
end

-- Функция для получения чистого имени из пути
local function getCleanNameFromPath(path)
    if not path or path == "" then
        return nil
    end
    
    -- Убираем кавычки и лишние символы
    local cleanPath = path:gsub('["\']', ''):gsub(":", "")
    
    -- Разбиваем путь на части
    local parts = {}
    for part in cleanPath:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    
    -- Ищем подходящее имя (последнее не-служебное)
    for i = #parts, 1, -1 do
        local name = parts[i]
        
        -- Пропускаем служебные имена
        if not (name:find("Remote") or 
                name:find("Module") or 
                name:find("Script") or
                name:find("Replicated") or
                name:find("Server") or
                name:find("Client") or
                name:find("Workspace") or
                name:find("Players") or
                #name < 3) then
            
            -- Очищаем имя от нежелательных символов
            local cleaned = name:gsub("%s+", "_")
                           :gsub("[^%w_]", "")
                           :gsub("^%d+", "") -- Убираем цифры в начале
                           :sub(1, 50) -- Ограничиваем длину
            
            if #cleaned >= 3 then
                return cleaned
            end
        end
    end
    
    return nil
end

-- Функция для получения информации о скрипте
local function getScriptInfo(scriptInstance)
    if not scriptInstance or typeof(scriptInstance) ~= "Instance" then
        return nil
    end
    
    -- Получаем полный путь к скрипту
    local success, fullPath = pcall(function()
        local path = {}
        local current = scriptInstance
        
        while current and current ~= game do
            local name = current.Name
            if name:find("[^%w_]") then
                name = string.format('["%s"]', name)
            end
            table.insert(path, 1, name)
            current = current.Parent
        end
        
        if #path > 0 then
            return table.concat(path, ".")
        end
        return scriptInstance.Name
    end)
    
    if success and fullPath then
        return {
            Path = fullPath,
            CleanName = getCleanNameFromPath(fullPath),
            Instance = scriptInstance
        }
    end
    
    return nil
end

-- Функция для сбора информации о ремоутах
local function collectRemoteInfo()
    log("Начинаем сбор информации о ремоутах...")
    
    local allRemotes = {}
    
    -- Функция рекурсивного поиска ремоутов
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
            
            -- Рекурсивно проверяем дочерние объекты
            searchInContainer(child)
        end
    end
    
    -- Ищем ремоуты в основных контейнерах
    local containers = {
        ReplicatedStorage,
        game:GetService("ServerScriptService"),
        game:GetService("ServerStorage"),
        game:GetService("Workspace"),
        game:GetService("Players")
    }
    
    for _, container in ipairs(containers) do
        searchInContainer(container)
    end
    
    log("Найдено %d ремоутов", #allRemotes)
    return allRemotes
end

-- Функция для создания нового имени на основе скрипта
local function generateRemoteName(remote, scriptInfo, counter)
    if not scriptInfo or not scriptInfo.CleanName then
        -- Если нет информации о скрипте, используем родительский путь
        local parentName = getCleanNameFromPath(remote.Parent:GetFullName())
        if parentName then
            return string.format("%s_Remote_%d", parentName, counter or 1)
        end
        return string.format("RenamedRemote_%d", counter or 1)
    end
    
    -- Используем очищенное имя скрипта
    local baseName = scriptInfo.CleanName
    
    -- Добавляем суффикс для уникальности
    if counter and counter > 1 then
        return string.format("%s_%d", baseName, counter)
    end
    
    return baseName
end

-- Функция переименования ремоута
local function renameRemote(remote, newName)
    if not remote or remote.Name == newName then
        return false, "Already has correct name"
    end
    
    local originalName = remote.Name
    
    if CONFIG.USE_RAW_METHOD then
        -- Агрессивный метод через rawset
        local success, result = pcall(function()
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
        
        if success then
            log("Агрессивно переименовано: %s -> %s", originalName, newName)
            return true
        end
    end
    
    -- Стандартный метод
    local success, result = pcall(function()
        remote.Name = newName
        return true
    end)
    
    if success then
        log("Переименовано: %s -> %s", originalName, newName)
        return true
    else
        errorLog("Ошибка переименования %s: %s", originalName, result)
        return false, result
    end
end

-- Основная функция переименования
local function renameAllRemotes()
    log("=== НАЧАЛО ПЕРЕИМЕНОВАНИЯ РЕМОУТОВ ===")
    
    local allRemotes = collectRemoteInfo()
    local renameResults = {
        success = 0,
        failed = 0,
        skipped = 0,
        details = {}
    }
    
    -- Группируем ремоуты по родительским контейнерам
    local groupedRemotes = {}
    for _, remote in ipairs(allRemotes) do
        local parentPath = remote.Parent:GetFullName()
        if not groupedRemotes[parentPath] then
            groupedRemotes[parentPath] = {}
        end
        table.insert(groupedRemotes[parentPath], remote)
    end
    
    -- Переименовываем ремоуты
    for parentPath, remotes in pairs(groupedRemotes) do
        log("Обрабатываем контейнер: %s", parentPath)
        
        -- Собираем информацию о скриптах в этом контейнере
        local scriptNames = {}
        local scriptsInContainer = {}
        
        -- Ищем скрипты в контейнере
        local function collectScripts(container)
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
                    local scriptInfo = getScriptInfo(child)
                    if scriptInfo and scriptInfo.CleanName then
                        scriptNames[scriptInfo.CleanName] = (scriptNames[scriptInfo.CleanName] or 0) + 1
                        scriptsInContainer[child] = scriptInfo
                    end
                end
                collectScripts(child)
            end
        end
        
        collectScripts(remotes[1].Parent)
        
        -- Переименовываем каждый ремоут
        local usedNames = {}
        
        for _, remote in ipairs(remotes) do
            -- Находим ближайший скрипт к ремоуту
            local nearestScript = nil
            local currentParent = remote.Instance.Parent
            
            while currentParent and currentParent ~= game do
                for scriptInstance, scriptInfo in pairs(scriptsInContainer) do
                    if scriptInstance.Parent == currentParent then
                        nearestScript = scriptInfo
                        break
                    end
                end
                
                if nearestScript then break end
                currentParent = currentParent.Parent
            end
            
            -- Генерируем новое имя
            local newName
            if nearestScript then
                local baseName = nearestScript.CleanName
                local counter = usedNames[baseName] or 0
                counter = counter + 1
                usedNames[baseName] = counter
                
                newName = generateRemoteName(remote, nearestScript, counter > 1 and counter or nil)
            else
                -- Используем имя родительского контейнера
                local parentName = getCleanNameFromPath(remote.Parent:GetFullName())
                local counter = usedNames[parentName] or 0
                counter = counter + 1
                usedNames[parentName] = counter
                
                newName = generateRemoteName(remote, {CleanName = parentName}, counter > 1 and counter or nil)
            end
            
            -- Проверяем, нужно ли переименовывать
            if remote.OriginalName == newName then
                log("Пропуск: %s уже имеет правильное имя", remote.OriginalName)
                renameResults.skipped = renameResults.skipped + 1
                table.insert(renameResults.details, {
                    status = "skipped",
                    original = remote.OriginalName,
                    new = newName,
                    path = remote.Path,
                    reason = "Already has correct name"
                })
            else
                -- Пытаемся переименовать
                local success, errorMsg
                
                if CONFIG.RENAME_IN_GAME then
                    success, errorMsg = renameRemote(remote.Instance, newName)
                else
                    success = true -- Только генерация скрипта
                    errorMsg = "In-game rename disabled"
                end
                
                if success then
                    renameResults.success = renameResults.success + 1
                    log("✓ Успех: %s -> %s", remote.OriginalName, newName)
                else
                    renameResults.failed = renameResults.failed + 1
                    errorLog("✗ Ошибка: %s -> %s: %s", remote.OriginalName, newName, errorMsg)
                end
                
                table.insert(renameResults.details, {
                    status = success and "success" or "failed",
                    original = remote.OriginalName,
                    new = newName,
                    path = remote.Path,
                    error = errorMsg
                })
            end
        end
    end
    
    log("=== РЕЗУЛЬТАТЫ ===")
    log("Успешно: %d", renameResults.success)
    log("Пропущено: %d", renameResults.skipped)
    log("Ошибок: %d", renameResults.failed)
    log("Всего обработано: %d", #allRemotes)
    
    -- Генерация скрипта для ручного выполнения
    local generateScript = function()
        local scriptLines = {
            "-- Remote Rename Script",
            "-- Generated at: " .. os.date("%Y-%m-%d %H:%M:%S"),
            "",
            "local remotesToRename = {"
        }
        
        for _, detail in ipairs(renameResults.details) do
            if detail.status == "success" or detail.status == "failed" then
                local line = string.format('    {path = "%s", old = "%s", new = "%s"},',
                    detail.path:gsub('"', '\\"'),
                    detail.original:gsub('"', '\\"'),
                    detail.new:gsub('"', '\\"'))
                table.insert(scriptLines, line)
            end
        end
        
        table.insert(scriptLines, "}")
        table.insert(scriptLines, "")
        table.insert(scriptLines, "for _, remoteInfo in ipairs(remotesToRename) do")
        table.insert(scriptLines, '    local remote = game:GetService("ReplicatedStorage"):FindFirstChild(remoteInfo.old, true)')
        table.insert(scriptLines, "    if remote then")
        table.insert(scriptLines, "        pcall(function()")
        table.insert(scriptLines, '            remote.Name = remoteInfo.new')
        table.insert(scriptLines, string.format('            print("Renamed: " .. remoteInfo.old .. " -> " .. remoteInfo.new)'))
        table.insert(scriptLines, "        end)")
        table.insert(scriptLines, "    end")
        table.insert(scriptLines, "end")
        
        return table.concat(scriptLines, "\n")
    end
    
    local generatedScript = generateScript()
    
    -- Сохраняем в буфер обмена
    local clipboardSuccess = pcall(function()
        if setclipboard then
            setclipboard(generatedScript)
            return true
        end
        return false
    end)
    
    -- Отправка в Discord Webhook
    if CONFIG.SEND_TO_WEBHOOK then
        local function sendToWebhook()
            local summary = string.format(
                "**Remote Rename Results**\n" ..
                "✅ Success: %d\n" ..
                "⏭️ Skipped: %d\n" ..
                "❌ Failed: %d\n" ..
                "📊 Total: %d",
                renameResults.success,
                renameResults.skipped,
                renameResults.failed,
                #allRemotes
            )
            
            local detailsText = "```lua\n"
            for i, detail in ipairs(renameResults.details) do
                if i <= 15 then -- Ограничиваем количество строк
                    detailsText = detailsText .. string.format("%s: %s -> %s\n",
                        detail.status:upper(),
                        detail.original,
                        detail.new)
                elseif i == 16 then
                    detailsText = detailsText .. "... and more\n"
                    break
                end
            end
            detailsText = detailsText .. "```"
            
            local payload = {
                embeds = {{
                    title = "Remote Renamer Report",
                    description = summary,
                    color = renameResults.failed > 0 and 0xFF0000 or 0x00FF00,
                    fields = {
                        {
                            name = "Details",
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
                        text = string.format("Executed by %s", Players.LocalPlayer.Name)
                    },
                    timestamp = DateTime.now():ToIsoDate()
                }},
                username = "Remote Renamer"
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
        
        local webhookSuccess, webhookResult = pcall(sendToWebhook)
        if webhookSuccess then
            log("Отчет отправлен в Discord")
        else
            errorLog("Ошибка отправки в Discord: %s", webhookResult)
        end
    end
    
    -- Вывод результатов пользователю
    local resultMessage = string.format(
        "Remote Renamer завершил работу!\n" ..
        "✅ Успешно: %d\n" ..
        "⏭️ Пропущено: %d\n" ..
        "❌ Ошибок: %d\n" ..
        "📊 Всего: %d\n\n" ..
        "%sСкрипт сгенерирован!",
        renameResults.success,
        renameResults.skipped,
        renameResults.failed,
        #allRemotes,
        clipboardSuccess and "📋 Скрипт скопирован в буфер!\n" or ""
    )
    
    -- Показываем уведомление
    if rconsoleprint then
        rconsoleclear()
        rconsoleprint("@@WHITE@@")
        rconsoleprint("=== REMOTE RENAMER RESULTS ===\n")
        rconsoleprint(resultMessage .. "\n")
        
        -- Показываем детали
        rconsoleprint("\n=== DETAILS ===\n")
        for i, detail in ipairs(renameResults.details) do
            if i <= 20 then
                local color = detail.status == "success" and "@@GREEN@@" or 
                             detail.status == "failed" and "@@RED@@" or "@@YELLOW@@"
                rconsoleprint(color)
                rconsoleprint(string.format("%s: %s -> %s\n", 
                    detail.status:upper(), detail.original, detail.new))
            end
        end
    end
    
    -- Вывод в обычную консоль
    print("\n" .. string.rep("=", 50))
    print("REMOTE RENAMER RESULTS")
    print(string.rep("=", 50))
    print(resultMessage)
    print(string.rep("=", 50))
    
    return renameResults, generatedScript
end

-- Функция для создания интерфейса (опционально)
local function createSimpleUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RemoteRenamerUI"
    screenGui.ResetOnSpawn = false
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 300, 0, 200)
    mainFrame.Position = UDim2.new(0.5, -150, 0.5, -100)
    mainFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Text = "Remote Renamer"
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 18
    title.Parent = mainFrame
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "Status"
    statusLabel.Text = "Готов к работе"
    statusLabel.Size = UDim2.new(1, -20, 0, 60)
    statusLabel.Position = UDim2.new(0, 10, 0, 40)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextSize = 14
    statusLabel.TextWrapped = true
    statusLabel.Parent = mainFrame
    
    local renameButton = Instance.new("TextButton")
    renameButton.Name = "RenameButton"
    renameButton.Text = "Переименовать все ремоуты"
    renameButton.Size = UDim2.new(1, -20, 0, 40)
    renameButton.Position = UDim2.new(0, 10, 0, 110)
    renameButton.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    renameButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    renameButton.Font = Enum.Font.SourceSansBold
    renameButton.TextSize = 16
    renameButton.Parent = mainFrame
    
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Text = "Закрыть"
    closeButton.Size = UDim2.new(1, -20, 0, 30)
    closeButton.Position = UDim2.new(0, 10, 0, 160)
    closeButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.Font = Enum.Font.SourceSans
    closeButton.TextSize = 14
    closeButton.Parent = mainFrame
    
    -- Обработчики событий
    renameButton.MouseButton1Click:Connect(function()
        statusLabel.Text = "Выполняется переименование...\nПожалуйста, подождите."
        renameButton.Active = false
        
        local results, script = renameAllRemotes()
        
        statusLabel.Text = string.format(
            "Готово!\n" ..
            "Успешно: %d\n" ..
            "Пропущено: %d\n" ..
            "Ошибок: %d",
            results.success,
            results.skipped,
            results.failed
        )
        
        renameButton.Active = true
    end)
    
    closeButton.MouseButton1Click:Connect(function()
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

-- Основная функция инициализации
local function initialize()
    log("Инициализация Remote Renamer...")
    
    -- Создаем интерфейс
    local ui = createSimpleUI()
    
    -- Автоматически запускаем переименование
    task.wait(2)
    
    log("Автозапуск переименования через 3 секунды...")
    for i = 3, 1, -1 do
        log("Запуск через %d...", i)
        task.wait(1)
    end
    
    -- Выполняем переименование
    local results, generatedScript = renameAllRemotes()
    
    -- Показываем результат в интерфейсе
    if ui and ui:FindFirstChild("MainFrame") then
        local statusLabel = ui.MainFrame:FindFirstChild("Status")
        if statusLabel then
            statusLabel.Text = string.format(
                "Автоматическое переименование завершено!\n" ..
                "Успешно: %d\n" ..
                "Пропущено: %d\n" ..
                "Ошибок: %d\n\n" ..
                "Скрипт сгенерирован и скопирован!",
                results.success,
                results.skipped,
                results.failed
            )
        end
    end
    
    log("Remote Renamer успешно инициализирован!")
    
    return {
        RenameAll = renameAllRemotes,
        GetRemoteInfo = collectRemoteInfo,
        UI = ui
    }
end

-- Запуск скрипта
local success, err = pcall(initialize)
if not success then
    errorLog("Ошибка инициализации: %s", err)
    
    -- Пытаемся хотя бы выполнить переименование без интерфейса
    pcall(function()
        renameAllRemotes()
    end)
end

-- Экспорт функций для ручного использования
getgenv().RemoteRenamer = {
    RenameAllRemotes = renameAllRemotes,
    CollectRemoteInfo = collectRemoteInfo,
    GenerateScript = function()
        local remotes = collectRemoteInfo()
        local renameResults = {
            success = 0,
            failed = 0,
            skipped = 0,
            details = {}
        }
        
        for _, remote in ipairs(remotes) do
            table.insert(renameResults.details, {
                original = remote.OriginalName,
                path = remote.Path,
                new = remote.OriginalName .. "_Renamed"
            })
        end
        
        local scriptLines = {
            "-- Auto-generated Remote Rename Script",
            "-- Place this script in a LocalScript",
            "",
            "local remotesToRename = {"
        }
        
        for _, detail in ipairs(renameResults.details) do
            table.insert(scriptLines, string.format('    {path = "%s", old = "%s", new = "%s"},',
                detail.path, detail.original, detail.new))
        end
        
        table.insert(scriptLines, "}")
        table.insert(scriptLines, "")
        table.insert(scriptLines, "for _, remoteInfo in ipairs(remotesToRename) do")
        table.insert(scriptLines, '    local success, remote = pcall(function()')
        table.insert(scriptLines, '        return game:GetService("ReplicatedStorage"):FindFirstChild(remoteInfo.old, true)')
        table.insert(scriptLines, "    end)")
        table.insert(scriptLines, "    if success and remote then")
        table.insert(scriptLines, "        pcall(function()")
        table.insert(scriptLines, "            remote.Name = remoteInfo.new")
        table.insert(scriptLines, "        end)")
        table.insert(scriptLines, "    end")
        table.insert(scriptLines, "end")
        
        local finalScript = table.concat(scriptLines, "\n")
        
        if setclipboard then
            setclipboard(finalScript)
            print("Скрипт скопирован в буфер обмена!")
        end
        
        return finalScript
    end
}
