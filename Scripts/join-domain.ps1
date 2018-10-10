Param(
    [string]$domainName,
    [string]$domainOuPath,
    [string]$tenantId,
    [string]$applicationId,
    [string]$keyVaultCertificateThumbprint,
    [string]$keyVaultName,
    [string]$keyVaultUsernameSecretName = "DomainJoinUserName",
    [string]$keyVaultPasswordSecretName = "DomainJoinUserPassword"
)

# This is a hack to ensure the NuGet provider is added
Get-PackageProvider -Name NuGet -Force
Install-Module PowerShellGet -Force

if (Get-Module -ListAvailable -Name AzureRm) {
    Write-Host "AzureRm is already installed"
} else {
    Write-Host "Installing AzureRm"
    Install-Module -Name AzureRm -Repository PSGallery -Force
}

# Import the Azure Resource Manager module so we can access Key Vault
Import-Module AzureRm

# Login
Login-AzureRmAccount -ServicePrincipal -TenantId $tenantId -CertificateThumbprint $keyVaultCertificateThumbprint -ApplicationId $applicationId

# Grab the current secrets
$secrets = Get-AzureKeyVaultSecret -VaultName "$keyVaultName"
$secrets | % { Write-Host "Found secret " $_.Name }

if ('' -eq $domainName)
{
    Write-Host "No domain name specified."
    exit 1
}

if (-Not (Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain)
{
    # Make sure we have the user and password in key vault
    if (-Not ($secrets | Where-Object {$_.Name -eq "DomainJoinUserName"}) -or
        -Not ($secrets | Where-Object {$_.Name -eq "DomainJoinUserPassword"}))
    {
        Write-Host "The specific Key Vault doesn't contain a secret for the domain username ($keyVaultUsernameSecretName) or domain password ($keyVaultPasswordSecretName)"
        exit 1
    }

    $domainUser = (Get-AzureKeyVaultSecret -VaultName "$keyVaultName" -Name 'DomainJoinUserName').SecretValueText
    $domainPasswordSecret = Get-AzureKeyVaultSecret -VaultName "$keyVaultName" -Name 'DomainJoinUserPassword'

    Write-Host "Joining domain $domainName with user $domainUser"

    $domainCred = New-Object System.Management.Automation.PSCredential($domainUser, $domainPasswordSecret.SecretValue)

    if ('' -ne $domainOuPath)
    {
        Add-Computer -DomainName "$domainName" -OUPath "$domainOuPath" -Credential $domainCred -Restart -Force
    }
    else
    {
        Add-Computer -DomainName "$domainName" -Credential $domainCred -Restart -Force
    }

    # Pause while we wait for the restart to ensure tasks don't run
    Start-Sleep -Seconds 120

    exit 0
}
else
{
    Write-Host "Compute node is already domain joined, skipping."
}
