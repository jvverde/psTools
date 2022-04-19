#Borrow from https://stackoverflow.com/a/27572703
function Get-Usage {
    #.Synopsis
    #  Calculate the size of a folder on disk
    #.Description
    #  Recursively calculate the size of a folder on disk,
    #  outputting it's size, and that of all it's children,
    #  and optionally, all of their children
    param(
        [string]$root=$PWD,
        # Show the size for each descendant recursively (otherwise, only immediate children)
        [Int]$Depth=1,
        [Switch]$Force
    )
    # Get the full canonical FileSystem path:
    $root = Convert-Path $root
    $DetailDepth = $Depth - 1
    $size = 0
    $files = 0
    $folders = 0
    $items = Get-ChildItem $root -Force:$Force
    foreach($item in $items) {
        if($item.PSIsContainer) {

            # Clear subItem in case the directory is empty.
            $subItem = @{ Folders = 0
                Files = 0
                Size = 0
                Name = $item.FullName }


            # Call myself recursively to calculate subfolder size
            # Since we're streaming output as we go, 
            #   we only use the last output of a recursive call
            #   because that's the summary object
            if($DetailDepth -ge 1) {
                Get-Usage $item.FullName -Depth $DetailDepth -Force:$Force | Tee-Object -Variable subItems
                if($subItems.GetType().FullName -eq "System.Management.Automation.PSCustomObject") {
                    $subItem = $subItems
                } else {
                    $subItem = $subItems[-1]
                }
            } else {

                $subItem = Get-Usage $item.FullName -Force:$Force | Select -Last 1
            }
            # The (recursive) size of all subfolders gets added
            $size += $subItem.Size
            $folders += $subItem.Folders + 1
            $files += $subItem.Files
            # avoid duplication by letting the parent report the summary values, except at the lowest detail depth
            if( $DetailDepth -lt 1) { 
                Write-Output $subItem
            }
        } else {
            $files += 1
            $size += $item.Length
        }
    }

    # in PS3, use the CustomObject trick to control the output order
    if($PSVersionTable.PSVersion -ge "3.0") {
        [PSCustomObject]@{ 
            Folders = $folders
            Files = $files
            Size = $size
            Name = $root
        }
    } else {
        New-Object PSObject -Property @{ 
            Folders = $folders
            Files = $files
            Size = $size
            Name = $root
        }
    }
}