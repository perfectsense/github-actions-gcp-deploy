#!/bin/bash

set -e -u

# Set the following environment variables:
# DEPLOY_BUCKET = your bucket name
# DEPLOY_BUCKET_PREFIX = a directory prefix within your bucket
# DEPLOY_BRANCHES = regex of branches to deploy; leave blank for all
# DEPLOY_EXTENSIONS = whitespace-separated file exentions to deploy; leave blank for "jar war zip"
# PURGE_OLDER_THAN_DAYS = Files in the .../deploy and .../pull-request prefixes in GCP older than this number of days will be deleted; leave blank for 90, 0 to disable.

if [[ -z "${DEPLOY_BUCKET}" ]]
then
    echo "Bucket not specified via \$DEPLOY_BUCKET"
fi

DEPLOY_BUCKET_PREFIX=${DEPLOY_BUCKET_PREFIX:-}

DEPLOY_BRANCHES=${DEPLOY_BRANCHES:-}

DEPLOY_EXTENSIONS=${DEPLOY_EXTENSIONS:-"jar war zip"}

DEPLOY_SOURCE_DIR=${DEPLOY_SOURCE_DIR:-$log_BUILD_DIR/target}

PURGE_OLDER_THAN_DAYS=${PURGE_OLDER_THAN_DAYS:-"90"}

if [[ -z "$GITHUB_ACTIONS_PULL_REQUEST" && "$GITHUB_ACTIONS_PULL_REQUEST" != "" ]]
then
   target_path=pull-request/$GITHUB_ACTIONS_PULL_REQUEST
elif [[ -z "$DEPLOY_BRANCHES" || "$BRANCH" =~ "$DEPLOY_BRANCHES" ]]
then
    echo "Deploying branch ${GITHUB_REF##*/}"

    BUILD_NUM=${GITHUB_RUN_NUMBER}
    if ! [[ -z "${BUILD_NUM_OFFSET}" ]]
    then
        BUILD_NUM=$((GITHUB_RUN_NUMBER+BUILD_NUM_OFFSET))
    fi

    target_path=deploy/${GITHUB_REF##*/}/$BUILD_NUM

else
    echo "Not deploying."
    exit

fi

# BEGIN fold/timer support

openssl des3 -d -in .github/gcp-deploy.json.des3 -out .github/gcp-deploy.json -pass pass:$GCP_CREDENTIALS
gcloud auth activate-service-account --key-file=.github/gcp-deploy.json

activity=""
timer_id=""
start_time=""

log_start() {
    if [[ -n "$activity" ]]
    then
        echo "Nested log_start is not supported!"
        return
    fi

    activity="$1"
    timer_id=$RANDOM
    start_time=$(date +%s%N)
    start_time=${start_time/N/000000000} # in case %N isn't supported

    echo "log_fold:start:$activity"
    echo "log_time:start:$timer_id"
}

log_end() {
    if [[ -z "$activity" ]]
    then
        echo "Can't log_end without log_start!"
        return
    fi

    end_time=$(date +%s%N)
    end_time=${end_time/N/000000000} # in case %N isn't supported
    duration=$(expr $end_time - $start_time)
    echo "log_time:end:$timer_id:start=$start_time,finish=$end_time,duration=$duration"
    echo "log_fold:end:$activity"

    # reset
    activity=""
    timer_id=""
    start_time=""
}

# END fold/timer support

discovered_files=""
for ext in ${DEPLOY_EXTENSIONS}
do
    discovered_files+=" $(ls $DEPLOY_SOURCE_DIR/*.${ext} 2>/dev/null || true)"
done

files=${DEPLOY_FILES:-$discovered_files}

if [[ -z "${files// }" ]]
then
    echo "Files not found; not deploying."
    exit
fi

target=builds/${DEPLOY_BUCKET_PREFIX}${DEPLOY_BUCKET_PREFIX:+/}$target_path/

log_start "gcp_rm"
gsutil ls gs://$DEPLOY_BUCKET/$target | \
while read -r line
do
    if [[ $line != CommandException* ]] && [[ $line != "" ]]; then
        echo "Deleting existing artifact [$line]."
        gsutil rm $line
    fi
done
log_end

log_start "gcp_cp"
for file in $files
do
    echo "Uploading ${file} to gs://${DEPLOY_BUCKET}/${target}"
    gsutil cp $file gs://$DEPLOY_BUCKET/$target
done
log_end

if [[ $PURGE_OLDER_THAN_DAYS -ge 1 ]]
then
    log_start "clean_gcp"
    echo "Cleaning up builds in GS older than $PURGE_OLDER_THAN_DAYS days . . ."

    cleanup_prefix=builds/${DEPLOY_BUCKET_PREFIX}${DEPLOY_BUCKET_PREFIX:+/}
    # TODO: this works with GNU date only
    older_than_ts=`date -d"-${PURGE_OLDER_THAN_DAYS} days" +%s`

    for suffix in deploy pull-request
    do
        gsutil ls -l gs://$DEPLOY_BUCKET/$cleanup_prefix$suffix/ | \
        while read -r line
        do
            last_modified=`echo "$line" | awk -F'[[:space:]][[:space:]]' '{print $4}'`
            if [[ -z $last_modified ]]
            then
                continue
            fi
            last_modified_ts=`date -d"$last_modified" +%s`
            filename=`echo "$line" | awk -F'\t' '{print $3}'`
            if [[ $last_modified_ts -lt $older_than_ts ]]
            then
                if [[ $filename != "" ]]
                then
                    echo "gs://$DEPLOY_BUCKET/$filename is older than $PURGE_OLDER_THAN_DAYS days ($last_modified). Deleting."
                    gsputil rm "gs://$DEPLOY_BUCKET/$filename"
                fi
            fi
        done
    done
    log_end
fi
