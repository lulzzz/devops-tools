Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main()
{
    if ($env:installazuretools)
    {
        iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex
        powershell "choco install windowsazurepowershell -y"
    }


    [string] $location = "West Europe"

    Log ("Login...")
    Login-AzureRmAccount | Out-Null

    [Diagnostics.Stopwatch] $totalwatch = [Diagnostics.Stopwatch]::StartNew()

    Log ("Retrieving ip addresses...")
    $ips = @(Get-AzureRmSubscription | % {
        [string] $subscriptionName = $_.SubscriptionName
        Set-AzureRmContext -SubscriptionName $subscriptionName | Out-Null
        Get-AzureRmPublicIpAddress | % {
            $IPAddress = $_
            $IPAddress | Add-Member "SubscriptionName" $subscriptionName
            $IPAddress
        }
    }) | sort SubscriptionName,IpAddress

    Log ("Found " + $ips.Count + " ip addresses.")

    $ips = @($ips | ? { $_.IpAddress -ne "Not Assigned" })

    Log ("Found " + $ips.Count + " assigned ip addresses.")

    [string] $filename = "result.txt"
    [string] $text = "Subscription`tIPAddress`tRDP`tSSH`tPing"
    sc $filename $text

    [int] $openrdp = 0
    [int] $openssh = 0

    $ips | % {
        [string] $ipaddress = $_.IpAddress
        Log ("Probing: " + $ipaddress)
        $rdp = Test-NetConnection -ComputerName $ipaddress -CommonTCPPort RDP
        Start-Sleep 5
        $ssh = Test-NetConnection -ComputerName $ipaddress -Port 22
        Start-Sleep 5

        if ($rdp.TcpTestSucceeded -or $rdp.PingSucceeded -or $ssh.TcpTestSucceeded -or $ssh.PingSucceeded)
        {
            [string] $text = $_.SubscriptionName + "`t" + $rdp.RemoteAddress + "`t" + $rdp.TcpTestSucceeded + "`t" + $ssh.TcpTestSucceeded + "`t" + ($rdp.PingSucceeded -or $ssh.PingSucceeded)
            ac $filename $text
        }
        if ($rdp.TcpTestSucceeded -or $rdp.PingSucceeded)
        {
            $openrdp++
        }
        if ($ssh.TcpTestSucceeded -or $ssh.PingSucceeded)
        {
            $openssh++
        }
    }

    Log ("Found " + $openrdp + " open rdp, " + $openssh + " open ssh.")

    $totalwatch.Stop()
    Log ("Done: " + $totalwatch.Elapsed)
}

function Log([string] $message, $color)
{
    [string] $logfile = "C:\ipcheck\ipcheck.log"
    md (Split-Path $logfile) -ErrorAction SilentlyContinue

    [string] $annotatedMessage = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss") + ": " + $message

    if ($color)
    {
        Write-Host $annotatedMessage -f $color
    }
    else
    {
        Write-Host $annotatedMessage -f Green
    }

    $annotatedMessage | ac $logfile
}

Main
