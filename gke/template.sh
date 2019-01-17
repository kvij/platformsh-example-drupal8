#!/usr/bin/env sh
repo="$REPO_NAME";
shortrepo=${repo//github-ewisenl-/};
database_name=${shortrepo//-/_};
sed -i "s|{{PROJECT}}|$PROJECT_ID|g"      ./gke/deploy-app.yaml;
sed -i "s|{{REPO_NAME}}|${shortrepo}|g"   ./gke/deploy-app.yaml;
sed -i "s|{{ENVIRONMENT}}|$ENVIRONMENT|g" ./gke/deploy-app.yaml;
sed -i "s|{{BRANCH_NAME}}|$BRANCH_NAME|g" ./gke/deploy-app.yaml;
sed -i "s|{{COMMIT_ID}}|$SHORT_SHA|g"     ./gke/deploy-app.yaml;
sed -i "s|{{TAG}}|$TAG_NAME|g"            ./gke/deploy-app.yaml;
sed -i "s|{{REPLICAS}}|$REPLICAS|g"       ./gke/deploy-app.yaml;
sed -i "s|{{DATABASE_NAME}}|$database_name|g"  ./gke/deploy-app.yaml;

export commitmsg=`/usr/bin/git log -1 --pretty=%B $COMMIT_SHA`;
perl -i -pe 's/\{\{COMMITMSG}}/$ENV{"commitmsg"}/g' ./gke/deploy-app.yaml;
/usr/bin/git log -1 --pretty=%B $COMMIT_SHA >commitmsg