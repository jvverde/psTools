
function Get-Perms {
	[CmdletBinding()]
    param(
        [string]$Path=$PWD,
		[Alias('i')]
		[bool]$Inherited,
		[Alias('r')]
		[switch]$Recurse=$false
    )
	function getacl ([string]$path) {
		$Acl = Get-Acl -Path $path
		$res = @()
		ForEach ($Access in $Acl.Access) {
			$Properties = [ordered]@{
				'Folder Name'=$path;
				'Group/User'=$Access.IdentityReference;
				'Permissions'=$Access.FileSystemRights;
				Type=$Access.AccessControlType;
				'Inherited'=$Access.IsInherited
			}
			$res += New-Object -TypeName PSObject -Property $Properties            
		}
		$res
	}
	$Output = @()
    $root = Convert-Path $Path
	$Output += getacl "$root"
	if ($Recurse) {
		$Folders = Get-ChildItem -Path "$root" -Recurse -Force
		ForEach ($Folder in $Folders) {
			$Output += getacl $Folder.FullName
		}
	}
	Write-Host "IsInherited=$IsInherited"
	if ($PSBoundParameters.ContainsKey('Inherited')) {
		Write-Host "Constains"
		$Output | where Inherited -eq $Inherited
	} else {
		Write-Host "not"
		$Output
	}
}