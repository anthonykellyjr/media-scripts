<#
.SYNOPSIS
    Flexible video remuxer with configurable output directory and audio conversion options.

.DESCRIPTION
    This script can either:
    - Remux video to MP4 with AAC audio conversion (default)
    - Remux video to MP4 keeping original audio (with -KeepAudio switch)
    
    Output directory can be specified via:
    - -OutputDir parameter
    - REMUX_OUTPUT_DIR environment variable
    - Default: Same directory as input file

.PARAMETER InputFile
    The full path to the video file you want to process. Required.

.PARAMETER OutputDir
    Directory where processed files will be saved. Optional.
    Falls back to $env:REMUX_OUTPUT_DIR, then input file directory.

.PARAMETER KeepAudio
    Switch to keep original audio instead of converting to AAC.

.EXAMPLE
    # Convert to AAC, save to specific directory
    remux_flexible.ps1 -InputFile "movie.mkv" -OutputDir "D:\Videos"
    
    # Keep original audio, use environment variable for output
    $env:REMUX_OUTPUT_DIR = "E:\Movies"
    remux_flexible.ps1 -InputFile "movie.mkv" -KeepAudio
    
    # Simple remux to MP4 keeping audio, output to same directory
    remux_flexible.ps1 "movie.mkv" -KeepAudio

.NOTES
    Set environment variable permanently in Windows:
    [System.Environment]::SetEnvironmentVariable("REMUX_OUTPUT_DIR", "C:\Videos", "User")
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$InputFile,
    
    [Parameter(Position=1)]
    [string]$OutputDir,
    
    [switch]$KeepAudio
)

# --- Configuration ---
$ffmpegPath = "ffmpeg"

# --- Functions ---

function Test-FFmpeg {
    Write-Host "Checking for FFmpeg..." -NoNewline
    try {
        & $ffmpegPath -version 2>&1 | Out-Null
        Write-Host " ✅ Found."
        return $true
    } catch {
        Write-Warning "FFmpeg not found. Please ensure it's installed and in your PATH."
        return $false
    }
}

function Get-OutputDirectory {
    param(
        [string]$InputFilePath,
        [string]$SpecifiedDir
    )
    
    # Priority order:
    # 1. Command line parameter
    if ($SpecifiedDir -and (Test-Path $SpecifiedDir -PathType Container)) {
        Write-Host "📁 Using specified output directory: $SpecifiedDir"
        return $SpecifiedDir
    }
    
    # 2. Environment variable
    if ($env:REMUX_OUTPUT_DIR -and (Test-Path $env:REMUX_OUTPUT_DIR -PathType Container)) {
        Write-Host "📁 Using environment variable output directory: $env:REMUX_OUTPUT_DIR"
        return $env:REMUX_OUTPUT_DIR
    }
    
    # 3. Same directory as input file
    $inputDir = Split-Path -Path $InputFilePath -Parent
    Write-Host "📁 Using input file directory: $inputDir"
    return $inputDir
}

function Get-StandardizedMovieName {
    param(
        [string]$Filename
    )

    $YearRegex = '(?<!\d)(19\d{2}|20\d{2}|210\d)(?!\d)'
    $ResolutionRegex = '(480p|720p|1080p|2160p|4K|8K)'
    $SourceRegexes = @('BluRay', 'WEB[-\. ]?DL', 'WEB[-\. ]?Rip', 'HDRip', 'DVDRip',
                       'HDCAM', 'HDTS', 'CAMRip', 'SCREENER', 'HMAX', 'AMZN', 'NF', 'HULU', 'BDRip')

    $name = [System.IO.Path]::GetFileNameWithoutExtension($Filename)
    $ext = [System.IO.Path]::GetExtension($Filename).ToLower()

    if ($ext -notin @('.mp4', '.mkv', '.avi', '.mov')) {
        return $null
    }

    $parts = $name.Split(".-_ ()[]") | Where-Object { $_ }

    $year = $null
    $resolution = $null
    $source = $null
    $titleParts = @()
    $remaining = $false

    foreach ($part in $parts) {
        if ($part -match $YearRegex -and -not $year) {
            $year = $matches[0]
            $remaining = $true
        } elseif ($remaining) {
            $currentSource = $SourceRegexes | Where-Object { $part -match $_ -and -not $source }
            if ($currentSource) {
                $source = $part
            }
            if ($part -match $ResolutionRegex -and -not $resolution) {
                $resolution = $part
            }
        } else {
            $titleParts += $part
        }
    }

    if (-not $year) {
        return $null
    }
    if (-not $resolution) {
        $resolution = "1080p"
    }
    if (-not $source) {
        $source = "WEB"
    }

    $source = $source -replace '[-\.]', ''
    $title = ($titleParts -join ' ') -replace '\s+', ' '
    $newFilename = "$title ($year) $source $resolution.mp4"
    $newFilename = $newFilename -replace '\.+', '.' -replace '_', ' '
    
    return $newFilename.Trim()
}

# --- Main Script Logic ---

if (-not (Test-FFmpeg)) {
    return
}

if (-not (Test-Path -Path $InputFile -PathType Leaf)) {
    Write-Warning "File not found: $InputFile"
    return
}

# Get the new filename
$newFilename = Get-StandardizedMovieName -Filename (Split-Path -Path $InputFile -Leaf)
if (-not $newFilename) {
    # If standardization fails, just change the extension
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $newFilename = "$baseName.mp4"
    Write-Warning "Could not standardize filename. Using: $newFilename"
}

# Determine output directory
$outputDirectory = Get-OutputDirectory -InputFilePath $InputFile -SpecifiedDir $OutputDir
$outputFile = Join-Path -Path $outputDirectory -ChildPath $newFilename

# Display conversion mode
$mode = if ($KeepAudio) { "REMUX (keeping original audio)" } else { "REMUX + AAC CONVERSION" }
Write-Host "`n🎬 Processing file in $mode mode:"
Write-Host "  Input:  $InputFile"
Write-Host "  Output: $outputFile`n"

# Build FFmpeg command based on mode
Write-Host "Running FFmpeg..."
try {
    if ($KeepAudio) {
        # Simple remux - copy all streams
        & $ffmpegPath -i "$InputFile" -map 0 -c copy -movflags +faststart "$outputFile"
    } else {
        # Convert audio to AAC
        & $ffmpegPath -i "$InputFile" -map 0:v -map 0:a -c:v copy -c:a aac -b:a 320k -ac 2 -movflags +faststart "$outputFile"
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Conversion complete!`n"
        Write-Host "Output file: $outputFile"
        
        # Verify audio codec if converted
        if (-not $KeepAudio) {
            Write-Host "`nVerifying audio codec..."
            $audioCodec = & ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$outputFile" 2>&1
            if ($audioCodec -match "aac") {
                Write-Host "✅ Audio successfully converted to AAC"
            } else {
                Write-Warning "⚠️ Audio codec is: $audioCodec (expected AAC)"
            }
        }
    } else {
        Write-Warning "`n❌ FFmpeg encountered an error. Exit code: $LASTEXITCODE`n"
    }
} catch {
    Write-Error "Error running FFmpeg: $_"
}