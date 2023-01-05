#!/usr/bin/env bash
# set -x

PROG=$0

help() {
    cat <<FILE
Usage: bash ${PROG} <arguments>
       Wrapper around terraform plan that provides a cleaner output as to what is being
       provisioned or destroyed.
Arguments:
       <terraform args>     All the arguments that terraform normally supports.
       -show-create         Shows the resources to be created
       -show-update         Shows the resources to be updated
       -show-delete         Shows the resources to be destroyed or replaced
       -show-all            Shows all of the above changes
       -destroy-plan        Create plan for terraform destroy
       -verbose             Increase the output verbosity (Defaults to false)
       -help                Show this message.
Example:
       # Plan for Applying
       bash ${PROG} -verbose -show-all -var-file=test.tfvars
       bash ${PROG} -show-all -var-file=test.tfvars

       # Plan for Destroy
       bash ${PROG} -verbose -destroy-plan -show-all -var-file=test.tfvars
       bash ${PROG} -show-all -destroy-plan -var-file=test.tfvars
FILE
}

colred='\u001b[31m' # Red
colgrn='\u001b[32m' # Green
colylw='\u001b[33m' # Yellow
colrst='\u001b[0m'  # Text Reset

check_error() {
    errors=$(echo "$tfp" | jq -r -R 'fromjson? | select((."@level" == "error" and .diagnostic.severity == "error")).diagnostic
                            | {"summary":.summary,"details":.detail,"file":.range.filename,"lines":"\(.range.start.line)-\(.range.end.line)"}')
    [[ -z "$errors" ]] && return
    while read -r object ; do
        summary=$(echo "$object" | jq -r '.summary')
        details=$(echo "$object" | jq -r '.details')
        file=$(echo "$object" | jq -r '.file')
        lines=$(echo "$object" | jq -r '.lines')
        echo -e "\n${colred}$summary${colrst}"
        echo -e "-----------------------------------------------------------------"
        echo -e "${colred}Details:${colrst} ${details}"
        echo -e "${colred}File:${colrst} ${file}"
        echo -e "${colred}Line No.:${colrst} ${lines}"
    done < <(echo "$errors" | jq -rc '.')
    exit 1
}

show() {
    # JQ Explanation:
    # 1. get all "info" @level objects,
    # 2. check if the action corresponds to the action specified,
    # 3. if verbose or module doesn't exist then print address

    TMPFILE=$(mktemp)
    trap 'rm -f $TMPFILE' EXIT
    echo "Generating terraform plan..."
    # shellcheck disable=SC2086,SC2048
    # Quotations adds empty quotes if no $EXTRA_ARGS or $DESTROY_PLAN is passed, this breaks terraform
    tfp=$(terraform plan ${DESTROY_PLAN:-$DESTROY_PLAN} -json -input=false -out="$TMPFILE" ${EXTRA_ARGS[*]})
    check_error
    for action in "${ACTION[@]}"; do
        clr="${action%|*}"
        txt="${action#*|}"
        echo -e "\nShowing ${clr}${txt}s$colrst"
        echo -e "-----------------------------------------------------------------$clr"
        echo "$tfp" |
            jq -r --arg VERBOSE "$VERBOSE" --arg ACTION "$txt" -R \
                'fromjson? | select(select(.["@level"] | (. != null) and test("info"; "in")).change.action
                | (. != null) and test($ACTION;"in")).change.resource
                | if (.module == "") or ($VERBOSE == "true") then .addr else .module end' | sort | uniq || exit 1
        echo -e "$colrst"
    done

    echo "Do you want to apply or cancel? (apply/cancel)"
    read -r ACTION

    [[ "$ACTION" != "apply" ]] && exit 0

    terraform apply "$TMPFILE" && exit 0
}

VERBOSE="false"
EXTRA_ARGS=""
ACTION=""
DESTROY_PLAN=""

while [[ -n "$1" ]]; do
    case "$1" in
        -show-create)
            ACTION=("${colgrn}|create")
            shift
            ;;
        -show-update)
            ACTION=("${colylw}|update")
            shift
            ;;
        -show-delete)
            ACTION=("${colred}|replace" "${colred}|delete")
            shift
            ;;
        -show-all)
            ACTION=("${colgrn}|create" "${colylw}|update" "${colred}|replace" "${colred}|delete")
            shift
            ;;
        -destroy-plan)
            DESTROY_PLAN="-destroy"
            shift
            ;;
        -help)
            help && exit 0
            ;;
        -verbose)
            VERBOSE="true"
            shift
            ;;
        *)
            EXTRA_ARGS=("$*")
            break
            ;;
    esac
done

if [[ -n "${ACTION[*]}" ]]; then
    show "${ACTION[@]}"
fi
