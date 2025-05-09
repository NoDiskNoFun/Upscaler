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
. "${LIBS_UPSCALER}/services/i18n/report-simulation.sh"
. "${LIBS_UPSCALER}/services/io/os.sh"
. "${LIBS_UPSCALER}/services/io/fs.sh"
. "${LIBS_UPSCALER}/services/io/strings.sh"




UPSCALER_Batch_Load() {
        #___video="$1"
        #___model="$2"
        #___scale="$3"
        #___format="$4"
        #___parallel="$5"
        #___gpu="$6"
        #___input="$7"
        #___output="$8"


        # validate input
        if [ "$(STRINGS_Is_Empty "$1")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$2")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$3")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$4")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$5")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$6")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$7")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$8")" = "0" ]; then
                return 1
        fi

        if [ "$(STRINGS_Is_Empty "$(UPSCALER_Program_Get)")" = "0" ]; then
                return 1
        fi


        # report status
        return 0
}




UPSCALER_Batch_Run() {
        #___video="$1"
        #___model="$2"
        #___scale="$3"
        #___format="$4"
        #___parallel="$5"
        #___gpu="$6"
        #___input="$7"
        #___output="$8"


        # validate input
        if [ "$(STRINGS_Is_Empty "$1")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$2")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$3")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$4")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$5")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$6")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$7")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$8")" = "0" ]; then
                return 1
        fi

        if [ "$(STRINGS_Is_Empty "$(UPSCALER_Program_Get)")" = "0" ]; then
                return 1
        fi


        # execute
        if [ ! "$(STRINGS_Is_Empty "$UPSCALER_TEST_MODE")" = "0" ]; then
                I18N_Report_Simulation "$(UPSCALER_Program_Get) ${___cmd}"
                FS_Make_Housing_Directory "$8"
                FS_Remove_Silently "$8"
                FS_Copy_File "$7" "$8"
                if [ $? -eq 0 ]; then
                        return 0
                fi
        fi


        # report status
        return 0
}




UPSCALER_Batch_Setup() {
        #___video="$1"
        #___model="$2"
        #___scale="$3"
        #___format="$4"
        #___parallel="$5"
        #___gpu="$6"
        #___input="$7"
        #___output="$8"


        # validate input
        if [ "$(STRINGS_Is_Empty "$1")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$2")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$3")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$4")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$5")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$6")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$7")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$8")" = "0" ]; then
                return 1
        fi

        if [ "$(STRINGS_Is_Empty "$(UPSCALER_Program_Get)")" = "0" ]; then
                return 1
        fi


        # report status
        return 0
}




UPSCALER_Format_Validate() {
        #___format="$1"


        # validate input
        if [ "$(STRINGS_Is_Empty "$1")" = "0" ]; then
                printf -- ""
                return 1
        fi


        # execute
        case "$(STRINGS_To_Lowercase "$1")" in
        jpeg|jpg)
                printf -- "jpg"
                ;;
        png)
                printf -- "png"
                ;;
        webp)
                printf -- "webp"
                ;;
        native)
                printf -- "native"
                ;;
        *)
                printf -- ""
                return 1
                ;;
        esac


        # report status
        return 0
}




UPSCALER_Output_Filename_Image() {
        #___output="$1"
        #___input="$2"
        #___format="$3"


        # validate input
        if [ ! -z "$1" ]; then
                printf -- "%b" "$1"
                return 0
        fi

        if [ -z "$2" ]; then
                printf -- ""
                return 1
        fi


        # execute
        ___output="$(FS_Extension_Remove "${2##*/}" "*")"
        if [ ! "${2%/*}" = "$2" ]; then
                ___output="${2%/*}/${___output}-upscaled"
        else
                ___output="./${___output}-upscaled"
        fi

        case "$3" in
        jpg)
                ___output="${___output}.jpg"
                ;;
        webp)
                ___output="${___output}.webp"
                ;;
        *)
                ___output="${___output}.png"
                ;;
        esac
        printf -- "%b" "$___output"


        # report status
        return 0
}




UPSCALER_Output_Filename_Video() {
        #___output="$1"
        #___input="$2"


        # validate input
        if [ ! -z "$1" ]; then
                printf -- "%b" "$1"
                return 0
        fi

        if [ -z "$2" ]; then
                printf -- ""
                return 1
        fi


        # execute
        ___output="$(FS_Extension_Remove "${2##*/}" "*")"
        ___output="${2%/*}/${___output}-upscaled.${2##*.}"
        printf -- "%b" "$___output"


        # report status
        return 0
}




UPSCALER_GPU_Scan() {
        # validate input
        ___program="$(UPSCALER_Program_Get)"
        if [ "$(STRINGS_Is_Empty "$___program")" = "0" ]; then
                printf -- ""
                return 1
        fi


        # Create a dummy PNG file for upscale
        ___filename="${UPSCALER_PATH_ROOT}/.dummy.png"
        ___target="${UPSCALER_PATH_ROOT}/.dummy-upscaled.png"
        ___header='\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\x0aIDAT\x08\x96\x96\x96\x96\x00\x00\x00\x00\x01\x74\x52\x47\x42\x00\xae\xce\x1c\xe9\x00\x00\x00\x00IEND\xaeB`\x82'
        FS_Remove_Silently "$___filename"
        FS_Remove_Silently "$___target"
        dd if=/dev/zero bs=1 count=1  2>/dev/null \
                | printf '%b' "$___header" \
                | cat > "${___filename}"
        printf -- "%b" "$(2>&1 "${___program}" -s 1 -i "$___filename" -o "$___target")"
        FS_Remove_Silently "$___filename"
        FS_Remove_Silently "$___target"


        # report status
        return 0
}




UPSCALER_GPU_Verify() {
        #___gpu="$1"


        # validate input
        if [ "$(STRINGS_Is_Empty "$1")" = "0" ]; then
                return 1
        fi


        # execute
        ___term="$(UPSCALER_GPU_Scan)"
        ___verdict="1"
        ___old_IFS="$IFS"
        while IFS="" read -r __line || [ -n "$__line" ]; do
                if [ ! "$(printf -- "%.1b" "$__line")" = "[" ]; then
                        continue
                fi

                __line="${__line%%] *}"
                __line="${__line#*[}"
                if [ "$1" = "${__line%% *}" ]; then
                        ___verdict="0"
                        break
                fi
        done <<EOF
${___term}
EOF
        IFS="$___old_IFS" && unset ___old_IFS


        # report status
        if [ "$___verdict" = "0" ]; then
                return 0
        fi

        return 1
}




UPSCALER_Is_Available() {
        # execute
        ___program="$(UPSCALER_Program_Get)"
        if [ "$(STRINGS_Is_Empty "$___program")" = "0" ]; then
                return 1
        fi


        # report status
        return 0
}




UPSCALER_Model_Get() {
        #___id="$1"


        # validate input
        if [ -z "$1" ]; then
                printf -- ""
                return 1
        fi


        # execute
        for ___model in "${UPSCALER_PATH_ROOT}/models"/*.sh; do
                ___model_ID="${___model##*/}"
                ___model_ID="${___model_ID%%.*}"

                if [ ! "$1" = "$___model_ID" ]; then
                        continue
                fi

                # given ID is a valid model
                . "$___model"
                ___model_NAME="${model_name}"
                ___model_SCALE_MAX="any"
                if [ "$model_max_scale" -gt 0 ]; then
                         ___model_SCALE_MAX="${model_max_scale}"
                fi

                printf "%b│%b│%b" "$___model_ID" "$___model_SCALE_MAX" "$___model_NAME"
                return 0
        done


        # report status
        printf -- ""
        return 1
}




UPSCALER_Program_Get() {
        # execute
        case "$(OS_Host_System)" in
        linux)
                ___program="${UPSCALER_PATH_ROOT}/bin/linux"
                ;;
        darwin)
                ___program="${UPSCALER_PATH_ROOT}/bin/mac"
                ;;
        *)
                printf -- ""
                return 1
                ;;
        esac


        case "$(OS_Host_Arch)" in
        amd64)
                ___program="${___program}-amd64"
                ;;
        *)
                printf -- ""
                return 1
                ;;
        esac


        FS_Is_Target_Exist "$___program"
        if [ $? -ne 0 ]; then
                printf -- ""
                return 1
        fi
        printf -- "%b" "$___program"


        # report status
        return 0
}




UPSCALER_Run_Image() {
        #___model="$1"
        #___scale="$2"
        #___format="$3"
        #___gpu="$4"
        #___input="$5"
        #___output="$6"


        # validate input
        if [ "$(STRINGS_Is_Empty "$1")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$2")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$3")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$4")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$5")" = "0" ] ||
                [ "$(STRINGS_Is_Empty "$6")" = "0" ]; then
                return 1
        fi

        if [ "$(STRINGS_Is_Empty "$(UPSCALER_Program_Get)")" = "0" ]; then
                return 1
        fi


        # construct argument
        ___cmd="-i '${5}' -o '${6}'"
        ___cmd="${___cmd} -m '${UPSCALER_PATH_ROOT}/models/' -n '${1}' -s ${2} -g ${4}"
        case "${3}" in
        jpg)
                ___args="${___args} -f jpg"
                ;;
        webp)
                ___args="${___args} -f webp"
                ;;
        *)
                ;;
        esac


        # execute
        FS_Make_Housing_Directory "$6"
        FS_Remove_Silently "$6"
        if [ ! "$(STRINGS_Is_Empty "$UPSCALER_TEST_MODE")" = "0" ]; then
                I18N_Report_Simulation "$(UPSCALER_Program_Get) ${___cmd}"
                FS_Copy_File "$5" "$6"
                if [ $? -eq 0 ]; then
                        return 0
                fi
        else
                eval "$(UPSCALER_Program_Get) $___cmd"
                if [ $? -eq 0 ]; then
                        return 0
                fi
        fi


        # report status
        return 1
}




UPSCALER_Scale_Get() {
        #___limit="$1"
        #___input="$2"


        # validate input
        if [ -z "$1" ]; then
                printf -- ""
                return 1
        fi


        # execute
        case "$1" in
        any)
                case "$2" in
                1|2|3|4)
                        printf -- "%b" "$2"
                        return 0
                        ;;
                *)
                        ;;
                esac
                ;;
        1)
                case "$2" in
                1)
                        printf -- "1"
                        return 0
                        ;;
                *)
                        ;;
                esac
                ;;
        2)
                case "$2" in
                2)
                        printf -- "2"
                        return 0
                        ;;
                *)
                        ;;
                esac
                ;;
        3)
                case "$2" in
                3)
                        printf -- "3"
                        return 0
                        ;;
                *)
                        ;;
                esac
                ;;
        4)
                case "$2" in
                4)
                        printf -- "4"
                        return 0
                        ;;
                *)
                        ;;
                esac
                ;;
        *)
                ;;
        esac


        # report status
        printf -- ""
        return 1
}
