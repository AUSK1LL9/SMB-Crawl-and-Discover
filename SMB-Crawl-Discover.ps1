<#
.SYNOPSIS
    Crawls through an SMB share and lists all directories the current user has access to.

.DESCRIPTION
    This script takes an SMB share path (e.g., \\server\share) as input.
    It attempts to list directories at the specified path and recursively
    explores subdirectories to identify all accessible directories.
    
.PARAMETER SmbPath
    The UNC path to the SMB share (e.g., \\server\share). This parameter is mandatory.

.PARAMETER Recurse
    A switch parameter. If present, the script will recursively crawl through
    all subdirectories. If omitted, it will only list directories at the top level
    of the specified SmbPath.

.EXAMPLE
    # List top-level accessible directories on a share
    .\Get-AccessibleSmbDirectories.ps1 -SmbPath '\\YourServer\YourShare'

.EXAMPLE
    # Recursively list all accessible directories on a share
    .\Get-AccessibleSmbDirectories.ps1 -SmbPath '\\AnotherServer\Data' -Recurse

.NOTES
    - Ensure the user running this script has network access to the SMB share.
    - This script uses 'Get-ChildItem' which might be slow on very large shares.
    - 'Access Denied' errors are caught and logged, preventing script termination.
    - 'Path Not Found' errors for the initial share path are also handled.
    - The script outputs the full UNC path of each accessible directory.
#>
function Get-AccessibleSmbDirectories {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, HelpMessage="The UNC path to the SMB share (e.g., \\\\server\\share).")]
        [string]$SmbPath,

        [Parameter(HelpMessage="If present, recursively crawl through subdirectories.")]
        [switch]$Recurse
    )

    # Validate SMB path format
    if (-not ($SmbPath -like '\\\*')) {
        Write-Warning "Invalid SMB path format. Path must start with '\\'. Example: \\server\share"
        return
    }

    Write-Host "Starting directory crawl for SMB share: '$SmbPath'" -ForegroundColor Cyan
    Write-Host "Recursion enabled: $($Recurse.IsPresent)" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor DarkGray

    $accessibleDirectories = New-Object System.Collections.Generic.List[string]

    # Use a queue for breadth-first traversal, especially useful for recursion
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue($SmbPath)

    while ($queue.Count -gt 0) {
        $currentPath = $queue.Dequeue()

        try {
            # Attempt to list directories in the current path
            # -ErrorAction Stop will convert non-terminating errors (like Access Denied) into terminating ones
            # so they can be caught by the 'catch' block.
            $dirs = Get-ChildItem -Path $currentPath -Directory -ErrorAction Stop

            # If Get-ChildItem succeeds, the current path is accessible
            $accessibleDirectories.Add($currentPath)
            Write-Host "Accessible: $currentPath" -ForegroundColor Green

            if ($Recurse.IsPresent) {
                foreach ($dir in $dirs) {
                    # Add subdirectories to the queue for further processing
                    $queue.Enqueue($dir.FullName)
                }
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-Warning "Access Denied: $($currentPath) - $($_.Exception.Message)"
        }
        catch [System.IO.DirectoryNotFoundException] {
            # This can happen if a path was valid but then removed, or if there's a typo in the initial path
            Write-Warning "Path Not Found: $($currentPath) - $($_.Exception.Message)"
            if ($currentPath -eq $SmbPath) {
                Write-Error "The initial SMB share path '$SmbPath' was not found or is inaccessible."
                return # Exit if the initial path is not found
            }
        }
        catch {
            Write-Warning "An unexpected error occurred for $($currentPath): $($_.Exception.Message)"
        }
    }

    Write-Host "----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Crawl complete. Found $($accessibleDirectories.Count) accessible directories." -ForegroundColor Cyan

    # Return the list of accessible directories
    return $accessibleDirectories
}

# --- Script Execution ---
# Check if the script is being run directly or sourced
if ($Pscmdlet) {
    # If running as a function (e.g., in an interactive session after sourcing)
    # The user will call Get-AccessibleSmbDirectories directly
} else {
    # If running as a script file
    # Parse command line arguments and call the function
    $script:SmbPath = $null
    $script:Recurse = $false

    # Simple argument parsing for direct script execution
    # For more robust parsing, consider using Param() block at script level or ArgParse module
    for ($i = 0; $i -lt $args.Length; $i++) {
        if ($args[$i] -eq '-SmbPath') {
            $script:SmbPath = $args[$i+1]
            $i++
        } elseif ($args[$i] -eq '-Recurse') {
            $script:Recurse = $true
        }
    }

    if (-not $script:SmbPath) {
        Write-Error "Error: -SmbPath parameter is mandatory when running the script directly."
        Write-Host "Usage: .\Get-AccessibleSmbDirectories.ps1 -SmbPath '\\server\share' [-Recurse]"
    } else {
        Get-AccessibleSmbDirectories -SmbPath $script:SmbPath -Recurse:$script:Recurse
    }
}
