Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main([string[]] $mainargs)
{
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools

    Log ("Installing Chocolatey.")
    iwr "https://chocolatey.org/install.ps1" -UseBasicParsing | iex

    Log ("Installing tools.")
    choco install notepadplusplus procexp procmon "7zip" cpu-z -y
    choco install googlechrome -y -ignorechecksum

    Setup-Grafana

    #Setup-IIS
}

function Setup-Grafana()
{
    [string] $sourceurl = "https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-4.2.0.windows-x64.zip"
    [string] $zipfile = "grafana.zip"
    [string] $hash = "A5D829AB0B912C7F90E43556D47CA96F"

    Download-MyFile $sourceurl $zipfile $hash

    [string] $nssmUrl = "https://raw.githubusercontent.com/collector-bank/savings-template/master/eventstore/nssm.7z"
    [string] $nssmZipfile = "nssm.7z"
    [string] $nssmHash = "C63DC77118418B32367BE50825918466"

    Download-MyFile $nssmUrl $nssmZipfile $nssmHash


    [string] $grafanaFolder = "C:\grafana"
    [string] $servicename = "grafana"


    if (Get-Service | ? { $_.Name -eq $servicename })
    {
        Log ("Stopping service: '" + $servicename + "'")
        Stop-Service $servicename

        Start-Sleep 5

        Log ("Deleting service: '" + $servicename + "'")
        sc.exe delete $servicename
    }


    if (Test-path $grafanaFolder)
    {
        Log ("Deleting folder: '" + $grafanaFolder + "'")
        rd -Recurse -Force $grafanaFolder
    }


    Set-Alias zip (Join-Path $env:ProgramFiles "7-Zip\7z.exe")

    Log ("Extracting: '" + $zipfile + "' -> '" + $grafanaFolder + "'")
    zip x ("-o" + $grafanaFolder) $zipfile

    $subentries = @(dir (Join-Path $grafanaFolder "*\*"))
    Log ("Moving " + $subentries.Length + " subentries closer to root.")
    $subentries | % {
        [string] $source = $_
        Log ("Moving: '" + $source + "' -> '" + $grafanaFolder + "'")
        move $_.FullName $grafanaFolder
    }

    [string] $binFolder = Join-Path $grafanaFolder "bin"

    Log ("Extracting: '" + $nssmZipfile + "' -> '" + $binFolder + "'")
    zip e ("-o" + $binFolder) $nssmZipfile "nssm.exe"


    [string] $grafanaExe = Join-Path $binFolder "grafana-server.exe"

    cd $binFolder
    Log ("Installing service: '" + $servicename + "' '" + $grafanaExe + "'")
    .\nssm.exe "install" $servicename $grafanaExe


    [string] $firewallrule = "Grafana"

    Log ("Deleting firewall rules: '" + $firewallrule + "'")
    netsh advfirewall firewall delete rule ("name=" + $firewallrule)

    Log ("Adding firewall rule: '" + $firewallrule + "'")
    netsh advfirewall firewall add rule ("name=" + $firewallrule) dir=in action=allow protocol=TCP localport=3000
}

function Download-MyFile([string] $sourceurl, [string] $localfile, [string] $hash)
{
    if ((Test-Path $localfile) -and ((Get-FileHash $localfile -Algorithm MD5).Hash -eq $hash))
    {
        Log ("File already downloaded: '" + $localfile + "'")
    }
    else
    {
        if (Test-Path $localfile)
        {
            Log ("Deleting corrupt file: '" + $localfile + "'")
            del $localfile
        }

        Log ("Downloading: '" + $sourceurl + "' -> '" + $localfile + "'")
        Invoke-WebRequest -UseBasicParsing $sourceurl -OutFile $localfile

        if (!(Test-Path $localfile) -or ((Get-FileHash $localfile -Algorithm MD5).Hash -ne $hash))
        {
            Log ("Couldn't download: '" + $sourceurl + "' -> '" + $localfile + "'")
            exit 1
        }
    }

    if (!(Test-Path $localfile))
    {
        Log ("Couldn't download: '" + $sourceurl + "' -> '" + $localfile + "'")
        exit 1
    }
}

function Setup-IIS()
{
    [string] $sourceurl = "https://github.com/Lone-Coder/letsencrypt-win-simple/releases/download/v1.9.3/letsencrypt-win-simple.V1.9.3.zip"
    [string] $zipfile = "letsencrypt.zip"
    [string] $hash = "E40634E5CECD4A24AB3F18EC63C54710"

    Download-MyFile $sourceurl $zipfile $hash

}

function Log([string] $message, $color)
{
    [string] $annotatedMessage = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss") + ": " + $message

    md "C:\installlogs" -ErrorAction SilentlyContinue | Out-Null
    $annotatedMessage | ac "C:\installlogs\Grafana.log"

    if ($color)
    {
        Write-Host ($message) -f $color
    }
    else
    {
        Write-Host ($message) -f Green
    }
}

Main $args
