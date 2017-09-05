Set-StrictMode -v latest
$ErrorActionPreference = "Stop"

function Main($mainargs)
{
    if (!$mainargs -or (($mainargs.Length -ne 4) -and ($mainargs.Length -ne 5)))
    {
        Log ("Script for creating infrastructure from arm template.")
        Log ("Usage: powershell .\CreateInfrastructure.ps1 <subscription> <name> <username> <password> [resourcegroup]")
        exit 1
    }

    [string] $subscriptionName = $mainargs[0]
    [string] $name = $mainargs[1]
    [string] $username = $mainargs[2]
    [string] $password = $mainargs[3]
    [string] $resourceGroupName = $null
    if ($mainargs.Count -eq 5)
    {
        [string] $resourceGroupName = $mainargs[4]
    }
    else
    {
        [string] $resourceGroupName = "Group-" + $name
    }
    [string] $location = "West Europe"
    [string] $templateFolder = "armwindows"
    [string] $templateFile = Join-Path $name "template.json"
    [string] $parametersFile = Join-Path $name "parameters.json"


    Create-Files $templateFolder $name $username $password


    if (!(Test-Path $templateFile))
    {
        Log ("Couldn't find template file: '" + $templateFile + "'")
        exit 1
    }
    if (!(Test-Path $parametersFile))
    {
        Log ("Couldn't find parameters file: '" + $parametersFile + "'")
        exit 1
    }

    Log ("Logging in...")
    Login-AzureRmAccount | Out-Null

    Log ("Available subscriptions:")
    Get-AzureRmSubscription | % { $_.SubscriptionName } | sort | % { Log ("'" + $_ + "'") }
    Set-AzureRmContext -SubscriptionName $subscriptionName

    if ($mainargs.Count -eq 4)
    {
        Log ("Creating resource group '" + $resourceGroupName + "' in '" + $location + "'")
        New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
    }
    else
    {
        Log ("Using existing resource group '" + $resourceGroupName + "'")
    }

    Log ("Deploying: '" + $resourceGroupName + "' '" + $templateFile + "' '" + $parametersFile + "'")
    New-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile $templateFile -TemplateParameterFile $parametersFile
}

function Create-Files([string] $folder, [string] $newname, [string] $username, [string] $password)
{
    if (Test-Path $newname)
    {
        Log ("Deleting folder: '" + $newname + "'")
        rd -Recurse -Force $newname
    }

    Load-Dependencies

    Log ("Copying '" + $folder + "' -> '" + $newname + "'")
    md $name | Out-Null

    $jsonfiles = @(dir $folder -r -i *.json)
    Log ("Found " + $jsonfiles.Count + " json files.")

    $jsonfiles | % {
        [string] $oldfile = $_.FullName
        [string] $newfile = Join-Path $newname $_.Name

        Update-JsonFile $_.FullName $newfile $newname
    }


    [string] $filename = Join-Path $newname "parameters.json"

    Update-CredentialsInParametersFile $filename $username $password
    Update-IpAddressInParametersFile $filename
}

function Update-JsonFile([string] $infile, [string] $outfile, [string] $newname)
{
    [string] $oldname = "REPLACE_NAME"

    Log ("Reading: '" + $infile + "'") Magenta
    [string] $content = [IO.File]::ReadAllText($infile)

    [string] $content = $content.Replace($oldname, $newname)

    Log ("Prettifying: '" + $infile + "' -> '" + $outfile + "'") Magenta
    [string] $pretty = [Newtonsoft.Json.Linq.JToken]::Parse($content).ToString([Newtonsoft.Json.Formatting]::Indented)

    Log ("Saving: '" + $outfile + "'")
    [IO.File]::WriteAllText($outfile, $pretty)
}

function Update-CredentialsInParametersFile([string] $filename, [string] $username, [string] $password)
{
    Log ("Reading: '" + $filename + "'")
    [string] $content = [IO.File]::ReadAllText($filename)

    $json = [Newtonsoft.Json.Linq.JToken]::Parse($content)
    
    $elements = $json.parameters.Children() | ? { $_.Name.EndsWith("Username") -or $_.Name.EndsWith("username") }

    if ($elements)
    {
        $elements | % {
            $_.value.value = $username
        }

        Log ("Saving: '" + $filename + "'")
        [string] $content = $json.ToString([Newtonsoft.Json.Formatting]::Indented)
        [IO.File]::WriteAllText($filename, $content)
    }

    $elements = $json.parameters.Children() | ? { $_.Name.EndsWith("Password") -or $_.Name.EndsWith("password") }

    if ($elements)
    {
        $elements | % {
            $_.value.value = $password
        }

        Log ("Saving: '" + $filename + "'")
        [string] $content = $json.ToString([Newtonsoft.Json.Formatting]::Indented)
        [IO.File]::WriteAllText($filename, $content)
    }
}

function Update-IpAddressInParametersFile([string] $filename)
{
    Log ("Reading: '" + $filename + "'")
    [string] $content = [IO.File]::ReadAllText($filename)

    $json = [Newtonsoft.Json.Linq.JToken]::Parse($content)

    $elements = $json.parameters.Children() | ? { $_.Name.EndsWith("IpAddress") -or $_.Name.EndsWith("ipaddress") }

    if ($elements)
    {
        Log ("Retrieving public ip address.")
        $ip = Invoke-RestMethod -Uri "https://api.ipify.org?format=json"

        Log ("Got public ip address: " + $ip.ip)

        $elements | % {
            $_.value.value = $ip.ip
        }

        Log ("Saving: '" + $filename + "'")
        [string] $content = $json.ToString([Newtonsoft.Json.Formatting]::Indented)
        [IO.File]::WriteAllText($filename, $content)
    }
}

function Load-Dependencies()
{
    if ([Environment]::Version.Major -lt 4)
    {
        Log ("Newtonsoft.Json 10.0.2 requires .net 4 (Powershell 3.0), you have: " + [Environment]::Version) Red
        exit 1
    }

    [string] $nugetpkg = "https://www.nuget.org/api/v2/package/Newtonsoft.Json/10.0.2"
    [string] $zipfile = Join-Path $env:temp "json.zip"
    [string] $dllfile = "Newtonsoft.Json.dll"
    [string] $zipfilepath = Join-Path (Join-Path $zipfile "lib\net45") $dllfile
    [string] $dllfilepath = Join-Path $env:temp $dllfile
    
    [string] $hash = "A6BE9EFDAA744E9947F4EE18DE5423BD"
    if ((Test-Path $dllfilepath) -and (Get-FileHash -Algorithm MD5 $dllfilepath).Hash -eq $hash)
    {
        Log ("File already downloaded: '" + $dllfilepath + "'")
    }
    else
    {
        Log ("Downloading: '" + $nugetpkg + "' -> '" + $zipfile + "'")
        if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)
        {
            Invoke-WebRequest -UseBasicParsing $nugetpkg -OutFile $zipfile
        }
        else
        {
            curl.exe -L $nugetpkg -o $zipfile
        }
        if (!(Test-Path $zipfile))
        {
            Log ("Couldn't download: '" + $zipfile + "'") Red
            exit 1
        }

        Log ("Extracting: '" + $zipfilepath + "' -> '" + $env:temp + "'")
        $shell = New-Object -com Shell.Application
        $shell.Namespace($env:temp).CopyHere($zipfilepath, 20)

        if (!(Test-Path $dllfilepath))
        {
            Log ("Couldn't extract: '" + $dllfilepath + "'") Red
            exit 1
        }

        Log ("Deleting file: '" + $zipfile + "'")
        del $zipfile
    }

    Log ("Loading assembly: '" + $dllfilepath + "'")
    [Reflection.Assembly]::LoadFile($dllfilepath) | Out-Null
}

function Log([string] $message, $color)
{
    [string] $date = [DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss")
    if ($color)
    {
        Write-Host ($date + ": " + $message) -f $color
    }
    else
    {
        Write-Host ($date + ": " + $message) -f Green
    }
}

Main $args
