Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main()
{
  [string] $location = "West Europe"

  Login-AzureRmAccount | Out-Null

  $limits = Get-AzureRmSubscription | % { Set-AzureRmContext -SubscriptionName $_.SubscriptionName | Out-Null; $o = Get-AzureRmVMUsage -Location $location; $o | Add-Member NoteProperty "SubscriptionName" $_.SubscriptionName; $o }

  $limits | group { $_.Name.Value } | % { $o=New-Object PSObject; $o | Add-Member NoteProperty "Name" $_.Name; [int] $i=0; $_.Group | sort SubscriptionName| % { $o | Add-Member NoteProperty $_.SubscriptionName ("" + $_.CurrentValue + "/" + $_.Limit) }; $o } | sort Name | ogv
  Read-Host
}

Main
