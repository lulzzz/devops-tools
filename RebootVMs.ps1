Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main($mainargs)
{
    if (!$mainargs -or $mainargs.Length -lt 3)
    {
        Write-Host ("Usage: powershell .\RebootVMs.ps1 <subscription> <resourcegroup> <server1> [server2] ...") -f Red
        exit 1
    }

    [string] $subscriptionName = $mainargs[0]
    [string] $resourceGroupName = $mainargs[1]
    [string[]] $servers = @($mainargs | select -Skip 2)

    Write-Host ("Got " + $servers.Length + " servers.")

    Write-Host ("Login...")
    Login-AzureRmAccount | Out-Null

    Write-Host ("Available subscriptions:")
    Get-AzureRmSubscription | % { $_.SubscriptionName } | sort | % { Write-Host ("'" + $_ + "'") }
    Set-AzureRmContext -SubscriptionName $subscriptionName

    $servers | % {
        [string] $server = $_
        Write-Host ("Rebooting " + $server) -f Cyan
        Restart-AzureRmVM -ResourceGroupName $resourceGroupName -Name $server
    }
}

Main $args
