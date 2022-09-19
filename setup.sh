#!/usr/bin/env bash

export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
export PROJECT_NAME=$(gcloud projects describe $PROJECT_ID --format='value(name)')
export REGION=us-central1

gcloud config set project $PROJECT_ID

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  clouddeploy.googleapis.com \
  artifactregistry.googleapis.com

gcloud artifacts repositories create containers-repo \
  --repository-format=docker \
  --location=${REGION} \
  --description="Containers repository"

sed -i "s/_PROJECT_ID/$PROJECT_ID/g" clouddeploy.yaml

gcloud deploy apply \
  --file=clouddeploy.yaml \
  --region=${REGION} \
  --project=${PROJECT_ID}

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
    --role=roles/clouddeploy.operator

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
    --role=roles/iam.serviceAccountUser

export RELEASE_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

gcloud builds submit \
  --config cloudbuild.yaml \
  --substitutions=_REGION=${REGION},_RELEASE_TIMESTAMP=${RELEASE_TIMESTAMP}

gcloud beta deploy releases promote \
    --release="release-${RELEASE_TIMESTAMP}" \
    --delivery-pipeline=cloud-run-pipeline \
    --region=${REGION} \
    --quiet
