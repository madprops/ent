#!/usr/bin/env fish
set ENGINE "ffmpeg"
set VIEWER "ristretto"
set RESOLUTION "800x600"

# Directory for generated images
set output_dir "/media/struct3/ent"
mkdir -p $output_dir
set -g latest_file "" # Variable to track the latest generated image

# Clean old images occasionally (keep last 20)
find $output_dir -name "noise_*.png" | sort | head -n -20 | xargs rm -f 2>/dev/null

function generate_image
    # Get higher precision timestamp for better entropy
    set timestamp (date +%s%N)
    set seed (math (echo $timestamp | cksum | cut -d ' ' -f1) % 1000000)

    # Generate multiple parameters based on seed with better distribution
    set noise_amount (math "$seed % 101")
    set hue_rotate (math "($seed * 13) % 360")
    set color_variation (math "($seed * 17) % 5")
    set pattern_type (math "($seed * 7) % 4")
    set texture_scale (math "($seed * 23) % 10 + 1")

    # Calculate derived parameters
    set seed_decimal (math "$seed % 100")
    set seed_small (echo "scale=2; $seed_decimal / 100" | bc)
    set hex_r (printf "%02x" (math "($seed * 31) % 256"))
    set hex_g (printf "%02x" (math "($seed * 43) % 256"))
    set hex_b (printf "%02x" (math "($seed * 61) % 256"))

    # Create unique fractal coordinates
    set m_start_x (echo "scale=6; -2.0 + $seed_small" | bc)
    set m_start_y (echo "scale=6; -1.5 + $seed_small" | bc)
    set m_bailout (math "10 + ($seed % 90)")
    set m_max_iter (math "50 + ($seed % 150)")

    # Generate unique filename
    set output_file "$output_dir/noise_"(date +%Y%m%d_%H%M%S_%N)".png"

    # Get pattern name for debugging
    set pattern_names "Custom Sine Wave" "Fractal" "Game of Life" "Color Sine Wave"
    set pattern_name $pattern_names[(math "$pattern_type + 1")] # Fish arrays are 1-indexed

    echo "Generating image with seed: $seed (Pattern: $pattern_name, noise: $noise_amount, hue: $hue_rotate)" >&2

    # Generate pattern with compatible parameters
    switch $pattern_type
        case 0
            set input "nullsrc=size=$RESOLUTION:duration=0.1,format=rgb24,geq=r='128+$noise_amount*sin(X/10)':g='128+$texture_scale*sin(Y/10)':b='128+$noise_amount*sin((X+Y)/10)'"
        case 1
            set input "mandelbrot=size=$RESOLUTION:rate=24:start_x=$m_start_x:start_y=$m_start_y:bailout=$m_bailout:maxiter=$m_max_iter"
        case 2
            set texture_scale_int (string replace -r '\..*$' '' $texture_scale)
            set input "life=size=$RESOLUTION:rate=24:ratio=$seed_small:mold=$texture_scale_int:life_color=0x$hex_r$hex_g$hex_b"
        case 3
            set input "nullsrc=size=$RESOLUTION:duration=0.1,format=rgb24,geq=r='128+128*sin($seed_small*2*PI*X/W)':g='128+128*sin($seed_small*2*PI*Y/H)':b='128+128*sin($seed_small*2*PI*(X+Y)/(W+H))'"
    end

    # Color filter selection with seed-dependent parameters
    switch $color_variation
        case 0
            set texture_scale_div (math "$texture_scale / 10")
            set color_filter "hue=h=$hue_rotate:s=$texture_scale_div"
        case 1
            set color_filter "hue=h=$hue_rotate:s=3,negate"
        case 2
            set color_filter "colorbalance=rs=0.$seed_decimal:gs=0.$seed_decimal:bs=0.$seed_decimal"
        case 3
            set color_filter "eq=contrast=1.$seed_decimal:brightness=0.$seed_decimal"
        case 4
            set color_filter "hue=h=$hue_rotate,colorchannelmixer=.$seed_decimal:.$seed_decimal:.$seed_decimal:0"
    end

    # Fixed texture filter with valid range
    set texture_filter "noise=alls=$noise_amount:allf=t"
    set filter_chain "$texture_filter,$color_filter"

    # Generate the image
    set error_file (mktemp)

    if $ENGINE -y -f lavfi -i "$input" -vf "$filter_chain" -frames:v 1 "$output_file" 2>$error_file
        echo "Image successfully generated as $output_file" >&2

        # Store the latest file path
        set -g latest_file "$output_file"

        # Return the filename
        echo "$output_file"
        rm "$error_file"
    else
        echo "Error: Failed to generate image with pattern: $pattern_name" >&2
        cat "$error_file" >&2
        rm "$error_file"
        return 1
    end
end

function start_viewer
    # Check if $VIEWER is already running
    if not pgrep -f "$VIEWER" >/dev/null
        # Create a placeholder image if needed
        if test -z "$latest_file"
            generate_image >/dev/null
        end

        # Launch Ristretto with the latest actual file
        $VIEWER "$latest_file" &

        # If you want a custom title, use wmctrl to rename the window after launch
        sleep 0.5
        wmctrl -r "$VIEWER" 2>/dev/null; or true

        # Wait a moment for $VIEWER to start
        sleep 0.2
    end
end

function update_viewer
    # Check if viewer is running, if not start it
    if not pgrep -f "$VIEWER" >/dev/null
        # Launch properly without title parameter
        $VIEWER "$latest_file" &

        # Set title if needed
        sleep 0.5
        wmctrl -r "$VIEWER" 2>/dev/null; or true
    else
        # Close and reopen the viewer with the new image
        pkill -f "$VIEWER"
        sleep 0.5
        $VIEWER "$latest_file" &
        sleep 0.5
    end
end

# Main script execution
if test (count $argv) -eq 0
    # Single image mode
    generate_image
    start_viewer
else
    # Auto refresh mode
    set delay $argv[1]

    # Generate first image and start viewer
    generate_image >/dev/null
    start_viewer

    echo "Starting auto-generation loop every $delay seconds. Press Ctrl+C to stop." >&2

    while true
        # Generate new image immediately
        generate_image >/dev/null
        update_viewer

        # Sleep after generating/showing the image
        sleep $delay
    end
end