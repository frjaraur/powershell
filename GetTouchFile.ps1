﻿function Install-TouchFile {
    $ModulePaths = @($env:PSModulePath -split ';')
    # $TouchFileDestinationModulePath is mostly needed for testing purposes,
    if ((Test-Path -Path Variable:TouchFileDestinationModulePath) -and $TouchFileDestinationModulePath) {
        $Destination = $TouchFileDestinationModulePath
        if ($ModulePaths -notcontains $Destination) {
            Write-Warning 'TouchFile install destination is not included in the PSModulePath environment variable'
        }
    }
    else {
        $ExpectedUserModulePath = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath WindowsPowerShell\Modules
        $Destination = $ModulePaths | Where-Object { $_ -eq $ExpectedUserModulePath }
        if (-not $Destination) {
            $Destination = $ModulePaths | Select-Object -Index 0
        }
    }
    New-Item -Path ($Destination + "\TouchFile\") -ItemType Directory -Force | Out-Null
    Write-Host 'Downloading TouchFile from https://raw.githubusercontent.com/agileramblings/powershell/master/TouchFile.psm1'
    $client = (New-Object Net.WebClient)
    $client.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $client.DownloadFile("https://raw.githubusercontent.com/agileramblings/powershell/master/TouchFile.psm1", $Destination + "\TouchFile\TouchFile.psm1")

    $executionPolicy = (Get-ExecutionPolicy)
    $executionRestricted = ($executionPolicy -eq "Restricted")
    if ($executionRestricted) {
        Write-Warning @"
Your execution policy is $executionPolicy, this means you will not be able import or use any scripts including modules.
To fix this change your execution policy to something like RemoteSigned.

        PS> Set-ExecutionPolicy RemoteSigned

For more information execute:

        PS> Get-Help about_execution_policies

"@
    }

    if (!$executionRestricted) {
        # ensure PsGet is imported from the location it was just installed to
        Import-Module -Name $Destination\TouchFile -Verbose
    }
    Write-Host "TouchFile is installed and ready to use" -Foreground Green
}

Install-TouchFile -Verbose
