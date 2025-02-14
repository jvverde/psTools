param (
  [Parameter(Mandatory,Position=0)]
  [string]$filename
)

try {
  if (-Not (Test-Path -Path $filename)) {
    Write-Error "The file [$filename] doesn't exist"
  }
  $vhd=Mount-VHD -Path $filename
  $partitions=$vhd|get-Disk|get-partition
  foreach ($p IN ($partitions |where {($_ |Get-volume) -ne $Null})) {
    #from https://stackoverflow.com/questions/12488030/getting-a-free-drive-letter
    $d = ls function:[d-z]: -n | ?{ !(test-path $_) } | random
    $p|Add-PartitionAccessPath -AccessPath $d
  }

} catch {
    Write-Error $_.Exception.Message  
}


