#
# This script will boot strap your Qube environment and create the
# necessary application packages and upload them to your existing Batch
# account.
#
Param(
    [string]$qubeVersion = "7.0-1",
    [string]$pythonVersion = "2.7.15",
    [string]$qubeSupervisorIp,
    [string]$batchAccountName
)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

$apps = @{
    qubecore='http://repo.pipelinefx.com/downloads/pub/qube/{0}/WIN32-6.3-x64/qube-core-{0}-WIN32-6.3-x64.msi' -f $qubeVersion;
    qubeworker='http://repo.pipelinefx.com/downloads/pub/qube/{0}/WIN32-6.3-x64/qube-worker-{0}-WIN32-6.3-x64.msi' -f $qubeVersion;
    qubeMaya='http://repo.pipelinefx.com/downloads/pub/jobtypes/{0}/maya/qube-mayajt-64-{0}.msi' -f $qubeVersion;
    qube3dsMax='http://repo.pipelinefx.com/downloads/pub/jobtypes/{0}/3dsmax/qube-3dsmaxjt-64-{0}.msi' -f $qubeVersion;
}

$deps = @{
    python='https://www.python.org/ftp/python/{0}/python-{0}.amd64.msi' -f $pythonVersion;
}

$scripts = @{
    installscript='https://raw.githubusercontent.com/Azure/azure-qube/master/Scripts/install-qube-worker.ps1';
    qbconf='https://raw.githubusercontent.com/Azure/azure-qube/master/Scripts/qb.conf';
}

$appPackages = @{
    QubeInstallFiles=$apps;
    QubeDependencies=$deps;
    QubeScripts=$scripts;
}

if ('' -eq $qubeSupervisorIp)
{
    $qubeSupervisorIp = Read-Host "Qube Supervisor IP"
}

$azureRmAvailable = $false
if (Get-Module -ListAvailable -Name AzureRM)
{
    Write-Host "Logging in to Azure..."
    Import-Module AzureRM
    Enable-AzureRmContextAutosave | Out-Null
    Connect-AzureRmAccount
    $azureRmAvailable = $true
} 
else 
{
    Write-Host "The AzureRM powershell module was not found."
}

$tmp = "$env:TEMP\AzureQube"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

$appPackages.Keys | % { 

    $applicationPackageName = $_
    $downloads = $appPackages.Item($_)
    $appPkgDir = "$tmp\$applicationPackageName"

    New-Item -ItemType Directory -Force -Path $appPkgDir | Out-Null

    $downloads.Keys | % { 
        $url = $downloads.Item($_)
        $filename = $url.Split("/")[-1].Split("?")[0]
        $localFile = "$appPkgDir\$filename"

        "Downloading $_ from $url to $localFile"
    
        (New-Object Net.WebClient).DownloadFile($url, "$localFile")
    }

    if ($applicationPackageName -eq 'QubeScripts')
    {
        $qbconf = "$appPkgDir\qb.conf"
        (Get-Content $qbconf) -replace '^qb_supervisor.*',"qb_supervisor = $qubeSupervisorIp" | Set-Content $qbconf
    }

    Compress-Archive -Path $appPkgDir\* -CompressionLevel Fastest -DestinationPath "$tmp\${applicationPackageName}.zip" -Force

    if ($azureRmAvailable)
    {
        if ('' -eq $batchAccountName)
        {
            Get-AzureRmBatchAccount | Select -Property AccountName, ResourceGroupName |Format-Table -AutoSize
            Write-Host "Please select a Batch account from above."
            $batchAccountName = Read-Host "Batch Account Name"
            $batchAccount = Get-AzureRmBatchAccount -AccountName $batchAccountName
        }

        if (!$batchAccount)
        {
            $batchAccount = Get-AzureRmBatchAccount -AccountName $batchAccountName
        }

        Write-Host "Creating Batch Application $applicationPackageName"
        New-AzureRmBatchApplication -AccountName $batchAccount.AccountName `
            -ResourceGroupName $batchAccount.ResourceGroupName `
            -ApplicationId "$applicationPackageName" `
            -AllowUpdates $True `
            -DisplayName "$applicationPackageName"

        Write-Host "Uploading Batch Application Package $tmp\${applicationPackageName}.zip"
        New-AzureRmBatchApplicationPackage -AccountName $batchAccount.AccountName `
            -ResourceGroupName $batchAccount.ResourceGroupName `
            -ApplicationId "$applicationPackageName" `
            -ApplicationVersion "1.0" `
            -FilePath "$tmp\${applicationPackageName}.zip" `
            -Format "zip"
    }
}

if (!$azureRmAvailable)
{
    Write-Host "You'll need to upload the following application package (ZIPs) in the following folder to your Batch account manually."
    Write-Host "Application Package: $tmp"
}
