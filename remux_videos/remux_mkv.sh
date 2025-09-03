#!/bin/bash

# remux_flexible.sh - Flexible video remuxer for Linux
# Usage: ./remux_flexible.sh [-k|--keep-audio] [-o|--output-dir DIR] input_file.mkv

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
KEEP_AUDIO=false
OUTPUT_DIR=""
FFMPEG_PATH="ffmpeg"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] INPUT_FILE

OPTIONS:
    -k, --keep-audio        Keep original audio instead of converting to AAC
    -o, --output-dir DIR    Specify output directory (overrides REMUX_OUTPUT_DIR)
    -h, --help              Show this help message

ENVIRONMENT:
    REMUX_OUTPUT_DIR        Default output directory if -o not specified

EXAMPLES:
    # Convert to AAC, save to specific directory
    $0 -o /home/user/videos movie.mkv
    
    # Keep original audio, use environment variable
    export REMUX_OUTPUT_DIR="/media/converted"
    $0 --keep-audio movie.mkv
    
    # Simple remux to same directory
    $0 movie.mkv

EOF
    exit 1
}

# Function to check if ffmpeg is installed
check_ffmpeg() {
    echo -n "Checking for FFmpeg..."
    if command -v "$FFMPEG_PATH" &> /dev/null; then
        echo -e " ${GREEN}✓ Found${NC}"
        return 0
    else
        echo -e " ${RED}✗ Not found${NC}"
        echo "Please install FFmpeg: sudo apt install ffmpeg"
        return 1
    fi
}

# Function to get output directory
get_output_directory() {
    local input_file="$1"
    local specified_dir="$2"
    
    # Priority order:
    # 1. Command line parameter
    if [[ -n "$specified_dir" ]] && [[ -d "$specified_dir" ]]; then
        echo -e "${BLUE}📁 Using specified output directory: $specified_dir${NC}"
        echo "$specified_dir"
        return
    fi
    
    # 2. Environment variable
    if [[ -n "$REMUX_OUTPUT_DIR" ]] && [[ -d "$REMUX_OUTPUT_DIR" ]]; then
        echo -e "${BLUE}📁 Using environment variable output directory: $REMUX_OUTPUT_DIR${NC}"
        echo "$REMUX_OUTPUT_DIR"
        return
    fi
    
    # 3. Same directory as input file
    local input_dir=$(dirname "$input_file")
    echo -e "${BLUE}📁 Using input file directory: $input_dir${NC}"
    echo "$input_dir"
}

# Function to standardize movie filename
get_standardized_movie_name() {
    local filename="$1"
    local basename=$(basename "$filename")
    local name="${basename%.*}"
    local ext="${basename##*.}"
    
    # Check if extension is valid
    if [[ ! "$ext" =~ ^(mp4|mkv|avi|mov)$ ]]; then
        return 1
    fi
    
    # Extract year (1900-2109)
    local year=""
    if [[ "$name" =~ (19[0-9]{2}|20[0-9]{2}|210[0-9]) ]]; then
        year="${BASH_REMATCH[1]}"
    else
        return 1  # Year is mandatory
    fi
    
    # Extract resolution
    local resolution=""
    if [[ "$name" =~ (480p|720p|1080p|2160p|4K|8K) ]]; then
        resolution="${BASH_REMATCH[1]}"
    else
        resolution="1080p"
    fi
    
    # Extract source
    local source=""
    if [[ "$name" =~ (BluRay|WEB[-. ]?DL|WEB[-. ]?Rip|HDRip|DVDRip|HDCAM|HDTS|CAMRip|SCREENER|HMAX|AMZN|NF|HULU|BDRip) ]]; then
        source="${BASH_REMATCH[1]}"
        # Clean up source name
        source=$(echo "$source" | sed 's/[-.]//g')
    else
        source="WEB"
    fi
    
    # Extract title (everything before the year)
    local title=""
    if [[ "$name" =~ ^(.+)[[:space:]]*\(?$year ]]; then
        title="${BASH_REMATCH[1]}"
        # Clean up title
        title=$(echo "$title" | sed 's/[._]/ /g' | sed 's/  */ /g' | sed 's/ *$//')
    fi
    
    # Construct new filename
    local new_filename="$title ($year) $source $resolution.mp4"
    echo "$new_filename"
}

# Parse command line arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--keep-audio)
            KEEP_AUDIO=true
            shift
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*|--*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

# Check if input file was provided
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: No input file specified${NC}"
    usage
fi

INPUT_FILE="$1"

# Main script logic
if ! check_ffmpeg; then
    exit 1
fi

# Check if input file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}Error: File not found: $INPUT_FILE${NC}"
    exit 1
fi

# Get standardized filename
NEW_FILENAME=$(get_standardized_movie_name "$INPUT_FILE")
if [[ -z "$NEW_FILENAME" ]]; then
    # Fallback: just change extension
    BASENAME=$(basename "$INPUT_FILE")
    NEW_FILENAME="${BASENAME%.*}.mp4"
    echo -e "${YELLOW}Warning: Could not standardize filename. Using: $NEW_FILENAME${NC}"
fi

# Get output directory
OUTPUT_DIRECTORY=$(get_output_directory "$INPUT_FILE" "$OUTPUT_DIR")
OUTPUT_FILE="$OUTPUT_DIRECTORY/$NEW_FILENAME"

# Display conversion mode
if $KEEP_AUDIO; then
    MODE="REMUX (keeping original audio)"
else
    MODE="REMUX + AAC CONVERSION"
fi

echo -e "\n${GREEN}🎬 Processing file in $MODE mode:${NC}"
echo -e "  Input:  $INPUT_FILE"
echo -e "  Output: $OUTPUT_FILE\n"

# Build and execute FFmpeg command
echo "Running FFmpeg..."
if $KEEP_AUDIO; then
    # Simple remux - copy all streams
    "$FFMPEG_PATH" -i "$INPUT_FILE" -map 0 -c copy -movflags +faststart "$OUTPUT_FILE"
else
    # Convert audio to AAC
    "$FFMPEG_PATH" -i "$INPUT_FILE" -map 0:v -map 0:a -c:v copy -c:a aac -b:a 320k -ac 2 -movflags +faststart "$OUTPUT_FILE"
fi

# Check result
if [[ $? -eq 0 ]]; then
    echo -e "\n${GREEN}✅ Conversion complete!${NC}"
    echo -e "Output file: $OUTPUT_FILE"
    
    # Verify audio codec if converted
    if ! $KEEP_AUDIO; then
        echo -e "\nVerifying audio codec..."
        AUDIO_CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>&1)
        if [[ "$AUDIO_CODEC" == *"aac"* ]]; then
            echo -e "${GREEN}✅ Audio successfully converted to AAC${NC}"
        else
            echo -e "${YELLOW}⚠️  Audio codec is: $AUDIO_CODEC (expected AAC)${NC}"
        fi
    fi
else
    echo -e "\n${RED}❌ FFmpeg encountered an error. Exit code: $?${NC}"
    exit 1
fi