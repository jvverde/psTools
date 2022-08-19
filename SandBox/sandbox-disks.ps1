#https://www.aaflalo.me/2021/04/windows-sandboxing-and-winget/
#https://gist.github.com/Belphemur/0d8d6ef7e047ffa67b050d40ec983b56#file-sandbox-winget-ps1
#https://megamorf.gitlab.io/2020/07/19/automating-the-windows-sandbox/

# Parse Arguments

Param(
)

# Check if Windows Sandbox is enabled

if (-Not (Test-Path "$env:windir\System32\WindowsSandbox.exe")) {
  Write-Error -Category NotInstalled -Message @'
Windows Sandbox does not seem to be available. Check the following URL for prerequisites and further details:    
https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-sandbox/windows-sandbox-overview
  
You can run the following command in an elevated PowerShell for enabling Windows Sandbox:
Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM'
'@ -ErrorAction Stop
}


# Create Bootstrap script

$bootstrapPs1Content = @"
Write-Host 'Here I am'
#start cmd /k
"@

$bootstrapPs1FileName = 'Bootstrap.ps1'

$SandboxDir = Join-Path -Path $PSScriptRoot -ChildPath '.sandboxDir'

New-Item $SandboxDir -ItemType Directory -ea 0 | Out-Null

$bootstrapPs1Content | Out-File (Join-Path -Path $SandboxDir -ChildPath $bootstrapPs1FileName)

# Create Wsb file

$tempFolderInSandbox = Join-Path -Path 'C:\Users\WDAGUtilityAccount\Desktop' -ChildPath (Split-Path $SandboxDir -Leaf)

$res = Get-PSDrive -PSProvider "FileSystem"| Select-Object Name,DisplayRoot,Free | where {$_.DisplayRoot -notmatch 'sshfs' -and $_.Free -ne $null }| %{
@"

  <MappedFolder>
    <HostFolder>$($_.Name):\</HostFolder>
    <SandboxFolder>C:\Users\WDAGUtilityAccount\Desktop\DISK-$($_.Name)</SandboxFolder>
    <ReadOnly>true</ReadOnly>
  </MappedFolder>

"@
}

$sandboxDisksWsbContent = @"
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$SandboxDir</HostFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    $res
  </MappedFolders>
  <LogonCommand>
  <Command>PowerShell Start-Process PowerShell -WorkingDirectory '$tempFolderInSandbox' -ArgumentList '-ExecutionPolicy Bypass -NoExit -File $bootstrapPs1FileName'</Command>
  </LogonCommand>
</Configuration>
"@

$sandboxDisksWsbFileName = 'SandboxDisks.wsb'
$sandboxDisksWsbFile = Join-Path -Path $SandboxDir -ChildPath $sandboxDisksWsbFileName
$sandboxDisksWsbContent | Out-File $sandboxDisksWsbFile

Write-Host 'Starting Windows Sandbox and trying to install the manifest file.'

WindowsSandbox $sandboxDisksWsbFile