#!/bin/bash

# Check params file
if [ -z "$1" ]; then
    echo "Usage: $0 params.yml"
    exit 1
fi

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg is not installed."
    exit 1
fi

# Params file
PARAM_FILE="$1"

# Output video name
OUTPUT=$(grep '^OUTPUT:' "$PARAM_FILE" | awk '{print $2}')
OUTPUT=${OUTPUT:-"output.png"}

# User token
TOKEN=$(grep '^TOKEN:' "$PARAM_FILE" | awk '{print $2}')

# Last index of segments
LAST_SEGMENT=$(grep '^LAST_SEGMENT:' "$PARAM_FILE" | awk '{print $2}')

# Video and audion base URLs
VIDEO_BASE_URL=$(grep '^VIDEO_BASE_URL:' "$PARAM_FILE" | awk '{print $2}')
AUDIO_BASE_URL=$(grep '^AUDIO_BASE_URL:' "$PARAM_FILE" | awk '{print $2}')

# Check if file already exists
if [ -f "$OUTPUT" ]; then
    echo "Error: Output file '$OUTPUT' already exists."
    exit 1
fi

# Check required params
if [ -z "$LAST_SEGMENT" ] || [ -z "$VIDEO_BASE_URL" ]; then
    echo "Error: LAST_SEGMENT and VIDEO_BASE_URL params required."
    exit 1
fi

# Function to display the progress bar
show_progress() {
    local length=50

    local progress=$1
    local total_steps=$2
    local filled=$((progress * length / total_steps))
    local empty=$((length - filled))
    
    # Build the progress bar
    local bar=$(printf "%0.s=" $(seq 1 $filled))
    local spaces=""
    
    # Only add spaces if progress is not 100%
    if [ "$progress" -lt "$total_steps" ]; then
        spaces=$(printf "%0.s " $(seq 1 $empty))
    fi
    
    # Calculate the percentage
    local percent=$((progress * 100 / total_steps))
    
    # Display the progress bar with current step and total steps
    printf "\rProgress: [${bar}${spaces}] %d%% (%d/%d)" "$percent" "$progress" "$total_steps"
}

# Default temporary directory
TEMP_DIR="./"

# Remove temporary directory
rm -rf "./tmp"

# Create temporary directory
if mkdir "./tmp"; then
    TEMP_DIR="./tmp"
fi

echo "Starting download of $((LAST_SEGMENT + 1)) segments."

for i in $(seq 0 $LAST_SEGMENT); do

    # Download video segments in parallel 
    wget -q "${VIDEO_BASE_URL}/seg_${i}.ts?viewerToken=${TOKEN}" -O "${TEMP_DIR}/video_seg_${i}.ts" &

    if [ -n "$AUDIO_BASE_URL" ]; then
        # Download audio segments in parallel 
        wget -q "${AUDIO_BASE_URL}/seg_${i}.aac" -O "${TEMP_DIR}/audio_seg_${i}.aac" &
    fi

    # Update progress
    show_progress $i $LAST_SEGMENT

    # Wait for downloading
    wait
done

# Final progress update
show_progress $LAST_SEGMENT $LAST_SEGMENT
echo -e "\nAll segments downloaded."

# Create file lists for ffmpeg
for i in $(seq 0 $LAST_SEGMENT); do
    echo "file 'video_seg_${i}.ts'" >> "${TEMP_DIR}/video_list.txt"

    if [ -n "$AUDIO_BASE_URL" ]; then
        echo "file 'audio_seg_${i}.aac'" >> "${TEMP_DIR}/audio_list.txt"
    fi
done

# Merge video segments separately
echo "Merging video segments..."
ffmpeg -f concat -safe 0 -i "${TEMP_DIR}/video_list.txt" -c copy "${TEMP_DIR}/merged_video.mp4" > /dev/null 2>&1

if [ -n "$AUDIO_BASE_URL" ]; then
    # Merge audio segments separately
    echo "Merging audio segments..."
    ffmpeg -f concat -safe 0 -i "${TEMP_DIR}/audio_list.txt" -c copy "${TEMP_DIR}/merged_audio.aac" > /dev/null 2>&1

    # Combine the merged video and audio into the final output
    echo "Combining video and audio into final file..."
    ffmpeg -i "${TEMP_DIR}/merged_video.mp4" -i "${TEMP_DIR}/merged_audio.aac" -c:v copy -c:a aac -strict experimental "${OUTPUT}" > /dev/null 2>&1
else
    mv "${TEMP_DIR}/merged_video.mp4" "${OUTPUT}"
fi

# Cleanup
if [ "$TEMP_DIR" = "./" ]; then
    rm -f video_seg_*.ts audio_seg_*.aac video_list.txt audio_list.txt merged_video.mp4 merged_audio.aac
else
    rm -rf "${TEMP_DIR}"
fi

echo "Download and merging complete. Final video saved as ${OUTPUT}."
