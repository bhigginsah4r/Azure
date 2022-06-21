﻿[Cmdletbinding()]
Param(
    [parameter(Mandatory)]
    [string]
    $AmdVmSize, 

    [parameter(Mandatory)]
    [string]
    $DisaStigCompliance,

    [parameter(Mandatory)]
    [string]
    $DomainName,    

    [parameter(Mandatory)]
    [string]
    $Environment,

    [parameter(Mandatory)]
    [array]
    $FileShares,

    [parameter(Mandatory)]
    [string]
    $HostPoolName,

    [parameter(Mandatory)]
    [string]
    $HostPoolRegistrationToken,    

    [parameter(Mandatory)]
    [string]
    $ImageOffer,
    
    [parameter(Mandatory)]
    [string]
    $ImagePublisher,

    [parameter(Mandatory)]
    [string]
    $NetAppFileShare,

    [parameter(Mandatory)]
    [string]
    $NvidiaVmSize,

    [parameter(Mandatory)]
    [string]
    $PooledHostPool,

    [parameter(Mandatory)]
    [string]
    $RdpShortPath,

    [parameter(Mandatory)]
    [string]
    $ScreenCaptureProtection,

    [parameter(Mandatory)]
    [string]
    $StorageAccountPrefix,

    [parameter(Mandatory)]
    [int]
    $StorageCount,

    [parameter(Mandatory)]
    [int]
    $StorageIndex,

    [parameter(Mandatory)]
    [string]
    $StorageSolution,

    [parameter(Mandatory)]
    [string]
    $StorageSuffix   
)


##############################################################
#  Functions
##############################################################
function Write-Log
{
    param(
        [parameter(Mandatory)]
        [string]$Message,
        
        [parameter(Mandatory)]
        [string]$Type
    )
    $Path = 'C:\cse.txt'
    if(!(Test-Path -Path $Path))
    {
        New-Item -Path 'C:\' -Name 'cse.txt' | Out-Null
    }
    $Timestamp = Get-Date -Format 'MM/dd/yyyy HH:mm:ss.ff'
    $Entry = '[' + $Timestamp + '] [' + $Type + '] ' + $Message
    $Entry | Out-File -FilePath $Path -Append
}


function Get-WebFile
{
    param(
        [parameter(Mandatory)]
        [string]$FileName,

        [parameter(Mandatory)]
        [string]$URL
    )
    $Counter = 0
    do
    {
        Invoke-WebRequest -Uri $URL -OutFile $FileName -ErrorAction 'SilentlyContinue'
        if($Counter -gt 0)
        {
            Start-Sleep -Seconds 30
        }
        $Counter++
    }
    until((Test-Path $FileName) -or $Counter -eq 9)
}


try 
{
    ##############################################################
    #  DISA STIG Compliance
    ##############################################################
    if($DisaStigCompliance -eq 'true')
    {
        # Set Local Admin account password expires True (V-205658)
        $localAdmin = Get-LocalUser | Where-Object Description -eq "Built-in account for administering the computer/domain"
        Set-LocalUser -name $localAdmin.Name -PasswordNeverExpires $false
    }

    ##############################################################
    #  Add Recommended AVD Settings
    ##############################################################
    $Settings = @(

        # Disable Automatic Updates: https://docs.microsoft.com/en-us/azure/virtual-desktop/set-up-customize-master-image#disable-automatic-updates
        [PSCustomObject]@{
            Name = 'NoAutoUpdate'
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
            PropertyType = 'DWord'
            Value = 1
        },

        # Enable Time Zone Redirection: https://docs.microsoft.com/en-us/azure/virtual-desktop/set-up-customize-master-image#set-up-time-zone-redirection
        [PSCustomObject]@{
            Name = 'fEnableTimeZoneRedirection'
            Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
            PropertyType = 'DWord'
            Value = 1
        }
    )


    ##############################################################
    #  Add GPU Settings
    ##############################################################
    # This setting applies to the VM Size's recommended for AVD with a GPU
    if ($AmdVmSize -eq 'true' -or $NvidiaVmSize -eq 'true') 
    {
        $Settings += @(

            # Configure GPU-accelerated app rendering: https://docs.microsoft.com/en-us/azure/virtual-desktop/configure-vm-gpu#configure-gpu-accelerated-app-rendering
            [PSCustomObject]@{
                Name = 'bEnumerateHWBeforeSW'
                Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
                PropertyType = 'DWord'
                Value = 1
            },

            # Configure fullscreen video encoding: https://docs.microsoft.com/en-us/azure/virtual-desktop/configure-vm-gpu#configure-fullscreen-video-encoding
            [PSCustomObject]@{
                Name = 'AVC444ModePreferred'
                Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
                PropertyType = 'DWord'
                Value = 1
            }
        )
    }

    # This setting applies only to VM Size's recommended for AVD with a Nvidia GPU
    if($NvidiaVmSize -eq 'true')
    {
        $Settings += @(

            # Configure GPU-accelerated frame encoding: https://docs.microsoft.com/en-us/azure/virtual-desktop/configure-vm-gpu#configure-gpu-accelerated-frame-encoding
            [PSCustomObject]@{
                Name = 'AVChardwareEncodePreferred'
                Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
                PropertyType = 'DWord'
                Value = 1
            }
        )
    }


    ##############################################################
    #  Add Screen Capture Protection
    ##############################################################
    if($ScreenCaptureProtection -eq 'true')
    {
        $Settings += @(

            # Enable Screen Capture Protection: https://docs.microsoft.com/en-us/azure/virtual-desktop/screen-capture-protection
            [PSCustomObject]@{
                Name = 'fEnableScreenCaptureProtect'
                Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
                PropertyType = 'DWord'
                Value = 1
            }
        )
    }

    ##############################################################
    #  Add RDP Short Path
    ##############################################################
    if($RdpShortPath -eq 'true')
    {
        # Allow inbound network traffic for RDP Shortpath
        New-NetFirewallRule -DisplayName 'Remote Desktop - Shortpath (UDP-In)'  -Action 'Allow' -Description 'Inbound rule for the Remote Desktop service to allow RDP traffic. [UDP 3390]' -Group '@FirewallAPI.dll,-28752' -Name 'RemoteDesktop-UserMode-In-Shortpath-UDP'  -PolicyStore 'PersistentStore' -Profile 'Domain, Private' -Service 'TermService' -Protocol 'udp' -LocalPort 3390 -Program '%SystemRoot%\system32\svchost.exe' -Enabled:True

        $Settings += @(

            # Enable RDP Shortpath for managed networks: https://docs.microsoft.com/en-us/azure/virtual-desktop/shortpath#configure-rdp-shortpath-for-managed-networks
            [PSCustomObject]@{
                Name = 'fUseUdpPortRedirector'
                Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'
                PropertyType = 'DWord'
                Value = 1
            },

            # Enable the port for RDP Shortpath for managed networks: https://docs.microsoft.com/en-us/azure/virtual-desktop/shortpath#configure-rdp-shortpath-for-managed-networks
            [PSCustomObject]@{
                Name = 'UdpPortNumber'
                Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'
                PropertyType = 'DWord'
                Value = 3390
            }
        )
    }


    # Set registry settings
    foreach($Setting in $Settings)
    {
        $Value = Get-ItemProperty -Path $Setting.Path -Name $Setting.Name -ErrorAction 'SilentlyContinue'
        $LogOutputValue = 'Path: ' + $Setting.Path + ', Name: ' + $Setting.Name + ', PropertyType: ' + $Setting.PropertyType + ', Value: ' + $Setting.Value
        if(!$Value)
        {
            New-ItemProperty -Path $Setting.Path -Name $Setting.Name -PropertyType $Setting.PropertyType -Value $Setting.Value -Force -ErrorAction 'Stop'
            Write-Log -Message "Added registry setting: $LogOutputValue" -Type 'INFO'
        }
        elseif($Value.$($Setting.Name) -ne $Setting.Value)
        {
            Set-ItemProperty -Path $Setting.Path -Name $Setting.Name -Value $Setting.Value -Force -ErrorAction 'Stop'
            Write-Log -Message "Updated registry setting: $LogOutputValue" -Type 'INFO'
        }
        else 
        {
            Write-Log -Message "Registry setting exists with correct value: $LogOutputValue" -Type 'INFO'    
        }
        Start-Sleep -Seconds 1
    }


    ##############################################################
    # Add Defender Exclusions for FSLogix 
    ##############################################################
    # https://docs.microsoft.com/en-us/azure/architecture/example-scenario/wvd/windows-virtual-desktop-fslogix#antivirus-exclusions
    if($PooledHostPool -eq 'true' -and $FSLogix -eq 'true')
    {

        $Files = @(
            "%ProgramFiles%\FSLogix\Apps\frxdrv.sys",
            "%ProgramFiles%\FSLogix\Apps\frxdrvvt.sys",
            "%ProgramFiles%\FSLogix\Apps\frxccd.sys",
            "%TEMP%\*.VHD",
            "%TEMP%\*.VHDX",
            "%Windir%\TEMP\*.VHD",
            "%Windir%\TEMP\*.VHDX"
        )
        foreach($Share in $Shares)
        {
            $Files += "$Share\*.VHD"
            $Files += "$Share\*.VHDX"
        }

        $CloudCache = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name 'CCDLocations' -ErrorAction 'SilentlyContinue'
        if($CloudCache)
        { 
            $Files += @(
                "%ProgramData%\FSLogix\Cache\*.VHD"
                "%ProgramData%\FSLogix\Cache\*.VHDX"
                "%ProgramData%\FSLogix\Proxy\*.VHD"
                "%ProgramData%\FSLogix\Proxy\*.VHDX"
            )
        }

        foreach($File in $Files)
        {
            Add-MpPreference -ExclusionPath $File -ErrorAction 'Stop'
        }
        Write-Log -Message 'Enabled Defender exlusions for FSLogix paths' -Type 'INFO'

        $Processes = @(
            "%ProgramFiles%\FSLogix\Apps\frxccd.exe",
            "%ProgramFiles%\FSLogix\Apps\frxccds.exe",
            "%ProgramFiles%\FSLogix\Apps\frxsvc.exe"
        )

        foreach($Process in $Processes)
        {
            Add-MpPreference -ExclusionProcess $Process -ErrorAction 'Stop'
        }
        Write-Log -Message 'Enabled Defender exlusions for FSLogix processes' -Type 'INFO'
    }


    ##############################################################
    #  Install the AVD Agent
    ##############################################################
    # Disabling this method for installing the AVD agent until AAD Join can completed successfully
    $BootInstaller = 'AVD-Bootloader.msi'
    Get-WebFile -FileName $BootInstaller -URL 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH'
    Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i $BootInstaller /quiet /qn /norestart /passive" -Wait -Passthru -ErrorAction 'Stop'
    Write-Log -Message 'Installed AVD Bootloader' -Type 'INFO'
    Start-Sleep -Seconds 5

    $AgentInstaller = 'AVD-Agent.msi'
    Get-WebFile -FileName $AgentInstaller -URL 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv'
    Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i $AgentInstaller /quiet /qn /norestart /passive REGISTRATIONTOKEN=$HostPoolRegistrationToken" -Wait -PassThru -ErrorAction 'Stop'
    Write-Log -Message 'Installed AVD Agent' -Type 'INFO'
    Start-Sleep -Seconds 5


    ##############################################################
    #  Run the Virtual Desktop Optimization Tool (VDOT)
    ##############################################################
    # https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool
    if($ImagePublisher -eq 'MicrosoftWindowsDesktop' -and $ImageOffer -ne 'windows-7')
    {
        # Download VDOT
        $URL = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/refs/heads/main.zip'
        $ZIP = 'VDOT.zip'
        Invoke-WebRequest -Uri $URL -OutFile $ZIP -ErrorAction 'Stop'
        
        # Extract VDOT from ZIP archive
        Expand-Archive -LiteralPath $ZIP -Force -ErrorAction 'Stop'
        
        # Fix to disable AppX Packages
        # As of 2/8/22, all AppX Packages are enabled by default
        $Files = (Get-ChildItem -Path .\VDOT\Virtual-Desktop-Optimization-Tool-main -File -Recurse -Filter "AppxPackages.json" -ErrorAction 'Stop').FullName
        foreach($File in $Files)
        {
            $Content = Get-Content -Path $File -ErrorAction 'Stop'
            $Settings = $Content | ConvertFrom-Json -ErrorAction 'Stop'
            $NewSettings = @()
            foreach($Setting in $Settings)
            {
                $NewSettings += [pscustomobject][ordered]@{
                    AppxPackage = $Setting.AppxPackage
                    VDIState = 'Disabled'
                    URL = $Setting.URL
                    Description = $Setting.Description
                }
            }

            $JSON = $NewSettings | ConvertTo-Json -ErrorAction 'Stop'
            $JSON | Out-File -FilePath $File -Force -ErrorAction 'Stop'
        }

        # Run VDOT
        & .\VDOT\Virtual-Desktop-Optimization-Tool-main\Windows_VDOT.ps1 -AcceptEULA
        Write-Log -Message 'Optimized the operating system using VDOT' -Type 'INFO'
    }
}
catch 
{
    Write-Log -Message $_ -Type 'ERROR'
}
