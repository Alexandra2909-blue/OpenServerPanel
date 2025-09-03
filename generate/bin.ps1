# ================================================================================
#                    AUTOMATED OSPANEL ADDONS AND UTILITIES BUILD SCRIPT
# ================================================================================
# Description: Automated OSPanel addons build from JSON configuration
#              and system utilities installation
# Author:      OSPanel Team
# Version:     2.1
# Date:        2025
# ================================================================================

# ================== SCRIPT CONFIGURATION ==================
# Path to JSON file with addons matrix
$JsonPath       = "..\resources\matrix\infodata.json"

# Path to JSON file with utilities matrix
$BinMatrixPath  = "..\resources\matrix\bin.json"

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
    
    $prefix = "[$script:ProcessedAddons/$script:TotalAddons]"
    $status = if ($Details) { "$Step - $Details" } else { $Step }
    
    Write-Host "$prefix " -ForegroundColor Yellow -NoNewline
    Write-Host "$AddonName" -ForegroundColor White -NoNewline
    Write-Host " → $status" -ForegroundColor Green
}

function Write-ToolProgress {
    param([string]$ToolName, [string]$Step, [string]$Details = "")
    
    $prefix = "[$script:ProcessedTools/$script:TotalTools]"
    $status = if ($Details) { "$Step - $Details" } else { $Step }
    
    Write-Host "$prefix " -ForegroundColor Yellow -NoNewline
    Write-Host "$ToolName" -ForegroundColor White -NoNewline
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
        Write-ToolProgress "SYSTEM" "Loading utilities configuration"
        
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
    
    .PARAMETER Version
    InstantClient version (e.g., 23.9.0.25.07)
    
    .PARAMETER DestDir
    Destination directory
    #>
    param([string]$Version, [string]$DestDir)
    
    try {
        Write-Progress "INSTANTCLIENT" "Special processing InstantClient version $Version"
        
        # List of archives to download with version substitution
        $archives = @(
            "https://download.oracle.com/otn_software/nt/instantclient/2390000/instantclient-odbc-windows.x64-$Version.zip",
            "https://download.oracle.com/otn_software/nt/instantclient/2390000/instantclient-jdbc-windows.x64-$Version.zip",
            "https://download.oracle.com/otn_software/nt/instantclient/2390000/instantclient-tools-windows.x64-$Version.zip",
            "https://download.oracle.com/otn_software/nt/instantclient/2390000/instantclient-sqlplus-windows.x64-$Version.zip",
            "https://download.oracle.com/otn_software/nt/instantclient/2390000/instantclient-basic-windows.x64-$Version.zip"
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
                # For InstantClient DownloadUrl contains version
                return (Process-InstantClient -Version $DownloadUrl -DestDir $DestDir)
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
    
    $bundleSrc = "..\resources\addons_bundle\$AddonName"
    
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
    
    Write-Banner "CLEANING UNNECESSARY FILES" "Magenta"
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
                    Remove-Item $_.FullName -Force
                    Write-Success "Removed file: $($_.Name)"
                }

        # Remove erts*\lib and erts*\include
        Get-ChildItem -Path $excludedDir.FullName -Directory -Filter "erts*" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $libPath = Join-Path $_.FullName "lib"
                $includePath = Join-Path $_.FullName "include"
                
                if (Test-Path $libPath) {
                    Remove-Item $libPath -Recurse -Force
                    Write-Success "Removed: $libPath"
                }
                
                if (Test-Path $includePath) {
                    Remove-Item $includePath -Recurse -Force
                    Write-Success "Removed: $includePath"
                }
            }
        
        # Clean usr\lib
        $usrLibPath = Join-Path $excludedDir.FullName "usr\lib"
        if (Test-Path $usrLibPath) {
            # Remove *.lib files
            Get-ChildItem -Path $usrLibPath -Filter "*.lib" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Remove-Item $_.FullName -Force
                    Write-Success "Removed file: $($_.Name)"
                }
            
            # Remove include folder
            $usrLibIncludePath = Join-Path $usrLibPath "include"
            if (Test-Path $usrLibIncludePath) {
                Remove-Item $usrLibIncludePath -Recurse -Force
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
                        Remove-Item $erlInterfaceIncludePath -Recurse -Force
                        Write-Success "Removed: $erlInterfaceIncludePath"
                    }
                    
                    if (Test-Path $erlInterfaceLibPath) {
                        Remove-Item $erlInterfaceLibPath -Recurse -Force
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
                    Remove-Item $targetPath -Recurse -Force
                    Write-Success "Removed directory: $_"
                }
            }
            
            # Remove unnecessary files
            $filesRemoved = 0
            @("*.pdb", "db2level.txt", "uidrvci.txt", "odbc_install.txt", "adrci.txt", "vc_redist.exe", "install.cmd") | ForEach-Object {
                Get-ChildItem -Path $addonPath -Filter $_ -Recurse -ErrorAction SilentlyContinue | 
                    ForEach-Object { 
                        Remove-Item $_.FullName -Force
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
            Remove-Item $_.FullName -Force
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
    
    Write-ToolProgress "DOWNLOAD" "Downloading archive" $Url
    
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
            Write-ToolProgress "COPYING" "File $file"
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
            Write-ToolProgress "COPYING" "Additional file $fileName"
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
    
    Write-ToolProgress "DOWNLOAD" "Direct downloading" $Url
    
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
    
    Write-ToolProgress "EXTRACTION" "Local archive" $LocalZip
    Expand-Archive $LocalZip $tmp -Force
    
    foreach ($file in $Files) {
        $sourceFile = Get-ChildItem -Path $tmp -Recurse -File | 
                     Where-Object { $_.Name -eq $file } | 
                     Select-Object -First 1
        
        if ($sourceFile) {
            Write-ToolProgress "COPYING" "File $file"
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
            Write-ToolProgress "COPYING" "Local file $fileName"
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
    
    Write-ToolProgress "HELP" "Generating help for $($Command[0])"
    
    try {
        $out = & $execPath $Command[1..($Command.Length-1)] 2>&1 | Where-Object {$_.ToString().Trim()}
        $out | Out-File $helpPath -Encoding utf8 -Force
        Write-Success "Help created: $OutputFile"
    } catch {
        Write-Warning "Error generating help for $($Command[0]): $_"
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
    Displays final execution statistics
    #>
    
    Write-Banner "FINAL STATISTICS" "Green"
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
    
    Write-Host "🔧 Utility processing results:" -ForegroundColor White
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
    Write-Host "   Utility success rate:" -NoNewline -ForegroundColor Gray
    Write-Host "$toolSuccessRate%" -ForegroundColor $(if ($toolSuccessRate -ge 90) { "Green" } elseif ($toolSuccessRate -ge 70) { "Yellow" } else { "Red" })
    Write-Host ""
}

# =====================================================

# ================== MAIN EXECUTION BLOCK ==================
Write-Banner "AUTOMATED OSPANEL ADDONS AND UTILITIES BUILD" "Cyan"
Write-Host ""
# Check prerequisites
if (-not (Test-Prerequisites)) {
    exit 1
}

# ==================== ADDON PROCESSING ====================

# Load addon configuration
$config = Get-AddonsList
if (-not $config) {
    Write-Error "Failed to load addon configuration"
    exit 1
}

$infodata = $config.InfoData
$addons = $config.Addons
Write-Host ""
Write-Banner "PROCESSING ADDONS" "Yellow"

# Main addon processing loop
foreach ($AddonName in $addons) {
    $script:ProcessedAddons++
    
    Write-Host ""
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host " ADDON: $AddonName [$script:ProcessedAddons/$script:TotalAddons]" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
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
            # For InstantClient don't download single file, process directly
            if (-not (Extract-Addon -AddonName $AddonName -ZipPath "" -DestDir $DestDir -DownloadUrl $addon.DownloadUrl)) {
                $script:FailedAddons++
                continue
            }
        } else {
            # 1. Download addon (for regular addons)
            if (-not (Download-Addon -DownloadUrl $addon.DownloadUrl -ZipPath $ZipPath)) {
                $script:FailedAddons++
                continue
            }

            # 2. Extract archive
            if (-not (Extract-Addon -AddonName $AddonName -ZipPath $ZipPath -DestDir $DestDir)) {
                $script:FailedAddons++
                continue
            }
        }

        # 3. Generate help files
        Generate-HelpFiles -AddonName $AddonName -DestDir $DestDir -Addon $addon

        # 4. Create addon.ini
        Generate-IniFile -DestDir $DestDir -Addon $addon

        # 5. Copy additional files
        Copy-BundleFiles -AddonName $AddonName -DestDir $DestDir

        Write-Success "Addon '$AddonName' successfully processed"
    }
    catch {
        Write-Error "Critical error processing '$AddonName': $_"
        $script:FailedAddons++
    }
}

# Final addon cleanup
Write-Host ""
Remove-UnnecessaryFiles

# ==================== UTILITY PROCESSING ====================

# Load utility configuration
$binMatrix = Get-ToolsList
if (-not $binMatrix) {
    Write-Error "Failed to load utility configuration"
    exit 1
}
Write-Host ""
Write-Banner "INSTALLING SYSTEM UTILITIES" "Yellow"

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
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host " UTILITY: $($tool.name) [$script:ProcessedTools/$script:TotalTools]" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Determine installation type and execute corresponding function
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
        
        # Generate help
        if ($tool.help_command) {
            Generate-ToolHelp -Command $tool.help_command
        }
        elseif ($tool.help_commands) {
            foreach ($helpCmd in $tool.help_commands) {
                Generate-ToolHelp -Command $helpCmd.command -OutputFile $helpCmd.output
            }
        }
        
        Write-Success "Utility '$($tool.name)' successfully installed"
    }
    catch {
        Write-Error "Critical error installing '$($tool.name)': $_"
        $script:FailedTools++
    }
}

# Show final statistics
Write-Host ""
Show-Summary

Write-Banner "ADDON AND UTILITY BUILD COMPLETED" "Green"