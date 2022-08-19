#https://www.aaflalo.me/2021/04/windows-sandboxing-and-winget/
#https://gist.github.com/Belphemur/0d8d6ef7e047ffa67b050d40ec983b56#file-sandbox-winget-ps1
#https://megamorf.gitlab.io/2020/07/19/automating-the-windows-sandbox/

# Parse Arguments

Param(
  [Parameter(Mandatory, HelpMessage = "The path for the Manifest.")]
  [String] $Manifest
)

if (-not (Test-Path -Path $Manifest -PathType Leaf)) {
  throw 'The Manifest file does not exist.'
}

# Validate manifest file
# We can't rely on status code until https://github.com/microsoft/winget-cli/issues/312 is solved
$validationResult = winget.exe validate $Manifest
if ($validationResult -like '*Manifest validation failed.*') {
  throw 'Manifest validation failed.'
}

# Check if Windows Sandbox is enabled

if (-Not (Test-Path "$env:windir\System32\WindowsSandbox.exe")) {
  Write-Error -Category NotInstalled -Message @'
Windows Sandbox does not seem to be available. Check the following URL for prerequisites and further details:    
https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-sandbox/windows-sandbox-overview
  
You can run the following command in an elevated PowerShell for enabling Windows Sandbox:
Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM'
'@ -ErrorAction Stop
}

# Set dependencies

$desktopAppInstaller = @{
  fileName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle'
  url      = 'https://github.com/microsoft/winget-cli/releases/download/v-0.2.10771-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle'
  hash     = '11ECD121B5A19E07A545E84BC4DC182BD64A6233C9DE137E10E3016D1527FC1E'
}

$vcLibs = @{
  fileName = 'Microsoft.VCLibs.140.00_14.0.29231.0_x64__8wekyb3d8bbwe.appxbundle'
  url      = 'http://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/c25ff6df-4333-4b94-8bbb-e33f0ead8e27?P1=1617466811&P2=404&P3=2&P4=m6dzqowVz7AxAQcLQ3PSy1bOobkzOB%2bRv78SjPolE7zSfwszpBi66JQ9BJ8WEP5zSl%2be2THw9kQoYH%2bwLLUO9g%3d%3d'
  hash     = 'E3339B2B40EE2522703FCAA451236653D8B9ACA2B98AE9162C427F978D08139A'
}

$vcLibsUwp = @{
  fileName = 'Microsoft.VCLibs.140.00.UWPDesktop_14.0.29231.0_x64__8wekyb3d8bbwe.appxbundle'
  url      = 'http://tlu.dl.delivery.mp.microsoft.com/filestreamingservice/files/0f3db454-690c-4d14-85cc-8c7c529c1594?P1=1617466723&P2=404&P3=2&P4=IApUypfgW95iQLjcYpWCqwRRI8gGetUIqBP3VV2Ij1X9eXV8GQ4GaPyNWnEboqPCTI4mRiiB%2fvc3mAN9uWsliA%3d%3d'
  hash     = '6602159C341BAFEA747D0EDF15669AC72DF8817299FBFAA90469909E06794256'
}

$dependencies = @($desktopAppInstaller, $vcLibsUwp)

# Initialize Temp Folder

$tempFolder = Join-Path -Path $PSScriptRoot -ChildPath 'SandboxTest_Temp'

New-Item $tempFolder -ItemType Directory -ea 0 | Out-Null

Get-ChildItem $tempFolder -Recurse -Exclude $dependencies.fileName | Remove-Item -Force

Copy-Item -Path $Manifest -Destination $tempFolder

# Download dependencies

$WebClient = New-Object System.Net.WebClient

foreach ($dependency in $dependencies) {
  $dependency.file = Join-Path -Path $tempFolder -ChildPath $dependency.fileName

  # Only download if the file does not exist, or its hash does not match.
  if (-Not ((Test-Path -Path $dependency.file -PathType Leaf) -And $dependency.hash -eq $(get-filehash $dependency.file).Hash)) {
    # This downloads the file
    Write-Host "Downloading $($dependency.url) ..."
    try { 
      $WebClient.DownloadFile($dependency.url, $dependency.file) 
    } 
    catch {
      throw "Error downloading $($dependency.url) ."
    }
    if (-not ($dependency.hash -eq $(get-filehash $dependency.file).Hash)) {
      throw 'Hashes do not match, try gain.'
    }
  }
}

# Create Bootstrap script

$manifestFileName = Split-Path $Manifest -Leaf

$bootstrapPs1Content = @"
Set-PSDebug -Trace 1

Add-AppxPackage -Path '$($desktopAppInstaller.fileName)' -DependencyPath '$($vcLibsUwp.fileName)'

winget install -m '$manifestFileName'
"@

$bootstrapPs1FileName = 'Bootstrap.ps1'
$bootstrapPs1Content | Out-File (Join-Path -Path $tempFolder -ChildPath $bootstrapPs1FileName)

# Create Wsb file

$tempFolderInSandbox = Join-Path -Path 'C:\Users\WDAGUtilityAccount\Desktop' -ChildPath (Split-Path $tempFolder -Leaf)

$sandboxTestWsbContent = @"
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$tempFolder</HostFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
  <Command>PowerShell Start-Process PowerShell -WorkingDirectory '$tempFolderInSandbox' -ArgumentList '-ExecutionPolicy Bypass -NoExit -File $bootstrapPs1FileName'</Command>
  </LogonCommand>
</Configuration>
"@

$sandboxTestWsbFileName = 'SandboxTest.wsb'
$sandboxTestWsbFile = Join-Path -Path $tempFolder -ChildPath $sandboxTestWsbFileName
$sandboxTestWsbContent | Out-File $sandboxTestWsbFile

Write-Host 'Starting Windows Sandbox and trying to install the manifest file.'

WindowsSandbox $SandboxTestWsbFile