#!/bin/bash

#CONSTANTS
export BUILD_NUMBER=${GITHUB_WORKFLOW// /-}-$GITHUB_RUN_NUMBER
echo "Build Number: $BUILD_NUMBER"

#FUNCTIONS
set_cft_dir() {
   if [ -z "$IAPP_pipeline_build_dir" ]
   then
      echo "Using the default directory cloudformation ..."   
      CFT_DIR="cloudformation"
   else
      echo "Using configured build directory $IAPP_pipeline_build_dir ..."
      CFT_DIR=$IAPP_pipeline_build_dir
   fi
}


###################### 
# Script starts here #
######################
# include common shared functions
. "$WORKFLOW_HOME/common.sh"
# First, get the configurations settings
parse_property_files $BRANCH

# determine the release level
case $BRANCH in
    development)
        echo "Using the development aws account for branch $BRANCH ..."
        ARTIFACT_MATURITY="alpha"
        ;;
    test)
        echo "Using the test aws account for branch $BRANCH ..."
        ARTIFACT_MATURITY="beta"
        ;;
    master)
        echo "Using the master aws account for branch $BRANCH ..."
        ARTIFACT_MATURITY="general-release"
        ;;
    *)
        echo "Using sandbox aws account for branch $BRANCH ..."
        ARTIFACT_MATURITY="pre-alpha"
        BRANCH="sandbox"
        ;;
esac

assume_role $IAPP_aws_account $DEPLOY_ROLE

case $ARTIFACT_MATURITY in 
    pre-alpha)
        # build from scratch 
        build_templates $IAPP_aws_account $DEPLOY_ROLE $IAPP_pipeline_build_dir $IAPP_aws_region $BUILD_NUMBER $IAPP_pipeline_release_vrs
        deploy_templates $IAPP_aws_account $DEPLOY_ROLE $IAPP_pipeline_build_dir $IAPP_aws_region $IAPP_pipeline_release_vrs
        ;;
    alpha)
        # build from scratch
        build_templates $IAPP_aws_account $DEPLOY_ROLE $IAPP_pipeline_build_dir $IAPP_aws_region $BUILD_NUMBER $IAPP_pipeline_release_vrs
        deploy_templates $IAPP_aws_account $DEPLOY_ROLE $IAPP_pipeline_build_dir $IAPP_aws_region $IAPP_pipeline_release_vrs
        ;;
    beta)
        # build from scratch
        build_templates $IAPP_aws_account $DEPLOY_ROLE $IAPP_pipeline_build_dir $IAPP_aws_region $BUILD_NUMBER $IAPP_pipeline_release_vrs
        deploy_templates $IAPP_aws_account $DEPLOY_ROLE $IAPP_pipeline_build_dir $IAPP_aws_region $IAPP_pipeline_release_vrs
        ;;
    general-release)
        # build from scratch
        build_templates $IAPP_aws_account $DEPLOY_ROLE $IAPP_pipeline_build_dir $IAPP_aws_region $BUILD_NUMBER $IAPP_pipeline_release_vrs
        deploy_templates $IAPP_aws_account $DEPLOY_ROLE $IAPP_pipeline_build_dir $IAPP_aws_region $IAPP_pipeline_release_vrs
        ;;
    *)
        echo "Error: $ARTIFACT_MATURITY is an unsupported build level!"
        exit 1
        ;;
esac

echo "Done ..."