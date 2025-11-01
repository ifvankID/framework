#!/bin/bash

# pkg install openjdk-17 zip unzip sed coreutils perl git -y

sdcard_path="/sdcard"
work_dir=$PWD

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

rm -rf ifvank_fw ifvank_sv *.bak *.apk > /dev/null 2>&1

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

apktool() {
    local jarfile=$work_dir/tool/apktool.jar
    if [[ ! -f "$jarfile" ]]; then
        echo -e "${RED}ERROR: apktool.jar not found in tool/ folder!${NC}"
        return 1
    fi
    java -Xmx2048M -jar "$jarfile" "$@"
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

remove_invoke_custom() {
    local unpack_dir="$1"
    if [[ ! -d "$unpack_dir" ]]; then
        echo -e "${RED}    ERROR: Directory '$unpack_dir' not found.${NC}" >&2
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

remove_debug_info_files() {
    local unpack_dir="$1"
    if [[ ! -d "$unpack_dir" ]]; then return 1; fi
    echo ""
    local perl_command="find \"$unpack_dir\" -name \"*.smali\" -type f -exec perl -i -ne 'print unless /^\s*\\.(line|source|param)/' {} +"
   
        bash -c "$perl_command"
    
    return $?
}

apk_protection_patches() {
    local unpack_dir="$1"
    local sig_verifier_smali=$(find "$unpack_dir" -type f -name 'ApkSignatureVerifier.smali' | head -n 1)
    if [[ -z "$sig_verifier_smali" ]]; then echo -e "${RED}    ERROR: ApkSignatureVerifier.smali not found.${NC}"; return 1; fi
    local find_v3='(invoke-static\s*\{[^,]+,\s*[^,]+,\s*[^,]+,\s*([v|p]\d+)[^}]*\}, Landroid/util/apk/ApkSignatureVerifier;->verifyV3AndBelowSignatures\(Landroid/content/pm/parsing/result/ParseInput;Ljava/lang/String;IZ\)Landroid/content/pm/parsing/result/ParseResult;)'
    local replace_v3="const/4 \\2, 0x0\n    \\1"
    perl -i'' -pe "s#$find_v3#$replace_v3#" "$sig_verifier_smali"
    local find_v4='(invoke-static\s*\{[^,]+,\s*[^,]+,\s*[^,]+,\s*([v|p]\d+)[^}]*\}, Landroid/util/apk/ApkSignatureVerifier;->verifyV4Signature\(Landroid/content/pm/parsing/result/ParseInput;Ljava/lang/String;IZ\)Landroid/content/pm/parsing/result/ParseResult;)'
    local replace_v4="const/4 \\2, 0x0\n    \\1"
    perl -i'' -pe "s#$find_v4#$replace_v4#" "$sig_verifier_smali"
    local find_min_sdk='(\.method\s*public\s*static\s*blacklist\s*getMinimumSignatureSchemeVersionForTargetSdk\(I\)I)[\s\S]+?(\.end method)'
    perl -0777 -i'' -pe "s#$find_min_sdk#\1\n    .locals 1\n\n    const/4 v0, 0x0\n\n    return v0\n\2#g" "$sig_verifier_smali"
}

mock_location_patch() {
    local unpack_dir="$1"

    local file3=$(grep -lr '.method public noteOp(ILandroid/location/util/identity/CallerIdentity;)Z' "$unpack_dir" | head -n 1)

    if [[ -n "$file3" ]]; then

    local FIND_REGEX='(\.method public noteOp\(ILandroid\/location\/util\/identity\/CallerIdentity;\)Z)[\s\S]*?(\.end method)'

    read -r -d '' REPLACE_TEXT <<'EOF'

    .locals 1
    const/4 v0, 0x1
    return v0

EOF

    export FIND_REGEX REPLACE_TEXT

    perl -0777 -i -pe 's/$ENV{FIND_REGEX}/$1 . $ENV{REPLACE_TEXT} . $2/se' "$file3"
    fi

    local file4=$(grep -lr 'Landroid/location/Location;->setIsFromMockProvider(Z)V' "$unpack_dir" | grep 'MockLocationProvider.smali$' | head -n 1)
    if [[ -n "$file4" ]]; then
        local FIND_REGEX='(const\/4 v1, 0x1\s*invoke-virtual \{v0, v1\}, Landroid\/location\/Location;->setIsFromMockProvider\(Z\)V)'
        read -r -d '' REPLACE_TEXT <<'EOF'
    const/4 v1, 0x0
    invoke-virtual {v0, v1}, Landroid/location/Location;->setIsFromMockProvider(Z)V
EOF
        export FIND_REGEX REPLACE_TEXT
        perl -0777 -i -pe 's#$ENV{FIND_REGEX}#$ENV{REPLACE_TEXT}#s' "$file4"
    fi
}

apply_lockout_patch() {
    local unpack_dir="$1"
    local limit_value="$2"
    
    local new_limit_hex=$(printf "0x%x" "$limit_value")
    find "$unpack_dir" -type f -name "*.smali" -exec sed -i -E "s/(\.field private static final MAX_FAILED_ATTEMPTS_LOCKOUT_TIMED:I = )0x[0-9a-fA-F]+/\\1$new_limit_hex/g" {} + > /dev/null 2>&1
    local patched_files_count=$(grep -l "MAX_FAILED_ATTEMPTS_LOCKOUT_TIMED:I = $new_limit_hex" "$unpack_dir" -r --include="*.smali" | wc -l)
    if [ "$patched_files_count" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

pif_submenu() {
    local unpack_dir="$1"
    local pif_patched_status="$2" 
    local ensure_unpacked_func_name="$3" 
    
    local new_pif_patched_status=$pif_patched_status
    local parent_is_unpacked=false 
    
    if [[ -d "$unpack_dir" ]]; then
        parent_is_unpacked=true
    fi

    while true; do
        clear
        echo "====================================="
        echo -e "${GREEN}      Play Integrity Fix Menu${NC}"
        echo "====================================="
        echo ""
        
        echo "  1. PIF Android 13-15"
        echo "  2. PIF Android 16"
        echo "  3. Play Integrity Fix By Danda"
        echo "  0. Back to Framework Menu"
        echo ""
        read -p "Select an option: " sub_choice

        if [[ "$new_pif_patched_status" = true && ( "$sub_choice" = "1" || "$sub_choice" = "2" || "$sub_choice" = "3" ) ]]; then
            echo -e "\n   ${GREEN}PIF patch is already applied. No need to patch again.${NC}"; sleep 2
            continue 
        fi

        case $sub_choice in
            1)
                "$ensure_unpacked_func_name" || { read -p "   Unpack failed. Press Enter..."; continue; }
                parent_is_unpacked=true 
                
                local script_path="tool/pif1"
                if [[ ! -f "$script_path" ]]; then
                    echo -e "\n   ${RED}ERROR: $script_path not found!${NC}"; sleep 2
                    continue
                fi
                
                chmod +x "$script_path" 
                run_with_spinner "Applying PIF Android 13-15..." bash "$script_path" "$unpack_dir"
                
                if [[ $? -eq 0 ]]; then
                    new_pif_patched_status=true
                    echo -e "\n   ${GREEN}Patch 'PIF Android 13-15' applied..${NC}"
                    echo "   Returning to framework menu..."
                    sleep 2
                    return 0
                else
                    echo -e "\n   ${RED}Patch 'PIF Android 13-15' failed.${NC}"
                    sleep 2
                fi
                ;;
            2)
                "$ensure_unpacked_func_name" || { read -p "   Unpack failed. Press Enter..."; continue; }
                parent_is_unpacked=true

                local script_path="tool/pif2"
                if [[ ! -f "$script_path" ]]; then
                    echo -e "\n   ${RED}ERROR: $script_path not found!${NC}"; sleep 2
                    continue
                fi
                
                chmod +x "$script_path" 
                run_with_spinner "Applying PIF Android 16..." bash "$script_path" "$unpack_dir"

                if [[ $? -eq 0 ]]; then
                    new_pif_patched_status=true
                    echo -e "\n   ${GREEN}Patch 'PIF Android 16' applied..${NC}"
                    echo "   Returning to framework menu..."
                    sleep 2
                    return 0
                else
                    echo -e "\n   ${RED}Patch 'PIF Android 16' failed.${NC}"
                    sleep 2
                fi
                ;;
            3)
                "$ensure_unpacked_func_name" || { read -p "   Unpack failed. Press Enter..."; continue; }
                parent_is_unpacked=true

                local script_path="tool/pifdanda"
                if [[ ! -f "$script_path" ]]; then
                    echo -e "\n   ${RED}ERROR: $script_path not found!${NC}"; sleep 2
                    continue
                fi
                
                chmod +x "$script_path" 
                run_with_spinner "Applying PIF By Danda..." bash "$script_path" "$unpack_dir"

                if [[ $? -eq 0 ]]; then
                    new_pif_patched_status=true
                    echo -e "\n   ${GREEN}Patch 'PIF By Danda' applied..${NC}"
                    echo "   Returning to framework menu..."
                    sleep 2
                    return 5
                else
                    echo -e "\n   ${RED}Patch 'PIF By Danda' failed.${NC}"
                    sleep 2
                fi
                ;;
            0)
                if [[ "$new_pif_patched_status" = true ]]; then
                    return 0 
                elif [[ "$parent_is_unpacked" = true ]]; then
                    return 2 
                else
                    return 1 
                fi
                ;;
            *) echo "Invalid option."; sleep 2 ;;
        esac
    done
}


framework_menu() {
    local framework_name="framework.jar"
    local source_file="$sdcard_path/$framework_name"
    local unpack_dir="ifvank_fw" 
    local is_unpacked=false
    local patches_applied=false
    local pif_patched=false
    local apk_protection_patched=false
    local invoke_custom_patched=false
    local debug_info_removed=false
    
    local pif_danda_mode=false

    ensure_unpacked_fw() {
        if [[ "$is_unpacked" = true ]]; then return 0; fi
        if [[ -d "$unpack_dir" ]]; then
            echo -e "\n   ${GREEN}Found existing directory '$unpack_dir'. Using...${NC}"
            is_unpacked=true 
            return 0
        fi
        echo ""
        rm -rf "$unpack_dir" "$framework_name" framework-patched.apk *.bak > /dev/null 2>&1
        if [[ ! -f "$source_file" ]]; then echo -e "${RED}ERROR: $framework_name not found!${NC}"; return 1; fi
        cp "$source_file" "$work_dir/$framework_name"
        run_with_spinner "Unpacking $framework_name..." apkeditor d -i "$framework_name" -o "$unpack_dir"
        if [[ ! -d "$unpack_dir" ]]; then
            echo -e "${RED}ERROR: Failed to unpack $framework_name.${NC}"; rm -rf "$framework_name"; return 1
        else
            is_unpacked=true
            rm -f "$framework_name" 
            return 0
        fi
    }

    while true; do
        clear
        echo "====================================="
        echo -e "${GREEN}       Framework Patcher Menu${NC}"
        echo "====================================="
        echo ""
        
        local check_pif=""
        if [[ "$pif_patched" = true ]]; then check_pif=" ${GREEN}✓${NC}"; fi
        echo -e "  1. Play Integrity Fix$check_pif"
        
        local check_apk_prot=""
        if [[ "$apk_protection_patched" = true ]]; then check_apk_prot=" ${GREEN}✓${NC}"; fi
        echo -e "  2. Remove Apk Protection$check_apk_prot"
        
        local check_invoke_custom=""
        if [[ "$invoke_custom_patched" = true ]]; then check_invoke_custom=" ${GREEN}✓${NC}"; fi
        echo -e "  3. Remove Invoke-Custom$check_invoke_custom"
        
        local check_debug_info=""
        if [[ "$debug_info_removed" = true ]]; then check_debug_info=" ${GREEN}✓${NC}"; fi
        echo -e "  4. Remove Debug Info$check_debug_info"

        echo "  5. Repack & Save Changes"
        echo "  0. Back (Discard Changes)"
        echo ""
        read -p "Select an option: " sub_choice
        case $sub_choice in
            1)
                pif_submenu "$unpack_dir" "$pif_patched" "ensure_unpacked_fw"
                local submenu_result=$? 
                
                if [[ $submenu_result -eq 0 ]]; then                    
                    patches_applied=true
                    pif_patched=true
                    is_unpacked=true 
                elif [[ $submenu_result -eq 5 ]]; then
                    patches_applied=true
                    pif_patched=true
                    pif_danda_mode=true
                    is_unpacked=true
                elif [[ $submenu_result -eq 2 ]]; then 
                    is_unpacked=true 
                fi
                ;;
            2)
                ensure_unpacked_fw || { read -p "   Press Enter to continue..."; continue; }
                apk_protection_patches "$unpack_dir"
                patches_applied=true; apk_protection_patched=true
                echo -e "\n   ${GREEN}Patch 'Remove APK Protection' applied.${NC}"; sleep 2
                ;;
            3)
                ensure_unpacked_fw || { read -p "   Press Enter to continue..."; continue; }
                remove_invoke_custom "$unpack_dir"
                patches_applied=true; invoke_custom_patched=true
                echo -e "\n   ${GREEN}Patch 'Remove Invoke-Custom' applied.${NC}"; sleep 2
                ;;
            4) 
                ensure_unpacked_fw || { read -p "   Press Enter to continue..."; continue; }
                remove_debug_info_files "$unpack_dir"
                debug_info_removed=true
                patches_applied=true
                echo -e "\n   ${GREEN}Debug info removed from smali files.${NC}"; sleep 2
                ;;
            5) 
                if [[ "$patches_applied" = false && "$is_unpacked" = false ]]; then
                    echo -e "\nNo changes detected. Nothing to repack."; sleep 2; continue
                fi
                if [[ "$is_unpacked" = false ]]; then
                    echo -e "\nFramework is not unpacked. Nothing to repack."; sleep 2; continue
                fi
                
                repack_framework() {
                    local temp_repack_apk="framework-repack.apk"
                    local final_jar_file="framework-patched.jar"
                    rm -f "$temp_repack_apk" "$final_jar_file"

                    apkeditor b -i "$unpack_dir" -o "$temp_repack_apk" > /dev/null 2>&1
                    [[ ! -f "$temp_repack_apk" ]] && echo -e "${RED}ERROR: apkeditor b failed.${NC}" && return 1

                    if [[ "$pif_danda_mode" = true ]]; then
                        
                        local temp_repack_dir="temp_repack_work"
                        rm -rf "$temp_repack_dir"
                        mkdir "$temp_repack_dir"
                        
                        unzip -q "$temp_repack_apk" -d "$temp_repack_dir"
                        
                        local last_num=$(find "$temp_repack_dir" -type f -name 'classes*.dex' | sed -n 's/.*classes\([0-9]\+\).dex/\1/p' | sort -n | tail -n 1)
                        if [[ -z "$last_num" ]]; then
                             if [[ -f "$temp_repack_dir/classes.dex" ]]; then last_num=1; else last_num=0; fi
                        fi
                        local patchclass_num=$(expr $last_num + 1)
                        local target_dex_name="classes${patchclass_num}.dex"
                        
                        local pif_source_file="$work_dir/PIF/danda.dex"
                        if [[ ! -f "$pif_source_file" ]]; then
                             echo -e "${RED}ERROR: PIF/danda.dex not found during repack!${NC}"; rm -rf "$temp_repack_dir" "$temp_repack_apk"; return 1
                        fi
                        cp "$pif_source_file" "$temp_repack_dir/$target_dex_name"
                        
                        (cd "$temp_repack_dir" && zip -qr0 -t 07302003 "$work_dir/$final_jar_file" ./*)
                        
                        rm -rf "$temp_repack_dir" "$temp_repack_apk"
                        
                    else
                        
                        mv -f "$temp_repack_apk" "$final_jar_file"
                    fi
                    
                    if [[ -f "$final_jar_file" ]]; then
                        mv -f "$final_jar_file" "$sdcard_path/${framework_name%.jar}-patched.jar"
                        return 0
                    else
                        echo -e "${RED}ERROR: Failed to create final jar file.${NC}"
                        return 1
                    fi
                }
                
                echo ""
                run_with_spinner "Repacking framework.jar..." repack_framework
                
                if [[ $? -eq 0 ]]; then 
                    echo "[✓] framework.jar patched successfully!"
                    echo -e "${GREEN}Output: $sdcard_path/${framework_name%.jar}-patched.jar${NC}"
                    rm -rf "$framework_name" "$unpack_dir" framework-patched.apk 
                else 
                    echo -e "${RED}ERROR: Failed to repack framework.jar.${NC}"
                fi
                
                read -p "   Press Enter to continue..."
                return
                ;;
            0)
                if [[ "$is_unpacked" = true ]]; then 
                    echo "Returning to main menu... (Changes in '$unpack_dir' are kept)"
                fi
                return
                ;;
            *) echo "Invalid option."; sleep 2 ;;
        esac
    done
}

services_menu() {
    local services_name="services.jar"
    local source_file="$sdcard_path/$services_name"
    local unpack_dir="ifvank_sv" 
    local is_unpacked=false
    local patches_applied=false
    local mock_location_patched=false
    local invoke_custom_patched=false
    local lockout_limit_patched=false

    ensure_unpacked_sv() {
        if [[ "$is_unpacked" = true ]]; then return 0; fi
        if [[ -d "$unpack_dir" ]]; then
            echo -e "\n   ${GREEN}Found existing directory '$unpack_dir'. Using...${NC}"
            is_unpacked=true
            return 0
        fi
        echo ""
        rm -rf "$unpack_dir" "$services_name" services-patched.apk *.bak > /dev/null 2>&1
        if [[ ! -f "$source_file" ]]; then echo -e "${RED}ERROR: $services_name not found!${NC}"; return 1; fi
        cp "$source_file" "$work_dir/$services_name"
        run_with_spinner "Unpacking $services_name..." apkeditor d -i "$services_name" -o "$unpack_dir"
        if [[ ! -d "$unpack_dir" ]]; then
            echo -e "${RED}ERROR: Failed to unpack $services_name.${NC}"; rm -rf "$services_name"; return 1
        else
            is_unpacked=true
            rm -f "$services_name"
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
        if [[ "$mock_location_patched" = true ]]; then check1=" ${GREEN}✓${NC}"; fi
        echo -e "  1. Bypass Mock Location$check1"
        
        local check2=""
        if [[ "$invoke_custom_patched" = true ]]; then check2=" ${GREEN}✓${NC}"; fi
        echo -e "  2. Remove Invoke-Custom$check2"

        local check3=""
        if [[ "$lockout_limit_patched" = true ]]; then check3=" ${GREEN}✓${NC}"; fi
        echo -e "  3. Increase Lockscreen Attempts$check3"

        echo "  4. Repack & Save Changes"
        echo "  0. Back (Discard Changes)"
        echo ""
        read -p "Select an option: " sub_choice
        case $sub_choice in
            1)
                ensure_unpacked_sv || { read -p "   Press Enter to continue..."; continue; }
                mock_location_patch "$unpack_dir"; patches_applied=true; mock_location_patched=true
                echo -e "\n   ${GREEN}Patch 'Bypass Mock Location' applied.${NC}"; sleep 2
                ;;
            2)
                ensure_unpacked_sv || { read -p "   Press Enter to continue..."; continue; }
                remove_invoke_custom "$unpack_dir"; patches_applied=true; invoke_custom_patched=true
                echo -e "\n   ${GREEN}Patch 'Remove Invoke-Custom' applied.${NC}"; sleep 2
                ;;
            3)
                ensure_unpacked_sv || { read -p "   Press Enter to continue..."; continue; }
                
                echo ""
                read -p "Enter the maximum number of failed attempts (1-20): " max_attempts
                if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || [ "$max_attempts" -lt 1 ] || [ "$max_attempts" -gt 20 ]; then
                    echo -e "\n${RED}ERROR: Invalid input. Please enter a number between 1 and 20.${NC}"
                    sleep 2
                    continue
                fi

                if apply_lockout_patch "$unpack_dir" "$max_attempts"; then
                    patches_applied=true; lockout_limit_patched=true
                    echo -e "\n   ${GREEN}Patch 'Increase Lockscreen Attempts' applied.${NC}"; sleep 2
                else
                    echo -e "\n   ${RED}Patch failed. Could not find the value to change.${NC}"; sleep 2
                fi
                ;;
            4)
                if [[ "$patches_applied" = false && "$is_unpacked" = false ]]; then
                    echo -e "\nNo changes detected. Nothing to repack."; sleep 2; continue
                fi
                if [[ "$is_unpacked" = false ]]; then
                    echo -e "\nServices is not unpacked. Nothing to repack."; sleep 2; continue
                fi
                
                repack_services() {
                    apkeditor b -i "$unpack_dir" -o services-patched.apk > /dev/null 2>&1
                    [[ ! -f "services-patched.apk" ]] && return 1
                    mv -f "services-patched.apk" "$sdcard_path/${services_name%.jar}-patched.jar"
                    return $?
                }
                echo ""
                run_with_spinner "Repacking $services_name..." repack_services
                if [[ $? -eq 0 ]]; then 
                    echo "[✓] services.jar patched successfully!"; echo -e "${GREEN}Output: $sdcard_path/services-patched.jar${NC}"
                    rm -rf "$services_name" "$unpack_dir" services-patched.apk 
                else 
                    echo -e "${RED}ERROR: Failed to repack.${NC}"; 
                fi
                
                read -p "   Press Enter to continue..."
                return
                ;;
            0)
                if [[ "$is_unpacked" = true ]]; then 
                    echo "Returning to main menu... (Changes in '$unpack_dir' are kept)"
                fi
                return
                ;;
            *) echo "Invalid option."; sleep 2 ;;
        esac
    done
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
    echo "  3. Disable Signature Verification"
    echo "  4. Disable Flag Secure"
    echo "  0. Exit"
    echo ""
    read -p "Select an option: " choice
}

while true; do
    main_menu
    case $choice in
        1) framework_menu ;;
        2) services_menu ;;
        3)
            while true; do
                clear
                echo "=========================================="
                echo -e "      ${GREEN}Disable Signature Verification${NC}"
                echo "=========================================="
                echo " 1. Android 13-14"
                echo " 2. Android 15-16"
                echo " 3. DSV - Strong 💪"
                echo " 0. Main Menu"
                echo ""
                read -p "   Select an option: " sub_choice

                case $sub_choice in
                    1)
                        dsv_path="./tool/dsv13-14"
                        if [[ -f "$dsv_path" ]]; then
                            chmod +x "$dsv_path" 
                            bash "$dsv_path"
                            echo ""
                            read -p "   Done. Press [Enter] to return..."
                        else
                            echo ""
                            echo -e "${RED}ERROR: Patcher file $dsv_path not found!${NC}"
                            sleep 2
                        fi
                        ;;
                    2)
                        dsv_path="./tool/dsv15"
                        if [[ -f "$dsv_path" ]]; then
                            chmod +x "$dsv_path" 
                            bash "$dsv_path"
                            echo ""
                            read -p "   Done. Press [Enter] to return..."
                        else
                            echo ""
                            echo -e "${RED}ERROR: Patcher file $dsv_path not found!${NC}"
                            sleep 2
                        fi
                        ;;
                    3)
                        dsv_path="./tool/strongdsv"
                        if [[ -f "$dsv_path" ]]; then
                            chmod +x "$dsv_path" 
                            bash "$dsv_path"
                            echo ""
                            read -p "   Done. Press [Enter] to return..."
                        else
                            echo ""
                            echo -e "${RED}ERROR: Patcher file $dsv_path not found!${NC}"
                            sleep 2
                        fi
                        ;;
                    0)
                        break
                        ;;
                    *)
                        echo ""
                        echo -e "${RED}Invalid option! Please try again.${NC}"
                        sleep 2
                        ;;
                esac
            done
            ;;
        4) 
            dfs_path="./tool/dfs"
                        if [[ -f "$dfs_path" ]]; then
                            chmod +x "$dfs_path" 
                            bash "$dfs_path"
                            echo ""
                            read -p "   Done. Press [Enter] to return..."
                        else
                            echo ""
                            echo -e "${RED}ERROR: Patcher file $dfs_path not found!${NC}"
                            sleep 2
                        fi
                        ;;
        0) 
            echo "Cleaning up temporary directories..."
            rm -rf ifvank_fw ifvank_sv
            echo "Exit!"
            exit 0
            ;;
        *) 
            echo "Invalid option, try again."
            sleep 2
            ;;
    esac
done
