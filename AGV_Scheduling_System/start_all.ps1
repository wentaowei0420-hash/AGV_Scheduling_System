$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

function Write-Step {
    param([string]$Message)
    Write-Host "[START] $Message" -ForegroundColor Cyan
}

function Test-TcpPort {
    param(
        [string]$HostName = "127.0.0.1",
        [int]$Port = 3306
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $connected = $iar.AsyncWaitHandle.WaitOne(800)
        if (-not $connected) {
            return $false
        }
        $client.EndConnect($iar)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Get-PythonLauncher {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        try {
            $null = & python --version
            if ($LASTEXITCODE -eq 0) {
                return @{
                    Executable = "python"
                    Arguments = @()
                }
            }
        }
        catch {}
    }

    if (Get-Command py -ErrorAction SilentlyContinue) {
        try {
            $null = & py -3 --version
            if ($LASTEXITCODE -eq 0) {
                return @{
                    Executable = "py"
                    Arguments = @("-3")
                }
            }
        }
        catch {}
    }

    throw "Python launcher was not found. Install Python or the py launcher first."
}

function Invoke-PythonCheck {
    param(
        [string]$Executable,
        [string[]]$BaseArguments,
        [string]$Code
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $global:ErrorActionPreference = "Continue"
        & $Executable @BaseArguments -c $Code 1>$null 2>$null
        $exitCode = $LASTEXITCODE
        return @{
            Success = ($exitCode -eq 0)
            Output = ""
        }
    }
    finally {
        $global:ErrorActionPreference = $previousErrorActionPreference
    }
}

function Assert-PythonDependencies {
    param(
        [string]$Executable,
        [string[]]$BaseArguments
    )

    $checks = @(
        @{
            Name = "PyMySQL"
            ImportCode = "import pymysql"
            Hint = "Install it with: pip install pymysql"
            UsedBy = "frontend login and database access"
        },
        @{
            Name = "MATLAB Engine for Python"
            ImportCode = "import matlab.engine"
            Hint = "Install the MATLAB Engine API for Python into this Python environment."
            UsedBy = "backend scheduling service"
        }
    )

    $errors = @()
    foreach ($check in $checks) {
        $result = Invoke-PythonCheck -Executable $Executable -BaseArguments $BaseArguments -Code $check.ImportCode
        if (-not $result.Success) {
            $message = "$($check.Name) is missing for $($check.UsedBy). $($check.Hint)"
            $errors += $message
        }
    }

    if ($errors.Count -gt 0) {
        throw ($errors -join [Environment]::NewLine)
    }
}

function Ensure-MySqlReady {
    if (Test-TcpPort) {
        Write-Step "Database port 3306 is ready."
        return
    }

    $serviceCandidates = @(
        "MySQL80",
        "MySQL",
        "mysql",
        "MariaDB",
        "mariadb"
    )

    $service = $null
    foreach ($serviceName in $serviceCandidates) {
        $found = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($found) {
            $service = $found
            break
        }
    }

    if (-not $service) {
        throw "No MySQL/MariaDB Windows service was found. Add the real service name to start_all.ps1."
    }

    if ($service.Status -ne "Running") {
        Write-Step "Starting database service $($service.Name)..."
        Start-Service -Name $service.Name
    }
    else {
        Write-Step "Database service $($service.Name) is already running."
    }

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort) {
            Write-Step "Database startup confirmed."
            return
        }
        Start-Sleep -Milliseconds 500
    }

    throw "Database service was started, but port 3306 is still not ready."
}

function Start-ProjectProcess {
    param(
        [string]$Title,
        [string]$Executable,
        [string[]]$Arguments
    )

    $quotedArgs = ($Arguments | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join " "
    $psCommand = "Set-Location '$projectRoot'; `$Host.UI.RawUI.WindowTitle = '$Title'; & '$Executable' $quotedArgs"
    Start-Process powershell -ArgumentList @(
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command", $psCommand
    ) | Out-Null
}

try {
    Write-Step "Checking database status."
    Ensure-MySqlReady

    $pythonLauncher = Get-PythonLauncher
    $pythonExecutable = $pythonLauncher.Executable
    $pythonArgs = @($pythonLauncher.Arguments)

    Write-Step "Checking Python dependencies."
    Assert-PythonDependencies -Executable $pythonExecutable -BaseArguments $pythonArgs

    Write-Step "Starting backend service."
    Start-ProjectProcess -Title "AGV Backend" -Executable $pythonExecutable -Arguments ($pythonArgs + @(".\start_backend_mes.py"))

    Start-Sleep -Seconds 2

    Write-Step "Starting frontend."
    Start-ProjectProcess -Title "AGV Frontend" -Executable $pythonExecutable -Arguments ($pythonArgs + @(".\main.py"))

    Write-Host ""
    Write-Host "Startup complete: database, backend, and frontend have been launched." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Startup failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
