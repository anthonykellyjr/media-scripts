#!/usr/bin/env python3
"""
remux_flexible.py - Flexible video remuxer for Linux/Unix

Usage:
    ./remux_flexible.py [-k|--keep-audio] [-o|--output-dir DIR] input_file.mkv
"""

import os
import sys
import re
import argparse
import subprocess
from pathlib import Path

# ANSI color codes
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

def check_ffmpeg():
    """Check if FFmpeg is installed."""
    print("Checking for FFmpeg...", end='')
    try:
        subprocess.run(['ffmpeg', '-version'], capture_output=True, check=True)
        print(f" {Colors.GREEN}✓ Found{Colors.NC}")
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(f" {Colors.RED}✗ Not found{Colors.NC}")
        print("Please install FFmpeg: sudo apt install ffmpeg")
        return False

def get_output_directory(input_file, specified_dir=None):
    """Determine the output directory based on priority."""
    # 1. Command line parameter
    if specified_dir and Path(specified_dir).is_dir():
        print(f"{Colors.BLUE}📁 Using specified output directory: {specified_dir}{Colors.NC}")
        return specified_dir
    
    # 2. Environment variable
    env_dir = os.environ.get('REMUX_OUTPUT_DIR')
    if env_dir and Path(env_dir).is_dir():
        print(f"{Colors.BLUE}📁 Using environment variable output directory: {env_dir}{Colors.NC}")
        return env_dir
    
    # 3. Same directory as input file
    input_dir = os.path.dirname(input_file)
    print(f"{Colors.BLUE}📁 Using input file directory: {input_dir}{Colors.NC}")
    return input_dir

def get_standardized_movie_name(filename):
    """Standardize movie filename to format: Title (Year) Source Resolution.mp4"""
    basename = os.path.basename(filename)
    name, ext = os.path.splitext(basename)
    
    # Check valid extension
    if ext.lower() not in ['.mp4', '.mkv', '.avi', '.mov']:
        return None
    
    # Regex patterns
    year_regex = r'(?<!\d)(19\d{2}|20\d{2}|210\d)(?!\d)'
    resolution_regex = r'(480p|720p|1080p|2160p|4K|8K)'
    source_regexes = [
        'BluRay', 'WEB[-\. ]?DL', 'WEB[-\. ]?Rip', 'HDRip', 'DVDRip',
        'HDCAM', 'HDTS', 'CAMRip', 'SCREENER', 'HMAX', 'AMZN', 'NF', 'HULU', 'BDRip'
    ]
    
    # Extract year (mandatory)
    year_match = re.search(year_regex, name)
    if not year_match:
        return None
    year = year_match.group()
    
    # Extract resolution
    resolution_match = re.search(resolution_regex, name, re.IGNORECASE)
    resolution = resolution_match.group() if resolution_match else "1080p"
    
    # Extract source
    source = "WEB"  # default
    for source_pattern in source_regexes:
        if re.search(source_pattern, name, re.IGNORECASE):
            source_match = re.search(source_pattern, name, re.IGNORECASE)
            source = source_match.group().replace('-', '').replace('.', '')
            break
    
    # Extract title (everything before year)
    title_match = re.match(rf'^(.+?)\s*\(?{year}', name)
    if title_match:
        title = title_match.group(1)
        # Clean up title
        title = re.sub(r'[._]', ' ', title)
        title = re.sub(r'\s+', ' ', title)
        title = title.strip()
    else:
        title = "Unknown"
    
    return f"{title} ({year}) {source} {resolution}.mp4"

def run_ffmpeg(input_file, output_file, keep_audio=False):
    """Run FFmpeg with appropriate settings."""
    print("Running FFmpeg...")
    
    if keep_audio:
        # Simple remux - copy all streams
        cmd = [
            'ffmpeg', '-i', input_file,
            '-map', '0', '-c', 'copy',
            '-movflags', '+faststart',
            output_file
        ]
    else:
        # Convert audio to AAC
        cmd = [
            'ffmpeg', '-i', input_file,
            '-map', '0:v', '-map', '0:a',
            '-c:v', 'copy',
            '-c:a', 'aac', '-b:a', '320k', '-ac', '2',
            '-movflags', '+faststart',
            output_file
        ]
    
    try:
        result = subprocess.run(cmd, check=True)
        return True
    except subprocess.CalledProcessError as e:
        print(f"{Colors.RED}❌ FFmpeg encountered an error. Exit code: {e.returncode}{Colors.NC}")
        return False

def verify_audio_codec(output_file):
    """Verify the audio codec of the output file."""
    print("\nVerifying audio codec...")
    try:
        cmd = [
            'ffprobe', '-v', 'error',
            '-select_streams', 'a:0',
            '-show_entries', 'stream=codec_name',
            '-of', 'default=noprint_wrappers=1:nokey=1',
            output_file
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        codec = result.stdout.strip()
        
        if 'aac' in codec.lower():
            print(f"{Colors.GREEN}✅ Audio successfully converted to AAC{Colors.NC}")
        else:
            print(f"{Colors.YELLOW}⚠️  Audio codec is: {codec} (expected AAC){Colors.NC}")
    except subprocess.CalledProcessError:
        print(f"{Colors.YELLOW}⚠️  Could not verify audio codec{Colors.NC}")

def main():
    parser = argparse.ArgumentParser(
        description='Flexible video remuxer with AAC audio conversion option',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
EXAMPLES:
    # Convert to AAC, save to specific directory
    %(prog)s -o /home/user/videos movie.mkv
    
    # Keep original audio, use environment variable
    export REMUX_OUTPUT_DIR="/media/converted"
    %(prog)s --keep-audio movie.mkv
    
    # Simple remux to same directory
    %(prog)s movie.mkv
        """
    )
    
    parser.add_argument('input_file', help='Input video file to process')
    parser.add_argument('-k', '--keep-audio', action='store_true',
                        help='Keep original audio instead of converting to AAC')
    parser.add_argument('-o', '--output-dir', help='Output directory (overrides REMUX_OUTPUT_DIR)')
    
    args = parser.parse_args()
    
    # Check FFmpeg
    if not check_ffmpeg():
        sys.exit(1)
    
    # Check input file exists
    if not Path(args.input_file).is_file():
        print(f"{Colors.RED}Error: File not found: {args.input_file}{Colors.NC}")
        sys.exit(1)
    
    # Get standardized filename
    new_filename = get_standardized_movie_name(args.input_file)
    if not new_filename:
        # Fallback: just change extension
        base = Path(args.input_file).stem
        new_filename = f"{base}.mp4"
        print(f"{Colors.YELLOW}Warning: Could not standardize filename. Using: {new_filename}{Colors.NC}")
    
    # Get output directory and construct output path
    output_dir = get_output_directory(args.input_file, args.output_dir)
    output_file = os.path.join(output_dir, new_filename)
    
    # Display mode
    mode = "REMUX (keeping original audio)" if args.keep_audio else "REMUX + AAC CONVERSION"
    print(f"\n{Colors.GREEN}🎬 Processing file in {mode} mode:{Colors.NC}")
    print(f"  Input:  {args.input_file}")
    print(f"  Output: {output_file}\n")
    
    # Run FFmpeg
    if run_ffmpeg(args.input_file, output_file, args.keep_audio):
        print(f"\n{Colors.GREEN}✅ Conversion complete!{Colors.NC}")
        print(f"Output file: {output_file}")
        
        # Verify audio codec if converted
        if not args.keep_audio:
            verify_audio_codec(output_file)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()