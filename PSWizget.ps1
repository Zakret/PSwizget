<#
.SYNOPSIS
    PowerShell script that allow you to manage the upgrade process with winget.

.DESCRIPTION
    PowerShell script that allow you to manage the upgrade process with winget. 
    It adds a few more options than 'winget upgrade --all':
    - create a file with the packages you would like to omit
    - add or remove packages from toSkip file directly from the script
    - automatically omit packages with "unknown" installed version, or when the 
      installed version and the available version does not match
    - it tries to guess the correct installed version by reading the pattern 
      from the available version
    - manually edit the upgrade queue
    - quick mode (it's similar to 'winget upgrade --all' but witha blacklist applied)

.NOTES
    This is my first powershell script for educational purposes.

.EXAMPLE
    PS> .PSWizget.ps1

.PARAMETER quick
    The Script won't ask for any unessentialy input. It will exclude packages blacklisted 
    or with an unrecognized version and then the update will start.

.INPUTS
    None. You cannot pipe objects to PSWizget.ps1.

.OUTPUTS
    None. PSWizget.ps1 does not generate any output.

.LINK
    Project page https://github.com/Zakret/PSwizget

.FUNCTIONALITY
    winget batch upgrade wizard update all queue

#>

param (
    [switch]$quick
)

#region FUNCTIONS
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
        $toSkip array with packages IDs
    #>
    $okList = @()
    $noList = @()
    $unknownVer = @()
    $toSkip = Get-Content $Script:toSkipPath
    foreach ($package in $Script:upgradeList) {
        if ($toSkip -contains $package.Id) { $noList += $package }
        elseif ($package.Version -contains "Unknown") { $unknownVer += $package }
        elseif ([Math]::Abs($package.Version.Length - $package.AvailableVersion.Length) -gt 1){
            if (($package.Version.Length - $package.AvailableVersion.Length -gt 0) -and !$quick) {
                $versionPattern = $package.AvailableVersion -replace "[a-z]",'[a-z]'
                $versionPattern = $versionPattern -replace "[0-9]",'[0-9]'
                $versionPattern = $versionPattern -replace "\.",'\.'
                $package.Version -match "(?<Version>$($versionPattern))" | Out-Null
                $hostResponse = Read-Host "Is version $($Matches.Version) the correct version$(
                                            ) of $($package.Name) installed? [y] for Yes, $(
                                            )anything else to skip this package"
                if ( $hostResponse -like "y" ) {
                    $package.Version = $Matches.Version
                    $versionsCoparison = @($package.Version, $package.AvailableVersion) | 
                    Sort-Object -Descending
                    if ( $package.Version -eq $package.AvailableVersion -or `
                    $versionsCoparison[0] -eq $package.Version) {
                        Write-Host "There is no need to update $($package.Name). $(
                                    )Omitting the package."
                    } else { $okList += $package }
                } else { $unknownVer += $package }
            } else {
                Write-Host "Installed ($($package.Version)) and available version ($(
                            $package.AvailableVersion)) formats for package $(
                            $package.Name) are different."
                $unknownList += $package
            }
        } else { $okList += $package }
    }
    return $okList, $noList, $unknownVer
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

function Show-PackagesStatus {
    <#
    .SYNOPSIS
        Show packages from array and message about their status

    .DESCRIPTION
        Show the status of packages, that means an array to which the package has been moved by 
        Split-Result function.
        It's displayed as follows: "Package/s <array> is/are <message>" or "<message>" 
        if list is empty.
    
    .EXAMPLE
        Show-PackagesStatus -packagesArray @(Package1, Package2) -secondHalf "fantastic!"
        "Packages Package1, Package2 are fantastic!"

    .PARAMETER packagesArray
        Array with list of packages of the same status.

    .PARAMETER secondHalf
        The string displayed after the package list. It's a status description.

    .PARAMETER emptyMessage
        The string displayed if the package array is empty
    #>

    param(
         [ Parameter(Mandatory) ]
         $packagesArray,
         [ Parameter(Mandatory) ]
         [string]$secondHalf,
         [ Parameter() ]
         [string]$emptyMessage = ""
    )
    if ( $packagesArray.Count -eq 1 ) {
        return "The package $($packagesArray.Name) is $($secondHalf)"
    } 
    elseif ( $packagesArray.Count -ne 0) {
        return "Packages $($packagesArray.Name -join ", ") are $($secondHalf)"
    } 
    elseif ( $emptyMessage -ne "" ) {
        return $emptyMessage
    }
}

function Get-IntAnswer {
    <#
    .SYNOPSIS
        Get selected numbers from the options presented to the user. User input must be integers separated by 
        spaces.

    .DESCRIPTION
        Get selected numbers from the options presented to the user. Options are packages that can be manipulated. 
        User input must be integers separated by spaces, any other input will be rejected 
        by function.

        This object must be defined in the script before calling this function:
        $optionList collection of Package objects with Name, ID, Version, AvailableVersion
    #>
    $i = 0
    foreach ( $package in $optionsList ) {
        $i ++
        Write-Host "[$($i)] $($package.Name)"
    }
    $hostSelection = Read-Host "Select the package indexes to which you want to apply the $(
                                )changes (eg. 1 4)"
    do {
        $hostArray = $hostSelection.Split(" ")
        $wrongInput = $false
        if ( !$hostArray ) { 
            $wrongInput = $true 
        }
        try {
            $hostArray = foreach ( $i in $hostArray ) { [Convert]::ToInt32($i) }
        } catch { $wrongInput = $true }
        if ( $wrongInput -eq $false ) {
            $wrongInput = $hostArray.Where({ $_ -le 0 -or $_ -gt $optionsList.Length},
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

function Show-Result {
    <#
    .DESCRIPTION
        It uses the Show-PackagesStatus function to return all the messages needed in this script 
        at once.
    #>
    $unknownPackages = Show-PackagesStatus -packagesArray $unknownVer `
    -secondHalf $Script:unknownVerMessage
    $noPackages = Show-PackagesStatus -packagesArray $noList `
    -secondHalf $Script:noListMessage
    $okPackages = Show-PackagesStatus -packagesArray $okList `
    -secondHalf $Script:okListMessage -emptyMessage $Script:emptyListMessage
    return $unknownPackages, $noPackages, $okPackages
}

function Show-UI {
    <#
    .SYNOPSIS
        It shows the user all the available options that he can choose to manipulate the Skipt blacklist file
        or the update queue.

    .DESCRIPTION
        It shows the user all the available options that he can choose to manipulate the toSkip blacklist file
        or the update queue. Options available:
        - Add the package Id to the toSkip file
        - Remove package Id from file toSkip
        - Add the excluded packages to the update queue
        - Only this time, skip the package in the queue 
        - Create a new custom upgrade queue
        The function determines which packages are relevant to which option and shows them to the user 
        as an indexed list. The sser select packages by entering their indexes separated 
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
        Package C is listed in the toSkip file.
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
    #>
param (
    [ Parameter(Mandatory) ]$okList, 
    [ Parameter(Mandatory) ]$noList, 
    [ Parameter(Mandatory) ]$unknownVer
)
$unknownPackages, $noPackages, $okPackages = Show-Result
Clear-Host
$Script:upgradeList | Format-Table
Write-Host @"
------------------------------------------------------
$($unknownPackages)
$($noPackages)
$($okPackages)
------------------------------------------------------
[B]      Add the package Id to the toSkip file
[W]      Remove package Id from file toSkip
[A]      Add the excluded packages to the update queue
[S]      Only this time, skip the package in the queue 
[C]      Create a new custom upgrade queue
------------------------------------------------------
Wait 10 sec or press anything else to continue
------------------------------------------------------

"@

$hostResponse = Get-Answer -Delay 100
$optionsList = @()
switch ( $hostResponse.Character ) {
    'b' {
        $optionsList = $Script:upgradeList | Where-Object {$_ -NotIn $noList}
        if ( !$optionsList ) {
            Write-Host "There are no packages that could be added to the toSkip file."
        } else {
            $hostArray = Get-IntAnswer
            foreach ( $k in $hostArray ) {
                Add-Content -Path $Script:toSkipPath -Value $optionsList.Id[$k - 1]
                $toSkip, $noList = @(), @()
                $toSkip = Get-Content $Script:toSkipPath
                foreach ($package in $Script:upgradeList) {
                    if ($toSkip -contains $package.Id) 
                    { $noList += $package }
                }
                $okList = $oklist | Where-Object {$_ -notIn @($optionsList[$k - 1])}
                if ( $null -eq $okList) { $okList = @() }
                Write-Host "Added $($optionsList.Name[$k - 1]) to the toSkip file."
            }
        }
    }
    'w' {
        $optionsList = $noList
        if ( !$optionsList ) {
            Write-Host "For now, the toSkip file is empty"
        } else {
            $hostArray = Get-IntAnswer
            foreach ( $k in $hostArray ) {
                Set-Content -Path $Script:toSkipPath -Value (get-content -Path $Script:toSkipPath |
                Select-String -SimpleMatch $optionsList.Id[$k - 1] -NotMatch)
                $noList = $nolist | Where-Object {$_ -notIn @($optionsList[$k - 1])}
                if ( $null -eq $noList) { $noList = @() }
                if ( $optionsList.Version[$k - 1] -ne 'Unknown' ){
                    $okList += @($optionsList[$k - 1])
                }
                Write-Host "Removed $($optionsList.Name[$k - 1]) from the toSkip file."
            }   
        }
    }
    'a' {
        $optionsList = $unknownVer + $noList
        if ( !$optionsList ) {
            Write-Host "There are no excluded packages"
        } else {
            $hostArray = Get-IntAnswer
            foreach ( $k in $hostArray ) {
                $okList += @($optionsList[$k - 1])
                Write-Host "Added $($optionsList.Name[$k - 1]) to this upgrade queue."
            }
        }
    }
    's' {
        $optionsList = $okList
        if ( !$optionsList ) {
            Write-Host "There are no upgradeable packages"
        } else {
            $hostArray = Get-IntAnswer
            foreach ( $k in $hostArray ) {
                $okList = $oklist | Where-Object {$_ -notin @($optionsList[$k - 1])}
                if ( $null -eq $okList) { $okList = @() }
                Write-Host "Removed $($optionsList.Name[$k - 1]) from this upgrade queue."
            }
        }
    }
    'c' {
        $optionsList = $Script:upgradeList
        $hostArray = Get-IntAnswer
        $okList = @()
        foreach ($k in $hostArray) {
            $okList += $optionsList[$k - 1]
        }
        $Script:okListS = $okList
        break
    }
    { $_ -in 'b', 'w', 'a', 's'} { 
        $Script:key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")
        Get-Answer -Delay 20 | Out-Null
        $Script:okListS = $okList
        Show-UI -okList $okList -noList $noList -unknownVer $unknownVer
    }
}
}
#endregion FUNCTIONS

# user input fix - flushing Enter
$key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")

#region  WINGET AND CONNECTION TEST
Write-Host 'Please wait...'
$wingetExist = test-path -path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\winget.exe"
if ( !$wingetExist ) {
    Write-Host "First please install winget from msstore"
    return
}
if ( !( Test-Connection 8.8.8.8 -Count 3 -Quiet ) ) {
  Write-Host "No internet connection"
  Return
}
#endregion  WINGET AND CONNECTION TEST

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
$upgradeResult = $upgradeResult -replace "ÔÇŽ", " "

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
$upgradeList = $upgradeList | Sort-Object -Property Id -Unique
If ( !$upgradeList ) {
    Read-Host "There are no packages to upgrade. Press Enter to close this window"
    return
}

#endregion FETCHING UPGRADEABLE PACKAGES

#region CREATE AND READ A FILE TOSKIP
#       WITH A SAVED LIST OF PACKAGES THAT THE USER DOESN'T WANT TO UPGRADE
$toSkipPath = ".\toSkip.txt"
if ( !(Test-Path -Path $toSkipPath) ) {
  New-Item -Path $toSkipPath -ItemType file
  Read-Host -Prompt  "A 'toSkip' file has been created. Add the IDs of packages $(
                     )with a different format for 'version' and 'available version' to this file"
}
#endregion CREATE AND READ A FILE TOSKIP

#region PREPARING MESSAGES ABOUT PACKAGES STATUSES
$unknownVerMessage = "recognized incorrectly (installed version info)."
$noListMessage = "listed in the toSkip file."
$okListMessage = "going to be updated."
$emptyListMessage = "There are no packages to upgrade."
#endregion PREPARING MESSAGES ABOUT PACKAGES STATUSES

#region UI
$okListS, $noListS, $unknownVerS = @(), @(), @()
$okListS, $noListS, $unknownVerS = Split-Result

if ( !$quick ) {
    Clear-Host
    $upgradeList | Format-Table
    Show-UI -okList $okListS -noList $noListS -unknownVer $unknownVerS
}
#endregion UI

#region UPGRADE A BATCH OF PACKAGES
Show-PackagesStatus -packagesArray $okListS -secondHalf $okListMessage -emptyMessage $emptyListMessage

if ( $oklistS.Count -gt 0) {
    Read-Host -Prompt 'Enter to continue, ctrl+c to abort'
    foreach ($package in $okListS) {
        Write-Host "Updating the $($package.Name) application."
        & winget upgrade $package.Id -h
    }
}

if ( !$quick ) {Read-Host -Prompt "Finished. Press Enter to close this script"}
#endregion UPGRADE A BATCH OF PACKAGES
