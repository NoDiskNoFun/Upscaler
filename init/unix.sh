#!/bin/sh
#
# BSD 3-Clause License
#
# Copyright (c) 2023, (Holloway) Chew, Kean Ho
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#############
# variables #
#############
repo="$(command -v $0)"
repo="${repo%%init/unix.sh}"

# arguments
action='run'
model="${UPSCALER_MODEL:-""}"
scale="${UPSCALER_SCALE:-0}"
source_file=""
output=""
format=""

# variables
video_mode=0
create_snippets=0
program=''
model_id=''
model_name=''
model_max_scale=''
subject_name=''
subject_ext=''
subject_dir=''
subject_suffix="${UPSCALER_SUFFIX:-"upscaled"}"
workspace=''
phase=0
max_workers_frame_extraction=1
max_workers_ai_upscale=1
job_size_in_frames=50
job_start_id=0
upscaling_done=0
skip_frame_check=0

#############
# functions #
#############

# Kill all workers on CTRL+C
trap 'printf "\n"; _print_status error "All Jobs have been canceled!"; kill 0' SIGINT

_print_status() {
        __status_mode="$1" && shift 1
        __msg=""
        __stop_color="\033[0m"
        case "$__status_mode" in
        error)
                __msg="[ ERROR   ] ${@}"
                __start_color="\e[91m"
                ;;
        warning)
                __msg="[ WARNING ] ${@}"
                __start_color="\e[93m"
                ;;
        info)
                __msg="[ INFO    ] ${@}"
                __start_color="\e[96m"
                ;;
        success)
                __msg="[ SUCCESS ] ${@}"
                __start_color="\e[92m"
                ;;
        ok)
                __msg="[ INFO    ] == OK =="
                __start_color="\e[96m"
                ;;
        plain)
                __msg="$@"
                ;;
        *)
                return 0
                ;;
        esac


        if [ $(tput colors) -ge 8 ]; then
                __msg="${__start_color}${__msg}${__stop_color}"
        fi


        1>&2 printf "${__msg}"
        unset __status_mode __msg __start_color __stop_color


        return 0
}

calculate_eta() {

        percent_done=$(cat /tmp/${subject_name}/.percent_done)
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        if [ "$percent_done" -gt 0 ]
        then
                        estimated_total_time=$((elapsed * 100 / $percent_done))
                        eta=$((estimated_total_time - elapsed))
        else
                eta=0
        fi

        echo $eta > /tmp/${subject_name}/.eta

        return 0

}

draw_bar() {

        printf "\r"
        progress=$(cat /tmp/${subject_name}/.percent_done)
        eta=$(cat /tmp/${subject_name}/.eta)
        local width=40
        local filled=$((progress * width / 100))
        local empty=$((width - filled))

        if [ -z "$1" ]
        then
                fe_worker_output=""
                ai_worker_output=""

                # Get FE Workers Status
                fe_worker_status=()
                while IFS= read -r line
                do
                        fe_worker_status+=("$line")
                done < <(cat /tmp/${subject_name}/.feworker* 2>/dev/null)

                for ((i=0; i<$max_workers_frame_extraction; i++))
                do
                        if [ -z "${fe_worker_status[$i]}" ]
                        then
                                fe_worker_output="$fe_worker_output W$i: idle"
                        else
                                fe_worker_output="$fe_worker_output W$i: ${fe_worker_status[$i]}"
                        fi
                done &> /dev/null

                # Get AI Workers Status
                ai_worker_status=()
                while IFS= read -r line
                do
                        ai_worker_status+=("$line")
                done < <(cat /tmp/${subject_name}/.aiworker* 2>/dev/null)

                for ((i=0; i<$max_workers_ai_upscale; i++))
                do
                        if [ -z "${ai_worker_status[$i]}" ]
                        then
                                ai_worker_output="$ai_worker_output W$i: idle"
                        else
                                ai_worker_output="$ai_worker_output W$i: ${ai_worker_status[$i]}"
                        fi
                done &> /dev/null

                jobs_done="$(cat /tmp/${subject_name}/.workers_done)/${#job_start_frames[@]}"
        fi

        printf "["
        printf "%0.s▓" $(seq 1 $filled)
        printf "%0.s░" $(seq 1 $empty)
        printf "]"

        if [ -z "$1" ]
        then
                printf " %3d%% | ETA: %02dh:%02dm:%02ds | AI: %s | FE: %s | Jobs done: %s           " "$progress" "$((eta/3600))" "$(((eta% 3600)/60))" "$((eta%60))" "$ai_worker_output" "$fe_worker_output" "$jobs_done"
        else
                printf " %3d%% | ETA: %02dm:%02ds           " "$progress" "$((eta/60))" "$((eta%60))"
        fi

}

count_workers_fe() {

        printf $(find "/tmp/${subject_name}" -maxdepth 1 -type f -regextype posix-extended -regex '.*/\.feworker[0-9]+' | wc -l)

}

count_workers_ai() {

        printf $(find "/tmp/${subject_name}" -maxdepth 1 -type f -regextype posix-extended -regex '.*/\.aiworker[0-9]+' | wc -l)

}

_provide_help() {
        _print_status plain """
HOLLOWAY'S UPSCALER - enhanced by NoDiskNoFun
-------------------
COMMAND:

$ ./start.cmd \\
        --model MODEL_NAME \\
        --scale SCALE_FACTOR \\
        --format FORMAT \\
        --gpu-ids COMMA,SEPARATED,LIST \\
        --job-size NUMBER                       # only for video upscaling \\
        --max_workers_ai_upscale NUMBER         # only for video upscaling \\
        --max_workers_frame_extraction NUMBER   # only for video upscaling \\
        --skip_frame_check                      # only for video upscaling \\
        --video                                 # only for video upscaling \\
        --input PATH_TO_FILE \\
        --output PATH_TO_FILE_OR_DIR            # optional

EXAMPLES

$ ./start.cmd \\
        --model ultrasharp \\
        --scale 4 \\
        --format webp \\
        --input my-image.jpg

$ ./start.cmd \\
        --model ultrasharp \\
        --scale 4 \\
        --format webp \\
        --input my-image.jpg \\
        --output my-image-upscaled.webp

$ ./start.cmd \\
        --model ultrasharp \\
        --scale 4 \\
        --format png \\
        --parallel 1 \\
        --video \\
        --input my-video.mp4 \\
        --output my-video-upscaled.mp4

$ ./start.cmd \\
        --model ultrasharp \\
        --scale 4 \\
        --format png \\
        --parallel 1 \\
        --input video/frames/input \\
        --output video/frames/output

AVAILABLE FORMATS:
(1) PNG
(2) JPG
(3) WEBP

AVAILABLE MODELS:
"""


        for model_type in "${repo}/models"/*.sh; do
                . "$model_type"

                model_id="${model_type##*/}"
                model_id="${model_id%%.*}"
                printf "ID        : ${model_id}\n"
                if [ $model_max_scale -gt 0 ]; then
                        printf "max scale : ${model_max_scale}\n"
                else
                        printf "max scale : any\n"
                fi
                printf "Purpose   : ${model_name}\n\n"
        done


        return 0
}

_check_os() {
        case "$(uname)" in
        Darwin)
                program="${repo}/bin/mac"
                ;;
        *)
                program="${repo}/bin/linux"
                ;;
        esac


        return 0
}

_check_arch() {
        program="${program}-amd64"


        return 0
}

_check_program_existence() {
        if [ ! -f "$program" ]; then
                _print_status error "missing AI executable: '${program}'.\n"
                return 1
        fi


        return 0
}

_check_model_and_scale() {
        if [ -z "$model" ]; then
                _print_status error "unspecified model.\n"
                return 1
        fi


        if [ -z $scale ]; then
                _print_status error "unspecified scaling factor.\n"
                return 1
        fi


        __supported=false
        for model_type in "${repo}/models"/*.sh; do
                model_id="${model_type##*/}"
                model_id="${model_id%%.*}"

                if [ "$model" = "$model_id" ]; then
                        __supported=true
                        . "$model_type"
                fi
        done

        if [ "$__supported" = "false" ]; then
                _print_status error "unsupported model: '${model}'.\n"
                return 1
        fi
        unset __supported


        if [ $model_max_scale -eq 0 ]; then
                if [ $scale -gt 1 ]; then
                        return 0
                else
                        _print_status error "bad scale: '${scale}'.\n"
                        return 1
                fi
        fi


        if [ $scale -gt $model_max_scale ]; then
                _print_status error "scale is too big: '${scale}/${model_max_scale}'.\n"
                return 1
        fi


        return 0
}

_check_rife_model() {

        if [ -z "$rife_model" ]; then
                _print_status error "unspecified rife model.\n"
                return 1
        fi

        return 0
}

_check_format() {
        if [ -z "$format" ]; then
                if [ $video_mode -gt 0 ]; then
                        format='png'
                else
                        format="${source_file##*/}"
                        format="${format#*.}"
                fi
        fi

        case "$format" in
        jpg|JPG)
                format="jpg"
                return 0
                ;;
        png|PNG)
                format="png"
                return 0
                ;;
        webp|WEBP)
                format="webp"
                return 0
                ;;
        *)
                _print_status error "unsupported output format: '$format'.\n"
                return 1
                ;;
        esac
}

_check_io() {
        if [ "$source_file" = "" ]; then
                _print_status error "missing input.\n"
                return 1
        fi

        if [ ! -e "$source_file" ]; then
                _print_status error "input does not exist: '${source_file}'.\n"
                return 1
        fi

        subject_name="${source_file##*/}"
        subject_dir="${source_file%/*}"
        subject_ext="${subject_name#*.}"
        subject_name="${subject_name%%.*}"

        if [ "${subject_dir}" = "${input}" ]; then
                subject_dir="${subject_name}"
        fi

        if [ $video_mode -gt 0 ]; then
                if [ "$(type -p ffmpeg)" = "" ]; then
                        _print_status error "missing required ffmpeg program for video.\n"
                        return 1
                fi

                if [ "$(type -p ffprobe)" = "" ]; then
                        _print_status error "missing required ffprobe program for video.\n"
                        return 1
                fi

                if [ ! $parallel -eq $parallel 2> /dev/null ]; then
                        _print_status error "unknown parallel value: ${parallel}.\n"
                        return 1
                fi
        fi

        return 0
}

check_bc_installed() {
  if ! command -v bc >/dev/null 2>&1; then
    _print_status error "Error: 'bc' is not installed. Please install it to continue."
    return 1
  fi
}

check_unzip_installed() {
  if ! command -v unzip >/dev/null 2>&1; then
    _print_status error "Error: 'unzip' is not installed. Please install it to continue."
    return 1
  fi
}

check_wget_installed() {
  if ! command -v wget >/dev/null 2>&1; then
    _print_status error "Error: 'wget' is not installed. Please install it to continue."
    return 1
  fi
}

check_rife_installed() {

        if [ ! -f rife-ncnn-vulkan-20221029-ubuntu/rife-ncnn-vulkan ]
        then
                _install_rife
        fi

}

detect_ffmpeg_hwaccel() {

        codecs=$(ffmpeg -hide_banner -encoders 2>/dev/null)

        # NVIDIA NVENC h.265
        if echo "$codecs" | grep -q "hevc_nvenc"; then
                printf "hevc_nvenc"
                return 0
        fi
        # NVIDIA NVENC h.264
        if echo "$codecs" | grep -q "h264_nvenc"; then
                printf "h264_nvenc"
                return 0
        fi

        # AMD VAAPI
        if printf "$codecs" | grep -q "h264_vaapi"; then
                echo "h264_vaapi"
                return 0
        fi

        # Intel Quick Sync Video (QSV)
        if echo "$codecs" | grep -q "h264_qsv"; then
                printf "h264_qsv"
                return 0
        fi

        # Fallback: Software-Encoding (libx264)
        if echo "$codecs" | grep -q "libx264"; then
                printf "libx264"
                return 0
        fi
  return 1
}

_install_rife() {

        check_unzip_installed
        if [ $? -ne 0 ]; then
                exit 1
        fi
        check_wget_installed
        if [ $? -ne 0 ]; then
                exit 1
        fi

        wget https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-ubuntu.zip
        unzip rife-ncnn-vulkan-20221029-ubuntu.zip

        return 0

}

____save_workspace_controller() {
        # ARG1 = Phase ID
        printf """\
#!/bin/bash
source_file="${source_file}"
total_frames=${total_frames}
frame_rate="${frame_rate}"
video_codec="${video_codec}"
input_frame_size="${input_frame_size}"
job_size_start_frames="$1"
job_size_in_frames="$job_size_in_frames"
upscaling_done="$upscaling_done"
""" > "$control"
        if [ $? -ne 0 ]; then
                 _print_status error
                return 1
        fi

        return 0
}

____exec_upscale_program() {
        $program -i "$1" \
                -o "$2" \
                -s "$scale" \
                -m "${repo}/models" \
                -n "$model" \
                -f "$format" \
                -g "$3" \
                &> /dev/null


        return $?
}

___generate_frame_input_name() {
        printf "${workspace}/frames/$2/input_0${1}.${format}"
}

___generate_frame_output_name() {
        printf "${workspace}/frames/input_0${1}.png"
}

___generate_frame_output_naming_pattern() {
        printf "${workspace}/frames/input_0%%d.png"
}

__print_job_info() {
        __output_format="$format"
        ___video_mode="No"
        if [ $video_mode -gt 0 ]; then
                __output_format="$subject_ext"
                ___video_mode="Yes"
        fi


        ___model_max_scale='unspecified'
        if [ $model_max_scale -gt 0 ]; then
                ___model_max_scale="$model_max_scale"
        fi


        _print_status info """
Upscale Model    : $model
Upscale Scale    : $scale
Model Max Scale  : $___model_max_scale
Upscale Format   : $format
Input File       : $source_file
Is Video Input   : $___video_mode

Output Directory : $subject_dir
Output Filename  : $subject_name
Output Suffix    : $subject_suffix
Output Extension : $__output_format


"""
        unset __output_format ___video_mode ___model_max_scale
}

__upscale_if_image() {
        if [ $video_mode -eq 0 ]; then

                # Read GPU-IDs to array
                gpu_array=()
                if [ -z "$gpu_ids" ] # Default GPU ID is 0
                then
                        gpu_array[0]=0
                fi

                IFS=','
                for id in $gpu_ids; do
                        gpu_array+=("$id")
                done
                unset IFS

                gpuid=${gpu_array[0]} # Only use first given GPU Id for image upscaling

                output="${subject_dir}/${subject_name}-${subject_suffix}.${format}"
                ____exec_upscale_program "$source_file" "$output" "$gpuid"
                if [ $? -eq 0 ]; then
                        _print_status success "\n"
                        return 10
                fi


                _print_status error
                return 1
        fi
}

__setup_video_workspace() {
        # setup variables
        if [ -z $workspace ]
        then
                workspace="${subject_dir}/${subject_name}-${subject_suffix}_workspace"
        fi
        control="${workspace}/control.sh"
        if [ -f $control ]
        then
                _print_status info "\nFound control file ($control).\nRestoring...\n\n"
                source $control
        else
                _print_status info "\nCreating workspace...\n"
                rm -rf "${workspace}" &> /dev/null
                mkdir -p "${workspace}/frames"

                # save settings to control file in not available
                ____save_workspace_controller $job_size_start_frames
                if [ $? -ne 0 ]; then
                         _print_status error "\n"
                        return 1
                fi

                _print_status info "Done\n\n\n"
        fi

        _print_status info "\nInspect video file ...\n\n"

        if [ -z $video_codec ]
        then
                # analyze input video and initialize sentinel variables
                video_codec="$(ffprobe -v error \
                                -select_streams v:0 \
                                -show_entries stream=codec_name \
                                -of default=noprint_wrappers=1:nokey=1 \
                                "$source_file"
                )"
        fi
        if [ -z $frame_rate ]
        then
                frame_rate="$(
                        ffprobe -v error \
                                -select_streams v \
                                -of default=noprint_wrappers=1:nokey=1 \
                                -show_entries stream=r_frame_rate \
                                "$source_file"
                )"
        fi
        if [ -z $total_frames ]
        then
                total_frames="$(($(
                        ffprobe -v error \
                                -select_streams v:0 \
                                -count_frames \
                                -show_entries stream=nb_read_frames \
                                -of default=nokey=1:noprint_wrappers=1 \
                                "$source_file"
                ) - 1))" # NOTE: system uses 0 as a starting point so we -1 out
        fi
        if [ -z $input_frame_size ]
        then
                input_frame_size="$(
                        ffprobe \
                                -v error \
                                -select_streams v:0 \
                                -show_entries stream=width,height \
                                -of csv=s=x:p=0 \
                                "$source_file"
                )"
        fi

        current_frame=0
        phase=0

        # Create fast r/w workspace for worker managment
        rm -rf /tmp/${subject_name} #&> /dev/null
        mkdir -p /tmp/${subject_name}

        if [ -z $job_size_start_frames ]
        then
                if [ $total_frames -gt $job_size_in_frames ]
                then
                        job_size_start_frames=0
                        for((i_jobs=1; $(($i_jobs * $job_size_in_frames))<total_frames; i_jobs++)) # Calculate startframe per job
                        do
                                job_size_start_frames="$job_size_start_frames,$(($job_size_in_frames * $i_jobs))"
                        done
                        echo $job_size_start_frames > /tmp/${subject_name}/.jobs
                        ____save_workspace_controller $job_size_start_frames
                fi
        else
                echo $job_size_start_frames > /tmp/${subject_name}/.jobs
        fi

        # Read job start frames to array
        job_size_start_frames=$(cat /tmp/${subject_name}/.jobs)
        job_start_frames=()
        IFS=','
        for i in $job_size_start_frames; do
                job_start_frames+=("$i")
        done
        unset IFS

        _print_status info """
Video Name                   : ${subject_name}.${subject_ext}
Video Codec                  : ${video_codec}
Input Frame                  : ${input_frame_size}

Frame Rate                   : ${frame_rate}
Total Frames                 : $((total_frames + 1))

Job Size                     : $job_size_in_frames
Total Jobs                   : ${#job_start_frames[@]}
Max Frame Extraction Workers : ${max_workers_frame_extraction}
Max Upscaling Workers        : ${max_workers_ai_upscale}


"""


        return 0
}

__reassemble_video() {
        _print_status info "Reassemble video ...\n"

        # determine pixel format and frame size from first frame
        output="$(___generate_frame_output_name "0")"
        pixel_format="$(ffprobe \
                -loglevel error \
                -show_entries \
                stream=pix_fmt \
                -of csv=p=0 \
                "${output}"
        )"
        output_frame_size="$(ffprobe \
                -v error \
                -select_streams v:0 \
                -show_entries stream=width,height \
                -of csv=s=x:p=0 \
                "${output}"
        )"


        if [ $rife -eq 1 ]
        then
                frame_rate=$(($frame_rate * 2))
        fi

        # reassemble video with upscaled frames
        output="${subject_dir}/${subject_name}-${subject_suffix}.${subject_ext}"
        pattern="$(___generate_frame_output_naming_pattern)"
        ffmpeg -y \
                -thread_queue_size 4096 \
                -i "$source_file" \
                -r "$frame_rate" \
                -thread_queue_size 4096 \
                -i "$pattern" \
                -c:v "$(detect_ffmpeg_hwaccel)" \
                -pix_fmt "yuv420p" \
                -r "$frame_rate" \
                -filter_complex \
                        "[0:v:0]scale=${output_frame_size}[v0];[v0][1]overlay=eof_action=pass" \
                -c:a copy \
                -v error -stats \
                "$output"
        if [ $? -ne 0 ]; then
                _print_status error "\n"
                return 1
        fi
        unset output pattern pixel_format output_frame_size


        # save settings to control file in case of future continuation
        ____save_workspace_controller 3
        if [ $? -ne 0 ]; then
                 _print_status error "\n"
                return 1
        fi


        # report and return
        _print_status info "Done\n\n"
        return 0
}

__spawn_workers() {

        # Skip if extraction is done
        if [ $upscaling_done -eq 1 ]
        then
                return 0
        fi

        # Prepare for ETA
        start_time=$(date +%s)

        # Read GPU-IDs to array
        gpu_array=()
        if [ -z "$gpu_ids" ] # Default GPU ID is 0
        then
                gpu_array[0]=0
        fi

        IFS=','
        for id in $gpu_ids; do
                gpu_array+=("$id")
        done
        unset IFS

        # Set start values
        echo $job_start_id > /tmp/${subject_name}/.workers_done
        echo 0 > /tmp/${subject_name}/.percent_done
        echo 0 > /tmp/${subject_name}/.eta


        # Update UI
        _print_status info "Extract and upscale frames ... \n"
        draw_bar

        # Spawn a worker for every job
        for ((i_workers=$job_start_id; i_workers<${#job_start_frames[@]}; i_workers++))
        do

                # Wait for free worker slot
                while [ $(count_workers_fe) -gt $(($max_workers_frame_extraction - 1 )) ]
                do
                        draw_bar&
                        sleep 0.$(( ( RANDOM % 1000 )  + 1 ))
                done

                # Do not spawn to much workers at once
                # This should mitigate that two or more workers start simutaneasly while max_worker is already reached
                # There will be a better solution one day (TM)
                while [ $i_workers -gt $(($(cat /tmp/${subject_name}/.workers_done) + 15 )) ]
                do
                        draw_bar&
                        sleep 0.$(( ( RANDOM % 1000 )  + 1 ))
                done


                # Create job folder and start worker
                mkdir -p "${workspace}/frames/${job_start_frames[$i_workers]}"
                __worker_frame_extraction ${job_start_frames[$i_workers]}&
                sleep 0.$(( ( RANDOM % 1000 )  + 1 ))

        done

        # Wait until every worker has finished
        while [ $(cat /tmp/${subject_name}/.workers_done) -lt ${#job_start_frames[@]} ]
        do
                draw_bar&
                sleep 1
        done

        # Show 100% bar
        echo 100 > /tmp/${subject_name}/.percent_done
        calculate_eta
        draw_bar
        printf "\n"
        _print_status info "Done\n"
        printf "\n\n"

        # Save status
        upscaling_done=1
        ____save_workspace_controller $job_size_start_frames


        return 0

}

__worker_frame_extraction() {

        current_frame=$1
        if [ $(($current_frame + $job_size_in_frames)) -lt $total_frames ] # Last Job may be smaller ...
        then
                job_frames_total_frames=$(($(($current_frame + $job_size_in_frames)) - 1 ))
        else
                job_frames_total_frames=$total_frames
        fi

        # Save status
        echo $current_frame to ${job_frames_total_frames} > /tmp/${subject_name}/.feworker$1

        # Extract frames
        ffmpeg -i $source_file \
                -vsync 0 \
                -q:v 2 \
                -vf "select='between(n\,${current_frame}\,${job_frames_total_frames})',setpts=N/FRAME_RATE/TB" \
                -frames:v $((job_frames_total_frames - current_frame + 1)) \
                $workspace/frames/$1/input_%d.png &> /dev/null

        # Rename frames to their actual framenumber
        for ((i_frame_number=1;i_frame_number<$(($job_size_in_frames + 1));i_frame_number++))
        do
                mv $workspace/frames/$1/input_$i_frame_number.png $workspace/frames/$1/input_0$(($i_frame_number + $current_frame - 1)).png &> /dev/null
        done

        # Clean up
        rm /tmp/${subject_name}/.feworker$1 &> /dev/null

        # Wait for free worker slot
        sleep 0.$(( ( RANDOM % 1000 )  + 1 ))
        while [ $(count_workers_ai) -gt $(($max_workers_ai_upscale - 1 )) ]
        do
                sleep $(( ( RANDOM % 2 )  + 0 )).$(( ( RANDOM % 1000 )  + 1 ))
        done

        __worker_ai_upscale $1 $job_size_in_frames

        return 0
}

__worker_ai_upscale() {

        # Wait for free worker slot
        sleep 0.$(( ( RANDOM % 1000 )  + 1 ))
        while [ $(count_workers_ai) -gt $(($max_workers_ai_upscale - 1 )) ]
        do
                sleep $(( ( RANDOM % 2 )  + 0 )).$(( ( RANDOM % 1000 )  + 1 ))
        done &> /dev/null

        # Choose GPU by checking if its available
        gpuid=""
        while [ -z $gpuid ]
        do
                for ((i=0;i<${#gpu_array[@]};i++))
                do
                        if [ ! -f /tmp/${subject_name}/.gpu-${gpu_array[$i]}-active ]
                        then
                                gpuid=${gpu_array[$i]}
                                break
                        fi
                done
        done

        # Mark GPU as active
        touch /tmp/${subject_name}/.gpu-$gpuid-active

        # Upscale all files in job folder
        input=$workspace/frames/$1/
        if [ $rife -eq 0 ]
        then
                output=$workspace/frames/
        else
                output=$workspace/frames/$1-rife/
                mkdir -p $output
        fi

        # Register Worker
        echo $1 to $(($(($1 + $2)) - 1 )) > /tmp/${subject_name}/.aiworker$1

        ____exec_upscale_program $input $output $gpuid
        if [ $? -ne 0 ]; then
                exit 1
        fi

        if [ $rife -eq 1 ]
        then
                _use_rife $1 $gpuid  &> /dev/null
        fi

        # Unregister Worker
        echo $(($(cat /tmp/${subject_name}/.workers_done) + 1 )) > /tmp/${subject_name}/.workers_done
        rm /tmp/${subject_name}/.gpu-$gpuid-active &> /dev/null

        percent_done=$(echo "scale=2; 100 * $(cat /tmp/${subject_name}/.workers_done) / ${#job_start_frames[@]}" | bc | cut -d'.' -f1)
        if [ -z $percent_done ]
        then
                percent_done=0
        fi

        # Update UI
        echo $percent_done > /tmp/${subject_name}/.percent_done
        calculate_eta

        # Remove Job from list
        job_size_start_frames=$(cat /tmp/${subject_name}/.jobs)
        IFS=',' read -ra frames <<< "$job_size_start_frames"

        new_frames=()

        for f in "${frames[@]}"
        do
                if [[ "$f" != "$1" ]]
                then
                        new_frames+=("$f")
                fi
        done

        IFS=','
        job_size_start_frames="${new_frames[*]}"
        unset IFS
        echo $job_size_start_frames > /tmp/${subject_name}/.jobs


        # Save Progress
        ____save_workspace_controller $job_size_start_frames

        # Clean up
        rm -rf $input &> /dev/null
        rm /tmp/${subject_name}/.aiworker$1 &> /dev/null

        return 0

}

_use_rife() {

        input_rife=$workspace/frames/$1-rife
        output_rife=$workspace/frames/$1-rife-output

        mkdir -p $output_rife
        rife-ncnn-vulkan-20221029-ubuntu/rife-ncnn-vulkan -i $input_rife -o $output_rife -g $2 -f input_0%d.png -m $rife_model
        if [ $? -ne 0 ]; then
                exit 1
        fi

        for ((i_rife=0;i_rife<$(($job_size_in_frames * 2));i_rife++))
        do
                current_frame_name=$output_rife/input_0$(($i_rife + 1)).png
                target_frame_name=$workspace/frames/input_0$(($i_rife + $(($1 * 2)))).png
                mv $current_frame_name $target_frame_name &> /dev/null
        done

        # Clean up
        rm -r $input_rife $output_rife
        return 0

}

_check_missing_frames() {

        # Prepare for ETA
        start_time=$(date +%s)

        # Set start values
        echo 0 > /tmp/${subject_name}/.percent_done
        echo 0 > /tmp/${subject_name}/.eta
        job_size_in_frames=1 # Only extract and upscale one frame
        last_check=0

        if [ $rife -eq 1 ]
        then
                total_frames=$(($total_frames * 2))
        fi

        _print_status info "Check for missing frames ... \n"
        draw_bar short

        for((i_missing_frames=0;i_missing_frames<$((total_frames + 1));i_missing_frames++))
        do
                if [ ! -f "$(___generate_frame_output_name $i_missing_frames)" ]
                then
                        printf "\n"
                        _print_status info "Frame $i_missing_frames missing. Extracting und uspcaling ...     \n"

                        # Create job folder and start worker
                        mkdir -p "${workspace}/frames/$i_missing_frames"
                        __worker_frame_extraction $i_missing_frames

                        # Wait for ai worker
                        sleep 1
                        while [ $(count_workers_ai) -gt 0 ]
                        do
                                sleep 1
                        done

                fi

                percent_done=$(echo "scale=2; 100 * $i_missing_frames / $total_frames" | bc | cut -d'.' -f1)
                if [ -z $percent_done ]
                then
                        percent_done=0
                fi

                if [ ! $last_check -eq $percent_done ]
                then
                        echo $percent_done > /tmp/${subject_name}/.percent_done
                        last_check=$percent_done
                        calculate_eta
                        draw_bar short
                fi
        done

        # Draw 100 % bar
        echo 100 > /tmp/${subject_name}/.percent_done
        calculate_eta
        draw_bar short
        printf "\n"
        _print_status info "Done\n\n\n"

        # Clean up
        rm -rf /tmp/${subject_name}

        return 0

}

_exec_program() {
        __print_job_info
        if [ $? -ne 0 ]; then
                exit 1
        fi


        __upscale_if_image
        case $? in
        10)
                exit 0
                ;;
        0)
                ;;
        *)
                exit 1
                ;;
        esac


        __setup_video_workspace
        if [ $? -ne 0 ]; then
                exit 1
        fi


        __spawn_workers
        if [ $? -ne 0 ]; then
                exit 1
        fi

        # Bash was not made with multithreading in mind
        # So better be safe than sorry, right?
        if [ $skip_frame_check -eq 0 ]
        then
                _check_missing_frames
                if [ $? -ne 0 ]; then
                        exit 1
                fi
        fi

        __reassemble_video
        if [ $? -ne 0 ]; then
                exit 1
        fi


        exit 0
}

main() {
        if [ "$*" = "" ]; then
                _provide_help
                exit 0
        fi

        # parse argument
        while [ $# -ne 0 ]; do
        case "$1" in
                --help|-h|help)
                        _provide_help
                        exit 0
                        ;;
                --video|-vd)
                        video_mode=1
                        ;;
                --skip-frame-check)
                        skip_frame_check=1
                        ;;
                --use-rife)
                        rife=1
                        ;;
                --gpu-ids)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                gpu_ids="$2"
                                shift 1
                        fi
                        ;;
                --workspace)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                workspace="$2"
                                shift 1
                        fi
                        ;;
                --job-size)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                job_size_in_frames="$2"
                                shift 1
                        fi
                        ;;
                --max_workers_ai_upscale|-mwau)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                max_workers_ai_upscale="$2"
                                shift 1
                        fi
                        ;;
                --max_workers_frame_extraction|-mwfe)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                max_workers_frame_extraction="$2"
                                shift 1
                        fi
                        ;;
                --override-job-start-id)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                job_start_id="$2"
                                shift 1
                        fi
                        ;;
                --model|-m)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                model="$2"
                                shift 1
                        fi
                        ;;
                --rife-model|-rm)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                rife_model="$2"
                                shift 1
                        fi
                        ;;
                --scale|-s)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                scale="$2"
                                shift 1
                        fi
                        ;;
                --input|-i)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                source_file="$2"
                                shift 1
                        fi
                        ;;
                --output|-o)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                output="$2"
                                shift 1
                        fi
                        ;;
                --format|-f)
                        if [ "$2" != "" ] && [ "$(printf "%.1s" "$2")" != "-" ]; then
                                format="$2"
                                shift 1
                        fi
                        ;;
                *)
                        ;;
                esac
                shift 1
        done

        # run function
        _check_os
        if [ $? -ne 0 ]; then
                exit 1
        fi

        _check_arch
        if [ $? -ne 0 ]; then
                exit 1
        fi

        _check_program_existence
        if [ $? -ne 0 ]; then
                exit 1
        fi

        check_bc_installed
        if [ $? -ne 0 ]; then
                exit 1
        fi

        _check_model_and_scale
        if [ $? -ne 0 ]; then
                exit 1
        fi

        if [ $rife -eq 1 ]
        then
                check_rife_installed
                _check_rife_model
                if [ $? -ne 0 ]; then
                        exit 1
                fi
        fi

        _check_format
        if [ $? -ne 0 ]; then
                exit 1
        fi

        _check_io
        if [ $? -ne 0 ]; then
                exit 1
        fi

        _exec_program
        if [ $? -ne 0 ]; then
                exit 1
        fi
}
main "$@"
