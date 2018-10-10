#
# Install and setup script for Qube workers.  The script performs the following:
# 1. Sets the application license token system wide, if present.
# 2. Installs Python 2.7.x
# 3. Installs qube-core-*
# 4. Installs qube-worker-*
# 5. Installs any Qube job types
#
# This script expects all MSIs to be in the current directory.  If the MSIs 
# are deployed with application packages, your start task script will need to
# copy or move the content to the local working directory.
#
# Example Batch start task script asumming the bootstrap script was used.
# cmd.exe /c copy %AZ_BATCH_APP_PACKAGE_QubeInstallFiles% . & copy %AZ_BATCH_APP_PACKAGE_QubeDependencies% . & copy %AZ_BATCH_APP_PACKAGE_QubeScripts% . & powershell -exec bypass .\install-qube-worker.ps1
#
Param(
    [string]$qubeSupervisorIp,
    [string]$domainName,
    [string]$domainOuPath,
    [string]$tenantId,
    [string]$applicationId,
    [string]$keyVaultCertificateThumbprint,
    [string]$keyVaultName
)

# Set any app licenses system wide.
if ($env:AZ_BATCH_SOFTWARE_ENTITLEMENT_TOKEN)
{
    [Environment]::SetEnvironmentVariable("AZ_BATCH_ACCOUNT_URL", "$env:AZ_BATCH_ACCOUNT_URL","Machine")
    [Environment]::SetEnvironmentVariable("AZ_BATCH_SOFTWARE_ENTITLEMENT_TOKEN", "$env:AZ_BATCH_SOFTWARE_ENTITLEMENT_TOKEN","Machine")
}

# Increase the FLEXLM timeout for lower latency VNet links
[Environment]::SetEnvironmentVariable("FLEXLM_TIMEOUT", "10000000", "Machine")
$env:FLEXLM_TIMEOUT = "10000000"

if ('' -eq $domainName)
{
    .\join-domain.ps1 -domainName $domainName -domainOuPath $domainOuPath -tenantId $tenantId -applicationId $applicationId -keyVaultCertificateThumbprint $keyVaultCertificateThumbprint -keyVaultName $keyVaultName
}

$python = Get-ChildItem . | where {$_.Name -like "python-2.7.*.amd64.msi"}

if (!$python)
{
    Write-Host "Could not find a Python 2.7.x installer MSI."
    exit 1
}

# Install Python
Write-Host "Installing " $python.FullName
Start-Process msiexec.exe -ArgumentList "/passive /i $($python.FullName)" -Wait

# Make sure Python is in the path
$paths = ${env:PATH}.ToLower().Split(";")
if (!$paths.Contains('C:\python27'))
{
    Write-Host "Adding Python to the path."
    [Environment]::SetEnvironmentVariable("PATH", "C:\Python27;${env:PATH}", "Machine")
}

New-Item -ItemType Directory -Force -Path 'C:\ProgramData\Pfx\Qube' | Out-Null

# Update the Supervisor IP in qb.conf if specified.
if ('' -ne $qubeSupervisorIp)
{
    (Get-Content qb.conf) -replace '^qb_supervisor.*',"qb_supervisor = $qubeSupervisorIp" | Set-Content qb.conf
}
copy qb.conf 'C:\ProgramData\Pfx\Qube'

# Install Qube Core
$qubecore = Get-ChildItem . | where {$_.Name -like "qube-core-*.msi"}

if (!$qubecore)
{
    Write-Host "Could not find a Qube Core installer MSI."
    exit 1
}

Write-Host "Installing " $qubecore.FullName
Start-Process msiexec.exe -ArgumentList "/passive /i $($qubecore.FullName)" -Wait

# Install Qube Worker
$qubeworker = Get-ChildItem . | where {$_.Name -like "qube-worker-*.msi"}

if (!$qubeworker)
{
    Write-Host "Could not find a Qube Worker installer MSI."
    exit 1
}

Write-Host "Installing " $qubeworker.FullName
Start-Process msiexec.exe -ArgumentList "/passive /i $($qubeworker.FullName)" -Wait

# Install Qube Job Type Extras
Get-ChildItem . | where { $_.Name -like "qube-*.msi" } | where {$_.Name -notlike "qube-core-*.msi" -and $_.Name -notlike "qube-worker-*.msi"} | % {
    Write-Host "Installing " $_.FullName
    Start-Process msiexec.exe -ArgumentList "/passive /i $($_.FullName)" -Wait
}

Start-Service -Name "qubeworker"
