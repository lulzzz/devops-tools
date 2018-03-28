# edit with: powershell_ise.exe

Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main()
{
    Login-AzureRmAccount | Out-Null
    $addresses = @(Get-AzureRmSubscription | % {
        Write-Host ("Gathering ip addresses from: '" + $_.Name + "'")
        Set-AzureRmContext -SubscriptionName $_.Name | Out-Null
        Get-AzureRmPublicIpAddress
    })

    Write-Host ("Found " + $addresses.Count + " ip addresses.")

    $addresses | select id,ipaddress | ogv

    Write-Host ("Press...")
    Read-Host
}

Main
