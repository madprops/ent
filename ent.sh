#!/usr/bin/env bash
ENGINE="ffmpeg"
VIEWER="ristretto"
RESOLUTION="800x600"

# Directory for generated images
output_dir="/media/struct3/ent"
mkdir -p "$output_dir"
latest_file="" # Variable to track the latest generated image

# Clean old images occasionally (keep last 20)
find "$output_dir" -name "noise_*.png" | sort | head -n -20 | xargs rm -f 2>/dev/null

generate_image() {
    # Get higher precision timestamp for better entropy
    timestamp=$(date +%s%N)
    seed=$(( $(echo "$timestamp" | cksum | cut -d ' ' -f1) % 1000000 ))

    # Generate multiple parameters based on seed with better distribution
    noise_amount=$(( seed % 101 ))
    hue_rotate=$(( (seed * 13) % 360 ))
    color_variation=$(( (seed * 17) % 5 ))
    pattern_type=$(( (seed * 7) % 4 ))
    texture_scale=$(( (seed * 23) % 10 + 1 ))

    # Calculate derived parameters
    seed_decimal=$(( seed % 100 ))
    seed_small=$(echo "scale=2; $seed_decimal / 100" | bc)
    hex_r=$(printf "%02x" $(( (seed * 31) % 256 )))
    hex_g=$(printf "%02x" $(( (seed * 43) % 256 )))
    hex_b=$(printf "%02x" $(( (seed * 61) % 256 )))

    # Create unique fractal coordinates
    m_start_x=$(echo "scale=6; -2.0 + $seed_small" | bc)
    m_start_y=$(echo "scale=6; -1.5 + $seed_small" | bc)
    m_bailout=$((10 + (seed % 90)))
    m_max_iter=$((50 + (seed % 150)))

    # Generate unique filename
    output_file="$output_dir/noise_$(date +%Y%m%d_%H%M%S_%N).png"

    # Get pattern name for debugging
    pattern_names=("Custom Sine Wave" "Fractal" "Game of Life" "Color Sine Wave")
    pattern_name="${pattern_names[$pattern_type]}"

    echo "Generating image with seed: $seed (Pattern: $pattern_name, noise: $noise_amount, hue: $hue_rotate)" >&2

    # Generate pattern with compatible parameters
    case $pattern_type in
        0) input="nullsrc=size=$RESOLUTION:duration=0.1,format=rgb24,geq=r='128+${noise_amount}*sin(X/10)':g='128+${texture_scale}*sin(Y/10)':b='128+${noise_amount}*sin((X+Y)/10)'" ;;
        1) input="mandelbrot=size=$RESOLUTION:rate=24:start_x=${m_start_x}:start_y=${m_start_y}:bailout=${m_bailout}:maxiter=${m_max_iter}" ;;
        2) input="life=size=$RESOLUTION:rate=24:ratio=${seed_small}:mold=${texture_scale%.*}:life_color=0x${hex_r}${hex_g}${hex_b}" ;;
        3) input="nullsrc=size=$RESOLUTION:duration=0.1,format=rgb24,geq=r='128+128*sin(${seed_small}*2*PI*X/W)':g='128+128*sin(${seed_small}*2*PI*Y/H)':b='128+128*sin(${seed_small}*2*PI*(X+Y)/(W+H))'" ;;
    esac

    # Color filter selection with seed-dependent parameters
    case $color_variation in
        0) color_filter="hue=h=${hue_rotate}:s=${texture_scale/10/1}" ;;
        1) color_filter="hue=h=${hue_rotate}:s=3,negate" ;;
        2) color_filter="colorbalance=rs=0.${seed_decimal}:gs=0.${seed_decimal}:bs=0.${seed_decimal}" ;;
        3) color_filter="eq=contrast=1.${seed_decimal}:brightness=0.${seed_decimal}" ;;
        4) color_filter="hue=h=${hue_rotate},colorchannelmixer=.${seed_decimal}:.${seed_decimal}:.${seed_decimal}:0" ;;
    esac

    # Fixed texture filter with valid range
    texture_filter="noise=alls=${noise_amount}:allf=t"
    filter_chain="${texture_filter},${color_filter}"

    # Generate the image
    error_file=$(mktemp)

    if $ENGINE -y -f lavfi -i "${input}" \
           -vf "${filter_chain}" \
           -frames:v 1 "$output_file" 2>"$error_file"; then
        echo "Image successfully generated as $output_file" >&2

        # Store the latest file path instead of creating symlink
        latest_file="$output_file"

        # Return the filename
        echo "$output_file"
        rm "$error_file"
    else
        echo "Error: Failed to generate image with pattern: $pattern_name" >&2
        cat "$error_file" >&2
        rm "$error_file"
        return 1
    fi
}

start_viewer() {
    # Check if $VIEWER is already running
    if ! pgrep -f "$VIEWER" >/dev/null; then
        # Create a placeholder image if needed
        if [ -z "$latest_file" ]; then
            generate_image >/dev/null
        fi

        # Launch Ristretto with the latest actual file
        $VIEWER "$latest_file" &

        # If you want a custom title, use wmctrl to rename the window after launch
        sleep 0.5
        wmctrl -r "$VIEWER" 2>/dev/null || true

        # Wait a moment for $VIEWER to start
        sleep 0.2
    fi
}

update_viewer() {
    # Check if viewer is running, if not start it
    if ! pgrep -f "$VIEWER" >/dev/null; then
        # Launch properly without title parameter
        $VIEWER "$latest_file" &

        # Set title if needed
        sleep 0.5
        wmctrl -r "$VIEWER" 2>/dev/null || true
    else
        # Close and reopen the viewer with the new image
        # This is more reliable than trying to refresh
        pkill -f "$VIEWER"
        sleep 0.5
        $VIEWER "$latest_file" &
        sleep 0.5
    fi
}

# Main script execution
if [ $# -eq 0 ]; then
    # Single image mode
    generate_image
    start_viewer
else
    # Auto refresh mode
    delay=$1

    # Generate first image and start viewer
    generate_image >/dev/null
    start_viewer

    echo "Starting auto-generation loop every $delay seconds. Press Ctrl+C to stop." >&2

    while true; do
        # Generate new image immediately rather than waiting first
        generate_image >/dev/null
        update_viewer

        # Sleep after generating/showing the image
        sleep "$delay"
    done
fi