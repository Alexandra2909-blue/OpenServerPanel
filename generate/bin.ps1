# ================================================================================
#                    AUTOMATED OSPANEL ADDONS AND UTILITIES BUILD SCRIPT
# ================================================================================
# Description: Automated OSPanel addons build from JSON configuration
#              and system utilities installation
# Author:      OSPanel Team
# Version:     2.1
# Date:        2025
# ================================================================================
$env:LC_ALL = "en_US.UTF-8"; $env:LANG = "en_US.UTF-8"
$env:TEMP = "A:"
# ================== SCRIPT CONFIGURATION ==================
# Path to JSON file with addons matrix
$JsonPath       = "..\resources\matrix\matrix-infodata.json"

# Path to JSON file with utilities matrix
$BinMatrixPath  = "..\resources\matrix\matrix-bin.json"

# Base directory for placing addons
$BaseAddonsDir  = "..\addons"

# Base directory for placing utilities
$BaseBinDir     = "..\bin"

# Enable SOCKS5 proxy for file downloads (true/false)
$UseProxy       = $true

# SOCKS5 proxy for file downloads
$ProxyUrl       = "127.0.0.1:1086"
# ==========================================================

# ================== GLOBAL VARIABLES ==================
$script:TotalAddons = 0
$script:ProcessedAddons = 0
$script:SkippedAddons = 0
$script:FailedAddons = 0

$script:TotalTools = 0
$script:ProcessedTools = 0
$script:SkippedTools = 0
$script:FailedTools = 0

$script:TotalModules = 0
$script:ProcessedModules = 0
$script:SkippedModules = 0
$script:FailedModules = 0

# Variables for tracking execution stages
$script:CurrentMainStep = 0
$script:TotalMainSteps = 12
$script:CurrentAddonSubStep = 0
$script:TotalAddonSubSteps = 6
$script:CurrentToolSubStep = 0
$script:TotalToolSubSteps = 3
# ===========================================================

# ================== UTILITY FUNCTIONS ==================
function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    
    $line = "═" * 80
    Write-Host $line -ForegroundColor $Color
    Write-Host " $Text" -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
}

function Write-Progress {
    param([string]$AddonName, [string]$Step, [string]$Details = "")
    
    $mainStepInfo = "[$($script:CurrentMainStep)/$($script:TotalMainSteps)]"
    $status = if ($Details) { "$Step - $Details" } else { $Step }
        
    Write-Host "$AddonName" -ForegroundColor White -NoNewline
    Write-Host " → $status" -ForegroundColor Green
}

function Write-PhpProgress {
    param([string]$ComponentName, [string]$Step, [string]$Details = "")
    
    $mainStepInfo = "[$($script:CurrentMainStep)/$($script:TotalMainSteps)]"
    $status = if ($Details) { "$Step - $Details" } else { $Step }
    
    Write-Host "$ComponentName" -ForegroundColor White -NoNewline
    Write-Host " → $status" -ForegroundColor Green
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Skip {
    param([string]$Message)
    Write-Host "⏭  $Message" -ForegroundColor Cyan
}

function Format-IniLine {
    <#
    .SYNOPSIS
    Formats a string for INI file with alignment
    
    .PARAMETER Key
    Parameter key
    
    .PARAMETER Value
    Parameter value
    #>
    param ([string]$Key, [string]$Value)
    
    $padding = 25 - $Key.Length
    if ($padding -lt 1) { $padding = 1 }
    $spaces = " " * $padding
    return "$Key$spaces= $Value"
}

function Convert-ToIni {
    <#
    .SYNOPSIS
    Converts PowerShell object to INI format
    
    .PARAMETER SectionName
    INI section name
    
    .PARAMETER Data
    Data to convert
    #>
    param ([string]$SectionName, [object]$Data)

    $lines = @()
    $lines += "[$SectionName]"
    $lines += ""  # Empty line after section name

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

function Test-Prerequisites {
    <#
    .SYNOPSIS
    Checks for required files and tools
    #>
    
    Write-Progress "SYSTEM" "Checking prerequisites"
    
    # Check JSON files
    if (-not (Test-Path $JsonPath)) {
        Write-Error "Addons configuration file not found: $JsonPath"
        return $false
    }
    
    if (-not (Test-Path $BinMatrixPath)) {
        Write-Error "Utilities configuration file not found: $BinMatrixPath"
        return $false
    }
    
    # Check curl
    try {
        $null = Get-Command curl -ErrorAction Stop
        Write-Success "Curl utility found"
    }
    catch {
        Write-Error "Curl utility not found in system"
        return $false
    }
    
    # Check proxy configuration
    if ($UseProxy) {
        Write-Success "Proxy enabled: $ProxyUrl"
    } else {
        Write-Success "Direct connection mode enabled"
    }
    
    Write-Success "All prerequisites met"
    return $true
}

function Get-AddonsList {
    <#
    .SYNOPSIS
    Loads and parses addon list from JSON
    #>
    
    try {
        Write-Progress "SYSTEM" "Loading addons configuration"
        
        $infodata = Get-Content $JsonPath -Raw | ConvertFrom-Json
        $addons = $infodata.addons.PSObject.Properties.Name | Sort-Object -Unique
        
        $script:TotalAddons = $addons.Count
        Write-Success "Loaded $($script:TotalAddons) addons from configuration"
        
        return @{
            InfoData = $infodata
            Addons = $addons
        }
    }
    catch {
        Write-Error "Error loading addons configuration: $_"
        return $null
    }
}

function Get-ToolsList {
    <#
    .SYNOPSIS
    Loads and parses utilities list from JSON
    #>
    
    try {
        Write-Progress "SYSTEM" "Loading utilities configuration"
        
        $binMatrix = Get-Content $BinMatrixPath -Raw | ConvertFrom-Json
        $tools = $binMatrix.tools
        
        $script:TotalTools = $tools.Count
        Write-Success "Loaded $($script:TotalTools) utilities from configuration"
        
        return $binMatrix
    }
    catch {
        Write-Error "Error loading utilities configuration: $_"
        return $null
    }
}

function Download-Addon {
    <#
    .SYNOPSIS
    Downloads addon via SOCKS5 proxy or direct connection
    
    .PARAMETER DownloadUrl
    URL for downloading
    
    .PARAMETER ZipPath
    Path to save archive
    #>
    param([string]$DownloadUrl, [string]$ZipPath)
    
    try {
        Write-Progress "DOWNLOAD" "Downloading archive" $DownloadUrl
        
        if ($UseProxy) {
            & curl --socks5 $ProxyUrl -L -o $ZipPath $DownloadUrl 2>$null
        } else {
            & curl -L -o $ZipPath $DownloadUrl 2>$null
        }
        
        if (-not (Test-Path $ZipPath)) {
            Write-Error "Failed to download file: $ZipPath"
            return $false
        }
        
        $fileSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)
        Write-Success "Archive downloaded successfully ($fileSize MB)"
        return $true
    }
    catch {
        Write-Error "Error during download: $_"
        return $false
    }
}

function Process-InstantClient {
    <#
    .SYNOPSIS
    Special processing for InstantClient addon
       
    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$DestDir)
    
    try {
        Write-Progress "INSTANTCLIENT" "Special processing InstantClient"
        
        # List of archives to download with version substitution
        $archives = @(
            "https://download.oracle.com/otn_software/nt/instantclient/instantclient-odbc-windows.zip",
            "https://download.oracle.com/otn_software/nt/instantclient/instantclient-jdbc-windows.zip",
            "https://download.oracle.com/otn_software/nt/instantclient/instantclient-tools-windows.zip",
            "https://download.oracle.com/otn_software/nt/instantclient/instantclient-sqlplus-windows.zip",
            "https://download.oracle.com/otn_software/nt/instantclient/instantclient-basic-windows.zip"
        )
        
        # Create target directory
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
        }
        
        $downloadedFiles = @()
        
        # Download all archives
        foreach ($downloadUrl in $archives) {
            $fileName = Split-Path $downloadUrl -Leaf
            $zipPath = Join-Path (Get-Location) $fileName
            
            Write-Progress "INSTANTCLIENT" "Downloading $fileName"
            
            if (Download-Addon -DownloadUrl $downloadUrl -ZipPath $zipPath) {
                $downloadedFiles += $zipPath
            } else {
                Write-Warning "Failed to download $fileName, continuing with others"
            }
        }
        
        if ($downloadedFiles.Count -eq 0) {
            Write-Error "Failed to download any InstantClient archives"
            return $false
        }
        
        Write-Success "Downloaded $($downloadedFiles.Count) of $($archives.Count) archives"
        
        # Extract all archives to addon root with file replacement
        foreach ($zipFile in $downloadedFiles) {
            Write-Progress "INSTANTCLIENT" "Extracting $(Split-Path $zipFile -Leaf)"
            
            try {
                Expand-Archive -Path $zipFile -DestinationPath $DestDir -Force
                Remove-Item $zipFile -Force
                Write-Success "Archive $(Split-Path $zipFile -Leaf) extracted and deleted"
            }
            catch {
                Write-Warning "Error extracting $(Split-Path $zipFile -Leaf): $_"
            }
        }
        
        # Find first instantclient* subfolder
        $instantclientDir = Get-ChildItem -Path $DestDir -Directory -Filter "instantclient*" -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($instantclientDir) {
            Write-Progress "INSTANTCLIENT" "Moving files from $($instantclientDir.Name)"
            
            # Copy everything from subfolder to addon root
            Get-ChildItem -Path $instantclientDir.FullName | ForEach-Object {
                $destPath = Join-Path $DestDir $_.Name
                if ($_.PSIsContainer) {
                    if (Test-Path $destPath) {
                        # If directory already exists, copy content
                        Copy-Item -Path (Join-Path $_.FullName "*") -Destination $destPath -Recurse -Force
                    } else {
                        Move-Item -Path $_.FullName -Destination $destPath -Force
                    }
                } else {
                    Move-Item -Path $_.FullName -Destination $destPath -Force
                }
            }
            
            # Remove empty instantclient* subfolder
            Remove-Item $instantclientDir.FullName -Force
            Write-Success "Files moved from $($instantclientDir.Name), subfolder removed"
        }
        
        # Remove META-INF subfolder if exists
        $metaInfDir = Join-Path $DestDir "META-INF"
        if (Test-Path $metaInfDir) {
            Remove-Item $metaInfDir -Recurse -Force
            Write-Success "META-INF subfolder removed"
        }
        
        Write-Success "InstantClient special processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing InstantClient: $_"
        return $false
    }
}

function Extract-Addon {
    <#
    .SYNOPSIS
    Extracts addon with special case handling
    
    .PARAMETER AddonName
    Addon name
    
    .PARAMETER ZipPath
    Path to archive
    
    .PARAMETER DestDir
    Destination directory
    
    .PARAMETER DownloadUrl
    Download URL (contains version for InstantClient)
    #>
    param([string]$AddonName, [string]$ZipPath, [string]$DestDir, [string]$DownloadUrl = "")
    
    try {
        Write-Progress "EXTRACTION" "Extracting archive"
        
        # Create target directory
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
        }

        # Special processing for different addon types
        switch -Wildcard ($AddonName) {
            "InstantClient" {
                Write-Progress "EXTRACTION" "Special InstantClient processing"
                return (Process-InstantClient -DestDir $DestDir)
            }
            
            "ImageMagick-*" {
                Write-Progress "EXTRACTION" "Special ImageMagick processing"
                # Standard extraction
                Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force
                
                # Special processing for ImageMagick
                Process-ImageMagick -DestDir $DestDir
            }
            
            "DB2-ODBC" {
                Write-Progress "EXTRACTION" "Special DB2-ODBC processing"
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
            
            "FFMpeg" {
                Write-Progress "EXTRACTION" "Special FFMpeg processing"
                $tmpDir = Join-Path $DestDir "_tmp"
                if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }

                Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force
                $ffmpegDir = Get-ChildItem -Path $tmpDir -Directory -Filter "ffmpeg*" | Select-Object -First 1

                if ($ffmpegDir) {
                    Get-ChildItem -Path $ffmpegDir.FullName | ForEach-Object {
                        Move-Item -Path $_.FullName -Destination $DestDir -Force
                    }
                }
                Remove-Item $tmpDir -Recurse -Force
            }
            
            "Libwebp" {
                Write-Progress "EXTRACTION" "Special Libwebp processing"
                $tmpDir = Join-Path $DestDir "_tmp"
                if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }

                Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force
                $libwebpDir = Get-ChildItem -Path $tmpDir -Directory -Filter "Libwebp*" | Select-Object -First 1

                if ($libwebpDir) {
                    Get-ChildItem -Path $libwebpDir.FullName | ForEach-Object {
                        Move-Item -Path $_.FullName -Destination $DestDir -Force
                    }
                }
                Remove-Item $tmpDir -Recurse -Force
            }

            "MDBTools" {
                Write-Progress "EXTRACTION" "Special MDBTools processing"
                $tmpDir = Join-Path $DestDir "_tmp"
                if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }

                Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force
                $libwebpDir = Get-ChildItem -Path $tmpDir -Directory -Filter "*tools*" | Select-Object -First 1

                if ($libwebpDir) {
                    Get-ChildItem -Path $libwebpDir.FullName | ForEach-Object {
                        Move-Item -Path $_.FullName -Destination $DestDir -Force
                    }
                }
                Remove-Item $tmpDir -Recurse -Force
            }

            "MongoShell" {
                Write-Progress "EXTRACTION" "Special MongoShell processing"
                $tmpDir = Join-Path $DestDir "_tmp"
                if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }

                Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force
                $libwebpDir = Get-ChildItem -Path $tmpDir -Directory -Filter "*mongosh*" | Select-Object -First 1

                if ($libwebpDir) {
                    Get-ChildItem -Path $libwebpDir.FullName | ForEach-Object {
                        Move-Item -Path $_.FullName -Destination $DestDir -Force
                    }
                }
                Remove-Item $tmpDir -Recurse -Force
            }
            
            default {
                # Standard extraction
                Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force
                
                # Remove archive after extraction (for regular addons)
                Remove-Item $ZipPath -Force
            }
        }

        # For InstantClient archive is not removed as it wasn't there
        if ($AddonName -ne "InstantClient") {
            # Remove archive after extraction (if it still exists)
            if (Test-Path $ZipPath) {
                Remove-Item $ZipPath -Force
            }
        }
        
        Write-Success "Archive successfully extracted and deleted"
        return $true
    }
    catch {
        Write-Error "Error extracting archive: $_"
        return $false
    }
}

function Process-ImageMagick {
    <#
    .SYNOPSIS
    Special processing for ImageMagick-* addons
    
    .PARAMETER DestDir
    Addon directory
    #>
    param([string]$DestDir)
    
    try {
        Write-Progress "IMAGEMAGICK" "Reorganizing files"
        
        $binDir = Join-Path $DestDir "bin"
        
        if (Test-Path $binDir) {
            # 1. Move everything from bin to addon root
            Get-ChildItem -Path $binDir | ForEach-Object {
                $destPath = Join-Path $DestDir $_.Name
                Move-Item -Path $_.FullName -Destination $destPath -Force
            }
            Write-Success "Files moved from bin to root"
            
            # 5. Remove bin folder
            Remove-Item $binDir -Force
            Write-Success "Bin folder removed"
        }
        
        # 2. Create coders subfolder and move all IM_*.dll files there
        $codersDir = Join-Path $DestDir "coders"
        if (-not (Test-Path $codersDir)) {
            New-Item -ItemType Directory -Force -Path $codersDir | Out-Null
        }
        
        $imFiles = Get-ChildItem -Path $DestDir -Filter "IM_*.dll" -ErrorAction SilentlyContinue
        if ($imFiles) {
            $imFiles | ForEach-Object {
                $destPath = Join-Path $codersDir $_.Name
                Move-Item -Path $_.FullName -Destination $destPath -Force
            }
            Write-Success "Moved $($imFiles.Count) IM_*.dll files to coders folder"
        }
        
        # 3. Create filters subfolder and move all FILTER_*.dll files there
        $filtersDir = Join-Path $DestDir "filters"
        if (-not (Test-Path $filtersDir)) {
            New-Item -ItemType Directory -Force -Path $filtersDir | Out-Null
        }
        
        $filterFiles = Get-ChildItem -Path $DestDir -Filter "FILTER_*.dll" -ErrorAction SilentlyContinue
        if ($filterFiles) {
            $filterFiles | ForEach-Object {
                $destPath = Join-Path $filtersDir $_.Name
                Move-Item -Path $_.FullName -Destination $destPath -Force
            }
            Write-Success "Moved $($filterFiles.Count) FILTER_*.dll files to filters folder"
        }
        
        # 4. Create imconfig subfolder and move all *.xml files there
        $imconfigDir = Join-Path $DestDir "imconfig"
        if (-not (Test-Path $imconfigDir)) {
            New-Item -ItemType Directory -Force -Path $imconfigDir | Out-Null
        }
        
        $xmlFiles = Get-ChildItem -Path $DestDir -Filter "*.xml" -ErrorAction SilentlyContinue
        if ($xmlFiles) {
            $xmlFiles | ForEach-Object {
                $destPath = Join-Path $imconfigDir $_.Name
                Move-Item -Path $_.FullName -Destination $destPath -Force
            }
            Write-Success "Moved $($xmlFiles.Count) *.xml files to imconfig folder"
        }
        
        Write-Success "ImageMagick special processing completed"
    }
    catch {
        Write-Error "Error processing ImageMagick: $_"
    }
}

function Generate-HelpFiles {
    <#
    .SYNOPSIS
    Generates help files for addon executable files
    
    .PARAMETER AddonName
    Addon name
    
    .PARAMETER DestDir
    Addon directory
    
    .PARAMETER Addon
    Addon object with settings
    #>
    param([string]$AddonName, [string]$DestDir, [object]$Addon)
    
    Write-Progress "HELP" "Generating help files"
    
    $HelpDir = "$DestDir\ospanel_data\help"
    
    # Create help directory
    if (-not (Test-Path $HelpDir)) {
        New-Item -ItemType Directory -Force -Path $HelpDir | Out-Null
    }

    # Skip generation for special addons
    if ($AddonName -like "ErlangOTP*" -or $AddonName -eq "Perl" -or $AddonName -eq "NVM") {
        Write-Skip "Help generation skipped for $AddonName"
        return
    }

    # Find executable files
    $executables = if ($AddonName -in @("DB2-ODBC")) {
        Get-ChildItem -Path (Join-Path $DestDir "bin") -Filter *.exe -Recurse -ErrorAction SilentlyContinue
    } else {
        Get-ChildItem -Path $DestDir -Filter *.exe -Recurse -ErrorAction SilentlyContinue
    }

    if (-not $executables) {
        Write-Warning "No executable files found"
        return
    }

    $helpCmd = if ($Addon.help) { $Addon.help } else { "--help" }
    $generatedFiles = 0

    foreach ($exe in $executables) {
        $outFile = Join-Path $HelpDir ($exe.BaseName + ".txt")
        try {
            # Special processing for ImageMagick
            if ($AddonName -like "ImageMagick-*") {
                # For ImageMagick use execution without parameters to get help
                $output = & $exe.FullName 2>nul
            } else {
                $args = $helpCmd -split "\s+"
                $output = & $exe.FullName @($args) 2>&1
            }
            
            # Filter empty lines and write to file
            $filteredOutput = $output | Where-Object { $_.ToString().Trim() -ne "" }
            
            if ($filteredOutput) {
                $filteredOutput | Out-File -FilePath $outFile -Encoding utf8
                $generatedFiles++
            } else {
                Write-Warning "Empty help output for $($exe.Name)"
            }
        }
        catch {
            Write-Warning "Error generating help for $($exe.Name): $_"
        }
    }

    Write-Success "Created $generatedFiles help files"
}

function Generate-IniFile {
    <#
    .SYNOPSIS
    Creates addon.ini file for addon
    
    .PARAMETER DestDir
    Addon directory
    
    .PARAMETER Addon
    Addon object with settings
    #>
    param([string]$DestDir, [object]$Addon)
    
    Write-Progress "CONFIGURATION" "Creating addon.ini"
    
    $IniPath = "$DestDir\ospanel_data\addon.ini"
    
    # Section order in INI file
    $sectionsOrder = @("main", "docs", "environment")
    $skipSections = @("DownloadUrl", "ZipPath", "help")

    $iniContent = @()

    # Add sections in specific order
    foreach ($sec in $sectionsOrder) {
        if ($Addon.PSObject.Properties.Name -contains $sec) {
            $iniContent += Convert-ToIni -SectionName $sec -Data $Addon.$sec
            $iniContent += ""
        }
    }

    # Add other sections
    $otherSections = $Addon.PSObject.Properties.Name |
                     Where-Object { $sectionsOrder -notcontains $_ -and $skipSections -notcontains $_ } |
                     Sort-Object

    foreach ($sec in $otherSections) {
        $iniContent += Convert-ToIni -SectionName $sec -Data $Addon.$sec
        $iniContent += ""
    }

    # Create directory and save file
    $iniDir = Split-Path $IniPath -Parent
    if (-not (Test-Path $iniDir)) {
        New-Item -ItemType Directory -Force -Path $iniDir | Out-Null
    }
    
    $iniContent | Out-File -FilePath $IniPath -Encoding utf8 -Force
    Write-Success "addon.ini file created"
}

function Copy-BundleFiles {
    <#
    .SYNOPSIS
    Copies additional files from addon bundle
    
    .PARAMETER AddonName
    Addon name
    
    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$AddonName, [string]$DestDir)
    
    $bundleSrc = "..\resources\addons\$AddonName"
    
    if (Test-Path $bundleSrc) {
        Write-Progress "COPYING" "Additional files from bundle"
        
        try {
            Copy-Item -Path (Join-Path $bundleSrc "*") -Destination $DestDir -Recurse -Force
            Write-Success "Additional files copied"
        }
        catch {
            Write-Warning "Error copying additional files: $_"
        }
    }
}

function Remove-UnnecessaryFiles {
    <#
    .SYNOPSIS
    Removes unnecessary files and directories from addons
    #>
    
    Write-Host ""
    # Patterns for excluded directories
    $excludePatterns = @("ErlangOTP*", "Ghostscript*")
    
    # Get excluded directories
    $excludedDirs = foreach ($pattern in $excludePatterns) {
        Get-ChildItem -Path $BaseAddonsDir -Directory -Filter $pattern
    }

    # Special cleanup for excluded directories
    foreach ($excludedDir in $excludedDirs) {
        Write-Progress "CLEANUP" "Special cleanup for $($excludedDir.Name)"
        
            Get-ChildItem -Path $excludedDir.FullName -Filter "*vc_redist.exe" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    Write-Success "Removed file: $($_.Name)"
                }

        # Remove erts*\lib and erts*\include
        Get-ChildItem -Path $excludedDir.FullName -Directory -Filter "erts*" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $libPath = Join-Path $_.FullName "lib"
                $includePath = Join-Path $_.FullName "include"
                
                if (Test-Path $libPath) {
                    Remove-Item $libPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Success "Removed: $libPath"
                }
                
                if (Test-Path $includePath) {
                    Remove-Item $includePath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Success "Removed: $includePath"
                }
            }
        
        # Clean usr\lib
        $usrLibPath = Join-Path $excludedDir.FullName "usr\lib"
        if (Test-Path $usrLibPath) {
            # Remove *.lib files
            Get-ChildItem -Path $usrLibPath -Filter "*.lib" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    Write-Success "Removed file: $($_.Name)"
                }
            
            # Remove include folder
            $usrLibIncludePath = Join-Path $usrLibPath "include"
            if (Test-Path $usrLibIncludePath) {
                Remove-Item $usrLibIncludePath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Success "Removed: $usrLibIncludePath"
            }
        }

        # Clean lib\erl_interface*
        $mainLibPath = Join-Path $excludedDir.FullName "lib"
        if (Test-Path $mainLibPath) {
            Get-ChildItem -Path $mainLibPath -Directory -Filter "erl_interface*" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $erlInterfaceIncludePath = Join-Path $_.FullName "include"
                    $erlInterfaceLibPath = Join-Path $_.FullName "lib"
                    
                    if (Test-Path $erlInterfaceIncludePath) {
                        Remove-Item $erlInterfaceIncludePath -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Success "Removed: $erlInterfaceIncludePath"
                    }
                    
                    if (Test-Path $erlInterfaceLibPath) {
                        Remove-Item $erlInterfaceLibPath -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Success "Removed: $erlInterfaceLibPath"
                    }
                }
        }
    }

    # General cleanup for other addons
    $cleanedDirs = 0
    Get-ChildItem -Path $BaseAddonsDir -Directory |
        Where-Object { 
            $dirName = $_.Name
            $isExcluded = $false
            foreach ($pattern in $excludePatterns) {
                if ($dirName -like $pattern) {
                    $isExcluded = $true
                    break
                }
            }
            -not $isExcluded
        } |
        ForEach-Object {
            $addonPath = $_.FullName
            $addonName = $_.Name
            
            Write-Progress "CLEANUP" "General cleanup for $addonName"
            
            # Remove standard directories
            @("include", "headers", "lib") | ForEach-Object {
                $targetPath = Join-Path $addonPath $_
                if (Test-Path $targetPath) {
                    Remove-Item $targetPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Success "Removed directory: $_"
                }
            }
            
            # Remove unnecessary files
            $filesRemoved = 0
            @("*.pdb", "db2level.txt", "uidrvci.txt", "odbc_install.txt", "adrci.txt", "vc_redist.exe", "install.cmd") | ForEach-Object {
                $filesToRemove = Get-ChildItem -Path $addonPath -Filter $_ -Recurse -ErrorAction SilentlyContinue
                foreach ($file in $filesToRemove) {
                    Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                    $filesRemoved++
                }
            }
            
            if ($filesRemoved -gt 0) {
                Write-Success "Removed $filesRemoved unnecessary files"
            }
            
            $cleanedDirs++
        }

    # Remove empty help files
    $emptyHelpFiles = Get-ChildItem -Path "$BaseAddonsDir\*\ospanel_data\help\*" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -eq 0 }
    
    if ($emptyHelpFiles) {
        $emptyHelpFiles | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
        Write-Success "Removed $($emptyHelpFiles.Count) empty help files"
    }

    Write-Success "Cleanup completed. Processed $cleanedDirs directories"
}

# ================== UTILITY FUNCTIONS ==================

function Find-FileInExtracted {
    <#
    .SYNOPSIS
    Search for files in extracted utility archive
    
    .PARAMETER BasePath
    Base path for search
    
    .PARAMETER Pattern
    File search pattern
    #>
    param(
        [string]$BasePath,
        [string]$Pattern
    )
    
    $found = Get-ChildItem -Path $BasePath -Recurse -File -ErrorAction SilentlyContinue | 
             Where-Object { $_.Name -like ($Pattern -split '\\')[-1] } |
             Select-Object -First 1
    
    return $found.FullName
}

function Install-ToolFromArchive {
    <#
    .SYNOPSIS
    Installs utility from archive
    
    .PARAMETER Url
    URL for downloading archive
    
    .PARAMETER ExtractPath
    Extraction path in archive
    
    .PARAMETER Files
    List of files to copy
    
    .PARAMETER CopyFiles
    Additional files to copy
    #>
    param(
        [string]$Url,
        [string]$ExtractPath,
        [array]$Files,
        [array]$CopyFiles = @()
    )
    
    $tmp = "$env:TEMP\tmpdir_$(Get-Random)"
    $zip = "$tmp.zip"
    
    Write-Progress "DOWNLOAD" "Downloading archive" $Url
    
    if ($UseProxy) {
        & curl --socks5 $ProxyUrl -L -o $zip $Url 2>$null
    } else {
        Invoke-WebRequest $Url -OutFile $zip
    }
    
    Expand-Archive $zip $tmp -Force
    
    # Copy main files
    foreach ($file in $Files) {
        $sourceFile = $null
        
        if ([string]::IsNullOrEmpty($ExtractPath)) {
            # Files in archive root
            $sourceFile = "$tmp\$file"
        }
        else {
            # Search in specified directory with mask support
            $searchPaths = Get-ChildItem -Path $tmp -Directory | Where-Object { $_.Name -like ($ExtractPath -replace '\\.*$', '') }
            
            if ($ExtractPath.Contains('\')) {
                # Has subpaths
                $subPath = $ExtractPath -replace '^[^\\]*\\', ''
                foreach ($basePath in $searchPaths) {
                    $fullPath = Join-Path $basePath.FullName $subPath
                    $testFile = Join-Path $fullPath $file
                    if (Test-Path $testFile -PathType Leaf) {
                        $sourceFile = $testFile
                        break
                    }
                }
            }
            else {
                # Only base directory
                foreach ($basePath in $searchPaths) {
                    $testFile = Join-Path $basePath.FullName $file
                    if (Test-Path $testFile -PathType Leaf) {
                        $sourceFile = $testFile
                        break
                    }
                }
            }
        }
        
        if ($sourceFile -and (Test-Path $sourceFile -PathType Leaf)) {
            Write-Progress "COPYING" "File $file"
            Copy-Item $sourceFile "$BaseBinDir\$file" -Force
            Write-Success "Copied: $sourceFile → $BaseBinDir\$file"
        }
        else {
            Write-Warning "File not found: $file (searched in $ExtractPath)"
        }
    }
    
    # Copy additional files
    foreach ($copyFile in $CopyFiles) {
        if (Test-Path $copyFile -PathType Leaf) {
            $fileName = Split-Path $copyFile -Leaf
            Write-Progress "COPYING" "Additional file $fileName"
            Copy-Item $copyFile "$BaseBinDir\$fileName" -Force
            Write-Success "Copied additional file: $copyFile"
        }
    }
    
    Remove-Item $tmp, $zip -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-DirectDownload {
    <#
    .SYNOPSIS
    Direct download of utility file
    
    .PARAMETER Url
    URL for download
    
    .PARAMETER TargetName
    Target file name
    #>
    param(
        [string]$Url,
        [string]$TargetName
    )
    
    Write-Progress "DOWNLOAD" "Direct downloading" $Url
    
    if ($UseProxy) {
        & curl --socks5 $ProxyUrl -L -o "$BaseBinDir\$TargetName" $Url 2>$null
    } else {
        & curl -L -o "$BaseBinDir\$TargetName" $Url 2>$null
    }
    
    Write-Success "File downloaded: $BaseBinDir\$TargetName"
}

function Install-FromLocalArchive {
    <#
    .SYNOPSIS
    Install utility from local archive
    
    .PARAMETER LocalZip
    Path to local archive
    
    .PARAMETER Files
    List of files to extract
    #>
    param(
        [string]$LocalZip,
        [array]$Files
    )
    
    $tmp = "$env:TEMP\tmpdir_$(Get-Random)"
    
    Write-Progress "EXTRACTION" "Local archive" $LocalZip
    Expand-Archive $LocalZip $tmp -Force
    
    foreach ($file in $Files) {
        $sourceFile = Get-ChildItem -Path $tmp -Recurse -File | 
                     Where-Object { $_.Name -eq $file } | 
                     Select-Object -First 1
        
        if ($sourceFile) {
            Write-Progress "COPYING" "File $file"
            Copy-Item $sourceFile.FullName "$BaseBinDir\$file" -Force
            Write-Success "Copied: $($sourceFile.FullName) → $BaseBinDir\$file"
        }
        else {
            Write-Warning "File not found in archive: $file"
        }
    }
    
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-LocalFiles {
    <#
    .SYNOPSIS
    Copy local utility files
    
    .PARAMETER LocalFiles
    List of local files to copy
    #>
    param(
        [array]$LocalFiles
    )
    
    foreach ($file in $LocalFiles) {
        if (Test-Path $file -PathType Leaf) {
            $fileName = Split-Path $file -Leaf
            Write-Progress "COPYING" "Local file $fileName"
            Copy-Item $file "$BaseBinDir\$fileName" -Force
            Write-Success "Copied local file: $file → $BaseBinDir\$fileName"
        }
        else {
            Write-Warning "Local file not found: $file"
        }
    }
}

function Generate-ToolHelp {
    <#
    .SYNOPSIS
    Generates help files for utilities
    
    .PARAMETER Command
    Command and arguments for help generation
    
    .PARAMETER OutputFile
    Output file name (auto-generated by default)
    #>
    param(
        [array]$Command,
        [string]$OutputFile = $null
    )
    
    if (-not $OutputFile) {
        $OutputFile = "$($Command[0] -replace '\.exe$', '').txt"
    }
    
    $helpPath = "$BaseBinDir\help\$OutputFile"
    $execPath = "$BaseBinDir\$($Command[0])"
    
    if (-not (Test-Path $execPath -PathType Leaf)) {
        Write-Warning "Executable not found for help generation: $execPath"
        return
    }
    
    Write-Progress "HELP" "Generating help for $($Command[0])"
    
    try {
        $out = & $execPath $Command[1..($Command.Length-1)] 2>&1 | Where-Object {$_.ToString().Trim()}
        $out | Out-File $helpPath -Encoding utf8 -Force
        Write-Success "Help created: $OutputFile"
    } catch {
        Write-Warning "Error generating help for $($Command[0]): $_"
    }
}

function Ensure-Directory {
    <#
    .SYNOPSIS
    Creates directory if it doesn't exist, ensuring parent directories are created
    
    .PARAMETER FilePath
    Path to file (directory will be created for this file)
    #>
    param([string]$FilePath)
    
    $directory = Split-Path -Path $FilePath -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

function Copy-ComposerFiles {
    <#
    .SYNOPSIS
    Downloads and copies Composer files and keys to PHP modules
    #>
    
    Write-Host ""
    
    Write-PhpProgress "COMPOSER" "Downloading Composer and keys"
    
    # Define source files
    $sources = @{
        "composer.phar" = "..\resources\php\composer.phar"
        "config.json" = "..\resources\php\config.json"
        "composer.json" = "..\resources\php\composer.json"
        "auth.json" = "..\resources\php\auth.json"
        "keys.tags.pub" = "..\resources\php\keys.tags.pub"
        "keys.dev.pub" = "..\resources\php\keys.dev.pub"
        "browscap.ini" = "..\resources\php\browscap.ini"
        "composer.bat" = "..\resources\php\composer.bat"
        "phpinfo.php" = "..\resources\php\phpinfo.php"
    }
    
    # Create source directory if it doesn't exist
    $sourceDir = "..\resources\composer"
    if (-not (Test-Path $sourceDir)) {
        New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
    }
    
    # Remove old files before downloading/updating
    $filesToDownload = @("composer.phar", "keys.tags.pub", "keys.dev.pub", "browscap.ini")
    foreach ($file in $filesToDownload) {
        $filePath = $sources[$file]
        if (Test-Path $filePath) {
            Remove-Item $filePath -Force -ErrorAction SilentlyContinue
            Write-Success "Removed old file: $file"
        }
    }
    
    # Download files (always overwrite)
    $downloads = @{
        "https://composer.github.io/snapshots.pub" = $sources["keys.dev.pub"]
        "https://composer.github.io/releases.pub" = $sources["keys.tags.pub"]
        "https://getcomposer.org/download/latest-stable/composer.phar" = $sources["composer.phar"]
        "https://browscap.org/stream?q=Lite_PHP_BrowsCapINI" = $sources["browscap.ini"]
    }
    
    foreach ($url in $downloads.Keys) {
        $destPath = $downloads[$url]
        Write-PhpProgress "COMPOSER" "Downloading $(Split-Path $destPath -Leaf)" $url
        
        try {
            if ($UseProxy) {
                & curl --socks5 $ProxyUrl -f -s -L -o $destPath $url 2>$null
            } else {
                & curl -f -s -L -o $destPath $url 2>$null
            }
            
            if (Test-Path $destPath) {
                Write-Success "Downloaded: $(Split-Path $destPath -Leaf)"
            } else {
                Write-Warning "Failed to download: $(Split-Path $destPath -Leaf)"
            }
        }
        catch {
            Write-Warning "Error downloading $(Split-Path $destPath -Leaf): $_"
        }
    }
    
    # Check for all required files
    $missingFiles = @()
    foreach ($file in $sources.Keys) {
        if (-not (Test-Path $sources[$file])) {
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-Error "Missing files: $($missingFiles -join ', ')"
        return $false
    }
    
    Write-Success "All Composer files verified"
    
    # Define files that go to composer subfolder vs PHP root
    $composerSubfolderFiles = @("composer.phar", "config.json", "composer.json", "auth.json", "keys.tags.pub", "keys.dev.pub")
    $phpRootFiles = @("browscap.ini", "composer.bat", "phpinfo.php")
    
    # Copy files to PHP modules with forced overwrite
    $phpVersions = @("7.2", "7.3", "7.4", "8.0", "8.1", "8.2", "8.3", "8.4")
    
    foreach ($version in $phpVersions) {
        $phpModuleDir = "..\modules\PHP-$version"
        $composerTargetDir = "$phpModuleDir\ospanel_data\default_data\composer"
        
        if (Test-Path $phpModuleDir) {
            Write-PhpProgress "COMPOSER" "Copying files to PHP $version"
            
            # Copy files to composer subfolder
            if (Test-Path $composerTargetDir) {
                foreach ($file in $composerSubfolderFiles) {
                    $sourcePath = $sources[$file]
                    $targetPath = Join-Path $composerTargetDir $file
                    
                    # Remove old file in target directory
                    if (Test-Path $targetPath) {
                        Remove-Item $targetPath -Force -ErrorAction SilentlyContinue
                    }
                    
                    try {
                        Copy-Item $sourcePath $targetPath -Force
                        Write-Success "Copied $file to PHP $version composer folder"
                    }
                    catch {
                        Write-Warning "Error copying $file to PHP $version composer folder: $_"
                    }
                }
            }
            
            # Copy files to PHP module root
            foreach ($file in $phpRootFiles) {
                $sourcePath = $sources[$file]
                $targetPath = Join-Path $phpModuleDir $file
                
                # Remove old file in target directory
                if (Test-Path $targetPath) {
                    Remove-Item $targetPath -Force -ErrorAction SilentlyContinue
                }
                
                try {
                    Copy-Item $sourcePath $targetPath -Force
                    Write-Success "Copied $file to PHP $version root"
                }
                catch {
                    Write-Warning "Error copying $file to PHP $version root: $_"
                }
            }
        }
        else {
            Write-Warning "PHP module directory not found: $phpModuleDir"
        }
    }
    
    Write-Success "Composer files copy operation completed"
}

function Copy-PhpMibFiles {
    <#
    .SYNOPSIS
    Downloads and copies SNMP MIB files to PHP modules
    #>
    
    # Define MIB archives for different PHP versions
    $mibArchives = @{
        "7.2" = "https://netix.dl.sourceforge.net/project/net-snmp/net-snmp/5.7.3/net-snmp-5.7.3.zip?viasf=1"
        "7.3" = "https://netix.dl.sourceforge.net/project/net-snmp/net-snmp/5.7.3/net-snmp-5.7.3.zip?viasf=1"
        "7.4" = "https://netix.dl.sourceforge.net/project/net-snmp/net-snmp/5.7.3/net-snmp-5.7.3.zip?viasf=1"
        "8.0" = "https://netix.dl.sourceforge.net/project/net-snmp/net-snmp/5.7.3/net-snmp-5.7.3.zip?viasf=1"
        "8.1" = "https://netix.dl.sourceforge.net/project/net-snmp/net-snmp/5.9.4/net-snmp-5.9.4.zip?viasf=1"
        "8.2" = "https://netix.dl.sourceforge.net/project/net-snmp/net-snmp/5.9.4/net-snmp-5.9.4.zip?viasf=1"
        "8.3" = "https://netix.dl.sourceforge.net/project/net-snmp/net-snmp/5.9.4/net-snmp-5.9.4.zip?viasf=1"
        "8.4" = "https://netix.dl.sourceforge.net/project/net-snmp/net-snmp/5.9.4/net-snmp-5.9.4.zip?viasf=1"
    }
    
    $processedVersions = 0
    $skippedVersions = 0
    $failedVersions = 0
    
    foreach ($version in $mibArchives.Keys) {
        $phpModuleDir = "..\modules\PHP-$version"
        $extrasDir = Join-Path $phpModuleDir "extras"
        $mibsDir = Join-Path $extrasDir "mibs"
        
        Write-Host ""
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host " PHP-$version MIB FILES" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host ""
        
        # Check if PHP module exists
        if (-not (Test-Path $phpModuleDir)) {
            Write-Skip "PHP module directory not found: $phpModuleDir"
            $skippedVersions++
            continue
        }
        
        $archiveUrl = $mibArchives[$version]
        
        try {
            Write-PhpProgress "MIB-PHP-$version" "Processing MIB files for PHP $version"
            
            # Create temporary directory
            $tmpDir = "$env:TEMP\mib_$(Get-Random)"
            $zipPath = "$tmpDir.zip"
            
            Write-PhpProgress "MIB-PHP-$version" "Downloading archive" $archiveUrl
            
            # Download archive
            if ($UseProxy) {
                & curl --socks5 $ProxyUrl -f -s -L -o $zipPath $archiveUrl 2>$null
            } else {
                & curl -f -s -L -o $zipPath $archiveUrl 2>$null
            }
            
            if (-not (Test-Path $zipPath)) {
                Write-Error "Failed to download MIB archive for PHP $version"
                $failedVersions++
                continue
            }
            
            $fileSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
            Write-Success "Archive downloaded successfully ($fileSize MB)"
            
            # Extract archive
            Write-PhpProgress "MIB-PHP-$version" "Extracting archive to temporary directory"
            Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
            
            # Find mibs subdirectory in extracted content
            $mibsSourceDir = Get-ChildItem -Path $tmpDir -Directory -Recurse | 
                             Where-Object { $_.Name -eq "mibs" } | 
                             Select-Object -First 1
            
            if (-not $mibsSourceDir) {
                Write-Warning "MIB subdirectory not found in archive for PHP $version"
                Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
                $failedVersions++
                continue
            }
            
            Write-PhpProgress "MIB-PHP-$version" "Found MIB directory: $($mibsSourceDir.FullName)"
            
            # Create extras directory if it doesn't exist
            if (-not (Test-Path $extrasDir)) {
                New-Item -ItemType Directory -Path $extrasDir -Force | Out-Null
                Write-Success "Created extras directory: $extrasDir"
            }
            
            # Remove existing mibs directory if it exists (for clean overwrite)
            if (Test-Path $mibsDir) {
                Remove-Item $mibsDir -Recurse -Force
                Write-Success "Removed existing MIB directory for clean overwrite"
            }
            
            # Copy mibs directory to PHP module extras
            Write-PhpProgress "MIB-PHP-$version" "Copying MIB files to PHP module"
            Copy-Item -Path $mibsSourceDir.FullName -Destination $extrasDir -Recurse -Force
            
            # Count copied files
            $copiedFiles = Get-ChildItem -Path $mibsDir -File -Recurse -ErrorAction SilentlyContinue
            $fileCount = if ($copiedFiles) { $copiedFiles.Count } else { 0 }
            
            Write-Success "Copied $fileCount MIB files to $mibsDir"
            
            # Clean up temporary files
            Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Temporary files cleaned up"
            
            $processedVersions++
            Write-Success "MIB files successfully processed for PHP $version"
        }
        catch {
            Write-Error "Critical error processing MIB files for PHP $version : $_"
            # Clean up on error
            Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
            $failedVersions++
        }
    }
    
    # Show summary
    Write-Host ""
    Write-Host "📊 PHP MIB processing results:" -ForegroundColor White
    Write-Host ""
    Write-Host "   Total PHP versions:  " -NoNewline -ForegroundColor Gray
    Write-Host $mibArchives.Count -ForegroundColor White
    Write-Host "   Processed:           " -NoNewline -ForegroundColor Gray
    Write-Host $processedVersions -ForegroundColor Green
    Write-Host "   Skipped:             " -NoNewline -ForegroundColor Gray
    Write-Host $skippedVersions -ForegroundColor Yellow
    Write-Host "   Errors:              " -NoNewline -ForegroundColor Gray
    Write-Host $failedVersions -ForegroundColor Red
    Write-Host ""
    
    $successRate = if ($mibArchives.Count -gt 0) { [math]::Round(($processedVersions / $mibArchives.Count) * 100, 1) } else { 0 }
    Write-Host "   Success rate:        " -NoNewline -ForegroundColor Gray
    Write-Host "$successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host ""
    Write-Success "PHP MIB files copy operation completed"
}

function Copy-PhpBlackfireFiles {
    <#
    .SYNOPSIS
    Downloads and copies Blackfire extension files to PHP modules
    #>
    
    # Define Blackfire archives for different PHP versions
    $blackfireArchives = @{
        "7.2" = "https://blackfire.io/api/v1/releases/probe/php/windows/amd64/72"
        "7.3" = "https://blackfire.io/api/v1/releases/probe/php/windows/amd64/73"
        "7.4" = "https://blackfire.io/api/v1/releases/probe/php/windows/amd64/74"
        "8.0" = "https://blackfire.io/api/v1/releases/probe/php/windows/amd64/80"
        "8.1" = "https://blackfire.io/api/v1/releases/probe/php/windows/amd64/81"
        "8.2" = "https://blackfire.io/api/v1/releases/probe/php/windows/amd64/82"
        "8.3" = "https://blackfire.io/api/v1/releases/probe/php/windows/amd64/83"
        "8.4" = "https://blackfire.io/api/v1/releases/probe/php/windows/amd64/84"
    }
    
    $processedVersions = 0
    $skippedVersions = 0
    $failedVersions = 0
    
    foreach ($version in $blackfireArchives.Keys) {
        $phpModuleDir = "..\modules\PHP-$version"
        $extDir = Join-Path $phpModuleDir "ext"
        $targetFile = Join-Path $extDir "php_blackfire.dll"
        
        Write-Host ""
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host " PHP-$version BLACKFIRE EXTENSION" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host ""
        
        # Check if PHP module exists
        if (-not (Test-Path $phpModuleDir)) {
            Write-Skip "PHP module directory not found: $phpModuleDir"
            $skippedVersions++
            continue
        }
        
        $archiveUrl = $blackfireArchives[$version]
        
        try {
            Write-Progress "BLACKFIRE-PHP-$version" "Processing Blackfire extension for PHP $version"
            
            # Create temporary directory
            $tmpDir = "$env:TEMP\blackfire_$(Get-Random)"
            $zipPath = "$tmpDir.zip"
            
            Write-Progress "BLACKFIRE-PHP-$version" "Downloading archive" $archiveUrl
            
            # Download archive
            if ($UseProxy) {
                & curl --socks5 $ProxyUrl -f -s -L -o $zipPath $archiveUrl 2>$null
            } else {
                & curl -f -s -L -o $zipPath $archiveUrl 2>$null
            }
            
            if (-not (Test-Path $zipPath)) {
                Write-Error "Failed to download Blackfire archive for PHP $version"
                $failedVersions++
                continue
            }
            
            $fileSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
            Write-Success "Archive downloaded successfully ($fileSize MB)"
            
            # Extract archive
            Write-Progress "BLACKFIRE-PHP-$version" "Extracting archive to temporary directory"
            Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
            
            # Find blackfire_php.dll file in extracted content
            $blackfireFile = Get-ChildItem -Path $tmpDir -File -Recurse | 
                            Where-Object { $_.Name -eq "blackfire_php.dll" } | 
                            Select-Object -First 1
            
            if (-not $blackfireFile) {
                Write-Warning "blackfire_php.dll file not found in archive for PHP $version"
                Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
                $failedVersions++
                continue
            }
            
            Write-Progress "BLACKFIRE-PHP-$version" "Found Blackfire DLL: $($blackfireFile.FullName)"
            
            # Create ext directory if it doesn't exist
            if (-not (Test-Path $extDir)) {
                New-Item -ItemType Directory -Path $extDir -Force | Out-Null
                Write-Success "Created ext directory: $extDir"
            }
            
            # Remove existing file if it exists (for clean overwrite)
            if (Test-Path $targetFile) {
                Remove-Item $targetFile -Force
                Write-Success "Removed existing Blackfire extension for clean overwrite"
            }
            
            # Copy blackfire_php.dll to PHP module ext directory as php_blackfire.dll
            Write-Progress "BLACKFIRE-PHP-$version" "Copying Blackfire extension to PHP module"
            Copy-Item -Path $blackfireFile.FullName -Destination $targetFile -Force
            
            # Verify file was copied
            if (Test-Path $targetFile) {
                $copiedFileSize = [math]::Round((Get-Item $targetFile).Length / 1KB, 2)
                Write-Success "Copied php_blackfire.dll to $targetFile ($copiedFileSize KB)"
            } else {
                Write-Warning "Failed to copy Blackfire extension for PHP $version"
                $failedVersions++
                continue
            }
            
            # Clean up temporary files
            Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Temporary files cleaned up"
            
            $processedVersions++
            Write-Success "Blackfire extension successfully processed for PHP $version"
        }
        catch {
            Write-Error "Critical error processing Blackfire extension for PHP $version : $_"
            # Clean up on error
            Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
            $failedVersions++
        }
    }
    
    # Show summary
    Write-Host ""
    Write-Host "📊 PHP Blackfire processing results:" -ForegroundColor White
    Write-Host ""
    Write-Host "   Total PHP versions:  " -NoNewline -ForegroundColor Gray
    Write-Host $blackfireArchives.Count -ForegroundColor White
    Write-Host "   Processed:           " -NoNewline -ForegroundColor Gray
    Write-Host $processedVersions -ForegroundColor Green
    Write-Host "   Skipped:             " -NoNewline -ForegroundColor Gray
    Write-Host $skippedVersions -ForegroundColor Yellow
    Write-Host "   Errors:              " -NoNewline -ForegroundColor Gray
    Write-Host $failedVersions -ForegroundColor Red
    Write-Host ""
    
    $successRate = if ($blackfireArchives.Count -gt 0) { [math]::Round(($processedVersions / $blackfireArchives.Count) * 100, 1) } else { 0 }
    Write-Host "   Success rate:        " -NoNewline -ForegroundColor Gray
    Write-Host "$successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host ""
    Write-Success "PHP Blackfire files copy operation completed"
}

function Copy-PhpIoncubeFiles {
    <#
    .SYNOPSIS
    Downloads and copies Ioncube loader files to PHP modules
    #>
       
    # Define Ioncube archives for different PHP versions
    $ioncubeArchives = @{
        "7.2" = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_win_nonts_vc15_x86-64.zip"
        "7.3" = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_win_nonts_vc15_x86-64.zip"
        "7.4" = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_win_nonts_vc15_x86-64.zip"
        "8.1" = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_win_nonts_vc16_x86-64.zip"
        "8.2" = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_win_nonts_vc16_x86-64.zip"
        "8.3" = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_win_nonts_vc16_x86-64.zip"
        "8.4" = "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_win_nonts_vc17_x86-64.zip"
    }
    
    $processedVersions = 0
    $skippedVersions = 0
    $failedVersions = 0
    
    foreach ($version in $ioncubeArchives.Keys) {
        $phpModuleDir = "..\modules\PHP-$version"
        $extDir = Join-Path $phpModuleDir "ext"
        $ioncubeDir = Join-Path $phpModuleDir "3rd-party\ioncube"
        $targetLoaderFile = Join-Path $extDir "php_ioncube.dll"
        
        Write-Host ""
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host " PHP-$version IONCUBE LOADER" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host ""
        
        # Check if PHP module exists
        if (-not (Test-Path $phpModuleDir)) {
            Write-Skip "PHP module directory not found: $phpModuleDir"
            $skippedVersions++
            continue
        }
        
        $archiveUrl = $ioncubeArchives[$version]
        
        try {
            Write-Progress "IONCUBE-PHP-$version" "Processing Ioncube loader for PHP $version"
            
            # Create temporary directory
            $tmpDir = "$env:TEMP\ioncube_$(Get-Random)"
            $zipPath = "$tmpDir.zip"
            
            Write-Progress "IONCUBE-PHP-$version" "Downloading archive" $archiveUrl
            
            # Download archive
            if ($UseProxy) {
                & curl --socks5 $ProxyUrl -f -s -L -o $zipPath $archiveUrl 2>$null
            } else {
                & curl -f -s -L -o $zipPath $archiveUrl 2>$null
            }
            
            if (-not (Test-Path $zipPath)) {
                Write-Error "Failed to download Ioncube archive for PHP $version"
                $failedVersions++
                continue
            }
            
            $fileSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
            Write-Success "Archive downloaded successfully ($fileSize MB)"
            
            # Extract archive
            Write-Progress "IONCUBE-PHP-$version" "Extracting archive to temporary directory"
            Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
            
            # Find specific loader file for this PHP version
            $loaderFileName = "ioncube_loader_win_$version.dll"
            $loaderFile = Get-ChildItem -Path $tmpDir -File -Recurse | 
                         Where-Object { $_.Name -eq $loaderFileName } | 
                         Select-Object -First 1
            
            if (-not $loaderFile) {
                Write-Warning "Ioncube loader file not found in archive for PHP $version (looking for: $loaderFileName)"
                Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
                $failedVersions++
                continue
            }
            
            Write-Progress "IONCUBE-PHP-$version" "Found Ioncube loader: $($loaderFile.FullName)"
            
            # Create ext directory if it doesn't exist
            if (-not (Test-Path $extDir)) {
                New-Item -ItemType Directory -Path $extDir -Force | Out-Null
                Write-Success "Created ext directory: $extDir"
            }
            
            # Remove existing loader file if it exists (for clean overwrite)
            if (Test-Path $targetLoaderFile) {
                Remove-Item $targetLoaderFile -Force
                Write-Success "Removed existing Ioncube loader for clean overwrite"
            }
            
            # Copy loader file to PHP module ext directory as php_ioncube.dll
            Write-Progress "IONCUBE-PHP-$version" "Copying Ioncube loader to PHP module ext directory"
            Copy-Item -Path $loaderFile.FullName -Destination $targetLoaderFile -Force
            
            # Verify loader file was copied
            if (Test-Path $targetLoaderFile) {
                $copiedFileSize = [math]::Round((Get-Item $targetLoaderFile).Length / 1KB, 2)
                Write-Success "Copied php_ioncube.dll to $targetLoaderFile ($copiedFileSize KB)"
            } else {
                Write-Warning "Failed to copy Ioncube loader for PHP $version"
                $failedVersions++
                continue
            }
            
            # Create 3rd-party/ioncube directory if it doesn't exist
            if (-not (Test-Path $ioncubeDir)) {
                New-Item -ItemType Directory -Path $ioncubeDir -Force | Out-Null
                Write-Success "Created 3rd-party/ioncube directory: $ioncubeDir"
            }
            
            # Remove existing files in 3rd-party/ioncube directory for clean overwrite
            if (Test-Path $ioncubeDir) {
                Get-ChildItem -Path $ioncubeDir | Remove-Item -Recurse -Force
                Write-Success "Cleaned existing files in 3rd-party/ioncube directory"
            }
            
            # Move remaining files to 3rd-party/ioncube directory
            Write-Progress "IONCUBE-PHP-$version" "Moving remaining files to 3rd-party/ioncube directory"
            $remainingFiles = Get-ChildItem -Path $tmpDir -Recurse -File | Where-Object { $_.FullName -ne $loaderFile.FullName }
            $movedFilesCount = 0
            
            foreach ($file in $remainingFiles) {
                try {
                    $relativePath = $file.FullName.Substring($tmpDir.Length + 1)
                    $targetPath = Join-Path $ioncubeDir $relativePath
                    
                    # Create subdirectory if needed
                    $targetDir = Split-Path $targetPath -Parent
                    if (-not (Test-Path $targetDir)) {
                        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                    }
                    
                    Move-Item -Path $file.FullName -Destination $targetPath -Force
                    $movedFilesCount++
                }
                catch {
                    Write-Warning "Error moving file $($file.Name): $_"
                }
            }
            
            Write-Success "Moved $movedFilesCount additional files to 3rd-party/ioncube directory"
            
            # Clean up temporary files
            Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Temporary files cleaned up"
            
            $processedVersions++
            Write-Success "Ioncube loader successfully processed for PHP $version"
        }
        catch {
            Write-Error "Critical error processing Ioncube loader for PHP $version : $_"
            # Clean up on error
            Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
            $failedVersions++
        }
    }
    
    # Show summary
    Write-Host ""
    Write-Host "📊 PHP Ioncube processing results:" -ForegroundColor White
    Write-Host ""
    Write-Host "   Total PHP versions:  " -NoNewline -ForegroundColor Gray
    Write-Host $ioncubeArchives.Count -ForegroundColor White
    Write-Host "   Processed:           " -NoNewline -ForegroundColor Gray
    Write-Host $processedVersions -ForegroundColor Green
    Write-Host "   Skipped:             " -NoNewline -ForegroundColor Gray
    Write-Host $skippedVersions -ForegroundColor Yellow
    Write-Host "   Errors:              " -NoNewline -ForegroundColor Gray
    Write-Host $failedVersions -ForegroundColor Red
    Write-Host ""
    
    $successRate = if ($ioncubeArchives.Count -gt 0) { [math]::Round(($processedVersions / $ioncubeArchives.Count) * 100, 1) } else { 0 }
    Write-Host "   Success rate:        " -NoNewline -ForegroundColor Gray
    Write-Host "$successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host "" 
    Write-Success "PHP Ioncube files copy operation completed"
}

function Copy-PhpFirebirdFiles {
    <#
    .SYNOPSIS
    Downloads and copies Firebird client files to PHP modules
    #>
        
    # Define Firebird archives for different PHP versions
    $firebirdArchives = @{
        "7.3" = "https://github.com/FirebirdSQL/firebird/releases/download/v3.0.13/Firebird-3.0.13.33818-0-x64.zip"
        "7.4" = "https://github.com/FirebirdSQL/firebird/releases/download/v3.0.13/Firebird-3.0.13.33818-0-x64.zip"
        "8.0" = "https://github.com/FirebirdSQL/firebird/releases/download/v4.0.6/Firebird-4.0.6.3221-0-x64.zip"
        "8.1" = "https://github.com/FirebirdSQL/firebird/releases/download/v4.0.6/Firebird-4.0.6.3221-0-x64.zip"
        "8.2" = "https://github.com/FirebirdSQL/firebird/releases/download/v4.0.6/Firebird-4.0.6.3221-0-x64.zip"
        "8.3" = "https://github.com/FirebirdSQL/firebird/releases/download/v4.0.6/Firebird-4.0.6.3221-0-x64.zip"
        "8.4" = "https://github.com/FirebirdSQL/firebird/releases/download/v4.0.6/Firebird-4.0.6.3221-0-x64.zip"
    }
    
    $processedVersions = 0
    $skippedVersions = 0
    $failedVersions = 0
    
    foreach ($version in $firebirdArchives.Keys) {
        $phpModuleDir = "..\modules\PHP-$version"
        $targetFile = Join-Path $phpModuleDir "fbclient.dll"
        
        Write-Host ""
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host " PHP-$version FIREBIRD CLIENT" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host ""
        
        $archiveUrl = $firebirdArchives[$version]
        
        try {
            Write-Progress "FIREBIRD-PHP-$version" "Processing Firebird client for PHP $version"
            
            # Create PHP module directory if it doesn't exist
            if (-not (Test-Path $phpModuleDir)) {
                New-Item -ItemType Directory -Path $phpModuleDir -Force | Out-Null
                Write-Success "Created PHP module directory: $phpModuleDir"
            }
            
            # Create temporary directory
            $tmpDir = "$env:TEMP\firebird_$(Get-Random)"
            $zipPath = "$tmpDir.zip"
            
            Write-Progress "FIREBIRD-PHP-$version" "Downloading archive" $archiveUrl
            
            # Download archive
            if ($UseProxy) {
                & curl --socks5 $ProxyUrl -f -s -L -o $zipPath $archiveUrl 2>$null
            } else {
                & curl -f -s -L -o $zipPath $archiveUrl 2>$null
            }
            
            if (-not (Test-Path $zipPath)) {
                Write-Error "Failed to download Firebird archive for PHP $version"
                $failedVersions++
                continue
            }
            
            $fileSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
            Write-Success "Archive downloaded successfully ($fileSize MB)"
            
            # Extract archive
            Write-Progress "FIREBIRD-PHP-$version" "Extracting archive to temporary directory"
            Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
            
            # Find fbclient.dll file in extracted content
            $fbclientFile = Get-ChildItem -Path $tmpDir -File -Recurse | 
                           Where-Object { $_.Name -eq "fbclient.dll" } | 
                           Select-Object -First 1
            
            if (-not $fbclientFile) {
                Write-Warning "fbclient.dll file not found in archive for PHP $version"
                Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
                $failedVersions++
                continue
            }
            
            Write-Progress "FIREBIRD-PHP-$version" "Found Firebird client: $($fbclientFile.FullName)"
            
            # Remove existing file if it exists (for clean overwrite)
            if (Test-Path $targetFile) {
                Remove-Item $targetFile -Force
                Write-Success "Removed existing Firebird client for clean overwrite"
            }
            
            # Copy fbclient.dll to PHP module directory
            Write-Progress "FIREBIRD-PHP-$version" "Copying Firebird client to PHP module"
            Copy-Item -Path $fbclientFile.FullName -Destination $targetFile -Force
            
            # Verify file was copied
            if (Test-Path $targetFile) {
                $copiedFileSize = [math]::Round((Get-Item $targetFile).Length / 1KB, 2)
                Write-Success "Copied fbclient.dll to $targetFile ($copiedFileSize KB)"
            } else {
                Write-Warning "Failed to copy Firebird client for PHP $version"
                $failedVersions++
                continue
            }
            
            # Clean up temporary files
            Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Temporary files cleaned up"
            
            $processedVersions++
            Write-Success "Firebird client successfully processed for PHP $version"
        }
        catch {
            Write-Error "Critical error processing Firebird client for PHP $version : $_"
            # Clean up on error
            Remove-Item $tmpDir, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
            $failedVersions++
        }
    }
    
    # Show summary
    Write-Host ""
    Write-Host "📊 PHP Firebird processing results:" -ForegroundColor White
    Write-Host ""
    Write-Host "   Total PHP versions:  " -NoNewline -ForegroundColor Gray
    Write-Host $firebirdArchives.Count -ForegroundColor White
    Write-Host "   Processed:           " -NoNewline -ForegroundColor Gray
    Write-Host $processedVersions -ForegroundColor Green
    Write-Host "   Skipped:             " -NoNewline -ForegroundColor Gray
    Write-Host $skippedVersions -ForegroundColor Yellow
    Write-Host "   Errors:              " -NoNewline -ForegroundColor Gray
    Write-Host $failedVersions -ForegroundColor Red
    Write-Host ""
    
    $successRate = if ($firebirdArchives.Count -gt 0) { [math]::Round(($processedVersions / $firebirdArchives.Count) * 100, 1) } else { 0 }
    Write-Host "   Success rate:        " -NoNewline -ForegroundColor Gray
    Write-Host "$successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host ""
    Write-Success "PHP Firebird files copy operation completed"
}

function Copy-AdditionalFiles {
    <#
    .SYNOPSIS
    Downloads and copies additional system files
    #>
    
    Write-Host ""
    
    # Download files with guaranteed overwrite
    $downloads = @{
        "https://curl.se/ca/cacert.pem" = @(
            "..\system\ssl\cacert.pem",
            "..\system\bin\curl-ca-bundle.crt",
            "..\bin\curl-ca-bundle.crt",
            "..\addons\Perl\perl\vendor\lib\Mozilla\CA\cacert.pem"
        )
    }
    
    foreach ($url in $downloads.Keys) {
        foreach ($destPath in $downloads[$url]) {
            Write-PhpProgress "ADDITIONAL" "Downloading $(Split-Path $destPath -Leaf)" $url
            
            # Ensure directory exists
            Ensure-Directory $destPath
            
            # Remove existing file
            if (Test-Path $destPath) {
                Remove-Item $destPath -Force
            }
            
            try {
                if ($UseProxy) {
                    & curl --socks5 $ProxyUrl -f -s -L -o $destPath $url 2>$null
                } else {
                    & curl -f -s -L -o $destPath $url 2>$null
                }
                
                if (Test-Path $destPath) {
                    Write-Success "Downloaded: $destPath"
                } else {
                    Write-Warning "Failed to download: $destPath"
                }
            }
            catch {
                Write-Warning "Error downloading to $destPath : $_"
            }
        }
    }
    
    # Copy local file with overwrite
    $localCopies = @{
        "..\..\OSPSource\Win64\Release\OpenServerPanel.exe" = "..\bin\ospanel.exe"
        "..\resources\dist\README.txt" = "..\user\geo\README.txt"
        "..\bin\bat.exe" = "..\system\bin\bat.exe"
        "..\bin\curl.exe" = "..\system\bin\curl.exe"
        "..\bin\libcurl-x64.dll" = "..\system\bin\libcurl-x64.dll"
        "..\bin\fd.exe" = "..\system\bin\fd.exe"
    }
    
    foreach ($sourcePath in $localCopies.Keys) {
        $destPath = $localCopies[$sourcePath]
        
        if (Test-Path $sourcePath) {
            Write-PhpProgress "ADDITIONAL" "Copying local file $(Split-Path $sourcePath -Leaf)"
            
            # Ensure directory exists
            Ensure-Directory $destPath
            
            try {
                Copy-Item $sourcePath $destPath -Force
                Write-Success "Copied: $sourcePath → $destPath"
            }
            catch {
                Write-Warning "Error copying $sourcePath to $destPath : $_"
            }
        }
        else {
            Write-Warning "Source file not found: $sourcePath"
        }
    }
    
    Write-Success "Additional files copy operation completed"
}

function Show-Summary {
    <#
    .SYNOPSIS
    Displays final execution statistics
    #>
    
    Write-Host ""
    Write-Host "📊 Addon processing results:" -ForegroundColor White
    Write-Host ""
    Write-Host "   Total addons:       " -NoNewline -ForegroundColor Gray
    Write-Host $script:TotalAddons -ForegroundColor White
    Write-Host "   Processed:          " -NoNewline -ForegroundColor Gray
    Write-Host $script:ProcessedAddons -ForegroundColor Green
    Write-Host "   Skipped:            " -NoNewline -ForegroundColor Gray
    Write-Host $script:SkippedAddons -ForegroundColor Yellow
    Write-Host "   Errors:             " -NoNewline -ForegroundColor Gray
    Write-Host $script:FailedAddons -ForegroundColor Red
    Write-Host ""
    
    $addonSuccessRate = if ($script:TotalAddons -gt 0) { [math]::Round(($script:ProcessedAddons / $script:TotalAddons) * 100, 1) } else { 0 }
    Write-Host "   Addon success rate: " -NoNewline -ForegroundColor Gray
    Write-Host "$addonSuccessRate%" -ForegroundColor $(if ($addonSuccessRate -ge 90) { "Green" } elseif ($addonSuccessRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host ""
    
    Write-Host "🔧 Module processing results:" -ForegroundColor White
    Write-Host ""
    Write-Host "   Total modules:      " -NoNewline -ForegroundColor Gray
    Write-Host $script:TotalModules -ForegroundColor White
    Write-Host "   Processed:          " -NoNewline -ForegroundColor Gray
    Write-Host $script:ProcessedModules -ForegroundColor Green
    Write-Host "   Skipped:            " -NoNewline -ForegroundColor Gray
    Write-Host $script:SkippedModules -ForegroundColor Yellow
    Write-Host "   Errors:             " -NoNewline -ForegroundColor Gray
    Write-Host $script:FailedModules -ForegroundColor Red
    Write-Host ""

    $moduleSuccessRate = if ($script:TotalModules -gt 0) { [math]::Round(($script:ProcessedModules / $script:TotalModules) * 100, 1) } else { 0 }
    Write-Host "   Module success rate: " -NoNewline -ForegroundColor Gray
    Write-Host "$moduleSuccessRate%" -ForegroundColor $(if ($moduleSuccessRate -ge 90) { "Green" } elseif ($moduleSuccessRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host ""

    Write-Host "🛠️  Utility processing results:" -ForegroundColor White
    Write-Host ""
    Write-Host "   Total utilities:    " -NoNewline -ForegroundColor Gray
    Write-Host $script:TotalTools -ForegroundColor White
    Write-Host "   Installed:          " -NoNewline -ForegroundColor Gray
    Write-Host $script:ProcessedTools -ForegroundColor Green
    Write-Host "   Skipped:            " -NoNewline -ForegroundColor Gray
    Write-Host $script:SkippedTools -ForegroundColor Yellow
    Write-Host "   Errors:             " -NoNewline -ForegroundColor Gray
    Write-Host $script:FailedTools -ForegroundColor Red
    Write-Host ""

    $toolSuccessRate = if ($script:TotalTools -gt 0) { [math]::Round(($script:ProcessedTools / $script:TotalTools) * 100, 1) } else { 0 }
    Write-Host "   Utility success rate: " -NoNewline -ForegroundColor Gray
    Write-Host "$toolSuccessRate%" -ForegroundColor $(if ($toolSuccessRate -ge 90) { "Green" } elseif ($toolSuccessRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host ""
}

# ================== MODULE PROCESSING FUNCTIONS ==================

function Get-ModuleType {
    <#
    .SYNOPSIS
    Determines module type by name

    .PARAMETER ModuleName
    Module name
    #>
    param([string]$ModuleName)

    $types = @{
        "Apache*" = "Apache"
        "Bind*" = "Bind"
        "Mailpit*" = "Mailpit"
        "MariaDB*" = "MariaDB"
        "Memcached*" = "Memcached"
        "MongoDB*" = "MongoDB"
        "MySQL*" = "MySQL"
        "Nginx*" = "Nginx"
        "PHP*" = "PHP"
        "PostgreSQL*" = "PostgreSQL"
        "RabbitMQ*" = "RabbitMQ"
        "Redis*" = "Redis"
        "Smtp4dev*" = "Smtp4dev"
        "Unbound*" = "Unbound"
    }

    foreach ($pattern in $types.Keys) {
        if ($ModuleName -like $pattern) {
            return $types[$pattern]
        }
    }

    return "Unknown"
}

function Process-ApacheModule {
    <#
    .SYNOPSIS
    Processes Apache-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "APACHE-PROCESSING" "Processing Apache module"

        # Create temporary directory
        $tmpDir = "$env:TEMP\apache_$(Get-Random)"

        # Extract to temporary directory
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force

        # Find Apache directory (usually Apache24 or similar)
        $apacheDir = Get-ChildItem -Path $tmpDir -Directory |
                     Where-Object { $_.Name -like "Apache*" } |
                     Select-Object -First 1

        if ($apacheDir) {
            # Move contents from Apache subfolder to module root
            Get-ChildItem -Path $apacheDir.FullName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Moved files from $($apacheDir.Name) to module root"
        } else {
            # Extract directly if no Apache subfolder found
            Get-ChildItem -Path $tmpDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Files moved directly to module root"
        }

        # Clean up specific Apache files and directories
        Write-Progress "APACHE-PROCESSING" "Cleaning up unnecessary Apache files"

        # Remove ApacheMonitor.exe from bin directory
        $apacheMonitorPath = Join-Path $DestDir "bin\ApacheMonitor.exe"
        if (Test-Path $apacheMonitorPath) {
            Remove-Item $apacheMonitorPath -Force -ErrorAction SilentlyContinue
            Write-Success "Removed ApacheMonitor.exe"
        }

        # Remove unnecessary directories
        $dirsToRemove = @("htdocs", "lib", "include", "manual", "logs")
        $removedDirs = 0

        foreach ($dir in $dirsToRemove) {
            $dirPath = Join-Path $DestDir $dir
            if (Test-Path $dirPath) {
                Remove-Item $dirPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Success "Removed directory: $dir"
                $removedDirs++
            }
        }

        if ($removedDirs -gt 0) {
            Write-Success "Cleaned up $removedDirs unnecessary directories"
        }

        # Clean up conf directory - keep only specific files
        $confDir = Join-Path $DestDir "conf"
        if (Test-Path $confDir) {
            Write-Progress "APACHE-PROCESSING" "Cleaning up conf directory"

            $filesToKeep = @("charset.conv", "magic", "openssl.cnf")
            $allConfFiles = Get-ChildItem -Path $confDir -File -ErrorAction SilentlyContinue
            $removedConfFiles = 0

            foreach ($file in $allConfFiles) {
                if ($file.Name -notin $filesToKeep) {
                    Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                    $removedConfFiles++
                }
            }

            # Remove all subdirectories in conf
            $confSubDirs = Get-ChildItem -Path $confDir -Directory -ErrorAction SilentlyContinue
            foreach ($subDir in $confSubDirs) {
                Remove-Item $subDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $removedConfFiles++
            }

            if ($removedConfFiles -gt 0) {
                Write-Success "Cleaned up $removedConfFiles items from conf directory"
            }
        }

        # Clean up temporary directory
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "Apache module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing Apache module: $_"
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Process-BindModule {
    <#
    .SYNOPSIS
    Processes Bind-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "BIND-PROCESSING" "Processing Bind module"

        # Standard extraction
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force

        # Clean up specific Bind files
        Write-Progress "BIND-PROCESSING" "Cleaning up unnecessary Bind files"

        $filesToRemove = @("BINDInstall.exe", "vcredist_x64.exe")
        $removedFiles = 0

        foreach ($file in $filesToRemove) {
            $filePath = Join-Path $DestDir $file
            if (Test-Path $filePath) {
                Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                Write-Success "Removed file: $file"
                $removedFiles++
            }
        }

        if ($removedFiles -gt 0) {
            Write-Success "Cleaned up $removedFiles unnecessary files"
        }

        Write-Success "Bind module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing Bind module: $_"
        return $false
    }
}

function Process-MailpitModule {
    <#
    .SYNOPSIS
    Processes Mailpit-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "MAILPIT-PROCESSING" "Processing Mailpit module"

        # Standard extraction for now
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force

        Write-Success "Mailpit module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing Mailpit module: $_"
        return $false
    }
}

function Process-MariaDBModule {
    <#
    .SYNOPSIS
    Processes MariaDB-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "MARIADB-PROCESSING" "Processing MariaDB module"

        # Create temporary directory
        $tmpDir = "$env:TEMP\mariadb_$(Get-Random)"

        # Extract to temporary directory
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force

        # Find MariaDB directory (usually mariadb-* or similar)
        $mariadbDir = Get-ChildItem -Path $tmpDir -Directory |
                      Where-Object { $_.Name -like "mariadb*" } |
                      Select-Object -First 1

        if ($mariadbDir) {
            # Move contents from MariaDB subfolder to module root
            Get-ChildItem -Path $mariadbDir.FullName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Moved files from $($mariadbDir.Name) to module root"
        } else {
            # Extract directly if no MariaDB subfolder found
            Get-ChildItem -Path $tmpDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Files moved directly to module root"
        }

        # Clean up specific MariaDB files and directories
        Write-Progress "MARIADB-PROCESSING" "Cleaning up unnecessary MariaDB files"

        # Remove *.lib and *.pdb files from lib directory
        $libDir = Join-Path $DestDir "lib"
        if (Test-Path $libDir) {
            $libFiles = @(Get-ChildItem -Path $libDir -Filter "*.lib" -File -ErrorAction SilentlyContinue)
            $pdbFiles = @(Get-ChildItem -Path $libDir -Filter "*.pdb" -File -ErrorAction SilentlyContinue)

            foreach ($file in $libFiles) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }

            foreach ($file in $pdbFiles) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }

            $totalRemovedFromLib = $libFiles.Count + $pdbFiles.Count
            if ($totalRemovedFromLib -gt 0) {
                Write-Success "Removed $totalRemovedFromLib *.lib and *.pdb files from lib directory"
            }
        }

        # Remove *.lib and *.pdb files from lib\plugin directory
        $libPluginDir = Join-Path $DestDir "lib\plugin"
        if (Test-Path $libPluginDir) {
            $pluginLibFiles = @(Get-ChildItem -Path $libPluginDir -Filter "*.lib" -File -ErrorAction SilentlyContinue)
            $pluginPdbFiles = @(Get-ChildItem -Path $libPluginDir -Filter "*.pdb" -File -ErrorAction SilentlyContinue)

            foreach ($file in $pluginLibFiles) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }

            foreach ($file in $pluginPdbFiles) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }

            $totalRemovedFromPlugin = $pluginLibFiles.Count + $pluginPdbFiles.Count
            if ($totalRemovedFromPlugin -gt 0) {
                Write-Success "Removed $totalRemovedFromPlugin *.lib and *.pdb files from lib\plugin directory"
            }
        }

        # Remove include directory
        $includeDir = Join-Path $DestDir "include"
        if (Test-Path $includeDir) {
            Remove-Item $includeDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Removed include directory"
        }

        # Remove *.lib and *.pdb files from bin directory
        $binDir = Join-Path $DestDir "bin"
        if (Test-Path $binDir) {
            $binLibFiles = @(Get-ChildItem -Path $binDir -Filter "*.lib" -File -ErrorAction SilentlyContinue)
            $binPdbFiles = @(Get-ChildItem -Path $binDir -Filter "*.pdb" -File -ErrorAction SilentlyContinue)

            $totalBinFiles = $binLibFiles.Count + $binPdbFiles.Count
            Write-Progress "MARIADB-PROCESSING" "Found $totalBinFiles files to remove from bin directory"

            foreach ($file in $binLibFiles) {
                Write-Progress "MARIADB-PROCESSING" "Removing $($file.Name) from bin"
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }

            foreach ($file in $binPdbFiles) {
                Write-Progress "MARIADB-PROCESSING" "Removing $($file.Name) from bin"
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }

            if ($totalBinFiles -gt 0) {
                Write-Success "Removed $totalBinFiles *.lib and *.pdb files from bin directory"
            } else {
                Write-Warning "No *.lib or *.pdb files found in bin directory"
            }
        } else {
            Write-Warning "Bin directory not found: $binDir"
        }

        # Clean up temporary directory
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "MariaDB module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing MariaDB module: $_"
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Process-MemcachedModule {
    <#
    .SYNOPSIS
    Processes Memcached-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "MEMCACHED-PROCESSING" "Processing Memcached module"

        # Standard extraction for now
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force

        Write-Success "Memcached module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing Memcached module: $_"
        return $false
    }
}

function Process-MongoDBModule {
    <#
    .SYNOPSIS
    Processes MongoDB-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "MONGODB-PROCESSING" "Processing MongoDB module"

        # Create temporary directory
        $tmpDir = "$env:TEMP\mongodb_$(Get-Random)"

        # Extract to temporary directory
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force

        # Find MongoDB directory (usually mongodb-* or similar)
        $mongodbDir = Get-ChildItem -Path $tmpDir -Directory |
                      Where-Object { $_.Name -like "mongodb*" } |
                      Select-Object -First 1

        if ($mongodbDir) {
            # Move contents from MongoDB subfolder to module root
            Get-ChildItem -Path $mongodbDir.FullName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Moved files from $($mongodbDir.Name) to module root"
        } else {
            # Extract directly if no MongoDB subfolder found
            Get-ChildItem -Path $tmpDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Files moved directly to module root"
        }

        # Clean up specific MongoDB files
        Write-Progress "MONGODB-PROCESSING" "Cleaning up unnecessary MongoDB files"

        # Remove vc_redist.x64.exe from bin directory
        $vcRedistPath = Join-Path $DestDir "bin\vc_redist.x64.exe"
        if (Test-Path $vcRedistPath) {
            Remove-Item $vcRedistPath -Force -ErrorAction SilentlyContinue
            Write-Success "Removed vc_redist.x64.exe from bin directory"
        }

        # Remove *.lib and *.pdb files from bin directory
        $binDir = Join-Path $DestDir "bin"
        if (Test-Path $binDir) {
            $binLibFiles = @(Get-ChildItem -Path $binDir -Filter "*.lib" -File -ErrorAction SilentlyContinue)
            $binPdbFiles = @(Get-ChildItem -Path $binDir -Filter "*.pdb" -File -ErrorAction SilentlyContinue)

            $totalBinFiles = $binLibFiles.Count + $binPdbFiles.Count

            foreach ($file in $binLibFiles) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }

            foreach ($file in $binPdbFiles) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
            }

            if ($totalBinFiles -gt 0) {
                Write-Success "Removed $totalBinFiles *.lib and *.pdb files from bin directory"
            }
        }

        # Clean up temporary directory
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "MongoDB module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing MongoDB module: $_"
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Process-MySQLModule {
    <#
    .SYNOPSIS
    Processes MySQL-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "MYSQL-PROCESSING" "Processing MySQL module"

        # Create temporary directory
        $tmpDir = "$env:TEMP\mysql_$(Get-Random)"

        # Extract to temporary directory
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force

        # Find MySQL directory (usually mysql-* or similar)
        $mysqlDir = Get-ChildItem -Path $tmpDir -Directory |
                    Where-Object { $_.Name -like "mysql*" } |
                    Select-Object -First 1

        if ($mysqlDir) {
            # Move contents from MySQL subfolder to module root
            Get-ChildItem -Path $mysqlDir.FullName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Moved files from $($mysqlDir.Name) to module root"

            # Remove empty MySQL directory
            Remove-Item $mysqlDir.FullName -Force -ErrorAction SilentlyContinue
        } else {
            # Extract directly if no MySQL subfolder found
            Get-ChildItem -Path $tmpDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Files moved directly to module root"
        }

        # Clean up specific MySQL directories and files
        Write-Progress "MYSQL-PROCESSING" "Cleaning up unnecessary MySQL files"

        # Remove directories
        $dirsToRemove = @("data", "include", "docs", "lib\plugin\debug", "lib\debug")
        $removedDirs = 0

        foreach ($dir in $dirsToRemove) {
            $dirPath = Join-Path $DestDir $dir
            if (Test-Path $dirPath) {
                Remove-Item $dirPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Success "Removed directory: $dir"
                $removedDirs++
            }
        }

        # Remove specific files
        $filesToRemove = @(
            "my-default.ini",
            "bin\mysqld-debug.exe",
            "bin\mysql_configurator.exe",
            "lib\libmysqld.dll"
        )

        $removedFiles = 0
        foreach ($file in $filesToRemove) {
            $filePath = Join-Path $DestDir $file
            if (Test-Path $filePath) {
                Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                Write-Success "Removed file: $file"
                $removedFiles++
            }
        }

        # Remove all *.lib and *.pdb files from entire directory structure
        $libFiles = @(Get-ChildItem -Path $DestDir -Filter "*.lib" -File -Recurse -ErrorAction SilentlyContinue)
        $pdbFiles = @(Get-ChildItem -Path $DestDir -Filter "*.pdb" -File -Recurse -ErrorAction SilentlyContinue)

        foreach ($file in $libFiles) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }

        foreach ($file in $pdbFiles) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }

        $totalLibPdbFiles = $libFiles.Count + $pdbFiles.Count
        if ($totalLibPdbFiles -gt 0) {
            Write-Success "Removed $totalLibPdbFiles *.lib and *.pdb files"
        }

        # Clean up temporary directory
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "MySQL module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing MySQL module: $_"
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Process-NginxModule {
    <#
    .SYNOPSIS
    Processes Nginx-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "NGINX-PROCESSING" "Processing Nginx module"

        # Standard extraction
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force

        # Clean up specific Nginx files and directories
        Write-Progress "NGINX-PROCESSING" "Cleaning up unnecessary Nginx files"

        $dirsToRemove = @("html", "logs", "temp")
        $removedDirs = 0

        foreach ($dir in $dirsToRemove) {
            $dirPath = Join-Path $DestDir $dir
            if (Test-Path $dirPath) {
                Remove-Item $dirPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Success "Removed directory: $dir"
                $removedDirs++
            }
        }

        # Remove nginx.conf file
        $nginxConfPath = Join-Path $DestDir "conf\nginx.conf"
        if (Test-Path $nginxConfPath) {
            Remove-Item $nginxConfPath -Force -ErrorAction SilentlyContinue
            Write-Success "Removed file: conf\nginx.conf"
        }

        if ($removedDirs -gt 0) {
            Write-Success "Cleaned up $removedDirs directories and configuration file"
        }

        Write-Success "Nginx module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing Nginx module: $_"
        return $false
    }
}

function Process-PHPModule {
    <#
    .SYNOPSIS
    Processes PHP-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "PHP-PROCESSING" "Processing PHP module"

        # Standard extraction for now
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force

        Write-Success "PHP module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing PHP module: $_"
        return $false
    }
}

function Process-PostgreSQLModule {
    <#
    .SYNOPSIS
    Processes PostgreSQL-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "POSTGRESQL-PROCESSING" "Processing PostgreSQL module"

        # Create temporary directory
        $tmpDir = "$env:TEMP\postgresql_$(Get-Random)"

        # Extract to temporary directory
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force

        # Find pgsql directory
        $pgsqlDir = Get-ChildItem -Path $tmpDir -Directory |
                    Where-Object { $_.Name -eq "pgsql" } |
                    Select-Object -First 1

        if ($pgsqlDir) {
            # Move contents from pgsql subfolder to module root
            Get-ChildItem -Path $pgsqlDir.FullName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Moved files from pgsql to module root"

            # Remove empty pgsql directory
            Remove-Item $pgsqlDir.FullName -Force -ErrorAction SilentlyContinue
        } else {
            # Extract directly if no pgsql subfolder found
            Get-ChildItem -Path $tmpDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Files moved directly to module root"
        }

        # Clean up specific PostgreSQL directories and files
        Write-Progress "POSTGRESQL-PROCESSING" "Cleaning up unnecessary PostgreSQL files"

        # Remove directories
        $dirsToRemove = @("pgAdmin 4", "pgAdmin 3", "include", "symbols", "lib\pkgconfig", "lib\pgxs")
        $removedDirs = 0

        foreach ($dir in $dirsToRemove) {
            $dirPath = Join-Path $DestDir $dir
            if (Test-Path $dirPath) {
                Remove-Item $dirPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Success "Removed directory: $dir"
                $removedDirs++
            }
        }

        # Remove all *.lib and *.pdb files from entire directory structure
        $libFiles = @(Get-ChildItem -Path $DestDir -Filter "*.lib" -File -Recurse -ErrorAction SilentlyContinue)
        $pdbFiles = @(Get-ChildItem -Path $DestDir -Filter "*.pdb" -File -Recurse -ErrorAction SilentlyContinue)

        foreach ($file in $libFiles) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }

        foreach ($file in $pdbFiles) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }

        $totalLibPdbFiles = $libFiles.Count + $pdbFiles.Count
        if ($totalLibPdbFiles -gt 0) {
            Write-Success "Removed $totalLibPdbFiles *.lib and *.pdb files"
        }

        # Clean up temporary directory
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "PostgreSQL module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing PostgreSQL module: $_"
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Process-RabbitMQModule {
    <#
    .SYNOPSIS
    Processes RabbitMQ-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "RABBITMQ-PROCESSING" "Processing RabbitMQ module"

        # Create temporary directory
        $tmpDir = "$env:TEMP\rabbitmq_$(Get-Random)"

        # Extract to temporary directory
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force

        # Find RabbitMQ directory (usually rabbitmq-* or similar)
        $rabbitmqDir = Get-ChildItem -Path $tmpDir -Directory |
                       Where-Object { $_.Name -like "rabbitmq*" } |
                       Select-Object -First 1

        if ($rabbitmqDir) {
            # Move contents from RabbitMQ subfolder to module root
            Get-ChildItem -Path $rabbitmqDir.FullName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Moved files from $($rabbitmqDir.Name) to module root"

            # Remove empty RabbitMQ directory
            Remove-Item $rabbitmqDir.FullName -Force -ErrorAction SilentlyContinue
        } else {
            # Extract directly if no RabbitMQ subfolder found
            Get-ChildItem -Path $tmpDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Files moved directly to module root"
        }

        # Clean up specific RabbitMQ files
        Write-Progress "RABBITMQ-PROCESSING" "Cleaning up unnecessary RabbitMQ files"

        # Remove README.txt from etc directory
        $readmePath = Join-Path $DestDir "etc\README.txt"
        if (Test-Path $readmePath) {
            Remove-Item $readmePath -Force -ErrorAction SilentlyContinue
            Write-Success "Removed file: etc\README.txt"
        }

        # Clean up temporary directory
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "RabbitMQ module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing RabbitMQ module: $_"
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Process-RedisModule {
    <#
    .SYNOPSIS
    Processes Redis-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "REDIS-PROCESSING" "Processing Redis module"

        # Create temporary directory
        $tmpDir = "$env:TEMP\redis_$(Get-Random)"

        # Extract to temporary directory
        Expand-Archive -Path $ZipPath -DestinationPath $tmpDir -Force

        # Find Redis directory (usually redis-* or similar)
        $redisDir = Get-ChildItem -Path $tmpDir -Directory |
                    Where-Object { $_.Name -like "redis*" } |
                    Select-Object -First 1

        if ($redisDir) {
            # Move contents from Redis subfolder to module root
            Get-ChildItem -Path $redisDir.FullName | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Moved files from $($redisDir.Name) to module root"

            # Remove empty Redis directory
            Remove-Item $redisDir.FullName -Force -ErrorAction SilentlyContinue
        } else {
            # Extract directly if no Redis subfolder found
            Get-ChildItem -Path $tmpDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $DestDir -Force
            }
            Write-Success "Files moved directly to module root"
        }

        # Clean up specific Redis files
        Write-Progress "REDIS-PROCESSING" "Cleaning up unnecessary Redis files"

        $filesToRemove = @(
            "redis.conf",
            "install_redis.cmd"
        )

        $removedFiles = 0
        foreach ($file in $filesToRemove) {
            $filePath = Join-Path $DestDir $file
            if (Test-Path $filePath) {
                Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                Write-Success "Removed file: $file"
                $removedFiles++
            }
        }

        # Download RedisJson rejson.dll
        Write-Progress "REDIS-PROCESSING" "Downloading RedisJson module"
        try {
            $rejsonUrl = "https://github.com/zkteco-home/RedisJson/raw/master/rejson.dll"
            $rejsonPath = Join-Path $DestDir "rejson.dll"

            Invoke-WebRequest -Uri $rejsonUrl -OutFile $rejsonPath -UseBasicParsing
            Write-Success "Downloaded rejson.dll to module directory"
        }
        catch {
            Write-Warning "Failed to download rejson.dll: $_"
        }

        # Clean up temporary directory
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Success "Redis module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing Redis module: $_"
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Process-Smtp4devModule {
    <#
    .SYNOPSIS
    Processes Smtp4dev-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "SMTP4DEV-PROCESSING" "Processing Smtp4dev module"

        # Extract archive directly to destination
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force

        # Clean up specific Smtp4dev files
        Write-Progress "SMTP4DEV-PROCESSING" "Cleaning up unnecessary Smtp4dev files"

        # Remove *.pdb files
        $pdbFiles = @(Get-ChildItem -Path $DestDir -Filter "*.pdb" -File -Recurse -ErrorAction SilentlyContinue)
        foreach ($file in $pdbFiles) {
            Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        }

        if ($pdbFiles.Count -gt 0) {
            Write-Success "Removed $($pdbFiles.Count) *.pdb files"
        }

        # Remove specific config files
        $filesToRemove = @(
            "web.config",
            "appsettings.json"
        )

        $removedFiles = 0
        foreach ($file in $filesToRemove) {
            $filePath = Join-Path $DestDir $file
            if (Test-Path $filePath) {
                Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                Write-Success "Removed file: $file"
                $removedFiles++
            }
        }

        # Rename Rnwood.Smtp4dev.xml to w3wp.Smtp4dev.exe.xml
        $xmlOldPath = Join-Path $DestDir "Rnwood.Smtp4dev.xml"
        $xmlNewPath = Join-Path $DestDir "w3wp.Smtp4dev.exe.xml"
        if (Test-Path $xmlOldPath) {
            Rename-Item -Path $xmlOldPath -NewName "w3wp.Smtp4dev.exe.xml" -Force
            Write-Success "Renamed Rnwood.Smtp4dev.xml to w3wp.Smtp4dev.exe.xml"
        }

        # Rename Rnwood.Smtp4dev.exe to w3wp.Smtp4dev.exe
        $exeOldPath = Join-Path $DestDir "Rnwood.Smtp4dev.exe"
        $exeNewPath = Join-Path $DestDir "w3wp.Smtp4dev.exe"
        if (Test-Path $exeOldPath) {
            Rename-Item -Path $exeOldPath -NewName "w3wp.Smtp4dev.exe" -Force
            Write-Success "Renamed Rnwood.Smtp4dev.exe to w3wp.Smtp4dev.exe"
        }

        Write-Success "Smtp4dev module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing Smtp4dev module: $_"
        return $false
    }
}

function Process-UnboundModule {
    <#
    .SYNOPSIS
    Processes Unbound-type modules

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to downloaded archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "UNBOUND-PROCESSING" "Processing Unbound module"

        # Standard extraction for now
        Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force

        Write-Success "Unbound module processing completed"
        return $true
    }
    catch {
        Write-Error "Error processing Unbound module: $_"
        return $false
    }
}

function Extract-Module {
    <#
    .SYNOPSIS
    Extracts and processes module with type-specific handling

    .PARAMETER ModuleName
    Module name

    .PARAMETER ZipPath
    Path to archive

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$ZipPath, [string]$DestDir)

    try {
        Write-Progress "EXTRACTION" "Extracting module archive"

        # Create target directory
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
        }

        # Determine module type and process accordingly
        $moduleType = Get-ModuleType -ModuleName $ModuleName

        $result = switch ($moduleType) {
            "Apache" { Process-ApacheModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "Bind" { Process-BindModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "Mailpit" { Process-MailpitModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "MariaDB" { Process-MariaDBModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "Memcached" { Process-MemcachedModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "MongoDB" { Process-MongoDBModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "MySQL" { Process-MySQLModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "Nginx" { Process-NginxModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "PHP" { Process-PHPModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "PostgreSQL" { Process-PostgreSQLModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "RabbitMQ" { Process-RabbitMQModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "Redis" { Process-RedisModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "Smtp4dev" { Process-Smtp4devModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            "Unbound" { Process-UnboundModule -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir }
            default {
                Write-Warning "Unknown module type for $ModuleName, using standard extraction"
                Expand-Archive -Path $ZipPath -DestinationPath $DestDir -Force
                $true
            }
        }

        # Remove archive after extraction
        if (Test-Path $ZipPath) {
            Remove-Item $ZipPath -Force
        }

        if ($result) {
            Write-Success "Module archive successfully extracted and deleted"
        }

        return $result
    }
    catch {
        Write-Error "Error extracting module archive: $_"
        return $false
    }
}

function Generate-ModuleHelpFiles {
    <#
    .SYNOPSIS
    Generates help files for module executable files

    .PARAMETER ModuleName
    Module name

    .PARAMETER DestDir
    Module directory

    .PARAMETER Module
    Module object with settings
    #>
    param([string]$ModuleName, [string]$DestDir, [object]$Module)

    Write-Progress "HELP" "Generating module help files"

    $HelpDir = "$DestDir\ospanel_data\help"

    # Create help directory
    if (-not (Test-Path $HelpDir)) {
        New-Item -ItemType Directory -Force -Path $HelpDir | Out-Null
    }

    # Find executable files
$executables = Get-ChildItem -Path $DestDir -Filter *.exe -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin 'logresolve.exe','nslookup.exe','isolationtester.exe' }

    if (-not $executables) {
        Write-Warning "No executable files found"
        return
    }

    $helpCmd = if ($Module.help) { $Module.help } else { "--help" }
    $generatedFiles = 0

    foreach ($exe in $executables) {
        $outFile = Join-Path $HelpDir ($exe.BaseName + ".txt")
        try { Write-Warning $exe.FullName
            $args = $helpCmd -split "\s+"
            $output = & $exe.FullName @($args) 2>&1

            # Filter empty lines and write to file
            $filteredOutput = $output | Where-Object { $_.ToString().Trim() -ne "" }

            if ($filteredOutput) {
                $filteredOutput | Out-File -FilePath $outFile -Encoding utf8
                $generatedFiles++
            } else {
                Write-Warning "Empty help output for $($exe.Name)"
            }
        }
        catch {
            Write-Warning "Error generating help for $($exe.Name): $_"
        }
    }

    Write-Success "Created $generatedFiles module help files"
}

function Generate-ModuleIniFile {
    <#
    .SYNOPSIS
    Creates module.ini file for module

    .PARAMETER DestDir
    Module directory

    .PARAMETER Module
    Module object with settings
    #>
    param([string]$DestDir, [object]$Module)

    Write-Progress "CONFIGURATION" "Creating module.ini"

    $IniPath = "$DestDir\ospanel_data\module.ini"

    # Section order in INI file
    $sectionsOrder = @("main", "docs")
    $skipSections = @("DownloadUrl", "ZipPath", "help")

    $iniContent = @()

    # Add sections in specific order
    foreach ($sec in $sectionsOrder) {
        if ($Module.PSObject.Properties.Name -contains $sec) {
            $iniContent += Convert-ToIni -SectionName $sec -Data $Module.$sec
            $iniContent += ""
        }
    }

    # Add other sections
    $otherSections = $Module.PSObject.Properties.Name |
                     Where-Object { $sectionsOrder -notcontains $_ -and $skipSections -notcontains $_ } |
                     Sort-Object

    foreach ($sec in $otherSections) {
        $iniContent += Convert-ToIni -SectionName $sec -Data $Module.$sec
        $iniContent += ""
    }

    # Create directory and save file
    $iniDir = Split-Path $IniPath -Parent
    if (-not (Test-Path $iniDir)) {
        New-Item -ItemType Directory -Force -Path $iniDir | Out-Null
    }

    $iniContent | Out-File -FilePath $IniPath -Encoding utf8 -Force
    Write-Success "module.ini file created"
}

function Copy-ModuleBundleFiles {
    <#
    .SYNOPSIS
    Copies additional files from module bundle

    .PARAMETER ModuleName
    Module name

    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$ModuleName, [string]$DestDir)

    $bundleSrc = "..\resources\modules\$ModuleName"

    if (Test-Path $bundleSrc) {
        Write-Progress "COPYING" "Additional files from module bundle"

        try {
            Copy-Item -Path (Join-Path $bundleSrc "*") -Destination $DestDir -Recurse -Force
            Write-Success "Additional module files copied"
        }
        catch {
            Write-Warning "Error copying additional module files: $_"
        }
    }
}

function Get-ModulesList {
    <#
    .SYNOPSIS
    Loads and parses module list from JSON
    #>

    try {
        Write-Progress "SYSTEM" "Loading modules configuration"

        $infodata = Get-Content $JsonPath -Raw | ConvertFrom-Json
        $modules = $infodata.modules.PSObject.Properties.Name | Sort-Object -Unique

        $script:TotalModules = $modules.Count
        Write-Success "Loaded $($script:TotalModules) modules from configuration"

        return @{
            InfoData = $infodata
            Modules = $modules
        }
    }
    catch {
        Write-Error "Error loading modules configuration: $_"
        return $null
    }
}

# =====================================================

# ================== MAIN EXECUTION BLOCK ==================
Write-Banner "AUTOMATED OSPANEL ADDONS AND UTILITIES BUILD" "Cyan"
Write-Host ""

$folders = @("..\addons", "..\modules", "..\bin", "..\config", "..\data", "..\user\geo")

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "📂 Created directory: $folder" -ForegroundColor Green
    }
}

# STEP 1: Prerequisites Check
$script:CurrentMainStep = 1

Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): PREREQUISITES CHECK" "Cyan"

Write-Host ""

if (-not (Test-Prerequisites)) {
    exit 1
}

# STEP 2: Addon Processing
$script:CurrentMainStep = 2
$config = Get-AddonsList
if (-not $config) {
    Write-Error "Failed to load addon configuration"
    exit 1
}

$infodata = $config.InfoData
$addons = $config.Addons
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): PROCESSING ADDONS" "Yellow"

# Main addon processing loop
foreach ($AddonName in $addons) {
    $script:ProcessedAddons++

    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host " ADDON: $AddonName [$script:ProcessedAddons/$script:TotalAddons]" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""

    $addon = $infodata.addons.$AddonName

    # Check for download URL
    if (-not $addon.DownloadUrl) {
        Write-Skip "Addon '$AddonName' skipped (missing DownloadUrl)"
        $script:SkippedAddons++
        continue
    }

    # Define paths
    $DestDir = Join-Path $BaseAddonsDir $AddonName

    # Check if addon folder exists
    if (Test-Path $DestDir) {
        Write-Skip "Addon '$AddonName' skipped (folder already exists)"
        $script:SkippedAddons++
        continue
    }

    $ZipPath = if ($addon.ZipPath) { $addon.ZipPath } else { "$AddonName.zip" }

    try {
        # Special processing for InstantClient
        if ($AddonName -eq "InstantClient") {
            # 2.1-2.2: Download & Extract (combined for InstantClient)
            $script:CurrentAddonSubStep = 1
            if (-not (Extract-Addon -AddonName $AddonName -ZipPath "" -DestDir $DestDir -DownloadUrl $addon.DownloadUrl)) {
                $script:FailedAddons++
                continue
            }
        } else {
            # 2.1: Download addon
            $script:CurrentAddonSubStep = 1
            if (-not (Download-Addon -DownloadUrl $addon.DownloadUrl -ZipPath $ZipPath)) {
                $script:FailedAddons++
                continue
            }

            # 2.2: Extract archive
            $script:CurrentAddonSubStep = 2
            if (-not (Extract-Addon -AddonName $AddonName -ZipPath $ZipPath -DestDir $DestDir)) {
                $script:FailedAddons++
                continue
            }
        }

        # 2.3: Generate help files
        $script:CurrentAddonSubStep = 3
        Generate-HelpFiles -AddonName $AddonName -DestDir $DestDir -Addon $addon

        # 2.4: Create addon.ini
        $script:CurrentAddonSubStep = 4
        Generate-IniFile -DestDir $DestDir -Addon $addon

        # 2.5: Copy additional files
        $script:CurrentAddonSubStep = 5
        Copy-BundleFiles -AddonName $AddonName -DestDir $DestDir

        # 2.6: Success
        $script:CurrentAddonSubStep = 6
        Write-Success "Addon '$AddonName' successfully processed"
        $script:CurrentAddonSubStep = 0
    }
    catch {
        Write-Error "Critical error processing '$AddonName': $_"
        $script:FailedAddons++
        $script:CurrentAddonSubStep = 0
    }
}

# STEP 3: Cleanup
$script:CurrentMainStep = 3
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): CLEANING UNNECESSARY FILES" "Magenta"
Remove-UnnecessaryFiles

# STEP 4: Module Processing
$script:CurrentMainStep = 4
$moduleConfig = Get-ModulesList
if (-not $moduleConfig) {
    Write-Error "Failed to load module configuration"
} else {
    $modules = $moduleConfig.Modules
    $moduleInfodata = $moduleConfig.InfoData

    Write-Host ""
    Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): PROCESSING MODULES" "Yellow"

    # Create base modules directory
    $BaseModulesDir = "..\modules"
    if (-not (Test-Path $BaseModulesDir)) {
        New-Item -ItemType Directory -Path $BaseModulesDir -Force | Out-Null
    }

    # Main module processing loop
    foreach ($ModuleName in $modules) {
        $script:ProcessedModules++

        Write-Host ""
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host " MODULE: $ModuleName [$script:ProcessedModules/$script:TotalModules]" -ForegroundColor Cyan
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host ""

        $module = $moduleInfodata.modules.$ModuleName

        # Check for download URL
        if (-not $module.DownloadUrl) {
            Write-Skip "Module '$ModuleName' skipped (missing DownloadUrl)"
            $script:SkippedModules++
            continue
        }

        # Define paths
        $DestDir = Join-Path $BaseModulesDir $ModuleName

        # Check if module folder exists
        if (Test-Path $DestDir) {
            Write-Skip "Module '$ModuleName' skipped (folder already exists)"
            $script:SkippedModules++
            continue
        }

        $ZipPath = if ($module.ZipPath) { $module.ZipPath } else { "$ModuleName.zip" }

        try {
            # Create module directory structure
            $ospanelDataDir = Join-Path $DestDir "ospanel_data\help"
            if (-not (Test-Path $ospanelDataDir)) {
                New-Item -ItemType Directory -Force -Path $ospanelDataDir | Out-Null
            }

            # Download module
            if (-not (Download-Addon -DownloadUrl $module.DownloadUrl -ZipPath $ZipPath)) {
                $script:FailedModules++
                continue
            }

            # Extract and process module
            if (-not (Extract-Module -ModuleName $ModuleName -ZipPath $ZipPath -DestDir $DestDir)) {
                $script:FailedModules++
                continue
            }

            # Generate help files
            Generate-ModuleHelpFiles -ModuleName $ModuleName -DestDir $DestDir -Module $module

            # Copy additional files from bundle
            Copy-ModuleBundleFiles -ModuleName $ModuleName -DestDir $DestDir

            # Create module.ini
            Generate-ModuleIniFile -DestDir $DestDir -Module $module

            Write-Success "Module '$ModuleName' successfully processed"
        }
        catch {
            Write-Error "Critical error processing '$ModuleName': $_"
            $script:FailedModules++
        }
    }
}

# STEP 5: Utility Processing
$script:CurrentMainStep = 5
$binMatrix = Get-ToolsList
if (-not $binMatrix) {
    Write-Error "Failed to load utility configuration"
    exit 1
}
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): INSTALLING SYSTEM UTILITIES" "Yellow"

# Create necessary directories for utilities
if (-not (Test-Path $BaseBinDir)) {
    New-Item $BaseBinDir -ItemType Directory -Force | Out-Null
}

$helpDir = Join-Path $BaseBinDir "help"
if (-not (Test-Path $helpDir)) {
    New-Item $helpDir -ItemType Directory -Force | Out-Null
}

# Main utility processing loop
foreach ($tool in $binMatrix.tools) {
    $script:ProcessedTools++

    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host " UTILITY: $($tool.name) [$script:ProcessedTools/$script:TotalTools]" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""

    try {
        # 4.1: Install utility
        $script:CurrentToolSubStep = 1
        if ($tool.direct_download) {
            Install-DirectDownload -Url $tool.url -TargetName $tool.target_name
        }
        elseif ($tool.url -eq "local" -and $tool.local_zip) {
            Install-FromLocalArchive -LocalZip $tool.local_zip -Files $tool.files
        }
        elseif ($tool.url -eq "local" -and $tool.local_files) {
            Install-LocalFiles -LocalFiles $tool.local_files
        }
        else {
            $copyFiles = if ($tool.copy_files) { $tool.copy_files } else { @() }
            Install-ToolFromArchive -Url $tool.url -ExtractPath $tool.extract_path -Files $tool.files -CopyFiles $copyFiles
        }

        # 4.2: Generate help
        $script:CurrentToolSubStep = 2
        if ($tool.help_command) {
            Generate-ToolHelp -Command $tool.help_command
        }
        elseif ($tool.help_commands) {
            foreach ($helpCmd in $tool.help_commands) {
                Generate-ToolHelp -Command $helpCmd.command -OutputFile $helpCmd.output
            }
        }

        # 4.3: Success
        $script:CurrentToolSubStep = 3
        Write-Success "Utility '$($tool.name)' successfully installed"
        $script:CurrentToolSubStep = 0
    }
    catch {
        Write-Error "Critical error installing '$($tool.name)': $_"
        $script:FailedTools++
        $script:CurrentToolSubStep = 0
    }
}

# STEP 6: Composer Files
$script:CurrentMainStep = 6
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): COPYING COMPOSER & OTHER PHP FILES" "Magenta"
Copy-ComposerFiles

# STEP 7: PHP MIB Files
$script:CurrentMainStep = 7
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): COPYING PHP MIB FILES" "Magenta"
Copy-PhpMibFiles

# STEP 8: PHP Blackfire Files
$script:CurrentMainStep = 8
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): COPYING PHP BLACKFIRE FILES" "Magenta"
Copy-PhpBlackfireFiles

# STEP 9: PHP Ioncube Files
$script:CurrentMainStep = 9
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): COPYING PHP IONCUBE FILES" "Magenta"
Copy-PhpIoncubeFiles

# STEP 10: PHP Firebird Files
$script:CurrentMainStep = 10
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): COPYING PHP FIREBIRD FILES" "Magenta"
Copy-PhpFirebirdFiles

# STEP 11: Additional Files
$script:CurrentMainStep = 11
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): COPYING ADDITIONAL FILES" "Magenta"
Copy-AdditionalFiles

# STEP 12: Final Statistics
$script:CurrentMainStep = 12
Write-Host ""
Write-Banner "STEP $($script:CurrentMainStep)/$($script:TotalMainSteps): FINAL STATISTICS" "Green"
Show-Summary

# Root folder. By default, one level above the script's folder. Set an explicit path if needed.
$Root = Split-Path -Parent $PSScriptRoot
# Example: $Root = "C:\Path\to\folder"

# Regex: C:\Portable\Documents\Git\OSPanel\modules\ + any characters up to \bin\
$pattern = [regex]::Escape("C:\Portable\Documents\Git\OSPanel\modules\") + ".*?" + [regex]::Escape("\bin\")
$regex = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

$processed = 0
$changed = 0
$errors = 0

Get-ChildItem -Path $Root -Filter *.txt -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $file = $_.FullName
    try {
        # Read entire file as a single string
        $content = Get-Content -LiteralPath $file -Raw -ErrorAction Stop

        # Remove matching substrings
        $newContent = $regex.Replace($content, "")

        # Save only if content changed
        if ($newContent -ne $content) {
            Set-Content -LiteralPath $file -Value $newContent -Encoding UTF8
            $changed++
        }
        $processed++
    }
    catch {
        Write-Host "Error: $file - $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
}

# ==================== MANUAL UPDATE NOTICE ====================
Write-Banner "MANUAL UPDATE REQUIRED" "Yellow"
Write-Host ""
Write-Host "⚠️  " -ForegroundColor Yellow -NoNewline
Write-Host "The following geodata files require manual update:" -ForegroundColor White
Write-Host ""
Write-Host "📍 IP Geolocation Databases:" -ForegroundColor Cyan
Write-Host ""
Write-Host "   1. DB-IP Country Lite Database" -ForegroundColor White
Write-Host "      🌐 " -ForegroundColor Green -NoNewline
Write-Host "https://db-ip.com/db/download/ip-to-country-lite" -ForegroundColor Gray
Write-Host ""
Write-Host "   2. GeoIP Legacy Database" -ForegroundColor White
Write-Host "      🌐 " -ForegroundColor Green -NoNewline
Write-Host "https://mailfud.org/geoip-legacy/" -ForegroundColor Gray
Write-Host ""
Write-Host "   3. MaxMind GeoOpen Database (MMDB format)" -ForegroundColor White
Write-Host "      🌐 " -ForegroundColor Green -NoNewline
Write-Host "https://data.public.lu/en/datasets/geo-open-ip-address-geolocation-per-country-in-mmdb-format/" -ForegroundColor Gray
Write-Host ""
Write-Host "💡 " -ForegroundColor Blue -NoNewline
Write-Host "Please download and update these geodata files manually to ensure" -ForegroundColor White
Write-Host "   accurate IP geolocation functionality in your applications." -ForegroundColor White
Write-Host ""

Write-Banner "ADDON AND UTILITY BUILD COMPLETED" "Green"