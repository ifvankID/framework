#!/bin/bash

# pkg install openjdk-17 zip unzip sed coreutils perl

sdcard_path="/sdcard"
framework_name="framework.jar"
source_file="$sdcard_path/$framework_name"
work_dir=$PWD

GREEN='\033[0;32m'
NC='\033[0m' # No Color

apkeditor() {
    jarfile=$work_dir/tool/APKEditor.jar
    if [[ ! -f "$jarfile" ]]; then
        echo "ERROR: APKEditor.jar not found in tool/ folder!"
        exit 1
    fi
    javaOpts="-Xmx4096M -Dfile.encoding=utf-8 -Djdk.util.zip.disableZip64ExtraFieldValidation=true -Djdk.nio.zipfs.allowDotZipEntry=true"
    java $javaOpts -jar "$jarfile" "$@" > /dev/null 2>&1
}
baksmali() {
    jarfile=$work_dir/tool/baksmali.jar
    if [[ ! -f $jarfile ]]; then
        echo "ERROR: baksmali.jar not found in tool/ folder!"
        exit 1
    fi
    java -jar "$jarfile" "$@" > /dev/null 2>&1
}
certificatechainPatch() {
 certificatechainPatch="
    .line $1
    invoke-static {}, Lcom/android/internal/util/ifvank/util/OplusPixelPropUtils;->onEngineGetCertificateChain()V
"
}
instrumentationPatch() {
	returnline=$(expr $2 + 1)
	instrumentationPatch="    invoke-static {$1}, Lcom/android/internal/util/ifvank/util/OplusAttestationHooks;->setProps(Landroid/content/Context;)V
    invoke-static {$1}, Lcom/android/internal/util/ifvank/util/OplusGamesFpsUtils;->setProps(Landroid/content/Context;)V
    invoke-static {$1}, Lcom/android/internal/util/ifvank/util/OplusPixelPropUtils;->setProps(Landroid/content/Context;)V
    .line $returnline
    "
}
keyboxutilsPatch() {
	keyboxutilsPatch="    invoke-static {$1}, Lcom/android/internal/util/ifvank/util/framework/KeyboxUtils;->engineGetCertificateChain([Ljava/security/cert/Certificate;)[Ljava/security/cert/Certificate;	
    move-result-object $1
    "
}
pixelPropsPatch() {
read -r -d '' pixelPropsPatch <<'EOF'
.method public whitelist hasSystemFeature(Ljava/lang/String;I)Z
    .registers 7
    .param p1, "name"  # Ljava/lang/String;
    .param p2, "version"  # I
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
    sget-object v0, Landroid/app/ApplicationPackageManager;->mHasSystemFeatureCache:Landroid/app/PropertyInvalidatedCache;
    new-instance v1, Landroid/app/ApplicationPackageManager$HasSystemFeatureQuery;
    invoke-direct {v1, p1, p2}, Landroid/app/ApplicationPackageManager$HasSystemFeatureQuery;-><init>(Ljava/lang/String;I)V
    invoke-virtual {v0, v1}, Landroid/app/PropertyInvalidatedCache;->query(Ljava/lang/Object;)Ljava/lang/Object;
    move-result-object v0
    check-cast v0, Ljava/lang/Boolean;
    invoke-virtual {v0}, Ljava/lang/Boolean;->booleanValue()Z
    move-result v0
    return v0
.end method
EOF
}
clinitWhitelistPatch() {
read -r -d '' clinitWhitelistPatch <<'EOF'
.method static constructor whitelist <clinit>()V
    .registers 18
    .line 806
    new-instance v0, Landroid/app/ApplicationPackageManager$1;
    const/16 v1, 0x100
    const-string v2, "cache_key.has_system_feature"
    invoke-direct {v0, v1, v2}, Landroid/app/ApplicationPackageManager$1;-><init>(ILjava/lang/String;)V
    sput-object v0, Landroid/app/ApplicationPackageManager;->mHasSystemFeatureCache:Landroid/app/PropertyInvalidatedCache;
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
    .line 1112
    new-instance v0, Landroid/app/ApplicationPackageManager$3;
    const/16 v1, 0x20
    const-string v2, "cache_key.get_packages_for_uid"
    invoke-direct {v0, v1, v2}, Landroid/app/ApplicationPackageManager$3;-><init>(ILjava/lang/String;)V
    sput-object v0, Landroid/app/ApplicationPackageManager;->mGetPackagesForUidCache:Landroid/app/PropertyInvalidatedCache;
    .line 3512
    new-instance v0, Ljava/lang/Object;
    invoke-direct {v0}, Ljava/lang/Object;-><init>()V
    sput-object v0, Landroid/app/ApplicationPackageManager;->sSync:Ljava/lang/Object;
    .line 3513
    new-instance v0, Landroid/util/ArrayMap;
    invoke-direct {v0}, Landroid/util/ArrayMap;-><init>()V
    sput-object v0, Landroid/app/ApplicationPackageManager;->sIconCache:Landroid/util/ArrayMap;
    .line 3515
    new-instance v0, Landroid/util/ArrayMap;
    invoke-direct {v0}, Landroid/util/ArrayMap;-><init>()V
    sput-object v0, Landroid/app/ApplicationPackageManager;->sStringCache:Landroid/util/ArrayMap;
    return-void
.end method
EOF
}
expressions_fix() {
	var=$1
	escaped_var=$(printf '%s\n' "$var" | sed 's/[\/&]/\\&/g')
	escaped_var=$(printf '%s\n' "$escaped_var" | sed 's/\[/\\[/g' | sed 's/\]/\\]/g' | sed 's/\./\\./g' | sed 's/;/\\;/g')
	echo "$escaped_var"
}

echo "====================================="
echo "        Framework Patcher"
echo "====================================="
echo ""

rm -rf ifvank framework.jar framework-patched.apk framework-final.jar > /dev/null 2>&1

if [[ ! -f "$source_file" ]]; then
    echo "ERROR: $framework_name not found in $sdcard_path!"
    exit 1
fi

(
    cp "$source_file" "$work_dir/$framework_name" && \
    apkeditor d -i framework.jar -o ifvank
) &
PID=$! 

spin='⣾⣽⣻⢿⡿⣟⣯⣷'
i=0
while kill -0 $PID 2>/dev/null; do
    i=$(( (i+1) % 8 ))
    printf "\r[*] Unpacking framework.jar... %s" "${spin:$i:1}"
    sleep 0.1
done

printf "\r[*] Unpacking framework.jar... [✓]\n"

if [[ ! -d "ifvank" ]]; then
    echo "ERROR: Failed to unpack framework.jar."
    exit 1
fi

# --- Main Process ---
{
    keystorespiclassfile=$(find ifvank/ -type f -name 'AndroidKeyStoreSpi.smali' | head -n 1)
    instrumentationsmali=$(find ifvank/ -type f -name "Instrumentation.smali"  | head -n 1)
    pm_smali=$(find ifvank/ -type f -name 'ApplicationPackageManager.smali' | head -n 1)
    sig_verifier_smali=$(find ifvank/ -type f -name 'ApkSignatureVerifier.smali' | head -n 1)

    if [[ -z "$pm_smali" || -z "$sig_verifier_smali" || -z "$keystorespiclassfile" || -z "$instrumentationsmali" ]]; then
        echo "ERROR: Could not find one or more required smali files!" >&2
        exit 1
    fi

    find_v3='(invoke-static\s*\{[^,]+,\s*[^,]+,\s*[^,]+,\s*([v|p]\d+)[^}]*\}, Landroid/util/apk/ApkSignatureVerifier;->verifyV3AndBelowSignatures\(Landroid/content/pm/parsing/result/ParseInput;Ljava/lang/String;IZ\)Landroid/content/pm/parsing/result/ParseResult;)'
    replace_v3="const/4 \\2, 0x0\n    \\1"
    perl -i -pe "s#$find_v3#$replace_v3#" "$sig_verifier_smali"
    find_v4='(invoke-static\s*\{[^,]+,\s*[^,]+,\s*[^,]+,\s*([v|p]\d+)[^}]*\}, Landroid/util/apk/ApkSignatureVerifier;->verifyV4Signature\(Landroid/content/pm/parsing/result/ParseInput;Ljava/lang/String;IZ\)Landroid/content/pm/parsing/result/ParseResult;)'
    replace_v4="const/4 \\2, 0x0\n    \\1"
    perl -i -pe "s#$find_v4#$replace_v4#" "$sig_verifier_smali"
    find_min_sdk='(\.method\s*public\s*static\s*blacklist\s*getMinimumSignatureSchemeVersionForTargetSdk\(I\)I)[\s\S]+?(\.end method)'
    perl -0777 -i -pe "s#$find_min_sdk#\1\n    .locals 1\n\n    const/4 v0, 0x0\n\n    return v0\n\2#g" "$sig_verifier_smali"

    engineGetCertMethod=$(expressions_fix "$(grep 'engineGetCertificateChain(' "$keystorespiclassfile")")
    newAppMethod1=$(expressions_fix "$(grep 'newApplication(Ljava/lang/ClassLoader;' "$instrumentationsmali")")
    newAppMethod2=$(expressions_fix "$(grep 'newApplication(Ljava/lang/Class;' "$instrumentationsmali")")
    sed -n "/^${engineGetCertMethod}/,/^\.end method/p" "$keystorespiclassfile" > tmp_keystore
    sed -i "/^${engineGetCertMethod}/,/^\.end method/d" "$keystorespiclassfile"
    sed -n "/^${newAppMethod1}/,/^\.end method/p" "$instrumentationsmali" > inst1
    sed -i "/^${newAppMethod1}/,/^\.end method/d" "$instrumentationsmali"
    sed -n "/^${newAppMethod2}/,/^\.end method/p" "$instrumentationsmali" > inst2
    sed -i "/^${newAppMethod2}/,/^\.end method/d" "$instrumentationsmali"
    inst1_insert=$(expr $(wc -l < inst1) - 2)
    instreg=$(grep "Landroid/app/Application;->attach(Landroid/content/Context;)V" inst1 | awk '{print $3}' | sed 's/},//')
    instline=$(expr $(grep -r ".line" inst1 | tail -n 1 | awk '{print $2}') + 1)
    instrumentationPatch $instreg $instline
    echo "$instrumentationPatch" | sed -i "${inst1_insert}r /dev/stdin" inst1
    inst2_insert=$(expr $(wc -l < inst2) - 2)
    instreg=$(grep "Landroid/app/Application;->attach(Landroid/content/Context;)V" inst2 | awk '{print $3}' | sed 's/},//')
    instline=$(expr $(grep -r ".line" inst2 | tail -n 1 | awk '{print $2}') + 1)
    instrumentationPatch $instreg $instline
    echo "$instrumentationPatch" | sed -i "${inst2_insert}r /dev/stdin" inst2
    kstoreline=$(expr $(grep -r ".line" tmp_keystore | head -n 1 | awk '{print $2}') - 2)
    certificatechainPatch $kstoreline
    echo "$certificatechainPatch" | sed -i '4r /dev/stdin' tmp_keystore
    lastaput=$(grep "aput-object" tmp_keystore | tail -n 1)
    leafcert=$(echo $lastaput | awk '{print $3}' | awk -F',' '{print $1}')
    keybox_utils=$(expr $(grep -n "$lastaput" tmp_keystore | awk -F':' '{print $1}') + 1)
    keyboxutilsPatch $leafcert
    echo "$keyboxutilsPatch" | sed -i "${keybox_utils}r /dev/stdin" tmp_keystore
    cat inst1 >> "$instrumentationsmali"
    cat inst2 >> "$instrumentationsmali"
    cat tmp_keystore >> "$keystorespiclassfile"
    rm -rf inst1 inst2 tmp_keystore
    FEATURES_FIELDS=".field private static final whitelist featuresAndroid:[Ljava/lang/String;\n\
.field private static final whitelist featuresNexus:[Ljava/lang/String;\n\
.field private static final whitelist featuresPixel:[Ljava/lang/String;\n\
.field private static final whitelist featuresPixelOthers:[Ljava/lang/String;\n\
.field private static final whitelist featuresTensor:[Ljava/lang/String;"
    sed -i "/# static fields/a ${FEATURES_FIELDS}" "$pm_smali"
    CODENAME_FIELD=".field private static final whitelist pTensorCodenames:[Ljava/lang/String;"
    sed -i "/\.field private static final greylist-max-o sDefaultFlags:I = 0x400/i ${CODENAME_FIELD}" "$pm_smali"
    find_regex='(\.method static constructor blacklist <clinit>\(\)V)[\s\S]*?(\.end method)'
    clinitWhitelistPatch
    export FIND_REGEX="$find_regex"
    export REPLACE_TEXT="$clinitWhitelistPatch"
    perl -0777 -i -pe 's/$ENV{FIND_REGEX}/$ENV{REPLACE_TEXT}/' "$pm_smali"
    find_regex='\.method public whitelist hasSystemFeature\(Ljava/lang/String;I\)Z[\s\S]+?sget-object v\d+, Landroid/app/ApplicationPackageManager;->mHasSystemFeatureCache:Landroid/app/PropertyInvalidatedCache;[\s\S]+?\.end method'
    pixelPropsPatch
    export FIND_REGEX="$find_regex"
    export REPLACE_TEXT="$pixelPropsPatch"
    perl -0777 -i -pe 's/$ENV{FIND_REGEX}/$ENV{REPLACE_TEXT}/' "$pm_smali"
    if [[ -f "PIF/classes.dex" ]]; then
        baksmali d "PIF/classes.dex" -o classes5
        if [ ! -d "classes5" ]; then exit 1; fi
        rm -rf "ifvank/smali_classes5"
        mv "classes5" "ifvank/smali/classes5"
        if [ ! -d "ifvank/smali/classes5" ]; then exit 1; fi
    fi
} &
PID=$!

spin='⣾⣽⣻⢿⡿⣟⣯⣷'
i=0
while kill -0 $PID 2>/dev/null; do
    i=$(( (i+1) % 8 ))
    printf "\r[*] Patching framework.jar... %s" "${spin:$i:1}"
    sleep 0.1
done

printf "\r[*] Patching framework.jar... [✓]\n"

{
    apkeditor b -i ifvank -o framework-patched.apk
    if [[ ! -f "framework-patched.apk" ]]; then exit 1; fi
    mv framework-patched.apk framework-final.jar
    if [[ ! -f "framework-final.jar" ]]; then exit 1; fi
    mv "framework-final.jar" "$source_file"
    if [[ $? -ne 0 ]]; then exit 1; fi
} &
PID=$!

spin='⣾⣽⣻⢿⡿⣟⣯⣷'
i=0
while kill -0 $PID 2>/dev/null; do
    i=$(( (i+1) % 8 ))
    printf "\r[*] Repacking framework.jar... %s" "${spin:$i:1}"
    sleep 0.1
done

printf "\r[*] Repacking framework.jar... [✓]\n"

rm -rf framework.jar ifvank

echo "[✓] Patching successful!"
echo -e "${GREEN}Output = $source_file${NC}"
