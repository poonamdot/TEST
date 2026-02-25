# ==========================================================
# COMPLETE DEPLOY + AUTO-SCALE SCRIPT FOR AZURE WINDOWS VM
# ==========================================================

# ---------------- CONFIGURATION ----------------
$ResourceGroup = "poonam"
$PrimaryVM     = "azure"
$Location      = "CentralIndia"
$ImageName     = "myCustomImage"

$AdminUser     = "automation"
$AdminPassword = "Poonam@17123"

$RepoUrl       = "https://github.com/poonamdot/TEST.git"
$RepoPath      = "C:/inetpub/wwwroot"

$CPUThreshold  = 20
# ------------------------------------------------

# ================= STEP 1: PUSH LOCAL CODE TO GIT =================
Write-Host "===================================="
Write-Host "STEP 1 - PUSH LOCAL CODE TO GIT"
Write-Host "===================================="

git config --global user.name "Automation"
git config --global user.email "automation@example.com"

git add .
git commit -m "Auto deployment $(Get-Date)"
git push
Write-Host "Local push completed."


# ================= STEP 2: CHECK / INSTALL GIT ON PRIMARY VM =================
Write-Host "===================================="
Write-Host "STEP 2 - CHECK / INSTALL GIT ON PRIMARY VM"
Write-Host "===================================="

$RemoteScript = @'
Write-Host "Starting Git check/install..."  # Safe first line

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing..."
    $gitInstaller = "C:/git.exe"
    Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe" -OutFile $gitInstaller
    Start-Process $gitInstaller -ArgumentList "/VERYSILENT" -Wait
    Write-Host "Git installed."
} else {
    Write-Host "Git already installed."
}
'@

az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $PrimaryVM `
  --command-id RunPowerShellScript `
  --scripts $RemoteScript


# ================= STEP 3: CLONE OR PULL REPO ON PRIMARY VM =================
Write-Host "===================================="
Write-Host "STEP 3 - CLONE OR PULL REPO ON PRIMARY VM"
Write-Host "===================================="

$RemoteScript = @"
Write-Host 'Starting repo deployment...'  # Safe first line

\$RepoPath = '$RepoPath'
\$RepoUrl  = '$RepoUrl'

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error 'Git is not installed.'
    exit 1
}

if (!(Test-Path (\$RepoPath + '/.git'))) {
    git clone \$RepoUrl \$RepoPath
    Write-Host 'Repository cloned.'
} else {
    Set-Location \$RepoPath
    git reset --hard
    git pull
    Write-Host 'Repository updated.'
}
"@

az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $PrimaryVM `
  --command-id RunPowerShellScript `
  --scripts @($RemoteScript)


# ================= STEP 4: CHECK CPU =================
Write-Host "===================================="
Write-Host "STEP 4 - CHECK CPU"
Write-Host "===================================="

$CPUResult = az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $PrimaryVM `
  --command-id RunPowerShellScript `
  --scripts "Write-Host 'Measuring CPU usage...'; Get-Counter '\Processor(_Total)\% Processor Time' | Select -ExpandProperty CounterSamples | Select -ExpandProperty CookedValue" `
  --query "value[0].message" -o tsv

# Convert to float and round
if ([string]::IsNullOrEmpty($CPUResult)) {
    $CPU = 0
} else {
    $CPUFloat = [float]$CPUResult
    $CPU = [int][math]::Round($CPUFloat)
}

Write-Host "Current CPU Usage: $CPU %"


# ================= STEP 5: AUTO SCALE IF CPU > THRESHOLD =================
Write-Host "===================================="
Write-Host "STEP 5 - AUTO SCALE IF NEEDED"
Write-Host "===================================="

if ($CPU -gt $CPUThreshold) {

    Write-Host "CPU above threshold. Creating new VM..."
    $NewVM = "webvm" + (Get-Random -Minimum 100 -Maximum 999)

    az vm create `
        --resource-group $ResourceGroup `
        --name $NewVM `
        --image $ImageName `
        --admin-username $AdminUser `
        --admin-password $AdminPassword `
        --location $Location `
        --size Standard_DS1_v2

    Write-Host "New VM Created: $NewVM"
    Start-Sleep -Seconds 30

    # Install Git on new VM
    $RemoteScript = @'
Write-Host "Installing Git on new VM..."  # Safe first line

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    $gitInstaller = "C:/git.exe"
    Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe" -OutFile $gitInstaller
    Start-Process $gitInstaller -ArgumentList "/VERYSILENT" -Wait
}
'@

    az vm run-command invoke `
        --resource-group $ResourceGroup `
        --name $NewVM `
        --command-id RunPowerShellScript `
        --scripts $RemoteScript

    # Clone or pull repo on new VM
    $RemoteScript = @"
Write-Host 'Deploying repo on new VM...'  # Safe first line

\$RepoPath = '$RepoPath'
\$RepoUrl  = '$RepoUrl'

if (!(Test-Path (\$RepoPath + '/.git'))) {
    git clone \$RepoUrl \$RepoPath
    Write-Host 'Repository cloned on new VM.'
} else {
    Set-Location \$RepoPath
    git reset --hard
    git pull
    Write-Host 'Repository updated on new VM.'
}
"@

    az vm run-command invoke `
        --resource-group $ResourceGroup `
        --name $NewVM `
        --command-id RunPowerShellScript `
        --scripts @($RemoteScript)

    Write-Host "New VM ready with application."
}
else {
    Write-Host "CPU below threshold. No scaling required."
}

Write-Host "===================================="
Write-Host "DEPLOYMENT COMPLETED"
Write-Host "===================================="