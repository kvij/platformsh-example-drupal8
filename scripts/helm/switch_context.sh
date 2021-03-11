#!/bin/bash

project="kuberdrupal"
region="europe-west4"

environment="$1"
if [[ "$1" == "" ]]; then
    echo "Please select an environment:"
    select environment in testing staging prod
    do
        if [[ ${environment} != "" ]]; then
            break
        fi
    done
fi

case "${environment}" in
    "testing" | "staging")
        context="gke_kuberdrupal_europe-west4_testing"
        cluster="testing"
        ;;
    "production")
        context="gke_kuberdrupal_europe-west4_prod"
        cluster="production"
        ;;
    *)
        echo "Usage: ./$0 <testing|staging|prod>"
        exit 1
        ;;
esac

echo "Ensuring context is set to ${environment}..."

has_context=$(kubectl config get-contexts -o name | grep -e "^${context}$")
if [[ "${has_context}" == "" ]]; then
    gcloud container clusters get-credentials ${cluster} --project ${project} --region ${region} > /dev/null
else
    kubectl config use-context ${context} > /dev/null
fi
