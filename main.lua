-- Lightweight Remote Renamer
-- Быстрое переименование всех RemoteEvents и RemoteFunctions

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Упрощенная конфигурация
local CONFIG = {
    RENAME_IN_GAME = true,      -- Переименовывать сразу в игре
    SIMPLE_NAMES = true,        -- Использовать простые имена
    MAX_PER_FRAME = 5,          -- Максимум ремоутов за кадр (для оптимизации)
    BATCH_SIZE = 50             -- Размер батча для обработки
}

-- Глобальные переменные
local processedRemotes = 0
local successfullyRenamed = 0

-- Функция для быстрого поиска ремоутов
local function findRemotesQuick()
    local remotes = {}
    local checked = {}
    
    -- Основные места для поиска
    local searchLocations = {
        ReplicatedStorage,
        game:GetService("ServerStorage"),
        game:GetService("ServerScriptService"),
        game:GetService("Workspace"),
        game:GetService("StarterPack"),
        game:GetService("StarterPlayer")
    }
    
    -- Быстрая проверка основных мест
    for _, location in ipairs(searchLocations) do
        local success, result = pcall(function()
            local descendants = location:GetDescendants()
            for _, obj in ipairs(descendants) do
                if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and not checked[obj] then
                    table.insert(remotes, {
                        Instance = obj,
                        Name = obj.Name,
                        Parent = obj.Parent,
                        ClassName = obj.ClassName,
                        Path = obj:GetFullName()
                    })
                    checked[obj] = true
                end
            end
        end)
        
        if not success then
            -- Если GetDescendants медленный, проверяем только первые уровни
            local children = location:GetChildren()
            for _, child in ipairs(children) do
                if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                    table.insert(remotes, {
                        Instance = child,
                        Name = child.Name,
                        Parent = child.Parent,
                        ClassName = child.ClassName,
                        Path = child:GetFullName()
                    })
                end
            end
        end
    end
    
    print("[Renamer] Найдено ремоутов: " .. #remotes)
    return remotes
end

-- Простая генерация имени
local function generateSimpleName(remote, index)
    if CONFIG.SIMPLE_NAMES then
        local prefix = ""
        if remote:IsA("RemoteEvent") then
            prefix = "Event_"
        elseif remote:IsA("RemoteFunction") then
            prefix = "Function_"
        end
        
        local parentName = remote.Parent.Name
        local cleanParent = parentName:gsub("[^%w_]", ""):sub(1, 20)
        
        return prefix .. cleanParent .. "_" .. index
    else
        -- Более простой вариант
        if remote:IsA("RemoteEvent") then
            return "RemoteEvent_" .. index
        elseif remote:IsA("RemoteFunction") then
            return "RemoteFunction_" .. index
        end
        return "Remote_" .. index
    end
end

-- Быстрое переименование батчами
local function renameBatch(batch)
    local results = {
        success = 0,
        failed = 0,
        details = {}
    }
    
    for i, remoteData in ipairs(batch) do
        local remote = remoteData.Instance
        local newName = generateSimpleName(remote, i + processedRemotes)
        
        if remote.Name ~= newName then
            local success, errorMsg = pcall(function()
                remote.Name = newName
            end)
            
            if success then
                results.success = results.success + 1
                table.insert(results.details, {
                    original = remoteData.Name,
                    new = newName,
                    success = true
                })
            else
                results.failed = results.failed + 1
                table.insert(results.details, {
                    original = remoteData.Name,
                    error = errorMsg,
                    success = false
                })
            end
        else
            table.insert(results.details, {
                original = remoteData.Name,
                new = newName,
                success = true,
                already = true
            })
        end
    end
    
    return results
end

-- Основная функция
local function renameRemotesLightweight()
    print("=== Lightweight Remote Renamer ===")
    print("Начинаю поиск ремоутов...")
    
    -- Находим ремоуты
    local allRemotes = findRemotesQuick()
    
    if #allRemotes == 0 then
        print("Ремоуты не найдены!")
        return
    end
    
    print("Найдено: " .. #allRemotes .. " ремоутов")
    print("Начинаю переименование...")
    
    -- Разбиваем на батчи для оптимизации
    local batches = {}
    for i = 1, #allRemotes, CONFIG.BATCH_SIZE do
        local batch = {}
        for j = i, math.min(i + CONFIG.BATCH_SIZE - 1, #allRemotes) do
            table.insert(batch, allRemotes[j])
        end
        table.insert(batches, batch)
    end
    
    local totalResults = {
        success = 0,
        failed = 0,
        skipped = 0
    }
    
    local renameLog = {}
    
    -- Обрабатываем каждый батч
    for batchIndex, batch in ipairs(batches) do
        print(string.format("Батч %d/%d (%d ремоутов)", 
            batchIndex, #batches, #batch))
        
        -- Небольшая задержка между батчами
        if batchIndex > 1 then
            wait(0.05) -- Минимальная задержка
        end
        
        local results = renameBatch(batch)
        
        totalResults.success = totalResults.success + results.success
        totalResults.failed = totalResults.failed + results.failed
        
        -- Добавляем в лог
        for _, detail in ipairs(results.details) do
            table.insert(renameLog, detail)
        end
        
        processedRemotes = processedRemotes + #batch
        
        -- Обновляем прогресс
        print(string.format("  Прогресс: %d/%d (Успешно: %d, Ошибок: %d)", 
            processedRemotes, #allRemotes, totalResults.success, totalResults.failed))
    end
    
    -- Формируем простой отчет
    local simpleScript = "-- Lightweight Remote Renamer Script\n"
    simpleScript = simpleScript .. "-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    simpleScript = simpleScript .. "-- Total remotes: " .. #allRemotes .. "\n"
    simpleScript = simpleScript .. "-- Renamed: " .. totalResults.success .. "\n"
    simpleScript = simpleScript .. "-- Failed: " .. totalResults.failed .. "\n\n"
    
    -- Добавляем команды только для успешных переименований
    for i, logEntry in ipairs(renameLog) do
        if logEntry.success and not logEntry.already then
            simpleScript = simpleScript .. "-- " .. logEntry.original .. " -> " .. logEntry.new .. "\n"
        end
    end
    
    simpleScript = simpleScript .. "\nprint(\"Renamed " .. totalResults.success .. " remotes\")"
    
    -- Копируем в буфер
    if setclipboard then
        setclipboard(simpleScript)
        print("\nСкрипт скопирован в буфер обмена")
    end
    
    -- Простой вывод результатов
    print("\n" .. string.rep("=", 50))
    print("РЕЗУЛЬТАТЫ:")
    print(string.rep("-", 50))
    print("Всего ремоутов: " .. #allRemotes)
    print("Обработано: " .. processedRemotes)
    print("Успешно переименовано: " .. totalResults.success)
    print("Не удалось: " .. totalResults.failed)
    print(string.rep("=", 50))
    
    -- Показываем несколько примеров
    if #renameLog > 0 then
        print("\nПримеры переименований:")
        local examples = math.min(5, #renameLog)
        for i = 1, examples do
            local logEntry = renameLog[i]
            if logEntry.success then
                print(string.format("  %s → %s", logEntry.original, logEntry.new))
            end
        end
        
        if #renameLog > examples then
            print("  ... и еще " .. (#renameLog - examples))
        end
    end
    
    return {
        total = #allRemotes,
        processed = processedRemotes,
        success = totalResults.success,
        failed = totalResults.failed,
        script = simpleScript
    }
end

-- Запускаем с защитой от ошибок
local success, result = pcall(renameRemotesLightweight)

if not success then
    print("Ошибка: " .. tostring(result))
    
    -- Максимально простая альтернатива
    print("\nПробую альтернативный простой метод...")
    
    local count = 0
    local function quickRename(obj)
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            pcall(function()
                obj.Name = "Renamed_" .. tostring(count)
                count = count + 1
            end)
        end
    end
    
    -- Только основные места
    local locations = {ReplicatedStorage, workspace}
    for _, loc in ipairs(locations) do
        local children = loc:GetChildren()
        for _, child in ipairs(children) do
            quickRename(child)
        end
    end
    
    print("Быстро переименовано: " .. count .. " ремоутов")
end

print("\nГотово!")
