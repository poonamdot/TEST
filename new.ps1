# ==========================================================
# COMPLETE DEPLOY + AUTO-SCALE SCRIPT (FIXED VERSION)
# ==========================================================

# ---------------- CONFIGURATION ----------------
$ResourceGroup = "poonam"
$PrimaryVM     = "azure"
$Location      = "CentralIndia"

$AdminUser     = "automation"
$AdminPassword = "Poonam@17123"

$RepoUrl       = "https://github.com/poonamdot/TEST.git"
$RepoPath      = "C:\inetpub\wwwroot"

$GitExe        = "C:\Program Files\Git\cmd\git.exe"

$CPUThreshold  = 20
# ------------------------------------------------


# ================= STEP 1: PUSH LOCAL CODE TO GIT =================
Write-Host "STEP 1 - PUSH LOCAL CODE TO GIT"

git add .
git commit -m "Auto deployment $(Get-Date)"
git push

Write-Host "Local push completed."


# ================= STEP 2: VERIFY GIT ON PRIMARY VM =================
Write-Host "STEP 2 - VERIFY GIT ON PRIMARY VM"

$RemoteScript = @"
`$GitPath = '$GitExe'

if (Test-Path `$GitPath) {
    Write-Host "Git exists."
}
else {
    Write-Host "Git not found. Installing..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    `$Installer = 'C:\git_installer.exe'
    Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe' -OutFile `$Installer
    Start-Process `$Installer -ArgumentList '/VERYSILENT' -Wait
}
"@

az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $PrimaryVM `
  --command-id RunPowerShellScript `
  --scripts $RemoteScript


# ================= STEP 3: CLONE OR PULL REPO =================
Write-Host "STEP 3 - DEPLOY CODE ON PRIMARY VM"

$RemoteScript = @"
`$RepoPath = '$RepoPath'
`$RepoUrl  = '$RepoUrl'
`$GitPath  = '$GitExe'

if (!(Test-Path `$RepoPath)) {
    New-Item -ItemType Directory -Path `$RepoPath -Force | Out-Null
}

if (!(Test-Path (Join-Path `$RepoPath '.git'))) {
    & `$GitPath clone `$RepoUrl `$RepoPath
}
else {
    Set-Location `$RepoPath
    & `$GitPath reset --hard
    & `$GitPath pull
}
"@

az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $PrimaryVM `
  --command-id RunPowerShellScript `
  --scripts $RemoteScript


# ================= STEP 4: CHECK CPU =================
Write-Host "STEP 4 - CHECK CPU USAGE"

$CPUResult = az vm run-command invoke `
  --resource-group $ResourceGroup `
  --name $PrimaryVM `
  --command-id RunPowerShellScript `
  --scripts "((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue)" `
  --query "value[0].message" -o tsv

$CPUValue = ($CPUResult -split "`n" | Where-Object { $_ -match '\d' })[0]

if ([string]::IsNullOrWhiteSpace($CPUValue)) {
    $CPU = 0
}
else {
    $CPU = [int][math]::Round([double]$CPUValue)
}

Write-Host "Current CPU Usage: $CPU %"


# ================= STEP 5: AUTO SCALE =================
Write-Host "STEP 5 - AUTO SCALE CHECK"

if ($CPU -gt $CPUThreshold) {

    Write-Host "CPU above threshold. Creating new VM..."

    $NewVM = "webvm" + (Get-Random -Minimum 100 -Maximum 999)

    # CREATE VM USING VALID IMAGE
    $CreateResult = az vm create `
        --resource-group $ResourceGroup `
        --name $NewVM `
        --image Win2022Datacenter `
        --admin-username $AdminUser `
        --admin-password $AdminPassword `
        --location $Location `
        --size Standard_DS1_v2 `
        --output json | ConvertFrom-Json

    if (!$CreateResult.name) {
        Write-Host "VM creation failed. Stopping process."
        return
    }

    Write-Host "VM Created Successfully: $NewVM"

    # Wait for VM provisioning
    Start-Sleep -Seconds 60

    # Install Git + Deploy Repo on New VM
    $RemoteScript = @"
`$RepoPath = '$RepoPath'
`$RepoUrl  = '$RepoUrl'
`$GitPath  = '$GitExe'

if (!(Test-Path `$GitPath)) {
    Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe' -OutFile 'C:\git.exe'
    Start-Process 'C:\git.exe' -ArgumentList '/VERYSILENT' -Wait
}

if (!(Test-Path `$RepoPath)) {
    New-Item -ItemType Directory -Path `$RepoPath -Force | Out-Null
}

if (!(Test-Path (Join-Path `$RepoPath '.git'))) {
    & `$GitPath clone `$RepoUrl `$RepoPath
}
else {
    Set-Location `$RepoPath
    & `$GitPath pull
}
"@

    az vm run-command invoke `
        --resource-group $ResourceGroup `
        --name $NewVM `
        --command-id RunPowerShellScript `
        --scripts $RemoteScript

    Write-Host "New VM deployment completed successfully."
}
else {
    Write-Host "CPU below threshold. No scaling required."
}

Write-Host "DEPLOYMENT COMPLETED"