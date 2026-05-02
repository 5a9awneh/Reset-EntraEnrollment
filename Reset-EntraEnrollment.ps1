# Reset-EntraEnrollment.ps1
# Called by RUN.bat with admin rights

# Verify admin (fail-safe)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Must be run as administrator. Use the .bat file." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Confirmation prompt — must explicitly type YES before any changes are made
Write-Host ""
Write-Host "WARNING: This script will:" -ForegroundColor Red
Write-Host "  - Run 'dsregcmd /leave' to leave Entra ID / Azure AD" -ForegroundColor Red
Write-Host "  - Remove enrollment registry keys under HKLM:\SOFTWARE\Microsoft\Enrollments" -ForegroundColor Red
Write-Host "  - Remove EnterpriseResourceManager registry entries" -ForegroundColor Red
Write-Host "  - Delete EnterpriseMgmt scheduled tasks" -ForegroundColor Red
Write-Host ""
Write-Host "These changes cannot be undone without re-enrolling the device." -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "Type YES to continue or press Enter to abort"
if ($confirm -ne 'YES') {
    Write-Host "Aborted. No changes were made." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 0
}

# Function to prompt with timeout
function Get-UserInput {
    param (
        [string]$Prompt,
        [string]$DefaultAnswer,
        [int]$Timeout
    )
    
    Write-Host "$Prompt (default: $DefaultAnswer) " -ForegroundColor Yellow -NoNewline
    $answer = $DefaultAnswer
    $startTime = Get-Date
    
    while ((Get-Date) -lt $startTime.AddSeconds($Timeout)) {
        $countdown = [math]::Round($Timeout - (Get-Date).Subtract($startTime).TotalSeconds)
        Write-Host "`rRespond in $countdown seconds... [y/n]: " -ForegroundColor Yellow -NoNewline
        
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'y' -or $key.KeyChar -eq 'n') {
                $answer = $key.KeyChar
                break
            }
            else {
                Write-Host "`nInvalid response. Please enter 'y' or 'n'. " -NoNewline
            }
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    Write-Host "`n"
    return $answer
}

# Start transcript for remote troubleshooting
Start-Transcript -Path "$PSScriptRoot\EntraCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-Host "=== Entra ID Enrollment Cleanup ===" -ForegroundColor Cyan
Write-Host "Running with administrator privileges..." -ForegroundColor Green
Write-Host ""

# Step 1: Check current state
Write-Host "[1/5] Checking current enrollment state..." -ForegroundColor Cyan
dsregcmd /status
Write-Host "Current state logged." -ForegroundColor Gray

# Step 2: Leave Azure AD
Write-Host "[2/5] Leaving Azure AD/Entra ID..." -ForegroundColor Cyan
try {
    dsregcmd /leave
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Successfully left." -ForegroundColor Green
    }
    else {
        Write-Host "  Already left or not joined (OK to continue)." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 3: Clean Enrollments registry
Write-Host "[3/5] Cleaning Enrollments registry..." -ForegroundColor Cyan
$enrollPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
$excludeKeys = @("Context", "Ownership", "Status", "ValidNodePaths")
$removed = 0

if (Test-Path $enrollPath) {
    Get-ChildItem -Path $enrollPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -notin $excludeKeys } | ForEach-Object {
        try {
            Write-Host "  Removing: $($_.PSChildName)" -ForegroundColor Yellow
            Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction Stop
            $removed++
        }
        catch {
            Write-Host "  Failed to remove $($_.PSChildName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "  Removed $removed enrollment(s)." -ForegroundColor Green
}
else {
    Write-Host "  Path not found (already clean)." -ForegroundColor Gray
}

# Step 4: Clean EnterpriseResourceManager
Write-Host "[4/5] Cleaning EnterpriseResourceManager..." -ForegroundColor Cyan
$ermPath = "HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked"
$ermRemoved = 0

if (Test-Path $ermPath) {
    Get-ChildItem -Path $ermPath -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Write-Host "  Removing: $($_.PSChildName)" -ForegroundColor Yellow
            Remove-Item -Path $_.PSPath -Recurse -Force -ErrorAction Stop
            $ermRemoved++
        }
        catch {
            Write-Host "  Failed to remove: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host "  Removed $ermRemoved item(s)." -ForegroundColor Green
}
else {
    Write-Host "  Path not found (already clean)." -ForegroundColor Gray
}

# Step 5: Remove scheduled tasks
Write-Host "[5/5] Removing EnterpriseMgmt scheduled tasks..." -ForegroundColor Cyan
$taskRemoved = 0

try {
    $tasks = Get-ScheduledTask -TaskPath "*EnterpriseMgmt*" -ErrorAction SilentlyContinue
    if ($tasks) {
        $tasks | ForEach-Object {
            try {
                Write-Host "  Removing: $($_.TaskPath)$($_.TaskName)" -ForegroundColor Yellow
                $_ | Unregister-ScheduledTask -Confirm:$false -ErrorAction Stop
                $taskRemoved++
            }
            catch {
                Write-Host "  Failed to remove task: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Host "  Removed $taskRemoved task(s)." -ForegroundColor Green
    }
    else {
        Write-Host "  No tasks found (already clean)." -ForegroundColor Gray
    }
}
catch {
    Write-Host "  Warning: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "=== CLEANUP COMPLETE ===" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "After restart, go to Settings > Accounts > Access work or school" -ForegroundColor White
Write-Host "Click 'Connect' and sign in with your work email address" -ForegroundColor White
Write-Host ""

# Prompt for restart with timeout
$restart = Get-UserInput -Prompt "Restart now?" -DefaultAnswer "n" -Timeout 5

Stop-Transcript

if ($restart -eq 'y') {
    Write-Host "Restarting computer..." -ForegroundColor Green
    try {
        Restart-Computer -Force
    }
    catch {
        Write-Host "Error restarting computer: $($Error[0].Exception.Message)" -ForegroundColor Red
        Write-Host "Please restart manually." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
}
else {
    Write-Host "Restart cancelled. Please restart manually when ready." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Log file saved to script folder (EntraCleanup_*.log)" -ForegroundColor Gray
    Start-Sleep -Seconds 2
}
