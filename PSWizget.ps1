<#PSScriptInfo

.VERSION 1.0.14

.GUID acb8f443-01c8-40b3-9369-c5e6e28548d1

.AUTHOR zakret.code@gmx.com

.COMPANYNAME

.COPYRIGHT GPL-3.0

.TAGS PSEdition_Core PSEdition_Desktop windows winget batch upgrade wizard update all queue

.LICENSEURI https://opensource.org/licenses/GPL-3.0

.PROJECTURI https://github.com/zakret/PSwizget

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
    - bug fixed "Parameter set cannot be resolved"
    - passed path is now tested if file location is really a path and if it exist
    - Aoption Soption and Coption are now unified under the -option <char>

.PRIVATEDATA

#>

<#
.SYNOPSIS
    PowerShell script that allow you to manage the upgrade process with winget.

.DESCRIPTION
    PowerShell script that allow you to manage the upgrade process with winget. 
    It adds a few more options than 'winget upgrade --all':
    - create a file with the packages you would like to omit
    - add or remove packages from the blacklist file directly from the script
    - automatically omit packages with "unknown" installed version, or when the formats of
      the installed version and the available version formatest does not match
    - it tries to guess the correct installed version by reading the pattern 
      from the available version
    - manually edit the upgrade queue
    - quick mode (it's similar to 'winget upgrade --all' but with a blacklist applied)
    - wingetParam <string> option with custom parameters to pass to winget. '-h' is set by default
    - blacklistPath <Path> option with custom blacklist file location. Default is "~\toSkip.txt".
    File doesn't need to be created beforehand
    - you can preselect one of the options available from the menu by adding the -option parameter
    with A, C or S argument 
    
    Known issue with Windows Powershell ver. <= 5.1 (desktop):
    Due to the ascii encoding, packages with longer names than 30 chars may corrupt 
    the 'winget upgrade' result, i.e. info about the long name package 
    and the packages listed after it. 
    Please use this script with PowerShell ver. > 5.1 (core) if you can 
    or avoid installing long name packages with winget.

.NOTES
    This is my first powershell script for educational purposes.

.EXAMPLE
    PS> .PSWizget.ps1

.INPUTS
    None. You cannot pipe objects to PSWizget.ps1.

.OUTPUTS
    None. PSWizget.ps1 does not generate any output.

.LINK
    Project page https://github.com/Zakret/PSwizget

.FUNCTIONALITY
    winget batch upgrade wizard update all queue

.PARAMETER quick
    The Script won't ask for any unessentialy input. It will exclude packages blacklisted 
    or with an unrecognized version and then the update will start.

.PARAMETER blacklistPath
    Custom blacklist file location. Default is "~\toSkip.txt". 
    It doesn't need to be created beforehand.

.PARAMETER wingetParam
    custom parameters to pass to winget. '-h' is set by default.

.PARAMETER option
    Start with the pre-selected option:
    C custom queue creation.
    A package addition.
    S package omission.

#>

[CmdletBinding(DefaultParameterSetName = 'set0')]
param (
    [string]$blacklistPath = "~\toSkip.txt",
    [string]$wingetParam = "-h",
    [ Parameter(ParameterSetName="set1") ]
    [switch]$quick,
    [ Parameter(ParameterSetName="set2") ]
    [ ValidateSet( 'a', 's', 'c' ) ]
    [string]$option
)

#region FUNCTIONS
#region UNIVERSAL FUNCTIONS
function Write-Separator {
    <#
    .DESCRIPTION
        Write-Host a colored line made of multipled string.

    .PARAMETER type
        The string to be multiplied.

    .PARAMETER number
        Line length.

    .PARAMETER color
        Line color.
    .PARAMETER allowMultiLines
        Don't trim line to the window size
    #>

    param (
        [string]$type = '-',
        [int]$number = $host.UI.RawUI.BufferSize.Width,
        [string]$color = 'Green',
        [switch]$allowMultiLines
    )
$line = ''
for ( $i = 0; $i -lt $number; $i ++ ) { $line = $line + $type } 
if ( !$allowMultiLines -and $line -gt $host.UI.RawUI.BufferSize.Width) {
    $line = $line.Substring(0,$host.UI.RawUI.BufferSize.Width)
}
Write-Host $line -ForegroundColor $color
}

function Get-Answer {
    <#
    .SYNOPSIS
        Wait for user input for specified amount of time.

    .DESCRIPTION
        Wait for user input for specified amount of time. The delay is an integer and amounts to 0.1s. 
        By default it's 50, so ~5s. It only takes one key ready. After the delay, function
        returns False.

    .EXAMPLE
        Get-Answer -Delay 100
        wait 10 seconds for user input, return single key object or false if no input has been entered

    .PARAMETER Delay
        Waiting time for the function to return False expressed in 0.1s.
        
    .NOTES
        Code by Every Villain Is Lemons
        https://stackoverflow.com/a/16965646

    #>
    param( [ Parameter() ] [int]$Delay = 50 )
    $counter = 0    
    $host.UI.RawUI.FlushInputBuffer()
    while( $counter++ -lt $Delay ) {
        if ( $Host.UI.RawUI.KeyAvailable ) {
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")
            break
        }
        else{
            Start-Sleep -Milliseconds 100
            $key = $false
        }
    }
    return ( $key )
}

function Get-IntAnswer {
    <#
    .SYNOPSIS
        Get selected numbers from the options presented to the user. User input must be integers separated by 
        spaces.

    .DESCRIPTION
        Get selected numbers from the options presented to the user.  
        User input must be integers separated by spaces, any other input will be rejected 
        by function.

    .PARAMETER options
        an array of item names from which the user can choose
    #>

    param (
        [ Parameter(Mandatory) ]
        [ string[] ]$options
    )
    $i = 0
    foreach ( $item in $options ) {
        $i ++
        Write-Host "[ $($i) ]    $($item)"
    }
    Write-Separator -number 55
    $hostSelection = Read-Host @"
Select the package indexes to which you want to apply the changes (eg. 1 4). 
Press [ Q ] to return to the menu
"@
    do {
        $hostArray = $hostSelection.Split(" ")
        $wrongInput = $false
        if ( !$hostArray -or $hostArray -eq 'q') { 
            break
        }
        try {
            $hostArray = foreach ( $i in $hostArray ) { [Convert]::ToInt32($i) }
        } catch { $wrongInput = $true }
        if ( $wrongInput -eq $false ) {
            $wrongInput = $hostArray.Where({ $_ -le 0 -or $_ -gt $options.Count},
                'SkipUntil', 1)
            $wrongInput = [boolean]$wrongInput
        }
        if ( $wrongInput -eq $true ) {
            $hostSelection = Read-Host "Don't be silly! Only mentioned numbers separated $(
                                        )by a space! Please select"
        }
    } while ( $wrongInput -eq $true )
    return $hostArray
}

function Write-PackagesStatus {
    <#
    .SYNOPSIS
        Show packages from array and message about their status

    .DESCRIPTION
        Show the status of packages, that means an array to which the package has been moved by 
        Split-Result function.
        It's displayed as follows: "Package/s <array> is/are <message>" or "<message>" 
        if list is empty.
    
    .EXAMPLE
        Write-PackagesStatus -namesArray @(Package1, Package2) -secondHalf "fantastic!"
        "Packages Package1, Package2 are fantastic!"

    .PARAMETER namesArray
        Array with list of packages names of the same status.

    .PARAMETER secondHalf
        The string displayed after the package list. It's a status description.

    .PARAMETER emptyMessage
        The string displayed if the package array is empty
    #>

    param(
         [ Parameter(Mandatory) ]
         [ AllowNull() ]
         [string[]]$namesArray,
         [ Parameter(Mandatory) ]
         [string]$secondHalf,
         [ Parameter() ]
         [string]$emptyMessage = ""
    )
    if ( $namesArray.Count -eq 1 ) {
        Write-Host "The package " -NoNewline
        Write-Host $namesArray[0] -ForegroundColor Yellow -NoNewline
        Write-Host " is $($secondHalf)"
    } 
    elseif ( $namesArray.Count -ne 0) {
        Write-Host "Packages " -NoNewline
        for ( $i=0; $i -lt $namesArray.count; $i++){
            Write-Host $namesArray[$i] -ForegroundColor Yellow -NoNewline
            if ( $i -ne $namesArray.count-1 ) {Write-Host ', ' -NoNewline}
        }
        Write-Host " are $($secondHalf)"
    } 
    elseif ( $emptyMessage -ne "" ) {
        Write-Host $emptyMessage -ForegroundColor Yellow
    }
}
#endregion UNIVERSAL FUNCTIONS

#region FUNCTIONS SPECIFIED FOR THE SCRIPT
function Split-Result {
    <#
    .SYNOPSIS
        Split the 'winget upgrade' result into three arrays: okList, noList, unknownVer

    .DESCRIPTION
        Split the 'winget upgrade' result into three groups: skippable (noList), 
        unrecognizable (unknownList) and upgradeable (okList) ones. 
        Also tries to correctly recognize packages with an incorrect format of the installed version.

        These objects must be defined in the script before calling this function:
        $upgradeList collection, with Package object with Name, ID, Version, AvailableVersion
        $blacklistPath with location to the blacklist file
    #>
    $Script:upgradeList | ForEach-Object -Begin {
        $okList = @()
        $noList = @()
        $unknownVer = @()
        $toSkip = Get-Content $Script:blacklistPath
    } -Process {   
        if ($toSkip -contains $_.Id) { $noList += $_ }
        elseif ($_.Version -contains "Unknown") { $unknownVer += $_ }
        elseif ([Math]::Abs($_.Version.Length - $_.AvailableVersion.Length) -gt 1){
            if (($_.Version.Length - $_.AvailableVersion.Length -gt 0) -and !$quick) {
                $versionPattern = $_.AvailableVersion -replace "[a-z]",'[a-z]'
                $versionPattern = $versionPattern -replace "[0-9]",'[0-9]'
                $versionPattern = $versionPattern -replace "\.",'\.'
                $_.Version -match "(?<Version>$($versionPattern))" | Out-Null
                $hostResponse = Read-Host "Is version '$($Matches.Version)' the correct version$(
                                        ) of $($_.Name) installed? Available version is '$(
                                        $_.AvailableVersion)'. [ Y ] for Yes, anything else to skip$(
                                        ) this package"
                if ( $hostResponse -like "y" ) {
                    $_.Version = $Matches.Version
                    $versionsCoparison = @($_.Version, $_.AvailableVersion) | 
                    Sort-Object -Descending
                    if ( $_.Version -eq $_.AvailableVersion -or `
                    $versionsCoparison[0] -eq $_.Version) {
                        Write-Host "There is no need to update $($_.Name). Omitting the package."
                    } else { $okList += $_ }
                } else { $unknownVer += $_ }
            } else {
                Write-Host "Installed ($($_.Version)) and available version ($(
                            $_.AvailableVersion)) formats for package $(
                            $_.Name) are different."
                $unknownList += $_
            }
        } else { $okList += $_ }
    } -End {
    return $okList, $noList, $unknownVer
    }
}

function Show-Result {
    <#
    .DESCRIPTION
        It uses the Write-PackagesStatus function to return all the messages needed in this script 
        at once.
    #>
    Write-PackagesStatus -namesArray $unknownVer.Name -secondHalf $Script:unknownVerMessage
    Write-PackagesStatus -namesArray $noList.Name -secondHalf $Script:noListMessage
    Write-PackagesStatus -namesArray $okList.Name -secondHalf $Script:okListMessage `
    -emptyMessage $Script:emptyListMessage
}

function Show-UI {
    <#
    .SYNOPSIS
        It shows the user all the available options that he can choose to manipulate the blacklist file
        or the update queue.

    .DESCRIPTION
        It shows the user all the available options that he can choose to manipulate the blacklist file
        or the update queue. Options available:
        - Add the package Id to the blacklist file
        - Remove package Id from the blacklist
        - Add the excluded packages to the update queue
        - Only this time, skip the package in the queue 
        - Create a new custom upgrade queue
        The function determines which packages are relevant to which option and shows them to the user 
        as an indexed list. The user select packages by entering their indexes separated 
        by spaces.
        The function has all the mechanisms needed for manipulation.

    .PARAMETER okList
        an object with packages to be updated

    .PARAMETER noList
        an object with blacklisted packages to be omitted

    .PARAMETER  unknownVer
        an object with packages to be omitted due to unrecognized version info

    .EXAMPLE
        Show-UI -okList $okList -noList $noList -unknownVer $unknownVer
        <Table with upgradable packages>
        ---
        Packages A, B are recognized incorrectly (installed version info).
        Package C is listed in the blacklist file.
        Package D id going to be updated.
        ---
        <a list with options indexed with single letters>
        [A] Option A
        ---
        Wait 10 sec or press anything else to continue
        <User input - only one char read>
        A
        <indexed list of packages relevant to selected option>
        [1] Package B
        [2] Package D
        Select the package indexes to which you want to apply the changes (eg. 1 4):
        <User input - integers seperated by spaces>
        1 2
        <Packages B and D are manipulated as indicated by the option>
        <Clear-Host and run function again>
        <User unput Enter>
        <Function ends>
    #>
param (
    [ Parameter(Mandatory) ]$okList, 
    [ Parameter(Mandatory) ]$noList, 
    [ Parameter(Mandatory) ]$unknownVer
)
Clear-Host
$Script:upgradeList | Format-Table
Write-Separator -type "‾"
Show-Result
Write-Separator
Write-Host @"
[ B ]    Add the package Id to the blacklist file
[ W ]    Remove package Id from the blacklist
[ A ]    Add the excluded packages to the update queue
[ S ]    Only this time, skip the package in the queue 
[ C ]    Create a new custom upgrade queue
"@
Write-Separator -number 55
Write-Host "Wait 10 sec or press anything else to continue"
Write-Separator -number 55

$hostResponse = New-Object -TypeName System.Management.Automation.Host.KeyInfo
if ( $option -eq 'a' ) {
    Write-Host "Do you want to add one of these packages to the update queue?"
    $hostResponse.Character = "a"
    $option = $false
} elseif ( $option -eq 'c' ) {
    Write-Host "Please define the update queue:"
    $hostResponse.Character = "c"
    $option = $false
} elseif ( $option -eq 's' ) {
    Write-Host "Do you want to omit any of these packages?"
    $hostResponse.Character = "s"
    $option = $false
} else {
    $hostResponse = Get-Answer -Delay 100
}
$optionsList = @()
switch ( $hostResponse.Character ) {
    'b' {
        $optionsList = $Script:upgradeList | Where-Object {$_ -NotIn $noList}
        if ( !$optionsList ) {
            Write-Host "There are no packages that could be added to the blacklist file."  `
            -ForegroundColor Yellow
        } else {
            $hostArray = Get-IntAnswer -options $optionsList.Name
            if ( $hostArray -notin @('q', $false ) ) {
                foreach ( $k in $hostArray ) {
                    Add-Content -Path $Script:blacklistPath -Value $optionsList[$k - 1].Id
                    $toSkip, $noList = @(), @()
                    $toSkip = Get-Content $Script:blacklistPath
                    foreach ($package in $Script:upgradeList) {
                        if ($toSkip -contains $package.Id) 
                        { $noList += $package }
                    }
                    $okList = $oklist | Where-Object {$_ -notIn @($optionsList[$k - 1])}
                    if ( $null -eq $okList) { $okList = @() }
                    Write-Host "Added $($optionsList[$k - 1].Name) to the blacklist file." `
                    -ForegroundColor Yellow
                }
            }
        }
    }
    'w' {
        $optionsList = $noList
        if ( !$optionsList ) {
            Write-Host "For now, the blacklist file is empty" -ForegroundColor Yellow
        } else {
            $hostArray = Get-IntAnswer -options $optionsList.Name
            if ( $hostArray -notin @('q', $false ) ) {
                foreach ( $k in $hostArray ) {
                    Set-Content -Path $Script:blacklistPath -Value (get-content `
                    -Path $Script:blacklistPath | Select-String `
                    -SimpleMatch $optionsList[$k - 1].Id -NotMatch)
                    $noList = $nolist | Where-Object {$_ -notIn @($optionsList[$k - 1])}
                    if ( $null -eq $noList) { $noList = @() }
                    if ( $optionsList[$k - 1].Version -ne 'Unknown' ){
                        $okList += @($optionsList[$k - 1])
                    }
                    Write-Host "Removed $($optionsList[$k - 1].Name) from the blacklist file." `
                    -ForegroundColor Yellow
                }   
            }
        }
    }
    'a' {
        $optionsList = $unknownVer + $noList
        if ( !$optionsList ) {
            Write-Host "There are no excluded packages" -ForegroundColor Yellow
        } else {
            $hostArray = Get-IntAnswer -options $optionsList.Name
            if ( $hostArray -notin @('q', $false ) ) {
                foreach ( $k in $hostArray ) {
                    $okList += @($optionsList[$k - 1])
                    Write-Host "Added $($optionsList[$k - 1].Name) to this upgrade queue." `
                    -ForegroundColor Yellow
                }
            }
        }
    }
    's' {
        $optionsList = $okList
        if ( !$optionsList ) {
            Write-Host "There are no upgradeable packages" -ForegroundColor Yellow
        } else {
            $hostArray = Get-IntAnswer -options $optionsList.Name
            if ( $hostArray -notin @('q', $false ) ) {
                foreach ( $k in $hostArray ) {
                    $okList = $oklist | Where-Object {$_ -notin @($optionsList[$k - 1])}
                    if ( $null -eq $okList) { $okList = @() }
                    Write-Host "Removed $($optionsList[$k - 1].Name) from this upgrade queue." `
                    -ForegroundColor Yellow
                }
            }    
        }
    }
    'c' {
        $optionsList = $Script:upgradeList
        $hostArray = Get-IntAnswer -options $optionsList.Name
        if ( $hostArray -ne 'q' ) {
            $okList = @()
            if ($hostArray -eq $false) {
                foreach ($k in $hostArray) {
                    $okList += $optionsList[$k - 1]
                }
            }
            $Script:okListS = $okList
            break
        }
    }
    { $_ -in 'b', 'w', 'a', 's', 'c'} { 
        if ( $hostArray -notin @('q', $false ) ) { Get-Answer -Delay 20 | Out-Null }
        $Script:okListS = $okList
        Show-UI -okList $okList -noList $noList -unknownVer $unknownVer
    }
}
}
#endregion FUNCTIONS SPECIFIED FOR THE SCRIPT
#endregion FUNCTIONS

#region STARTUP

# window configuration
$host.UI.RawUI.BufferSize.Width = 120;  $host.UI.RawUI.WindowSize.Width = 120
$oldTitle = $host.UI.RawUI.WindowTitle; $host.UI.RawUI.WindowTitle = 'PS Wizget'

# winget test
$wingetExist = test-path -path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\winget.exe"
if ( !$wingetExist ) {
    Write-Host -NoNewline -ForegroundColor Yellow "First please install winget from msstore"
    return
}

# encoding test
if( $OutputEncoding.WindowsCodePage -ne 1200 ) {
    Write-Host "Your Powershell encoding is not utf8. Packages with longer names than 30 chars $(
               )may corrupt the 'winget upgrade' result." -ForegroundColor Red
    Write-Host "Powershell encoding : ", $OutputEncoding.HeaderName
} 

# create and read blacklist file
if ( $blacklistPath -match '\\' ){
    $fileName = $blacklistPath -replace '^.+\\', ""

} elseif ( $blacklistPath -match '/' ){
    $fileName = $blacklistPath -replace '^.+/', ""
} else {
    Write-Host 'Passed location does not exist!' -ForegroundColor Red
    return
}
if ( $null -ne $fileName ) {
    $folderPath = $blacklistPath.TrimEnd($fileName)
    if ( !(Test-Path -Path $folderPath) ) {
        Write-Host 'Passed location does not exist!' -ForegroundColor Red
        return
    }
}

if ( $blacklistPath[-1] -in @("\","/")) {
    $blacklistPath = $blacklistPath + "blacklist.txt"
}


if ( !(Test-Path -Path $blacklistPath) ) {
  New-Item -Path $blacklistPath -ItemType file
  Write-Host
  Write-Host "A blacklist file has been created in " -NoNewline
  Write-Host $(Resolve-Path -path $blacklistPath) -ForegroundColor Yellow
  Read-Host "Add the IDs of packages with a different format for 'version' and $(
            )'available version' to this file"
}

Write-Host 'Please wait...'
# internet connection test
Write-Host -NoNewline  -ForegroundColor Yellow "`rTesting connection...         "
if ( !( Test-Connection 8.8.8.8 -Count 3 -Quiet ) ) {
    Write-Host -ForegroundColor Yellow "`rNo internet connection.       "
  Return
}
#endregion STARTUP

Write-Host -ForegroundColor Yellow "`rConnected. Fetching from 'winget upgrade'..."
#region FETCHING UPGRADEABLE PACKAGES
#       FROM WINGET TO COLLECTION OF OBJECT
#It's not mine code in this region. I found it on stackoverflow some time ago but can't find it now.
#Temporory no author, no link

class Software {
    [string]$Name
    [string]$Id
    [string]$Version
    [string]$AvailableVersion
}

$upgradeResult = winget upgrade | Out-String

# my fix to this code
$upgradeResult = $upgradeResult -replace 'ÔÇŽ', ' '


$lines = $upgradeResult.Split([Environment]::NewLine)

# Find the line that starts with Name, it contains the header
$fl = 0
while (-not $lines[$fl].StartsWith("Name")) { $fl++ }

# Line $i has the header, we can find char where we find ID and Version
$idStart = $lines[$fl].IndexOf("Id")
$versionStart = $lines[$fl].IndexOf("Version")
$availableStart = $lines[$fl].IndexOf("Available")
$sourceStart = $lines[$fl].IndexOf("Source")

# Now cycle in real package and split accordingly
$upgradeList = @()
for ($i = $fl + 1; $i -le $lines.Length; $i++) {
    $line = $lines[$i]
    if ($line.Length -gt ($availableStart + 1) -and -not $line.StartsWith('-')) {
        $name = $line.Substring(0, $idStart).TrimEnd()
        $id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
        $version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
        $available = $line.Substring($availableStart, $sourceStart - $availableStart).TrimEnd()
        $software = [Software]::new()
        $software.Name = $name
        $software.Id = $id
        $software.Version = $version
        $software.AvailableVersion = $available

        $upgradeList += $software
    }
}
#endregion FETCHING UPGRADEABLE PACKAGES

#region POSTPROCESSING WINGET UPGRAGE RESULT      
$upgradeList = $upgradeList | Sort-Object -Property Id -Unique
If ( !$upgradeList ) {
    Read-Host "There are no packages to upgrade. Press Enter to close this window"
    return
}

$maxLength = 20
foreach ( $package in $upgradeList) {
    if ( $package.Name.Length -gt $maxLength -and $package.Name.Length -le $package.ID.Length) {
        $package.Name = $package.Name.Substring(0,$maxLength-3) + '...'
    } 
    elseif ( $package.Name.Length -gt $maxLength -and $package.Name.Length -gt $package.ID.Length) {
        $package.Name = $package.Name.Substring(0,$package.ID.Length-3) + '...'
    }
}
#endregion POSTPROCESSING WINGET UPGRAGE RESULT

#region PREPARING MESSAGES ABOUT PACKAGES STATUSES
$unknownVerMessage = "recognized incorrectly (installed version info)."
$noListMessage = "listed in the blacklist file."
$okListMessage = "going to be updated."
$emptyListMessage = "There are no packages to upgrade."
#endregion PREPARING MESSAGES ABOUT PACKAGES STATUSES

#region UI
<#
$dummySoftware = [Software]::new()
$dummySoftware.Name = ''
$dummySoftware.Id = ''
$dummySoftware.Version = ''
$dummySoftware.AvailableVersion = ''

$okListS += $dummySoftware
$noListS += $dummySoftware
$unknownVerS += $dummySoftware
#>

$okListS, $noListS, $unknownVerS = Split-Result


if ( !$quick ) {
    Show-UI -okList $okListS -noList $noListS -unknownVer $unknownVerS
}
#endregion UI

#region UPGRADE A BATCH OF PACKAGES
Write-PackagesStatus -namesArray $okListS.Name -secondHalf $okListMessage -emptyMessage $emptyListMessage

if ( $oklistS.Count -gt 0) {
    Write-Host
    $abort = Read-Host '[ Enter ] to continue, [ Q ] to abort'
    if ( $abort -ne 'q') {
        foreach ($package in $okListS) {
            $winget = "winget upgrade" + " " + $package.Id + " " + $wingetParam
            $host.UI.RawUI.WindowTitle = "PS Wizget: Updating " + $package.Name
            Write-Separator -number 55
            Write-Host "Updating the $($package.Name) application." -ForegroundColor Yellow
            & Invoke-Expression $winget
        }
        Write-Separator -number 55
        Write-Host "All updates completed" -ForegroundColor Yellow
    }
}

$host.UI.RawUI.WindowTitle = $oldTitle
#endregion UPGRADE A BATCH OF PACKAGES
