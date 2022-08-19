Function Install-WinGet {
    #Install the latest package from GitHub
    [cmdletbinding(SupportsShouldProcess)]
    [alias("iwg")]
    [OutputType("None")]
    [OutputType("Microsoft.Windows.Appx.PackageManager.Commands.AppxPackage")]
    Param(
        [Parameter(HelpMessage = "Display the AppxPackage after installation.")]
        [switch]$Passthru
    )

    Write-Verbose "[$((Get-Date).TimeofDay)] Starting $($myinvocation.mycommand)"

    if ($PSVersionTable.PSVersion.Major -eq 7) {
        Write-Warning "This command does not work in PowerShell 7. You must install in Windows PowerShell."
        return
    }
    $WebClient = New-Object System.Net.WebClient
    
    $temp = [System.IO.Path]::GetTempPath()

    $SandboxDownloads = Join-Path -Path $temp -ChildPath 'SandboxDownloads'
    
    $null = New-Item -Path "$SandboxDownloads" -ItemType Directory -Force

    $vcLibs = @{
        fileName = 'Microsoft.VCLibs.x64.14.00.Desktop.appx'
        url      = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
    }

    $xamlPkg = @{
        fileName = 'microsoft.ui.xaml.2.7.0.nupkg'
        url      = 'https://globalcdn.nuget.org/packages/microsoft.ui.xaml.2.7.0.nupkg'
    }

    #test for requirement
    $Requirement = Get-AppPackage "Microsoft.DesktopAppInstaller"
    if (-not $requirement) {
        Write-Verbose "Installing Desktop App Installer requirement"
        try {
            $appx = Join-Path -Path $SandboxDownloads -ChildPath $vcLibs.fileName
            #Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile $appx
            $WebClient.DownloadFile($vcLibs.url, $appx) 
            Add-AppxPackage -Path $appx -erroraction Stop
            #Workaround https://github.com/microsoft/winget-cli/issues/1861#issuecomment-1186552694
            $nupkg = Join-Path -Path $SandboxDownloads -ChildPath "$($xamlPkg.fileName).zip"
            $WebClient.DownloadFile($xamlPkg.url, $nupkg)
            $expanded = Join-Path -Path $SandboxDownloads -ChildPath 'expanded-nupkg'
            Expand-Archive $nupkg -DestinationPath  $expanded
            $xaml = (Get-ChildItem -Recurse -Filter '*.appx'  -Path $expanded |Where {$_.FulLName -match 'x64'}).FullName
            Add-AppxPackage -Path $xaml -erroraction Stop
        } catch {
            throw $_
        }
    }

    $uri = "https://api.github.com/repos/microsoft/winget-cli/releases"

    try {
        Write-Verbose "[$((Get-Date).TimeofDay)] Getting information from $uri"
        $get = Invoke-RestMethod -uri $uri -Method Get -ErrorAction stop

        Write-Verbose "[$((Get-Date).TimeofDay)] getting latest release"
        #$data = $get | Select-Object -first 1
        $data = $get[0].assets | Where-Object name -Match 'msixbundle'

        $appx = $data.browser_download_url
        #$data.assets[0].browser_download_url
        Write-Verbose "[$((Get-Date).TimeofDay)] $appx"
        if ($pscmdlet.ShouldProcess($appx, "Downloading asset")) {
            $file = Join-Path -path $SandboxDownloads -ChildPath $data.name

            Write-Verbose "[$((Get-Date).TimeofDay)] Saving to $file"
            Invoke-WebRequest -Uri $appx -UseBasicParsing -DisableKeepAlive -OutFile $file

            Write-Verbose "[$((Get-Date).TimeofDay)] Adding Appx Package"
            Add-AppxPackage -Path $file -ErrorAction Stop

            if ($passthru) {
                Get-AppxPackage microsoft.desktopAppInstaller
            }
        }
    } catch {
        Write-Verbose "[$((Get-Date).TimeofDay)] There was an error."
        throw $_
    }
    Write-Verbose "[$((Get-Date).TimeofDay)] Ending $($myinvocation.mycommand)"
}