#!/usr/bin/env bash
set -e

if [[ "$1" = "--auto-prepare" ]]
then
    PREPARE=1
    DEP_NAME="$2"
    COMMIT_MESSAGE="$3"
else
    DEP_NAME="$1"
    COMMIT_MESSAGE="$2"
fi

if [[ -z "$DEP_NAME" ]] || [[ -z "$COMMIT_MESSAGE" ]]
then
    echo "USAGE: $0 dependency_name \"Commit message\""
    exit 1
fi

updateCurentRepo() {
    # Test $DEP_NAME is used in current repo
    if ! grep -q "$DEP_NAME" composer.lock 2> /dev/null
    then
        return
    fi

    echo Updating \"$(basename $(pwd))\"

    if [[ -n $PREPARE ]]
    then
        echo Preparing repo

        local branch_name=$(git symbolic-ref -q HEAD)
        local branch_name=${branch_name##refs/heads/}

        if git status --porcelain | grep -qv '^?? '
        then
            local dirty=true
            git stash > /dev/null
        else
            local dirty=false
        fi

        [[ "$branch_name" != "master" ]]  && git checkout master > /dev/null

        git pull > /dev/null
    fi

    lando composer update "$DEP_NAME"
    git add composer.lock
    git commit -m "$COMMIT_MESSAGE"
    git push

    if [[ -n $PREPARE ]]
    then
        echo Restoring repo state
        [[ "$branch_name" != "master" ]]  && git checkout "$branch_name" > /dev/null
        [[ $dirty = true ]] && git stash pop > /dev/null
    fi
}

# Loop over all directories in folder
for repo in $(ls)
do
    [[ ! -d "$repo" ]] && continue
    [[ "$repo" = "drupal8-base" ]] && continue
    cd "$repo"
    updateCurentRepo
    cd ..
done
