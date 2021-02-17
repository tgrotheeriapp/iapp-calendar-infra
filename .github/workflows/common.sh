#!/bin/bash

echo "loading common shared functions ..."

###################### 
# Script starts here #
######################
# include dependencies
. $WORKFLOW_HOME/yaml.sh

#CONSTANTS
DEFAULT_VALUE="na"
TEMPLATE_EXT="yaml"
ACCOUNTS="[]"
ACCOUNT="{}"
ARTIFACT_BCKT="iapp-artifact-repository"
declare -a QUEUE
TEMPLATES="[]"
DEPLOY_ROLE="OrganizationAccountAccessRole"

#FUNCTIONS

# Parameters
# $1 = The account number where to assume the role
# $2 = Name of the role to assume, (e.g.: OrganizationAccountAccessRole)
assume_role() {
    reset_credentials
    
    echo " Assuming the role arn:aws:iam::$1:role/$2 ..."

    # duration of session set to 1 hour (see: https://docs.aws.amazon.com/cli/latest/reference/sts/assume-role.html)
    TMP_CREDENTIALS=$(aws sts assume-role --role-arn arn:aws:iam::$1:role/$2 --role-session-name ${GITHUB_RUN_NUMBER}_${1} --duration-seconds 3600)

    #echo $TMP_CREDENTIALS

    export AWS_ACCESS_KEY_ID=$(echo "${TMP_CREDENTIALS}" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "${TMP_CREDENTIALS}" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "${TMP_CREDENTIALS}" | jq -r '.Credentials.SessionToken' )

    #echo "AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
    #echo "AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY"
    #echo "AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN"
}

# This function performs the build processes for the template
#
# Paramters
# $1 = The build number
# $2 = The name of the template file to build located in the build directory, (e.g.: myapp-infra.yaml)
# $3 = The release the artifact is related with, (e.g.: 0.1.19)
#
build_artifact_template() {
    echo "   building a template artifact for $2 using the $3 release tag ..."
    CATALOG_PATH=$IAPP_catalog_organization/$IAPP_catalog_portfolio/$IAPP_catalog_product/$IAPP_catalog_application
    # upload the scripts
    cd $GITHUB_WORKSPACE/$IAPP_pipeline_build_dir
    
    ARTIFACT="$2"
    
    aws s3 cp $ARTIFACT s3://$ARTIFACT_BCKT/artifacts/$CATALOG_PATH/builds/$1/$ARTIFACT --acl bucket-owner-full-control
    tagset $1 $3
    aws s3api put-object-tagging --bucket $ARTIFACT_BCKT --key artifacts/$CATALOG_PATH/builds/$1/$ARTIFACT --tagging $TAGSET

    # if automated unit tests pass, then stage built artifact
    echo "   build has passed all tests ..."
    echo "   staging $ARTIFACT to $ARTIFACT_MATURITY ..."
    stage_built_artifact "s3://$ARTIFACT_BCKT/artifacts/$CATALOG_PATH/builds/$1/$ARTIFACT" $ARTIFACT_MATURITY $ARTIFACT $3 $TAGSET
}

# This function builds (which includes deploying) the templates in the sepcified directory
#
# Parameters
# $1 = The account number where to assume the role
# $2 = Name of the role to assume, (e.g.: OrganizationAccountAccessRole)
# $3 = The aws region to deploy to
# $4 = The name of the template file to build
# $5 = The build number
# $6 = The release the artifact is related with, (e.g.: 0.1.19)
#
build_template() {
    echo " Building template $4 ..."
    set_parameters $4
    build_artifact_template $5 $4 $6
}

# This function builds (which includes deploying) the templates in the sepcified directory
#
# Parameters
# $1 = The account number where to assume the role
# $2 = Name of the role to assume, (e.g.: OrganizationAccountAccessRole)
# $3 = The directory path (within the GITHUB_WORKSPACE) to search through for the templates to build, (e.g.: cloudformation/sandbox-nonprod)
# $4 = The aws region to deploy to
# $5 = The build number
# $6 = The release the artifact is related with, (e.g.: 0.1.19)
# 
build_templates() {
    echo " Building templates ..."
    echo " Getting the list of templates in scope ..."

    # clear the QUEUE
    declare -a QUEUE

    if [ -z ${IAPP_queue} ];
    then
        echo "  Using default build queue ..."
        default_template_queue "$GITHUB_WORKSPACE/${3}"
    else
        echo "  Using custom build queue ..."
        # custom_template_queue $BRANCH
        custom_template_queue manifest
    fi

    echo "  Building templates in the following order:"
    i=0
    for t in "${QUEUE[@]}"
    do
        echo "    $i - $t"
        i=$((i+1))
    done

    for t in "${QUEUE[@]}"
    do
        cd $GITHUB_WORKSPACE/${3}
        build_template $1 $2 $4 $t $5 $6
    done
}


# This function polls a changeset to find it's status and set the CHNGSET_EXEC variable accodingly
#
# Parameters
# $1 = The name of the changeset
# $2 = The name of the stack
#
check_changeset() {
    CHNGSET_EXEC='CREATE_PENDING'

    while [[ ${CHNGSET_EXEC} = 'CREATE_PENDING' ]]
    do
        chngset=$(aws cloudformation describe-change-set --change-set-name $1 --stack-name $2)
        case $(echo "${chngset}" | jq -r '.Status') in 
            CREATE_COMPLETE)
                echo "Executable changeset ..."
                CHNGSET_EXEC="RUN"
                ;;
            FAILED)
                status_reason=$(echo "${chngset}" | jq -r '.StatusReason')

                if [[ ( "$status_reason" =~ "No updates" ) || ( "$status_reason" =~ "The submitted information didn't contain changes" ) ]];
                then    
                    echo "Skip empty changeset ..."
                    CHNGSET_EXEC="SKIP"
                else   
                    echo "Error is changeset ..."
                    CHNGSET_EXEC="STOP"
                fi
                ;;
            *) #CREATE_IN_PROGRESS
                echo "sleeping for 5 seconds ..."
                sleep 5
                ;;
        esac
    done
}

# This function builds the queue of template files to build based on the custom setting (.queue) in the account property file
#
# Parameters
# $1 = The name of the account property file to parse, (e.g.: master, sandbox-nonprod, etc.)
#
# Output
# $QUEUE = The array of template file names in order of execution 
#
custom_template_queue() {
    i=0

    IAPP_queue=$(yq r $IAPP_HOME/$1.$TEMPLATE_EXT queue)

    echo " Loading ${TEMPLATE_EXT} templates from property file $IAPP_HOME/$1.$TEMPLATE_EXT ..."

    while IFS= read -r line
    do
        line=$(echo ${line} | sed -e 's/- //g')
        #echo " QUEUE[$i]=$line"
        QUEUE[$i]=$line
        i=$((i+1))
    done <<< "$IAPP_queue"
}

# This function builds the queue of template files to build based on the template files found in the build directory
#
# Parameters
# $1 = The path to the build directory relative to the $GITHUB_WORKSPACE, (e.g.: cloudformation)
#
# Output
# $QUEUE = The array of template file names in order of execution 
#
default_template_queue() {
    i=0

    echo " Loading ${TEMPLATE_EXT} templates from directory $1 ..."
    
    echo "  Changing directory to $1 ..."
    cd $1

    for t in ./*.$TEMPLATE_EXT
    do
        t=${t/.\//}
        #echo " QUEUE[$i]=$t"
        QUEUE[$i]=$t        
        i=$((i+1))
    done
}

# This function deploys a Cloudformation Template
#
# Parameters
# $1 = The name of the template file, (e.g.: myapp-infra.yaml)
# $2 = The release the artifact is related with, (e.g.: 0.1.19)
# $3 = The name of the build level (a.k.a. artifact maturity). [Options: pre-alpha or alpha]
#
deploy_template() {
    # set variables
    url="https://$ARTIFACT_BCKT.s3.amazonaws.com/releases/$2/$3/$1"
    stack_name $1
    
    # Determine the action to take, (CREATE< UPDATE, DELETE)
    if ! aws cloudformation describe-stacks --stack-name $STACK ;
    then
        echo " Stack doesn't exist, so changeset will be a created"
        STACK_ACTION='CREATE'
    else
        echo " Stack exists, so changeset will be an update"
        STACK_ACTION='UPDATE'
    fi
    
    # build the tag set
    tagset $BUILD_NUMBER $2
    chgtagset=''
    chgtagset=${chgtagset}$(echo "${TAGSET}" | jq -r '.TagSet')
    chgtagset=${chgtagset}''

    echo $chgtagset > /tmp/${STACK}-$BUILD_NUMBER.tags.json

    # create the change set
    echo " Creating change set ..."
    aws cloudformation create-change-set --stack-name "${STACK}" \
    --change-set-name "${STACK}-$BUILD_NUMBER" \
    --description "Build Number: $BUILD_NUMBER" \
    --change-set-type $STACK_ACTION \
    --template-url $url \
    --capabilities CAPABILITY_NAMED_IAM \
    --tags file:///tmp/${STACK}-$BUILD_NUMBER.tags.json > ${STACK}-$BUILD_NUMBER.chgset.json

    check_changeset "$STACK-$BUILD_NUMBER" $STACK

    case $CHNGSET_EXEC in 
        RUN)
            execute_change_set
            ;;
        SKIP) 
            echo " Skipping empty changeset ..."
            ;;
        *)
            echo " Error with changeset!"
            exit 1
            ;;
    esac
}

# This function builds (which includes deploying) the templates in the sepcified directory
#
# Parameters
# $1 = The account number where to assume the role
# $2 = Name of the role to assume, (e.g.: OrganizationAccountAccessRole)
# $3 = The directory path (within the GITHUB_WORKSPACE) to search through for the templates to build, (e.g.: cloudformation/sandbox-nonprod)
# $4 = The aws region to deploy to
# $5 = The release the artifact is related with, (e.g.: 0.1.19)
# 
deploy_templates() {
    echo " Deploying templates ..."
    echo " Getting the list of templates in scope ..."

    # clear the QUEUE
    declare -a QUEUE

    if [ -z ${IAPP_queue} ];
    then
        echo "  Using default build queue ..."
        default_template_queue "$GITHUB_WORKSPACE/${3}"
    else
        echo "  Using custom build queue ..."
        # custom_template_queue $BRANCH
        custom_template_queue manifest
    fi

    echo "  Building templates in the following order:"
    i=0
    for t in "${QUEUE[@]}"
    do
        echo "    $i - $t"
        i=$((i+1))
    done

    for t in "${QUEUE[@]}"
    do
        cd $GITHUB_WORKSPACE/${3}
        validate_template $4 $t $5 $ARTIFACT_MATURITY
        deploy_template $t $5 $ARTIFACT_MATURITY
    done
}

# This function executes the change set to create or update the stack.
# It will exit with error code if the stack deployment fails
# 
execute_change_set() {
    echo " Executing changeset ..."
    aws cloudformation execute-change-set --change-set-name "${STACK}-$BUILD_NUMBER" --stack-name "${STACK}" > ${STACK}-$BUILD_NUMBER.execchgset.json

    STOP=0
    LAST_TMSTMP=$(date +%s)
    echo "| Timestamp | Logical Id | Status | Type | Physical Id |"
    echo "| --------- | ---------- | ------ | ---- | ----------- |"

    while [ $STOP -lt 1 ]
    do
        # Get the latest events
        describe_events
        # Check to see if it is completed or rolledback
        describe_stack
        sleep 5s
    done  

    # print the status of the stack
    echo "| Stack Name | Status | Reason |"
    echo "| ---------- | ------ | ------ |"
    echo "| $STACK_NAME | $STACK_STATUS | $STACK_REASON |"

    # Exit the job if the was an error with deploying the stack
    if [ "${ERROR}" -gt "0" ]
    then
        exit ${ERROR}
    fi
}

# This function queries the events of the stack sinc ethe last time it ran
#
# Return
# $LAST_TMSTMP = The timestamp of the last event record returned
# 
describe_events() {
    EVENTS=$(aws cloudformation describe-stack-events --stack-name $STACK --max-items 20)

    for row in $(echo "${EVENTS}" | jq -c '.StackEvents[] | @base64');
    do
        trim_double_quotes $row
        _jq() {
            echo ${TRIMMED} | base64 --decode | jq -r ${1}
        }

        TMSTMP=$(_jq '.Timestamp' )
        dt=$(date --date=$TMSTMP +%s)
        
        if [ $LAST_TMSTMP -lt $dt ]
        then

            RESID=$(_jq '.LogicalResourceId' )
            STATUS=$(_jq '.ResourceStatus' )
            TYPE=$(_jq '.ResourceType' )
            PHYID=$(_jq '.PhysicalResourceId' )
            echo "| ${TMSTMP} | ${RESID} | ${STATUS} | ${TYPE} | ${PHYID} |"
        fi
    done 

    LAST_TMSTMP=$(date --date=$TMSTMP +%s)
}


# This function queries the status of the stack to see if it is done
#
# Return
# $STOP = The STOP indicator is set to 1 if the stack is done
# $ERROR = The ERROR indicator is set to 1 if there was an problem
# 
describe_stack() {
    #echo "Stack Name|Status|Status Reason"
    STACK_RSLT=$(aws cloudformation describe-stacks --stack-name ${STACK})
    STACK_NAME=$(echo "${STACK_RSLT}" | jq '.Stacks[].StackName')
    STACK_STATUS=$(echo "${STACK_RSLT}" | jq '.Stacks[].StackStatus')
    STACK_REASON=$(echo "${STACK_RSLT}" | jq '.Stacks[].StackStatusReason')
    #echo -e "$STACK_NAME|$STACK_STATUS\|$STACK_REASON"
    
    trim_double_quotes $STACK_STATUS
    
    if [ $TRIMMED == "UPDATE_COMPLETE" ] || [ $TRIMMED == "CREATE_COMPLETE" ] || [ $TRIMMED == "ROLLBACK_COMPLETE" ]
    then
        STOP=1
        if [ $TRIMMED == "ROLLBACK_COMPLETE" ]
        then
            ERROR=1
        fi
    fi
}

# This function parses the template, extracts tha parameters and returns a json list of key value pairs
#
# Parameters
# $1 - The name of the template file
#
extract_parameters_from_template() {
    echo "Parsing template $1 for parameters list ..."
    
    while IFS= read -r line
    do
        line=$(echo ${line})
        #para=$(echo "${line/Parameters./\"ParameterKey\": \"}")
        #para=$(echo ${para/.Default: /\",\"ParameterValue\": \"})
        para=$(echo "${line/Parameters./\"}")
        para=$(echo ${para/.Default: /=})
        PARAMS="${PARAMS}${para}\" "

    done <<< $(yq r $1 --printMode pv "Parameters.*.Default")

    #PARAMS=$(echo ${PARAMS} | sed 's/.$//' )
    #PARAMS="{${PARAMS}}"
    #PARAMS=""
    echo $PARAMS
}

# This function parses the $BRANCH and manifest property files
#
# Parameters
# $1 = The name of the file (excluding file extension) to parse, (e.g.: sandbox-nonprod)
#
# Output
# $IAPP_[based on property file structure] (e.g.: IAPP_catalog_organization, IAPP_pipeline_build_dir, IAPP_aws_environment, etc.)
#
parse_property_files() {
    echo "Parsing the ${1}.yaml properties file ..."
    eval $(parse_yaml $IAPP_HOME/${1}.yaml "IAPP_")

    echo "Parsing the manifest.yaml file ..."
    eval $(parse_yaml $IAPP_HOME/manifest.yaml "IAPP_")  
}

# This function promotes artifacts to the specified build level (a.k.a. Artifact Maturity)
#
# Parameters
# $1 = The buld level where the artifact is moving from (a.k.k source), (e.g.: alpha)
# $2 = The buld level where the artifact is moving to (a.k.k target), (e.g.: beta)
# $3 = The release the artifact is related with, (e.g.: 0.1.19)
#
promote_artifacts() {
    echo "   promoting artifacts from $1 to $2 for the release $3 ..."
    CATALOG_PATH=$IAPP_catalog_organization/$IAPP_catalog_portfolio/$IAPP_catalog_product/$IAPP_catalog_application
    
    aws s3 cp s3://$ARTIFACT_BCKT/artifacts/$CATALOG_PATH/$1 s3://$ARTIFACT_BCKT/artifacts/$CATALOG_PATH/$2 --recursive --acl bucket-owner-full-control
    aws s3 cp s3://$ARTIFACT_BCKT/releases/$3/$1 s3://$ARTIFACT_BCKT/releases/$3/$2 --recursive --acl bucket-owner-full-control
}

# This function resets the AWS credentials back to the original settings from when the Workflow initiated.
# NOTE: The $MASTER_AWS_ACCESS_KEY_ID and $MASTER_AWS_SECRET_ACCESS_KEY environment variables are the orginal credentials
# 
reset_credentials() {
    export AWS_ACCESS_KEY_ID=$MASTER_AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$MASTER_AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN

    #echo "AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
    #echo "AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY"
    #echo "AWS_SESSION_TOKEN: $AWS_SESSION_TOKEN"
}

# This function extracts an account from the $ACCOUNTS variable
# NOTE: The retrieve_accounts() funciton must be run prior to calling this function.
#
# Parameters
# $1 = The name of the account, (e.g.: sandbox-nonprod)
# 
# Output
# $ACCOUNT = The json string of the account record
#
retrieve_account() {
    ACCOUNT="{}"
    for row in $(echo $ACCOUNTS | jq -c '.[]'); 
    do
        echo $row
        if [[ $(echo "${row}" | jq -r '.name') =~ $1 ]];
        then
            ACCOUNT=${row}
        fi
    done
}

# This function extracts all the account records from the property files in the IAPP_HOME directory
#
# Output
# $ACCOUNTS = The json array of the account records
#
retrieve_accounts() {
    echo "Retrieving accounts from property files in $IAPP_HOME ..."
    echo " Changing directory to $IAPP_HOME ..."
    
    cd $IAPP_HOME

    ACCOUNTS="["
    
    for ACCNT_FILE in ./*.$TEMPLATE_EXT
    do
       ACCNT_FILE=${ACCNT_FILE/.\//}
       
       if ! [[ $ACCNT_FILE =~ manifest.yaml ]];
       then
            # read account manifest file
            eval $(parse_yaml $IAPP_HOME/${ACCNT_FILE} "ACCNT_")
            # need to figure out how to use $TEMPLATE_EXT instead of hard coded yaml
            TMP_ACCNT_FILE_NAME=$(echo $ACCNT_FILE | sed -e 's/.yaml//g')
            ACCOUNTS="${ACCOUNTS}{"
            ACCOUNTS="${ACCOUNTS}\"name\":\"${TMP_ACCNT_FILE_NAME}\","
            ACCOUNTS="${ACCOUNTS}\"account\":${ACCNT_aws_account},"
            ACCOUNTS="${ACCOUNTS}\"environment\":\"${ACCNT_aws_environment}\","
            ACCOUNTS="${ACCOUNTS}\"region\":\"${ACCNT_aws_region}\""
            ACCOUNTS="${ACCOUNTS}},"
       fi
    done

    #remove the last comma
    ACCOUNTS=$(echo $ACCOUNTS | sed 's/\(.*\),/\1/')
    ACCOUNTS="${ACCOUNTS}]"
}

# This function extracts all the template file from the specified directory
#
# Parameters
# $1 = The directory path (within the GITHUB_WORKSPACE) to search through for the tempaltes to build, (e.g.: cloudformation/sandbox-nonprod)
# 
# Output
# $TEMPLATES = The json array of the templates records
#
retrieve_templates() {
    echo " Changing directory to ${GITHUB_WORKSPACE} ..."
    cd $GITHUB_WORKSPACE/$1

    TEMPLATES="["

    echo " Searching for ${TEMPLATE_EXT} templates in directory $GITHUB_WORKSPACE/${1} ..."
    for FILE in ./*.$TEMPLATE_EXT
    do
        FILE=${FILE/.\//}
        TEMPLATES="${TEMPLATES}$FILE,"
    done

    #remove the last comma
    TEMPLATES=$(echo $TEMPLATES | sed 's/\(.*\),/\1/')
    TEMPLATES="${TEMPLATES}]"
}

# This function sets a parameter for the specified template file
#
# Parameters
# $1 = The name of the template file
# $2 = The name of the parameter to set, (e.g.: ${{ iapp.catalog.organization }} )
# $3 = The value to use when setting the parameter, (e.g.: iapp)
#
set_parameter() {
   #echo "  Setting $2 to $3 in $1 ..."
   sed -i "s|$2|$3|g" $1
}

# This function sets all the standard parameters in the template
#
# Parameters
# $1 = The name of the template file
#
set_parameters() {
   set_parameter $1 "\${{ iapp.catalog.organization }}" $IAPP_catalog_organization
   set_parameter $1 "\${{ iapp.catalog.portfolio }}" $IAPP_catalog_portfolio
   set_parameter $1 "\${{ iapp.catalog.product }}" $IAPP_catalog_product
   set_parameter $1 "\${{ iapp.catalog.application }}" $IAPP_catalog_application
   set_parameter $1 "\${{ iapp.catalog.department }}" $IAPP_catalog_department
   set_parameter $1 "\${{ iapp.pipeline.release_lvl }}" $IAPP_pipeline_release_lvl
   set_parameter $1 "\${{ iapp.pipeline.release_vrs }}" $IAPP_pipeline_release_vrs
   set_parameter $1 "\${{ iapp.aws.environment }}" $IAPP_aws_environment
   set_parameter $1 "\${{ iapp.aws.domain }}" $IAPP_aws_domain
   set_parameter $1 "\${{ iapp.code.sourcecode_url }}" $IAPP_code_sourcecode_url

   # optional paramters
   if [ -z "$IAPP_catalog_component" ]
   then
      echo "  Using default value for parameter iapp.catalog.component ..." 
      set_parameter $1 "\${{ iapp.catalog.component }}" $DEFAULT_VALUE  
   else
      set_parameter $1 "\${{ iapp.catalog.component }}" $DEFAULT_VALUE
   fi

   if [ -z "$IAPP_catalog_support_email" ]
   then
      echo "  Using default value for parameter iapp.catalog.support_email ..."   
   else
      set_parameter $1 "\${{ iapp.catalog.support_email }}" $IAPP_catalog_support_email
   fi

    if [ -z "$IAPP_aws_certarn" ]
   then
      echo "  Using default value for parameter iapp.aws.certarn ..."   
   else
      set_parameter $1 "\${{ iapp.aws.certarn }}" $IAPP_aws_certarn
   fi
}

# This function generates the name of the stack
#
# Parameters
# $1 = The name of the template file
#
# Output
# $STACK = The name of the stack
#
stack_name() {
    # need to figure out how to use $TEMPLATE_EXT instead of hard coded yaml
    STACK_PART=$(echo $1 | sed 's/.yaml//g')
    echo " Setting stack name to ${IAPP_catalog_portfolio}-${STACK_PART}-${IAPP_aws_environment} ..."
    STACK=$(echo ${IAPP_catalog_portfolio}-${STACK_PART}-${IAPP_aws_environment} | sed 's/.*/\U&/g')
}

# This function stages the built artifact by placing it into the appropriate build level (a.k.a. artifact maturity)
#
# Parameters
# $1 = The object path in the S3 bucket of the built artifact S3 object (a.k.a. source)
# $2 = The name of the build level (a.k.a. artifact maturity). [Options: pre-alpha or alpha]
# $3 = The artifact file name, (e.g.: lkp-ami.zip)
# $4 = The release the artifact is related with, (e.g.: 0.1.19)
# $5 = The aws Tagset to use for tagging the artifacts
#
stage_built_artifact() {
    if [[ $2 == pre-alpha ]] || [[ $2 == alpha ]] ||  [[ $2 == beta ]]  ||  [[ $2 == general-release ]];
    then        
        CATALOG_PATH=$IAPP_catalog_organization/$IAPP_catalog_portfolio/$IAPP_catalog_product/$IAPP_catalog_application
        aws s3 cp $1 s3://$ARTIFACT_BCKT/artifacts/$CATALOG_PATH/$2/$3 --acl bucket-owner-full-control
        aws s3 cp $1 s3://$ARTIFACT_BCKT/releases/$4/$2/$3 --acl bucket-owner-full-control

        aws s3api put-object-tagging --bucket $ARTIFACT_BCKT --key artifacts/$CATALOG_PATH/$2/$3 --tagging $5
        aws s3api put-object-tagging --bucket $ARTIFACT_BCKT --key releases/$4/$2/$3 --tagging $5
    else
        echo "   Error: build level $2 is invalid!"
        exit 1
    fi
}

# This function builds the json string for the aws tagset 
#
# Paramters
# $1 = The build number
# $2 = The release name
#
# Returns
# $TAGSET = The json string repesenting the tagset
#
tagset() {
    TAGSET=""
    TAGSET=${TAGSET}'{"TagSet":['
    TAGSET=${TAGSET}'{"Key":"iapp-organization",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${IAPP_catalog_organization}
    TAGSET=${TAGSET}'"},'
    TAGSET=${TAGSET}'{"Key":"iapp-portfolio",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${IAPP_catalog_portfolio}
    TAGSET=${TAGSET}'"},'
    TAGSET=${TAGSET}'{"Key":"iapp-product",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${IAPP_catalog_product}
    TAGSET=${TAGSET}'"},'
    TAGSET=${TAGSET}'{"Key":"iapp-application",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${IAPP_catalog_application}
    TAGSET=${TAGSET}'"},'
    TAGSET=${TAGSET}'{"Key":"iapp-component",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${IAPP_catalog_component}
    TAGSET=${TAGSET}'"},'
    TAGSET=${TAGSET}'{"Key":"iapp-department",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${IAPP_catalog_department}
    TAGSET=${TAGSET}'"},'
    TAGSET=${TAGSET}'{"Key":"iapp-support-email",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${IAPP_catalog_support_email}
    TAGSET=${TAGSET}'"},'
    TAGSET=${TAGSET}'{"Key":"iapp-build-number",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${1}
    TAGSET=${TAGSET}'"},'
    TAGSET=${TAGSET}'{"Key":"iapp-release-name",'
    TAGSET=${TAGSET}'"Value":"'
    TAGSET=${TAGSET}${2}
    TAGSET=${TAGSET}'"}'
    TAGSET=${TAGSET}']}'
    TAGSET=${TAGSET}""
}

# This function removes the first and last double quotes from the string
#
# Parameters
# $1 = The string to trim
#
# Return
# TRIMMED = The name of the variable to use that represents the trimmed string
#
trim_double_quotes() {
    #echo "Trimming ${1} ..."
    TRIMMED=$(echo "${1}" | sed -e 's/^"//' -e 's/"$//')
}

# This function validates the template with the cloudformation service
#
# Parameters
# $1 = The aws region to deploy to
# $2 = The name of the template file, (e.g.: myapp-infra.yaml)
# $3 = The release the artifact is related with, (e.g.: 0.1.19)
# $4 = The name of the build level (a.k.a. artifact maturity). [Options: pre-alpha or alpha]
#
validate_template() {
   echo " Validating Cloud Formation Template $2 ..."
   url="https://$ARTIFACT_BCKT.s3.amazonaws.com/releases/$3/$4/$2"
   #aws cloudformation validate-template --template-body file://$2 --region $1 > template-validation-results.json
   aws cloudformation validate-template --template-url $url --region $1 > template-validation-results.json

   rc=$?
   if [ $rc -ne 0 ]; 
   then
      echo "Build Failed: Invalid template $2!"
      exit $rc
   fi
}