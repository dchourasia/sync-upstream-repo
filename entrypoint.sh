#!/usr/bin/env bash

set -x

UPSTREAM_REPO=$1
UPSTREAM_BRANCH=$2
DOWNSTREAM_BRANCH=$3
GITHUB_TOKEN=$4
FETCH_ARGS=$5
MERGE_ARGS=$6
PUSH_ARGS=$7
SPAWN_LOGS=$8
DOWNSTREAM_REPO=$9
IGNORE_FILES=${10}
PUSH_TAGS=${11}


if [[ -z "$UPSTREAM_REPO" ]]; then
  echo "Missing \$UPSTREAM_REPO"
  exit 1
fi

if [[ -z "$DOWNSTREAM_BRANCH" ]]; then
  echo "Missing \$DOWNSTREAM_BRANCH"
  echo "Default to ${UPSTREAM_BRANCH}"
  DOWNSTREAM_BRANCH=UPSTREAM_BRANCH
fi

if ! echo "$UPSTREAM_REPO" | grep '\.git'; then
  UPSTREAM_REPO="https://github.com/${UPSTREAM_REPO_PATH}.git"
fi

echo "UPSTREAM_REPO=$UPSTREAM_REPO"

if [[ $DOWNSTREAM_REPO == "GITHUB_REPOSITORY" ]]
then
  git clone "https://github.com/${GITHUB_REPOSITORY}.git" --branch ${DOWNSTREAM_BRANCH} work
  cd work || { echo "Missing work dir" && exit 2 ; }
  git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
else
  git clone $DOWNSTREAM_REPO --branch ${DOWNSTREAM_BRANCH} work
  cd work || { echo "Missing work dir" && exit 2 ; }
  git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${DOWNSTREAM_REPO/https:\/\/github.com\//}"
fi



git config user.name "${GITHUB_ACTOR}"
git config user.email "${GITHUB_ACTOR}@users.noreply.github.com"
git config --local user.password ${GITHUB_TOKEN}
git config --global merge.ours.driver true

git remote add upstream "$UPSTREAM_REPO"
git fetch ${FETCH_ARGS} upstream
git remote -v

git checkout ${DOWNSTREAM_BRANCH}

case ${SPAWN_LOGS} in
  (true)    echo -n "sync-upstream-repo https://github.com/dabreadman/sync-upstream-repo keeping CI alive."\
            "UNIX Time: " >> sync-upstream-repo
            date +"%s" >> sync-upstream-repo
            git add sync-upstream-repo
            git commit sync-upstream-repo -m "Syncing upstream";;
  (false)   echo "Not spawning time logs"
esac

git push origin


IFS=', ' read -r -a exclusions <<< "$IGNORE_FILES"
for exclusion in "${exclusions[@]}"
do
   echo "$exclusion"
   echo "$exclusion merge=ours" >> .git/info/attributes
   cat .git/info/attributes
done

MERGE_RESULT=$(git merge ${MERGE_ARGS} upstream/${UPSTREAM_BRANCH} 2>&1)
echo $MERGE_RESULT

echo "checking git status"
git status


if [[ $MERGE_RESULT == "" ]] || [[ $MERGE_RESULT == *"merge failed"* ]] || [[ $MERGE_RESULT == *"CONFLICT ("* ]] || [[ $MERGE_RESULT == *"error:"* ]] || [[ $MERGE_RESULT == *"Aborting"* ]]
then
  exit 1
elif [[ $MERGE_RESULT != *"Already up to date."* ]]
then
  git commit -m "Merged upstream"
  git push ${PUSH_ARGS} origin ${DOWNSTREAM_BRANCH} || exit $?
  if [[ -n ${PUSH_TAGS} ]]; then
      git push origin ${PUSH_ARGS} ${PUSH_TAGS:-"refs/tags/*"}
  fi
fi

cd ..
rm -rf work
