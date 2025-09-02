# ================== НАСТРОЙКИ ==================
# JSON с матрицей
$JsonPath       = "..\resources\matrix\infodata.json"

# Базовый каталог для addons
$BaseAddonsDir  = "..\addons"

# SOCKS5 прокси
$ProxyUrl       = "127.0.0.1:1086"
# ===============================================

if (-not (Test-Path $JsonPath)) {
    Write-Error "Файл $JsonPath не найден."
    exit 1
}

# Загружаем JSON
$infodata = Get-Content $JsonPath -Raw | ConvertFrom-Json
$addons   = $infodata.addons.PSObject.Properties.Name | Sort-Object -Unique

# --- функции для форматирования ---
function Format-IniLine {
    param ([string]$Key,[string]$Value)
    $padding = 25 - $Key.Length
    if ($padding -lt 1) { $padding = 1 }
    $spaces = " " * $padding
    return "$Key$spaces= $Value"
}

function Convert-ToIni {
    param ([string]$SectionName,[object]$Data)

    $lines = @()
    $lines += "[$SectionName]"
    $lines += ""  # пустая строка после имени секции

    $props = $Data.PSObject.Properties | Sort-Object Name

    foreach ($prop in $props) {
        if ($prop.Value -is [PSCustomObject]) {
            $lines += Convert-ToIni -SectionName $prop.Name -Data $prop.Value
        }
        elseif ($prop.Value -is [System.Collections.IDictionary]) {
            foreach ($kv in ($prop.Value.GetEnumerator() | Sort-Object Key)) {
                $lines += (Format-IniLine $kv.Key $kv.Value)
            }
        }
        else {
            $lines += (Format-IniLine $prop.Name $prop.Value)
        }
    }
    return $lines
}

# --- основной цикл по аддонам ---
foreach ($AddonName in $addons) {
    $addon = $infodata.addons.$AddonName
    if (-not $addon.DownloadUrl) {
        Write-Host "⏭ Пропуск аддона '$AddonName' (нет DownloadUrl)"
        continue
    }

    Write-Host "=== Обработка аддона $AddonName ==="

    # Пути
    $DestDir  = Join-Path $BaseAddonsDir $AddonName
    $HelpDir  = "$DestDir\ospanel_data\help"
    $IniPath  = "$DestDir\ospanel_data\addon.ini"
    $ZipPath  = if ($addon.ZipPath) { $addon.ZipPath } else { "$AddonName.zip" }

    # 1. Скачать архив через curl + SOCKS5
    Write-Host "Скачивание $($addon.DownloadUrl) -> $ZipPath через SOCKS5 $ProxyUrl"
    & curl --socks5 $ProxyUrl -L -o $ZipPath $addon.DownloadUrl
    if (-not (Test-Path $ZipPath)) {
        Write-Error "Ошибка: не удалось скачать $ZipPath"
        continue
    }

    # 2. Извлечь архив (fix для DB2-ODBC)
    if (-not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    }

    if ($AddonName -eq "DB2-ODBC") {
        $tmpDir = Join-Path $DestDir "_tmp"
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force
        $clidriver = Join-Path $tmpDir "clidriver"
        if (Test-Path $clidriver) {
            Get-ChildItem -Path $clidriver | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
        }
        Remove-Item $tmpDir -Recurse -Force
    }
    else {
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force
    }

    Remove-Item $ZipPath -Force

    # 3. Help
# 3. Help
if (-not (Test-Path $HelpDir)) {
    New-Item -ItemType Directory -Force -Path $HelpDir | Out-Null
}

if ($AddonName -eq "ErlangOTP") {
    Write-Host "⏭ Пропуск генерации help для ErlangOTP"
    $executables = @()
}
elseif ($AddonName -in @("DB2-ODBC")) {
    $executables = Get-ChildItem -Path (Join-Path $DestDir "bin") -Filter *.exe -Recurse -ErrorAction SilentlyContinue
}
else {
    $executables = Get-ChildItem -Path $DestDir -Filter *.exe -Recurse -ErrorAction SilentlyContinue
}


    $helpCmd = if ($addon.help) { $addon.help } else { "--help" }

    foreach ($exe in $executables) {
        $outFile = Join-Path $HelpDir ($exe.BaseName + ".txt")
        try {
            $args = $helpCmd -split "\s+"
            $output = & $exe.FullName @($args) 2>&1
            $output | Out-File -FilePath $outFile -Encoding utf8
            Write-Host "Создан файл помощи: $outFile"
        }
        catch {
            Write-Warning "Ошибка при вызове help у $($exe.FullName): $_"
        }
    }

    # 4. addon.ini
    $sectionsOrder = @("main","docs","environment")
    $skipSections  = @("DownloadUrl","ZipPath","help")

    $iniContent = @()

    foreach ($sec in $sectionsOrder) {
        if ($addon.PSObject.Properties.Name -contains $sec) {
            $iniContent += Convert-ToIni -SectionName $sec -Data $addon.$sec
            $iniContent += ""
        }
    }

    $otherSections = $addon.PSObject.Properties.Name |
                     Where-Object { $sectionsOrder -notcontains $_ -and $skipSections -notcontains $_ } |
                     Sort-Object

    foreach ($sec in $otherSections) {
        $iniContent += Convert-ToIni -SectionName $sec -Data $addon.$sec
        $iniContent += ""
    }

    $iniDir = Split-Path $IniPath -Parent
    if (-not (Test-Path $iniDir)) {
        New-Item -ItemType Directory -Force -Path $iniDir | Out-Null
    }
    $iniContent | Out-File -FilePath $IniPath -Encoding utf8 -Force
    Write-Host "Файл INI создан: $IniPath"

# 5. Копирование дополнительных файлов из addons_bundle
    $bundleSrc = "..\resources\addons_bundle\$AddonName"
    $bundleDst = Join-Path $DestDir "ospanel_data"

    if (Test-Path $bundleSrc) {
        Write-Host "Копирование файлов из $bundleSrc в $bundleDst"
        Copy-Item -Path (Join-Path $bundleSrc "*") -Destination $bundleDst -Recurse -Force
    }
}

# === Очистка ненужных файлов ===
Write-Host "=== Очистка ненужных файлов ==="

# удаляем vc_redist.exe
Get-ChildItem -Path "$BaseAddonsDir\*\vc_redist.exe" -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "Удален файл: $($_.FullName)"
    }

# удаляем db2level.txt
Get-ChildItem -Path "$BaseAddonsDir\*\ospanel_data\help\db2level.txt" -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "Удален файл: $($_.FullName)"
    }

# удаляем файлы нулевого размера
Get-ChildItem -Path "$BaseAddonsDir\*\ospanel_data\help\*" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -eq 0 } |
    ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "Удален пустой файл: $($_.FullName)"
    }