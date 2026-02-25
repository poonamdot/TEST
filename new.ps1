# ==========================================================
# COMPLETE DEPLOY + AUTO SCALE SCRIPT (NO WINRM)
# ==========================================================
# C:\Program Files\Git\cmd\git.exe -->git path on vm 
# ---------------- CONFIGURATION ----------------
$ResourceGroup = "poonam"
$PrimaryVM     = "azure"
$Location      = "eastus"
$ImageName     = "myCustomImage"

$AdminUser     = "automation"
$AdminPassword = "Poonam@17123"

$RepoUrl       = "https://github.com/poonamdot/TEST.git"
$RepoPath      = "C:\inetpub\wwwroot"

$CPUThreshold  = 20
# ------------------------------------------------

Write-Host "===================================="
Write-Host "STEP 1 - PUSH LOCAL CODE TO GIT"
Write-Host "===================================="

git add .
git commit -m "Auto deployment $(Get-Date)"
git push
Write-Host "Local push completed."


Write-Host "===================================="
Write-Host "STEP 2 - CHECK / INSTALL GIT ON VM"
Write-Host "===================================="

$RemoteScript = @'
# Force TLS 1.2 for Git download
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Check if Git exists
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing..."
    $gitInstaller = "C:\git.exe"
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

Write-Host "===================================="
Write-Host "STEP 3 - CLONE OR PULL REPO ON VM"
Write-Host "===================================="

$RemoteScript = @"
$RepoPath = 'C:\inetpub\wwwroot'
$RepoUrl  = '$RepoUrl'

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error 'Git is not installed on this VM.'
    exit 1
}

if (!(Test-Path "$RepoPath\.git")) {
    git clone $RepoUrl $RepoPath
    Write-Host 'Repository cloned.'
} else {
    Set-Location $RepoPath
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

Write-Host "===================================="
Write-Host "STEP 4 - CHECK CPU"
Write-Host "===================================="

$CPUResult = az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $PrimaryVM `
  --command-id RunPowerShellScript `
  --scripts "Get-Counter '\Processor(_Total)\% Processor Time' | Select -ExpandProperty CounterSamples | Select -ExpandProperty CookedValue" `
  --query "value[0].message" -o tsv

$CPU = [int][math]::Round($CPUResult)
Write-Host "Current CPU Usage: $CPU %"


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

    Write-Host "Installing Git on new VM if required..."

    az vm run-command invoke `
      --resource-group $ResourceGroup `
      --name $NewVM `
      --command-id RunPowerShellScript `
      --scripts @"
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
Invoke-WebRequest -Uri https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe -OutFile C:\git.exe
Start-Process C:\git.exe -ArgumentList '/VERYSILENT' -Wait
}
"@

    Write-Host "Deploying application to new VM..."

    az vm run-command invoke `
      --resource-group $ResourceGroup `
      --name $NewVM `
      --command-id RunPowerShellScript `
      --scripts @"
if (!(Test-Path '$RepoPath')) {
    git clone $RepoUrl $RepoPath
} else {
    cd $RepoPath
    git pull
}
"@

    Write-Host "New VM ready."
}
else {
    Write-Host "CPU below threshold. No scaling required."
}

Write-Host "===================================="
Write-Host "DEPLOYMENT COMPLETED"
Write-Host "===================================="