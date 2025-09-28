#!/bin/bash

# pkg install openjdk-17 zip unzip sed coreutils perl git -y

sdcard_path="/sdcard"
work_dir=$PWD

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

apkeditor() {
    local jarfile=$work_dir/tool/APKEditor.jar
    if [[ ! -f "$jarfile" ]]; then
        echo -e "${RED}ERROR: APKEditor.jar not found in tool/ folder!${NC}"
        return 1
    fi
    java -Xmx4096M -Dfile.encoding=utf-8 -Djdk.util.zip.disableZip64ExtraFieldValidation=true -Djdk.nio.zipfs.allowDotZipEntry=true -jar "$jarfile" "$@" > /dev/null 2>&1
}

baksmali() {
    local jarfile=$work_dir/tool/baksmali.jar
    if [[ ! -f "$jarfile" ]]; then
        echo -e "${RED}ERROR: baksmali.jar not found in tool/ folder!${NC}"
        return 1
    fi
    java -jar "$jarfile" "$@" > /dev/null 2>&1
}

run_with_spinner() {
    local message="$1"
    shift
    "$@" &
    local PID=$!
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local i=0
    while kill -0 $PID 2>/dev/null; do
        i=$(( (i+1) % 8 ))
        printf "\r[*] %s %s" "$message" "${spin:$i:1}"
        sleep 0.1
    done
    printf "\r[*] %s [✓]\n" "$message"
    wait $PID
    return $?
}

expressions_fix() {
    local var="$1"
    local escaped_var
    escaped_var=$(printf '%s\n' "$var" | sed 's/[\/&]/\\&/g')
    escaped_var=$(printf '%s\n' "$escaped_var" | sed 's/\[/\\[/g' | sed 's/\]/\\]/g' | sed 's/\./\\./g' | sed 's/;/\\;/g')
    echo "$escaped_var"
}

apply_pif_patches() {
    local unpack_dir="$1"
    
    certificatechainPatch() { certificatechainPatch="
    .line $1
    invoke-static {}, Lcom/android/internal/util/ifvank/util/OplusPixelPropUtils;->onEngineGetCertificateChain()V
"; }
    instrumentationPatch() { local returnline=$(expr $2 + 1); instrumentationPatch="    invoke-static {$1}, Lcom/android/internal/util/ifvank/util/OplusAttestationHooks;->setProps(Landroid/content/Context;)V
    invoke-static {$1}, Lcom/android/internal/util/ifvank/util/OplusGamesFpsUtils;->setProps(Landroid/content/Context;)V
    invoke-static {$1}, Lcom/android/internal/util/ifvank/util/OplusPixelPropUtils;->setProps(Landroid/content/Context;)V
    .line $returnline
    "; }
    keyboxutilsPatch() { keyboxutilsPatch="    invoke-static {$1}, Lcom/android/internal/util/ifvank/util/framework/KeyboxUtils;->engineGetCertificateChain([Ljava/security/cert/Certificate;)[Ljava/security/cert/Certificate;	
    move-result-object $1
    "; }

    local keystorespiclassfile=$(find "$unpack_dir" -type f -name 'AndroidKeyStoreSpi.smali' | head -n 1)
    local instrumentationsmali=$(find "$unpack_dir" -type f -name "Instrumentation.smali"  | head -n 1)
    local pm_smali=$(find "$unpack_dir" -type f -name 'ApplicationPackageManager.smali' | head -n 1)
    
    if [[ -z "$pm_smali" || -z "$keystorespiclassfile" || -z "$instrumentationsmali" ]]; then 
        echo -e "${RED}    ERROR: PIF patch failed. Required files not found.${NC}" >&2
        return 1
    fi

    local engineGetCertMethod=$(expressions_fix "$(grep 'engineGetCertificateChain(' "$keystorespiclassfile")")
    local newAppMethod1=$(expressions_fix "$(grep 'newApplication(Ljava/lang/ClassLoader;' "$instrumentationsmali")")
    local newAppMethod2=$(expressions_fix "$(grep 'newApplication(Ljava/lang/Class;' "$instrumentationsmali")")
    sed -n "/^${engineGetCertMethod}/,/^\.end method/p" "$keystorespiclassfile" > tmp_keystore
    sed -i "/^${engineGetCertMethod}/,/^\.end method/d" "$keystorespiclassfile"
    sed -n "/^${newAppMethod1}/,/^\.end method/p" "$instrumentationsmali" > inst1
    sed -i "/^${newAppMethod1}/,/^\.end method/d" "$instrumentationsmali"
    sed -n "/^${newAppMethod2}/,/^\.end method/p" "$instrumentationsmali" > inst2
    sed -i "/^${newAppMethod2}/,/^\.end method/d" "$instrumentationsmali"
    local inst1_insert=$(expr $(wc -l < inst1) - 2)
    local instreg=$(grep "Landroid/app/Application;->attach(Landroid/content/Context;)V" inst1 | awk '{print $3}' | sed 's/},//')
    local instline=$(expr $(grep -r ".line" inst1 | tail -n 1 | awk '{print $2}') + 1)
    instrumentationPatch "$instreg" "$instline"
    echo "$instrumentationPatch" | sed -i "${inst1_insert}r /dev/stdin" inst1
    local inst2_insert=$(expr $(wc -l < inst2) - 2)
    instreg=$(grep "Landroid/app/Application;->attach(Landroid/content/Context;)V" inst2 | awk '{print $3}' | sed 's/},//')
    instline=$(expr $(grep -r ".line" inst2 | tail -n 1 | awk '{print $2}') + 1)
    instrumentationPatch "$instreg" "$instline"
    echo "$instrumentationPatch" | sed -i "${inst2_insert}r /dev/stdin" inst2
    local kstoreline=$(expr $(grep -r ".line" tmp_keystore | head -n 1 | awk '{print $2}') - 2)
    certificatechainPatch "$kstoreline"
    echo "$certificatechainPatch" | sed -i '4r /dev/stdin' tmp_keystore
    local lastaput=$(grep "aput-object" tmp_keystore | tail -n 1)
    local leafcert=$(echo "$lastaput" | awk '{print $3}' | awk -F',' '{print $1}')
    local keybox_utils=$(expr $(grep -n "$lastaput" tmp_keystore | awk -F':' '{print $1}') + 1)
    keyboxutilsPatch "$leafcert"
    echo "$keyboxutilsPatch" | sed -i "${keybox_utils}r /dev/stdin" tmp_keystore
    cat inst1 >> "$instrumentationsmali"
    cat inst2 >> "$instrumentationsmali"
    cat tmp_keystore >> "$keystorespiclassfile"
    rm -rf inst1 inst2 tmp_keystore

    patch_application_package_manager() {
        local FEATURES_FIELDS=".field private static final whitelist featuresAndroid:[Ljava/lang/String;\n.field private static final whitelist featuresNexus:[Ljava/lang/String;\n.field private static final whitelist featuresPixel:[Ljava/lang/String;\n.field private static final whitelist featuresPixelOthers:[Ljava/lang/String;\n.field private static final whitelist featuresTensor:[Ljava/lang/String;"
        sed -i "/# static fields/a ${FEATURES_FIELDS}" "$pm_smali"
        local CODENAME_FIELD=".field private static final whitelist pTensorCodenames:[Ljava/lang/String;"
        sed -i '/\.field private static final greylist-max-o sDefaultFlags:I = 0x400/i\'"$CODENAME_FIELD"'' "$pm_smali"

        read -r -d '' clinit_addition_patch <<'EOF'

    const-string/jumbo v16, "oriole"
    const-string/jumbo v17, "raven"
    const-string/jumbo v3, "komodo"
    const-string v4, "caiman"
    const-string/jumbo v5, "tokay"
    const-string v6, "comet"
    const-string v7, "akita"
    const-string/jumbo v8, "husky"
    const-string/jumbo v9, "shiba"
    const-string v10, "felix"
    const-string/jumbo v11, "tangorpro"
    const-string/jumbo v12, "lynx"
    const-string v13, "cheetah"
    const-string/jumbo v14, "panther"
    const-string v15, "bluejay"
    filled-new-array/range {v3 .. v17}, [Ljava/lang/String;
    move-result-object v0
    sput-object v0, Landroid/app/ApplicationPackageManager;->pTensorCodenames:[Ljava/lang/String;
    const-string v13, "com.google.android.feature.GOOGLE_BUILD"
    const-string v14, "com.google.android.feature.GOOGLE_EXPERIENCE"
    const-string v1, "com.google.android.apps.photos.PIXEL_2019_PRELOAD"
    const-string v2, "com.google.android.apps.photos.PIXEL_2019_MIDYEAR_PRELOAD"
    const-string v3, "com.google.android.apps.photos.PIXEL_2018_PRELOAD"
    const-string v4, "com.google.android.apps.photos.PIXEL_2017_PRELOAD"
    const-string v5, "com.google.android.feature.PIXEL_2021_MIDYEAR_EXPERIENCE"
    const-string v6, "com.google.android.feature.PIXEL_2020_EXPERIENCE"
    const-string v7, "com.google.android.feature.PIXEL_2020_MIDYEAR_EXPERIENCE"
    const-string v8, "com.google.android.feature.PIXEL_2019_EXPERIENCE"
    const-string v9, "com.google.android.feature.PIXEL_2019_MIDYEAR_EXPERIENCE"
    const-string v10, "com.google.android.feature.PIXEL_2018_EXPERIENCE"
    const-string v11, "com.google.android.feature.PIXEL_2017_EXPERIENCE"
    const-string v12, "com.google.android.feature.PIXEL_EXPERIENCE"
    filled-new-array/range {v1 .. v14}, [Ljava/lang/String;
    move-result-object v0
    sput-object v0, Landroid/app/ApplicationPackageManager;->featuresPixel:[Ljava/lang/String;
    const-string v14, "com.google.android.apps.dialer.call_recording_audio"
    const-string v15, "com.google.android.apps.dialer.SUPPORTED"
    const-string v1, "com.google.android.feature.ASI"
    const-string v2, "com.google.android.feature.ANDROID_ONE_EXPERIENCE"
    const-string v3, "com.google.android.feature.GOOGLE_FI_BUNDLED"
    const-string v4, "com.google.android.feature.LILY_EXPERIENCE"
    const-string v5, "com.google.android.feature.TURBO_PRELOAD"
    const-string v6, "com.google.android.feature.WELLBEING"
    const-string v7, "com.google.lens.feature.IMAGE_INTEGRATION"
    const-string v8, "com.google.lens.feature.CAMERA_INTEGRATION"
    const-string v9, "com.google.photos.trust_debug_certs"
    const-string v10, "com.google.android.feature.AER_OPTIMIZED"
    const-string v11, "com.google.android.feature.NEXT_GENERATION_ASSISTANT"
    const-string v12, "android.software.game_service"
    const-string v13, "com.google.android.feature.EXCHANGE_6_2"
    filled-new-array/range {v1 .. v15}, [Ljava/lang/String;
    move-result-object v0
    sput-object v0, Landroid/app/ApplicationPackageManager;->featuresPixelOthers:[Ljava/lang/String;
    const-string v8, "com.google.android.feature.PIXEL_2022_MIDYEAR_EXPERIENCE"
    const-string v9, "com.google.android.feature.PIXEL_2021_EXPERIENCE"
    const-string v1, "com.google.android.feature.PIXEL_2025_EXPERIENCE"
    const-string v2, "com.google.android.feature.PIXEL_2025_MIDYEAR_EXPERIENCE"
    const-string v3, "com.google.android.feature.PIXEL_2024_EXPERIENCE"
    const-string v4, "com.google.android.feature.PIXEL_2024_MIDYEAR_EXPERIENCE"
    const-string v5, "com.google.android.feature.PIXEL_2023_EXPERIENCE"
    const-string v6, "com.google.android.feature.PIXEL_2023_MIDYEAR_EXPERIENCE"
    const-string v7, "com.google.android.feature.PIXEL_2022_EXPERIENCE"
    filled-new-array/range {v1 .. v9}, [Ljava/lang/String;
    move-result-object v0
    sput-object v0, Landroid/app/ApplicationPackageManager;->featuresTensor:[Ljava/lang/String;
    const-string v0, "com.google.android.feature.GOOGLE_BUILD"
    const-string v1, "com.google.android.feature.GOOGLE_EXPERIENCE"
    const-string v2, "com.google.android.apps.photos.NEXUS_PRELOAD"
    const-string v3, "com.google.android.apps.photos.nexus_preload"
    const-string v4, "com.google.android.feature.PIXEL_EXPERIENCE"
    filled-new-array {v2, v3, v4, v0, v1}, [Ljava/lang/String;
    move-result-object v0
    sput-object v0, Landroid/app/ApplicationPackageManager;->featuresNexus:[Ljava/lang/String;
    const-string v0, "android.software.freeform_window_management"
    filled-new-array {v0}, [Ljava/lang/String;
    move-result-object v0
    sput-object v0, Landroid/app/ApplicationPackageManager;->featuresAndroid:[Ljava/lang/String;
EOF
        local clinit_signature_raw=$(grep '\.method static constructor.*<clinit>()V' "$pm_smali" | head -n 1)
        if [[ -n "$clinit_signature_raw" ]]; then
            local clinit_signature_escaped=$(expressions_fix "$clinit_signature_raw")
            sed -n "/^${clinit_signature_escaped}/,/^\.end method/p" "$pm_smali" > clinit_temp.smali
            sed -i "/^${clinit_signature_escaped}/,/^\.end method/d" "$pm_smali"
            
            local injection_line_num=$(grep -n "mHasSystemFeatureCache:Landroid/app/PropertyInvalidatedCache;" "clinit_temp.smali" | head -n 1 | cut -d: -f1)
            if [[ -n "$injection_line_num" ]]; then
                echo "$clinit_addition_patch" > patch_data.tmp
                sed -i "${injection_line_num}r patch_data.tmp" "clinit_temp.smali"
                rm patch_data.tmp
            fi
            
            local max_v=$(grep -o 'v[0-9]\+' clinit_temp.smali | sed 's/v//' | sort -rn | head -n 1)
            local new_registers=$(( ${max_v:--1} + 1 ))
            
            sed -i '1,2d' clinit_temp.smali
            local new_clinit_header=".method static constructor whitelist <clinit>()V\n    .registers $new_registers"
            echo -e "$new_clinit_header" > clinit_final.smali
            cat clinit_temp.smali >> clinit_final.smali
            
            cat clinit_final.smali >> "$pm_smali"
            rm clinit_temp.smali clinit_final.smali
        fi

        read -r -d '' has_feature_addition_patch <<'EOF'
    invoke-static {}, Landroid/app/ActivityThread;->currentPackageName()Ljava/lang/String;
    move-result-object v0
    const/4 v1, 0x1
    if-eqz v0, :cond_63
    const-string v2, "com.google.android.googlequicksearchbox"
    invoke-virtual {v0, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
    move-result v2
    if-nez v2, :cond_2f
    const-string v2, "com.google.android.apps.pixel.agent"
    invoke-virtual {v0, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
    move-result v2
    if-nez v2, :cond_2f
    const-string v2, "com.google.android.apps.pixel.creativeassistant"
    invoke-virtual {v0, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
    move-result v2
    if-nez v2, :cond_2f
    const-string v2, "com.google.android.dialer"
    invoke-virtual {v0, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
    move-result v2
    if-nez v2, :cond_2f
    const-string v2, "com.google.android.apps.nexuslauncher"
    invoke-virtual {v0, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
    move-result v2
    if-eqz v2, :cond_63
    :cond_2f
    sget-object v2, Landroid/app/ApplicationPackageManager;->featuresPixel:[Ljava/lang/String;
    invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v2
    invoke-interface {v2, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v2
    if-eqz v2, :cond_3c
    return v1
    :cond_3c
    sget-object v2, Landroid/app/ApplicationPackageManager;->featuresPixelOthers:[Ljava/lang/String;
    invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v2
    invoke-interface {v2, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v2
    if-eqz v2, :cond_49
    return v1
    :cond_49
    sget-object v2, Landroid/app/ApplicationPackageManager;->featuresTensor:[Ljava/lang/String;
    invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v2
    invoke-interface {v2, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v2
    if-eqz v2, :cond_56
    return v1
    :cond_56
    sget-object v2, Landroid/app/ApplicationPackageManager;->featuresNexus:[Ljava/lang/String;
    invoke-static {v2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v2
    invoke-interface {v2, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v2
    if-eqz v2, :cond_63
    return v1
    :cond_63
    const/4 v2, 0x0
    if-eqz v0, :cond_ab
    const-string v3, "com.google.android.apps.photos"
    invoke-virtual {v0, v3}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_ab
    const-string/jumbo v0, "persist.sys.ifvankprops.photos"
    invoke-static {v0, v2}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z
    move-result v0
    if-eqz v0, :cond_ab
    sget-object v0, Landroid/app/ApplicationPackageManager;->featuresPixel:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_84
    return v2
    :cond_84
    sget-object v0, Landroid/app/ApplicationPackageManager;->featuresPixelOthers:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_91
    return v1
    :cond_91
    sget-object v0, Landroid/app/ApplicationPackageManager;->featuresTensor:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_9e
    return v2
    :cond_9e
    sget-object v0, Landroid/app/ApplicationPackageManager;->featuresNexus:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_ab
    return v1
    :cond_ab
    if-eqz p1, :cond_cd
    sget-object v0, Landroid/app/ApplicationPackageManager;->featuresTensor:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_cd
    sget-object v0, Landroid/app/ApplicationPackageManager;->pTensorCodenames:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    const-string/jumbo v3, "ro.oplus_ifvank.device"
    invoke-static {v3}, Landroid/os/SystemProperties;->get(Ljava/lang/String;)Ljava/lang/String;
    move-result-object v3
    invoke-interface {v0, v3}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-nez v0, :cond_cd
    return v2
    :cond_cd
    sget-object v0, Landroid/app/ApplicationPackageManager;->featuresAndroid:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_da
    return v1
    :cond_da
    sget-object v0, Landroid/app/ApplicationPackageManager;->featuresPixel:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_e7
    return v1
    :cond_e7
    sget-object v0, Landroid/app/ApplicationPackageManager;->featuresPixelOthers:[Ljava/lang/String;
    invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
    move-result-object v0
    invoke-interface {v0, p1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :cond_f4
    return v1
    :cond_f4
EOF
        local has_feature_signature_raw=$(grep '\.method public whitelist hasSystemFeature(Ljava/lang/String;I)Z' "$pm_smali" | head -n 1)
        if [[ -z "$has_feature_signature_raw" ]]; then
            has_feature_signature_raw=$(grep '\.method public hasSystemFeature(Ljava/lang/String;I)Z' "$pm_smali" | head -n 1)
        fi

        if [[ -n "$has_feature_signature_raw" ]]; then
            local has_feature_signature_escaped=$(expressions_fix "$has_feature_signature_raw")
            sed -n "/^${has_feature_signature_escaped}/,/^\.end method/p" "$pm_smali" > has_feature_temp.smali
            sed -i "/^${has_feature_signature_escaped}/,/^\.end method/d" "$pm_smali"
            
            local target_line_num=$(grep -n "mHasSystemFeatureCache:Landroid/app/PropertyInvalidatedCache;" "has_feature_temp.smali" | head -n 1 | cut -d: -f1)
            if [[ -n "$target_line_num" && "$target_line_num" -gt 1 ]]; then
                local injection_line_num=$((target_line_num - 1))
                echo "$has_feature_addition_patch" > patch_data.tmp
                sed -i "${injection_line_num}r patch_data.tmp" "has_feature_temp.smali"
                rm patch_data.tmp
            fi
            
            local new_registers=7
            
            sed -i '1,2d' has_feature_temp.smali
            local new_hsf_header=".method public whitelist hasSystemFeature(Ljava/lang/String;I)Z\n    .registers $new_registers"
            echo -e "$new_hsf_header" > has_feature_final.smali
            cat has_feature_temp.smali >> has_feature_final.smali

            cat has_feature_final.smali >> "$pm_smali"
            rm has_feature_temp.smali has_feature_final.smali
        fi
    }

    patch_application_package_manager

    if [[ -f "PIF/classes.dex" ]]; then 
        baksmali d "PIF/classes.dex" -o classes5
        if [ ! -d "classes5" ]; then return 1; fi
        rm -rf "$unpack_dir/smali_classes5"
        mv "classes5" "$unpack_dir/smali/classes5"
    fi
}

apply_apk_protection_patches() {
    local unpack_dir="$1"
    local sig_verifier_smali=$(find "$unpack_dir" -type f -name 'ApkSignatureVerifier.smali' | head -n 1)
    if [[ -z "$sig_verifier_smali" ]]; then echo -e "${RED}    ERROR: ApkSignatureVerifier.smali not found.${NC}"; return 1; fi
    local find_v3='(invoke-static\s*\{[^,]+,\s*[^,]+,\s*[^,]+,\s*([v|p]\d+)[^}]*\}, Landroid/util/apk/ApkSignatureVerifier;->verifyV3AndBelowSignatures\(Landroid/content/pm/parsing/result/ParseInput;Ljava/lang/String;IZ\)Landroid/content/pm/parsing/result/ParseResult;)'
    local replace_v3="const/4 \\\\2, 0x0\n    \\\\1"
    perl -i -pe "s#$find_v3#$replace_v3#" "$sig_verifier_smali"
    local find_v4='(invoke-static\s*\{[^,]+,\s*[^,]+,\s*[^,]+,\s*([v|p]\d+)[^}]*\}, Landroid/util/apk/ApkSignatureVerifier;->verifyV4Signature\(Landroid/content/pm/parsing/result/ParseInput;Ljava/lang/String;IZ\)Landroid/content/pm/parsing/result/ParseResult;)'
    local replace_v4="const/4 \\\\2, 0x0\n    \\\\1"
    perl -i -pe "s#$find_v4#$replace_v4#" "$sig_verifier_smali"
    local find_min_sdk='(\.method\s*public\s*static\s*blacklist\s*getMinimumSignatureSchemeVersionForTargetSdk\(I\)I)[\s\S]+?(\.end method)'
    perl -0777 -i -pe "s#$find_min_sdk#\1\n    .locals 1\n\n    const/4 v0, 0x0\n\n    return v0\n\2#g" "$sig_verifier_smali"
}

apply_secure_screenshot_patch() {
    local unpack_dir="$1"
    local file1=$(grep -lr '\.method isSecureLocked()Z' "$unpack_dir" | grep 'WindowState.smali$' | head -n 1)
    if [[ -n "$file1" ]]; then
        local BLOCK_START_LINE=$(grep -n '\.method isSecureLocked()Z' "$file1" | cut -d: -f1)
        local INJECT_LINE=$(tail -n +$BLOCK_START_LINE "$file1" | grep -n -E '\.registers\s+[0-9]+' | head -n 1 | cut -d: -f1)
        local TARGET_LINE=$((BLOCK_START_LINE + INJECT_LINE))
        read -r -d '' INJECTION_CODE <<'EOF'

    const-string/jumbo v0, "persist.sys.oplus.dfs"
    const/4 v1, 0x0
    invoke-static {v0, v1}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z
    move-result v0
    if-eqz v0, :cond_continue_secure_check
    const/4 v0, 0x0
    return v0
    :cond_continue_secure_check
EOF
        local ESCAPED_CODE=$(echo "$INJECTION_CODE" | sed 's/^[ \t]*//; s/[ \t]*$//' | sed -E ':a;N;$!ba;s/\n/\\n/g')
        sed -i "${TARGET_LINE}a\\\\${ESCAPED_CODE}" "$file1"
    fi
    local file2=$(grep -lr '\.method public notifyScreenshotListeners(I)Ljava/util/List;' "$unpack_dir" | grep 'WindowManagerService.smali$' | head -n 1)
    if [[ -n "$file2" ]]; then
        local FIND_REGEX='(\.method public notifyScreenshotListeners\(I\)Ljava\/util\/List;[\s\S]*?\.end annotation)'
        read -r -d '' REPLACE_TEXT <<'EOF'
    const-string/jumbo v0, "persist.sys.oplus.dfs"
    const/4 v1, 0x0
    invoke-static {v0, v1}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z
    move-result v0
    if-eqz v0, :cond_continue_notify_check
    new-instance v0, Ljava/util/ArrayList;
    invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
    return-object v0
    :cond_continue_notify_check
EOF
        export FIND_REGEX REPLACE_TEXT
        perl -0777 -i -pe 's/$ENV{FIND_REGEX}/"$1\n" . $ENV{REPLACE_TEXT}/se' "$file2"
    fi
}

apply_mock_location_patch() {
    local unpack_dir="$1"
    local file3=$(grep -lr '.method public noteOp(ILandroid/location/util/identity/CallerIdentity;)Z' "$unpack_dir" | grep 'SystemAppOpsHelper.smali$' | head -n 1)
    if [[ -n "$file3" ]]; then
        local FIND_REGEX='(\.method public noteOp\(ILandroid\/location\/util\/identity\/CallerIdentity;\)Z[\s\S]*?\.param p2, "callerIdentity"[\s\S]*?;)'
        read -r -d '' REPLACE_TEXT <<'EOF'
    const-string/jumbo v0, "persist.sys.oplus.mocklocation"
    const/4 v1, 0x0
    invoke-static {v0, v1}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z
    move-result v0
    if-eqz v0, :cond_continue_noteOp_check
    const/4 v0, 1
    return v0
    :cond_continue_noteOp_check
EOF
        export FIND_REGEX REPLACE_TEXT
        perl -0777 -i -pe 's/$ENV{FIND_REGEX}/"$1\n" . $ENV{REPLACE_TEXT}/se' "$file3"
    fi
    local file4=$(grep -lr 'Landroid/location/Location;->setIsFromMockProvider(Z)V' "$unpack_dir" | grep 'MockLocationProvider.smali$' | head -n 1)
    if [[ -n "$file4" ]]; then
        local FIND_REGEX='(const\/4 v1, 0x1\s*invoke-virtual \{v0, v1\}, Landroid\/location\/Location;->setIsFromMockProvider\(Z\)V)'
        read -r -d '' REPLACE_TEXT <<'EOF'
    const-string/jumbo v1, "persist.sys.oplus.mocklocation"
    const/4 v2, 0x0
    invoke-static {v1, v2}, Landroid/os/SystemProperties;->getBoolean(Ljava/lang/String;Z)Z
    move-result v1
    if-nez v1, :cond_set_mock_false
    const/4 v1, 0x1
    goto :goto_set_flag
    :cond_set_mock_false
    const/4 v1, 0x0
    :goto_set_flag
    invoke-virtual {v0, v1}, Landroid/location/Location;->setIsFromMockProvider(Z)V
EOF
        export FIND_REGEX REPLACE_TEXT
        perl -0777 -i -pe 's/$ENV{FIND_REGEX}/$ENV{REPLACE_TEXT}/s' "$file4"
    fi
}

remove_invoke_custom() {
    local unpack_dir="$1"
    if [[ ! -d "$unpack_dir" ]]; then
        echo -e "${RED}    ERROR: Direktori '$unpack_dir' tidak ditemukan.${NC}" >&2
        return 1
    fi
    local target_files
    target_files=$(grep -Rl "invoke-custom" "$unpack_dir" --include="*.smali")
    if [[ -z "$target_files" ]]; then
        return 0
    fi
    local find_equals='(\.method[^\n]*? equals\(Ljava/lang/Object;\)Z)[\s\S]*?invoke-custom[\s\S]*?(\.end method)'
    local replace_equals='\1\n    .registers 2\n    const/4 v0, 0x0\n    return v0\n\2'
    local find_hashcode='(\.method[^\n]*? hashCode\(\)I)[\s\S]*?invoke-custom[\s\S]*?(\.end method)'
    local replace_hashcode='\1\n    .registers 2\n    const/4 v0, 0x0\n    return v0\n\2'
    local find_tostring='(\.method[^\n]*? toString\(\)Ljava/lang/String;)[\s\S]*?invoke-custom[\s\S]*?(\.end method)'
    local replace_tostring='\1\n    .registers 2\n    const/4 v0, 0x0\n    return-object v0\n\2'
    echo "$target_files" | while read -r file; do
        perl -0777 -i -pe "s#$find_equals#$replace_equals#g" "$file"
        perl -0777 -i -pe "s#$find_hashcode#$replace_hashcode#g" "$file"
        perl -0777 -i -pe "s#$find_tostring#$replace_tostring#g" "$file"
    done
}

framework_menu() {
    local framework_name="framework.jar"
    local source_file="$sdcard_path/$framework_name"
    local is_unpacked=false
    local patches_applied=false
    local pif_patched=false
    local apk_protection_patched=false
    local invoke_custom_patched=false

    _ensure_unpacked() {
        if [[ "$is_unpacked" = true ]]; then return 0; fi
        echo ""
        rm -rf ifvank "$framework_name" framework-patched.apk *.bak > /dev/null 2>&1
        if [[ ! -f "$source_file" ]]; then echo -e "${RED}ERROR: $framework_name not found!${NC}"; return 1; fi
        cp "$source_file" "$work_dir/$framework_name"
        run_with_spinner "Unpacking $framework_name..." apkeditor d -i "$framework_name" -o ifvank
        if [[ ! -d "ifvank" ]]; then
            echo -e "${RED}ERROR: Failed to unpack $framework_name.${NC}"; rm -rf "$framework_name"; return 1
        else
            is_unpacked=true
            return 0
        fi
    }

    while true; do
        clear
        echo "====================================="
        echo -e "${GREEN}       Framework Patcher Menu${NC}"
        echo "====================================="
        echo ""
        
        local check1=""
        if [[ "$pif_patched" = true ]]; then check1=" ${GREEN}✓${NC}"; fi
        echo -e "  1. Play Integrity Fix$check1"
        
        local check2=""
        if [[ "$apk_protection_patched" = true ]]; then check2=" ${GREEN}✓${NC}"; fi
        echo -e "  2. Remove Apk Protection$check2"
        
        local check3=""
        if [[ "$invoke_custom_patched" = true ]]; then check3=" ${GREEN}✓${NC}"; fi
        echo -e "  3. Remove Invoke-Custom$check3"
        
        echo "  4. Repack & Save Changes"
        echo "  0. Back (Discard Changes)"
        echo ""
        read -p "Enter the number: " sub_choice
        case $sub_choice in
            1)
                _ensure_unpacked || { read -p "   Press Enter to continue..."; continue; }
                apply_pif_patches "ifvank"
                patches_applied=true; pif_patched=true
                echo -e "\n   ${GREEN}Patch 'Play Integrity Fix' applied.${NC}"; sleep 2
                ;;
            2)
                _ensure_unpacked || { read -p "   Press Enter to continue..."; continue; }
                apply_apk_protection_patches "ifvank"
                patches_applied=true; apk_protection_patched=true
                echo -e "\n   ${GREEN}Patch 'Remove APK Protection' applied.${NC}"; sleep 2
                ;;
            3)
                _ensure_unpacked || { read -p "   Press Enter to continue..."; continue; }
                remove_invoke_custom "ifvank"
                patches_applied=true; invoke_custom_patched=true
                echo -e "\n   ${GREEN}Patch 'Remove Invoke-Custom' applied.${NC}"; sleep 2
                ;;

            4)
                if [[ "$patches_applied" = false ]]; then
                    echo -e "\nNo patches were applied. Nothing to repack."; sleep 2; continue
                fi
                repack_framework() {
                    # Sembunyikan output lagi setelah kita yakin berhasil
                    apkeditor b -i ifvank -o framework-patched.apk > /dev/null 2>&1
                    [[ ! -f "framework-patched.apk" ]] && return 1
                    mv framework-patched.apk "$source_file"; return $?
                }
                echo ""
                run_with_spinner "Repacking framework.jar..." repack_framework
                if [[ $? -eq 0 ]]; then echo "[✓] framework.jar patched successfully!"; echo -e "${GREEN}Output: $source_file${NC}"; else echo -e "${RED}ERROR: Failed to repack framework.jar.${NC}"; fi
                rm -rf "$framework_name" ifvank framework-patched.apk
                read -p "   Press Enter to continue..."
                return
                ;;
            0)
                if [[ "$is_unpacked" = true ]]; then echo "Discarding changes..."; rm -rf "$framework_name" ifvank; fi
                return
                ;;
            *) echo "Invalid number."; sleep 2 ;;
        esac
    done
}

services_menu() {
    local services_name="services.jar"
    local source_file="$sdcard_path/$services_name"
    local is_unpacked=false
    local patches_applied=false
    local secure_screenshot_patched=false
    local mock_location_patched=false
    local invoke_custom_patched=false

    _ensure_unpacked() {
        if [[ "$is_unpacked" = true ]]; then return 0; fi
        echo ""
        rm -rf ifvank "$services_name" services-patched.apk *.bak > /dev/null 2>&1
        if [[ ! -f "$source_file" ]]; then echo -e "${RED}ERROR: $services_name not found!${NC}"; return 1; fi
        cp "$source_file" "$work_dir/$services_name"
        run_with_spinner "Unpacking $services_name..." apkeditor d -i "$services_name" -o ifvank
        if [[ ! -d "ifvank" ]]; then
            echo -e "${RED}ERROR: Failed to unpack $services_name.${NC}"; rm -rf "$services_name"; return 1
        else
            is_unpacked=true
            return 0
        fi
    }

    while true; do
        clear
        echo "====================================="
        echo -e "${GREEN}        services.jar Patcher${NC}"
        echo "====================================="
        echo ""
                
        local check1=""
        if [[ "$secure_screenshot_patched" = true ]]; then check1=" ${GREEN}✓${NC}"; fi
        echo -e "  1. Disable Secure Screenshot$check1"
        
        local check2=""
        if [[ "$mock_location_patched" = true ]]; then check2=" ${GREEN}✓${NC}"; fi
        echo -e "  2. Bypass Mock Location$check2"
        
        local check3=""
        if [[ "$invoke_custom_patched" = true ]]; then check3=" ${GREEN}✓${NC}"; fi
        echo -e "  3. Remove Invoke-Custom$check3"
        
        echo "  4. Repack & Save Changes"
        echo "  0. Back (Discard Changes)"
        echo ""
        read -p "Enter the number: " sub_choice
        case $sub_choice in
            1)
                _ensure_unpacked || { read -p "   Press Enter to continue..."; continue; }
                apply_secure_screenshot_patch "ifvank"; patches_applied=true; secure_screenshot_patched=true
                echo -e "\n   ${GREEN}Patch 'Disable Secure Screenshot' applied.${NC}"; sleep 2
                ;;
            2)
                _ensure_unpacked || { read -p "   Press Enter to continue..."; continue; }
                apply_mock_location_patch "ifvank"; patches_applied=true; mock_location_patched=true
                echo -e "\n   ${GREEN}Patch 'Bypass Mock Location' applied.${NC}"; sleep 2
                ;;
            3)
                _ensure_unpacked || { read -p "   Press Enter to continue..."; continue; }
                remove_invoke_custom "ifvank"; patches_applied=true; invoke_custom_patched=true
                echo -e "\n   ${GREEN}Patch 'Remove Invoke-Custom' applied.${NC}"; sleep 2
                ;;
            4)
                if [[ "$patches_applied" = false ]]; then
                    echo -e "\nNo patches were applied. Nothing to repack."; sleep 2; continue
                fi
                repack_services() {
                    apkeditor b -i ifvank -o services-patched.apk > /dev/null 2>&1
                    [[ ! -f "services-patched.apk" ]] && return 1
                    mv services-patched.apk "$source_file"; return $?
                }
                echo ""
                run_with_spinner "Repacking $services_name..." repack_services
                if [[ $? -eq 0 ]]; then echo "[✓] services.jar patched successfully!"; echo -e "${GREEN}Output: $source_file${NC}"; else echo -e "${RED}ERROR: Failed to repack.${NC}"; fi
                rm -rf "$services_name" ifvank services-patched.apk
                read -p "   Press Enter to continue..."
                return
                ;;
            0)
                if [[ "$is_unpacked" = true ]]; then echo "Discarding changes..."; rm -rf "$services_name" ifvank; fi
                return
                ;;
            *) echo "Invalid number."; sleep 2 ;;
        esac
    done
}

patch_both() {
    clear
    echo "====================================="
    echo -e "${GREEN}        Framework Auto Patch${NC}"
    echo "====================================="
    local framework_name="framework.jar"
    local source_file_fw="$sdcard_path/$framework_name"
    echo ""
    rm -rf ifvank "$framework_name" "${framework_name%.jar}-patched.apk" *.bak > /dev/null 2>&1
    if [[ ! -f "$source_file_fw" ]]; then
        echo -e "${RED}ERROR: $framework_name not found. Skipping.${NC}"
    else
        cp "$source_file_fw" "$work_dir/$framework_name"
        run_with_spinner "Unpacking $framework_name..." apkeditor d -i "$framework_name" -o ifvank
        if [[ ! -d "ifvank" ]]; then
            echo -e "${RED}ERROR: Failed to unpack $framework_name. Aborting patch.${NC}"; rm -rf "$framework_name"
        else
            _apply_all_framework_patches() {
                apply_pif_patches "ifvank"
                apply_apk_protection_patches "ifvank"
            }
            run_with_spinner "Patching framework.jar..." _apply_all_framework_patches
            repack_fw() {
                apkeditor b -i ifvank -o "${framework_name%.jar}-patched.apk" > /dev/null 2>&1
                [[ ! -f "${framework_name%.jar}-patched.apk" ]] && return 1
                mv "${framework_name%.jar}-patched.apk" "$source_file_fw"; return $?
            }
            run_with_spinner "Repacking $framework_name..." repack_fw
            if [[ $? -eq 0 ]]; then echo "[✓] framework.jar patched successfully!"; echo -e "${GREEN} Output: /sdcard/framework.jar${NC}"; else echo -e "${RED}ERROR: Failed to repack framework.jar.${NC}"; fi
        fi
        rm -rf "$framework_name" ifvank
    fi
    local services_name="services.jar"
    local source_file_sv="$sdcard_path/$services_name"
    echo ""
    rm -rf ifvank "$services_name" "${services_name%.jar}-patched.apk" *.bak > /dev/null 2>&1
    if [[ ! -f "$source_file_sv" ]]; then
        echo -e "${RED}ERROR: $services_name not found. Skipping.${NC}"
    else
        cp "$source_file_sv" "$work_dir/$services_name"
        run_with_spinner "Unpacking $services_name..." apkeditor d -i "$services_name" -o ifvank
        if [ ! -d "ifvank" ]; then
            echo -e "${RED}ERROR: Failed to unpack $services_name. Aborting patch.${NC}"; rm -rf "$services_name"
        else
            _apply_all_services_patches() {
                apply_secure_screenshot_patch "ifvank"
                apply_mock_location_patch "ifvank"
            }
            run_with_spinner "Patching services.jar..." _apply_all_services_patches
            repack_sv() {
                apkeditor b -i ifvank -o "${services_name%.jar}-patched.apk" > /dev/null 2>&1
                [[ ! -f "${services_name%.jar}-patched.apk" ]] && return 1
                mv "${services_name%.jar}-patched.apk" "$source_file_sv"; return $?
            }
            run_with_spinner "Repacking $services_name..." repack_sv
            if [[ $? -eq 0 ]]; then echo "[✓] services.jar patched successfully!"; echo -e "${GREEN} Output: /sdcard/services.jar${NC}"; else echo -e "${RED}ERROR: Failed to repack services.jar.${NC}"; fi
        fi
        rm -rf "$services_name" ifvank
    fi
}

main_menu() {
    clear
    echo -e "${GREEN}           Framework Patcher${NC}"
    echo -e "${GREEN}               By IFVank     ${NC}"
    echo -e "${GREEN}         Telegram : @AsalJadi${NC}"
    echo -e "${GREEN}--------------------------------------${NC}"
    echo ""
    echo "Main Menu:"
    echo "  1. Patch framework.jar"
    echo "  2. Patch services.jar"
    echo "  3. Patch Both (Auto)"
    echo "  0. Exit"
    echo ""
    read -p "Enter the number: " choice
}

while true; do
    main_menu
    case $choice in
        1) framework_menu ;;
        2) services_menu ;;
        3)
            patch_both
            echo ""
            read -p "   Process complete. Press Enter to return to the menu..."
            ;;
        0) echo "Exiting!"; exit 0 ;;
        *) echo "Invalid number, please try again."; sleep 2 ;;
    esac
done
