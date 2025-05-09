# Copyright 2024 (Holloway) Chew, Kean Ho <hello@hollowaykeanho.com>
#
#
# Licensed under (Holloway) Chew, Kean Ho’s Liberal License (the "License").
# You must comply with the license to use the content. Get the License at:
#
#                 https://doi.org/10.5281/zenodo.13770769
#
# You MUST ensure any interaction with the content STRICTLY COMPLIES with
# the permissions and limitations set forth in the license.
. "${env:LIBS_HESTIA}\HestiaKERNEL\Unicode\Index_Any_Left_Unicode.ps1"
. "${env:LIBS_HESTIA}\HestiaKERNEL\Unicode\Index_Any_Right_Unicode.ps1"




function HestiaKERNEL-Index-Any-Unicode {
        param (
                [uint32[]]$___content_unicode,
                [uint32[]]$___target_unicode,
                [string]$___from_right
        )


        # execute
        if ($___from_right -ne "") {
                # from right
                return HestiaKERNEL-Index-Any-Right-Unicode $___content_unicode $___target_unicode
        } else {
                return HestiaKERNEL-Index-Any-Left-Unicode $___content_unicode $___target_unicode
        }
}
