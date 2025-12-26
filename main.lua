-- Simple Remote Renamer
-- Автоматически переименовывает все RemoteEvents и RemoteFunctions в игре
-- На основе скриптов, которые их вызывают

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Конфигурация
local CONFIG = {
    WEBHOOK_URL = "https://discord.com/api/webhooks/1434181472423776277/wrgeevBbOT05meDtUawJvTomccDgrCn8qml8x2Y18fRhAswj_fOPE3LLM13-R3bCkC7g",
    SEND_TO_DISCORD = true,
    RENAME_IN_GAME = true,
    DEBUG_MODE = true
}

-- Глобальные переменные
local renamedRemotes = {}
local remoteCallers = {}
local processedRemotes = 0
local successfullyRenamed = 0

-- Функция для логирования
local function log(message)
    if CONFIG.DEBUG_MODE then
        print("[RemoteRenamer]: " .. message)
    end
end

-- Функция для отправки на Discord вебхук
local function sendToDiscord(message)
    if not CONFIG.SEND_TO_DISCORD or not CONFIG.WEBHOOK_URL then
        return false
    end
    
    local success, result = pcall(function()
        local payload = {
            content = message,
            username = "Remote Renamer",
            avatar_url = "https://cdn.discordapp.com/attachments/1067061486574907412/1067061597392310292/Simple_Spy_logo.png"
        }
        
        local jsonPayload = HttpService:JSONEncode(payload)
        
        -- Пробуем разные методы отправки
        local requestFunc = syn and syn.request or request or http_request
        if requestFunc then
            requestFunc({
                Url = CONFIG.WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        else
            -- Альтернативный метод через HttpPostAsync
            HttpService:PostAsync(CONFIG.WEBHOOK_URL, jsonPayload, Enum.HttpContentType.ApplicationJson)
        end
        
        return true
    end)
    
    return success
end

-- Функция для поиска всех ремоутов в игре
local function findAllRemotes()
    local remotes = {}
    
    -- Рекурсивная функция поиска
    local function searchIn(instance)
        if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") or instance:IsA("UnreliableRemoteEvent") then
            table.insert(remotes, {
                Instance = instance,
                Path = instance:GetFullName(),
                OriginalName = instance.Name,
                Parent = instance.Parent,
                ClassName = instance.ClassName
            })
        end
        
        -- Ищем в дочерних объектах
        for _, child in ipairs(instance:GetChildren()) do
            searchIn(child)
        end
    end
    
    -- Начинаем поиск с основных мест
    searchIn(game)
    
    log("Найдено ремоутов: " .. #remotes)
    return remotes
end

-- Функция для получения информации о вызове ремоута
local function getRemoteCallerInfo(remote)
    -- Этот метод использует debug.traceback для отслеживания вызовов
    -- Внимание: может не работать в некоторых окружениях
    local callerInfo = {
        ScriptName = "Unknown",
        ScriptPath = "Unknown",
        FunctionName = "Unknown"
    }
    
    -- Пробуем получить информацию через debug.traceback
    local success, traceback = pcall(function()
        -- Создаем временную функцию для вызова
        local function tempCall()
            if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
                remote:FireServer("__REMOTE_RENAMER_PROBE__")
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer("__REMOTE_RENAMER_PROBE__")
            end
        end
        
        -- Запускаем и перехватываем ошибку
        xpcall(tempCall, function(err)
            return debug.traceback(err)
        end)
    end)
    
    if success and traceback then
        -- Анализируем traceback для поиска информации о скрипте
        for line in traceback:gmatch("[^\n]+") do
            if line:find("Script") and not line:find("RemoteRenamer") then
                -- Пробуем извлечь имя скрипта
                local scriptMatch = line:match("(%w+%.lua)")
                if scriptMatch then
                    callerInfo.ScriptName = scriptMatch:gsub("%.lua$", "")
                    break
                end
                
                -- Альтернативный поиск
                local pathMatch = line:match("game%.([%w%.]+)")
                if pathMatch then
                    callerInfo.ScriptPath = pathMatch
                    -- Извлекаем последнюю часть как имя
                    local parts = {}
                    for part in pathMatch:gmatch("[%w_]+") do
                        table.insert(parts, part)
                    end
                    if #parts > 0 then
                        callerInfo.ScriptName = parts[#parts]
                    end
                    break
                end
            end
        end
    end
    
    return callerInfo
end

-- Альтернативный метод: анализ существующих вызовов через хук
local function hookRemotesForAnalysis()
    log("Начинаем анализ вызовов ремоутов...")
    
    -- Временное хранилище для отслеживания вызовов
    local callTracker = {}
    
    -- Создаем защищенные ссылки на оригинальные методы
    local originalFireServer
    local originalInvokeServer
    
    -- Функция для отслеживания вызовов FireServer
    local function trackFireServer(remote, ...)
        local callerScript = getcallingscript()
        if callerScript then
            local remoteId = tostring(remote)
            if not callTracker[remoteId] then
                callTracker[remoteId] = {
                    Remote = remote,
                    CallerScript = callerScript,
                    CallCount = 0
                }
            end
            callTracker[remoteId].CallCount = callTracker[remoteId].CallCount + 1
            log("Вызов FireServer: " .. remote.Name .. " из " .. callerScript.Name)
        end
        
        -- Вызываем оригинальный метод
        if originalFireServer then
            return originalFireServer(remote, ...)
        end
    end
    
    -- Функция для отслеживания вызовов InvokeServer
    local function trackInvokeServer(remote, ...)
        local callerScript = getcallingscript()
        if callerScript then
            local remoteId = tostring(remote)
            if not callTracker[remoteId] then
                callTracker[remoteId] = {
                    Remote = remote,
                    CallerScript = callerScript,
                    CallCount = 0
                }
            end
            callTracker[remoteId].CallCount = callTracker[remoteId].CallCount + 1
            log("Вызов InvokeServer: " .. remote.Name .. " из " .. callerScript.Name)
        end
        
        -- Вызываем оригинальный метод
        if originalInvokeServer then
            return originalInvokeServer(remote, ...)
        end
    end
    
    -- Пробуем установить хуки
    local success = pcall(function()
        -- Сохраняем оригинальные методы
        local remoteEvent = Instance.new("RemoteEvent")
        local remoteFunction = Instance.new("RemoteFunction")
        
        originalFireServer = remoteEvent.FireServer
        originalInvokeServer = remoteFunction.InvokeServer
        
        remoteEvent:Destroy()
        remoteFunction:Destroy()
        
        -- Устанавливаем хуки
        if hookfunction then
            hookfunction(originalFireServer, trackFireServer)
            hookfunction(originalInvokeServer, trackInvokeServer)
            log("Хуки установлены успешно")
        else
            log("hookfunction не доступен")
        end
    end)
    
    if not success then
        log("Не удалось установить хуки, используем альтернативный метод")
    end
    
    return callTracker
end

-- Функция для генерации нового имени на основе скрипта
local function generateNewName(remote, callerInfo)
    local baseName = callerInfo.ScriptName
    
    -- Если не удалось определить имя скрипта, используем родительскую папку
    if baseName == "Unknown" or baseName:len() < 2 then
        baseName = remote.Parent.Name
    end
    
    -- Очищаем имя
    local cleanName = baseName:gsub("%s+", "_")
    cleanName = cleanName:gsub("[^%w_]", "")
    
    -- Добавляем суффикс в зависимости от типа
    if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
        return cleanName .. "_Event"
    elseif remote:IsA("RemoteFunction") then
        return cleanName .. "_Function"
    end
    
    return cleanName .. "_Remote"
end

-- Основная функция переименования
local function renameRemotes()
    log("Запуск Remote Renamer...")
    
    -- Находим все ремоуты
    local allRemotes = findAllRemotes()
    log("Всего найдено ремоутов: " .. #allRemotes)
    
    -- Собираем информацию о вызовах
    local callTracker = hookRemotesForAnalysis()
    
    -- Ждем немного для сбора статистики
    log("Сбор статистики вызовов (5 секунд)...")
    wait(5)
    
    -- Создаем отчет
    local report = "=== ОТЧЕТ О ПЕРЕИМЕНОВАНИИ РЕМОУТОВ ===\n\n"
    report = report .. "Всего ремоутов: " .. #allRemotes .. "\n"
    
    local renameCommands = {}
    local renameLog = {}
    
    -- Обрабатываем каждый ремоут
    for _, remoteData in ipairs(allRemotes) do
        processedRemotes = processedRemotes + 1
        local remote = remoteData.Instance
        
        -- Получаем информацию о вызывающем скрипте
        local callerInfo = {
            ScriptName = "Unknown",
            ScriptPath = "Unknown"
        }
        
        -- Проверяем, есть ли информация в трекере
        local remoteId = tostring(remote)
        if callTracker and callTracker[remoteId] then
            local trackerData = callTracker[remoteId]
            if trackerData.CallerScript then
                callerInfo.ScriptName = trackerData.CallerScript.Name
                callerInfo.ScriptPath = trackerData.CallerScript:GetFullName()
            end
        else
            -- Используем альтернативный метод
            callerInfo = getRemoteCallerInfo(remote)
        end
        
        -- Генерируем новое имя
        local newName = generateNewName(remote, callerInfo)
        
        -- Проверяем, нужно ли переименовывать
        if newName ~= remote.Name then
            -- Создаем команду для переименования
            local command = string.format([[
-- Переименование: %s -> %s
-- Тип: %s
-- Путь: %s
-- Вызывающий скрипт: %s
local remote = game:GetService("%s"):WaitForChild("%s"):WaitForChild("%s")
if remote then
    remote.Name = "%s"
    print("✅ Переименован: %s -> %s")
end
]],
                remote.Name,
                newName,
                remote.ClassName,
                remote:GetFullName(),
                callerInfo.ScriptName,
                remote.Parent.ClassName,
                remote.Parent.Name,
                remote.Name,
                newName,
                remote.Name,
                newName
            )
            
            table.insert(renameCommands, command)
            
            -- Записываем в лог
            table.insert(renameLog, {
                OriginalName = remote.Name,
                NewName = newName,
                Path = remote:GetFullName(),
                ClassName = remote.ClassName,
                CallerScript = callerInfo.ScriptName,
                Command = command
            })
            
            -- Пробуем переименовать в игре
            if CONFIG.RENAME_IN_GAME then
                local success = pcall(function()
                    remote.Name = newName
                    successfullyRenamed = successfullyRenamed + 1
                    log("Успешно переименован: " .. remoteData.OriginalName .. " -> " .. newName)
                end)
                
                if not success then
                    log("Не удалось переименовать: " .. remoteData.OriginalName .. " (защищен)")
                end
            end
        end
    end
    
    -- Формируем итоговый скрипт
    local finalScript = "-- === AUTO REMOTE RENAME SCRIPT ===\n"
    finalScript = finalScript .. "-- Сгенерировано Remote Renamer\n"
    finalScript = finalScript .. "-- Время: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    finalScript = finalScript .. "-- Всего ремоутов: " .. #allRemotes .. "\n"
    finalScript = finalScript .. "-- Для переименования: " .. #renameCommands .. "\n\n"
    
    for i, command in ipairs(renameCommands) do
        finalScript = finalScript .. command .. "\n\n"
    end
    
    finalScript = finalScript .. string.format([[
print("==================================")
print("Remote Renamer завершил работу")
print("Обработано ремоутов: %d")
print("Успешно переименовано: %d")
print("==================================")]],
        processedRemotes,
        successfullyRenamed
    )
    
    -- Копируем в буфер обмена
    if setclipboard then
        setclipboard(finalScript)
        log("Скрипт скопирован в буфер обмена (" .. #finalScript .. " символов)")
    end
    
    -- Формируем отчет для Discord
    local discordMessage = "**Remote Renamer - Отчет**\n\n"
    discordMessage = discordMessage .. "**Статистика:**\n"
    discordMessage = discordMessage .. "• Всего ремоутов: " .. #allRemotes .. "\n"
    discordMessage = discordMessage .. "• Обработано: " .. processedRemotes .. "\n"
    discordMessage = discordMessage .. "• Успешно переименовано: " .. successfullyRenamed .. "\n\n"
    
    if #renameLog > 0 then
        discordMessage = discordMessage .. "**Переименованные ремоуты:**\n"
        discordMessage = discordMessage .. "```\n"
        
        for i, logEntry in ipairs(renameLog) do
            if i <= 15 then -- Ограничиваем для Discord
                discordMessage = discordMessage .. string.format("%s → %s\n", 
                    logEntry.OriginalName, 
                    logEntry.NewName)
            end
        end
        
        if #renameLog > 15 then
            discordMessage = discordMessage .. "... и еще " .. (#renameLog - 15) .. "\n"
        end
        
        discordMessage = discordMessage .. "```\n"
    end
    
    discordMessage = discordMessage .. "**Скрипт:**\n"
    discordMessage = discordMessage .. "```lua\n" .. finalScript:sub(1, 1000) .. "\n...\n```"
    
    -- Отправляем на Discord
    if CONFIG.SEND_TO_DISCORD then
        local webhookSuccess = sendToDiscord(discordMessage)
        if webhookSuccess then
            log("Отчет отправлен на Discord")
        else
            log("Не удалось отправить отчет на Discord")
        end
    end
    
    -- Выводим итоговый отчет
    report = report .. "Обработано: " .. processedRemotes .. "\n"
    report = report .. "Успешно переименовано: " .. successfullyRenamed .. "\n\n"
    
    if #renameLog > 0 then
        report = report .. "СПИСОК ПЕРЕИМЕНОВАНИЙ:\n"
        report = report .. string.rep("=", 50) .. "\n"
        
        for _, logEntry in ipairs(renameLog) do
            report = report .. string.format("[%s] %s → %s\n", 
                logEntry.ClassName,
                logEntry.OriginalName,
                logEntry.NewName)
            report = report .. "    Путь: " .. logEntry.Path .. "\n"
            report = report .. "    Скрипт: " .. logEntry.CallerScript .. "\n"
            report = report .. string.rep("-", 50) .. "\n"
        end
    end
    
    -- Показываем уведомление
    if Players.LocalPlayer then
        local notification = Instance.new("ScreenGui", Players.LocalPlayer:WaitForChild("PlayerGui"))
        local frame = Instance.new("Frame", notification)
        frame.Size = UDim2.new(0, 300, 0, 150)
        frame.Position = UDim2.new(0.5, -150, 0.5, -75)
        frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        
        local title = Instance.new("TextLabel", frame)
        title.Size = UDim2.new(1, 0, 0, 40)
        title.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        title.Text = "Remote Renamer"
        title.TextColor3 = Color3.new(1, 1, 1)
        title.TextSize = 18
        
        local message = Instance.new("TextLabel", frame)
        message.Position = UDim2.new(0, 10, 0, 50)
        message.Size = UDim2.new(1, -20, 0, 60)
        message.BackgroundTransparency = 1
        message.Text = string.format("Обработано: %d\nПереименовано: %d\nСкрипт в буфере", 
            processedRemotes, successfullyRenamed)
        message.TextColor3 = Color3.new(1, 1, 1)
        message.TextSize = 14
        
        local closeBtn = Instance.new("TextButton", frame)
        closeBtn.Position = UDim2.new(0.5, -50, 1, -35)
        closeBtn.Size = UDim2.new(0, 100, 0, 30)
        closeBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
        closeBtn.Text = "Закрыть"
        closeBtn.TextColor3 = Color3.new(1, 1, 1)
        
        closeBtn.MouseButton1Click:Connect(function()
            notification:Destroy()
        end)
        
        -- Автоматическое закрытие через 10 секунд
        delay(10, function()
            if notification then
                notification:Destroy()
            end
        end)
    end
    
    -- Выводим отчет в консоль
    print("\n" .. report)
    log("Remote Renamer завершил работу")
    
    return {
        TotalRemotes = #allRemotes,
        Processed = processedRemotes,
        Renamed = successfullyRenamed,
        Script = finalScript,
        Log = renameLog
    }
end

-- Запускаем переименование
local success, result = pcall(renameRemotes)

if not success then
    log("Ошибка при выполнении: " .. tostring(result))
    
    -- Альтернативный простой метод
    log("Пробуем простой метод переименования...")
    
    local simpleResult = pcall(function()
        local allRemotes = findAllRemotes()
        local simpleRenamed = 0
        
        for _, remoteData in ipairs(allRemotes) do
            local remote = remoteData.Instance
            local parentName = remote.Parent.Name
            local cleanName = parentName:gsub("[^%w_]", "_")
            
            local newName
            if remote:IsA("RemoteEvent") then
                newName = cleanName .. "_Event"
            elseif remote:IsA("RemoteFunction") then
                newName = cleanName .. "_Function"
            else
                newName = cleanName .. "_Remote"
            end
            
            if pcall(function() remote.Name = newName end) then
                simpleRenamed = simpleRenamed + 1
                log("Простое переименование: " .. remoteData.OriginalName .. " -> " .. newName)
            end
        end
        
        return simpleRenamed
    end)
    
    log("Простой метод завершил: " .. (simpleResult and "успешно" or "с ошибкой"))
end

log("Скрипт Remote Renamer завершил выполнение")
