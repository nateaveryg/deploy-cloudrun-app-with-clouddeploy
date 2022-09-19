# Deploy Cloud Run Application with Cloud Deploy

Make sure you're using gcloud CLI version 402.0.0 or greater.

Check current version:
```shell
gcloud version
```

Update to the latest:
```shell
gcloud components update --version=4.0.2
```

Set project environment variables:
```shell
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID \
--format='value(projectNumber)')
export REGION=us-central1
```

Enable APIs:
```shell
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  clouddeploy.googleapis.com \
  artifactregistry.googleapis.com
```

Create Artifact Registry repository:
```shell
gcloud artifacts repositories create containers-repo \
  --repository-format=docker \
  --location=${REGION} \
  --description="Containers repository"
```

Configure docker to utilize your gcloud credentials when accessing Artifact Registry.
```shell
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
```

Clone the code:
```shell
git clone https://github.com/gitrey/deploy-cloudrun-app-with-clouddeploy.git
cd deploy-cloudrun-app-with-clouddeploy
```

Review `cloudbuild.yaml` config file below - it will be used to create container image:
```yaml
steps:
- name: 'gcr.io/k8s-skaffold/pack'
  entrypoint: 'pack'
  args: ['build', 
         '--builder=gcr.io/buildpacks/builder', 
         '--publish', '${REGION}-docker.pkg.dev/${PROJECT_ID}/containers-repo/app:$BUILD_ID']
  id: Build and package .net app
```

Create container image using Cloud Build:
```shell
gcloud builds submit \
  --config cloudbuild.yaml \
  --substitutions=_REGION=${REGION}
```

Review details in Cloud Build History:

![Cloud Build](./images/cloudbuild.png)

Review container image in Artifact Registry:

![Cloud Build](./images/ar.png)

Review deployment targets configuration files for Cloud Deploy.

DEV env - `deploy-dev.yaml`:
```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: app-dev
spec:
  template:
    spec:
      containers:
      - image: app
        resources:
          limits:
            cpu: 1000m
            memory: 128Mi
```
QA env - `deploy-qa.yaml`:
```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: app-qa
spec:
  template:
    spec:
      containers:
      - image: app
```
PROD env - `deploy-prod.yaml`:
```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: app-prod
spec:
  template:
    spec:
      containers:
      - image: app
```

Review `skaffold.yaml` file that lists out all three environments,
and it's using Cloud Run as target service.
```yaml
apiVersion: skaffold/v3alpha1
kind: Config
metadata: 
  name: cloud-run-app
profiles:
- name: dev
  manifests:
    rawYaml:
    - deploy-dev.yaml
- name: qa
  manifests:
    rawYaml:
    - deploy-qa.yaml
- name: prod
  manifests:
    rawYaml:
    - deploy-prod.yaml
deploy:
  cloudrun: {}
```

Review Cloud Deploy pipeline config - `clouddeploy.yaml`
```yaml
apiVersion: deploy.cloud.google.com/v1
kind: DeliveryPipeline
metadata:
 name: cloud-run-pipeline
description: application deployment pipeline
serialPipeline:
 stages:
 - targetId: dev-env
   profiles: [dev]
 - targetId: qa-env
   profiles: [qa]
 - targetId: prod-env
   profiles: [prod]
---

apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
 name: dev-env
description: Cloud Run development service
run:
 location: projects/_PROJECT_ID/locations/us-west1
---

apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
 name: qa-env
description: Cloud Run QA service
run:
 location: projects/_PROJECT_ID/locations/us-central1
---

apiVersion: deploy.cloud.google.com/v1
kind: Target
metadata:
 name: prod-env
description: Cloud Run PROD service
run:
 location: projects/_PROJECT_ID/locations/us-south1

```

Replace _PROJECT_ID value in the `clouddeploy.yaml`:
```shell
sed -i "s/_PROJECT_ID/$PROJECT_ID/g" clouddeploy.yaml
```

Create Cloud Deploy pipeline:
```shell
gcloud deploy apply \
  --file=clouddeploy.yaml \
  --region=${REGION} \
  --project=${PROJECT_ID}
```

Review Cloud Deploy pipeline:

![Cloud Build](./images/cd-pipeline.png)

![Cloud Build](./images/cd-pipeline-details.png)

Review updated `cloudbuild-plus.yaml` file with new step to create Cloud Deploy release:
```shell
steps:
- name: 'gcr.io/k8s-skaffold/pack'
  entrypoint: 'pack'
  args: ['build', '--builder=gcr.io/buildpacks/builder', '--publish', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/containers-repo/app:$BUILD_ID']
  id: Build and package .net app
- name: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
  args: 
      [
        "deploy", "releases", "create", "release-$_RELEASE_TIMESTAMP",
        "--delivery-pipeline", "cloud-run-pipeline",
        "--region", "${_REGION}",
        "--images", "app=${_REGION}-docker.pkg.dev/${PROJECT_ID}/containers-repo/app:$BUILD_ID"
      ]
  entrypoint: gcloud
```
Add Cloud Deploy Operator permissions to Cloud Build service account:
```shell
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
    --role=roles/clouddeploy.operator

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
    --role=roles/iam.serviceAccountUser
```

Create Cloud Deploy release:
```shell
export RELEASE_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

gcloud builds submit \
  --config cloudbuild-plus.yaml \
  --substitutions=_REGION=${REGION},_RELEASE_TIMESTAMP=${RELEASE_TIMESTAMP}
```

Review Cloud Deploy release.

Deployment will start shortly:

![Cloud Build](./images/clouddeploy-queued.png)

Application deployment to Cloud Run is in progress:

![Cloud Build](./images/clouddeploy-in-progress.png)

Wait until Dev deployment is done:

![Cloud Build](./images/clouddeploy-dev.png)

View services in Cloud Run:

![Cloud Build](./images/clouddeploy-view-in-cloudrun.png)

Application in Cloud Run:

![Cloud Build](./images/cloudrun-dev.png)

Using Cloud Console or Cloud Shell, promote release to the next target(app-qa).

![Cloud Build](./images/cloud-deploy-promote.png)

If you want to promote with Cloud Shell, set RELEASE env variable to correct release value and run gcloud command to promote the release.
```shell
gcloud beta deploy releases promote \
    --release="release-${RELEASE_TIMESTAMP}" \
    --delivery-pipeline=cloud-run-pipeline \
    --region=${REGION} \
    --quiet
```

Promote release to the next target(app-prod).

```shell
gcloud beta deploy releases promote \
    --release=${RELEASE} \
    --delivery-pipeline=cloud-run-pipeline \
    --region=${REGION} \
    --quiet
```

Review Cloud Deploy pipeline state and available [DORA metrics](https://cloud.google.com/deploy/docs/metrics?_ga=2.157539578.-1719619211.1663508373) ("deployment count", "deployment frequency", "deployment failure rate").


![Cloud Build](./images/cloud-deploy-status.png)

| Metric                  | Description                                                                                                                                                        |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Number of deployments   | The total number of successful and failed deployments to the final target in your delivery pipeline.                                                                            | 
| Deployment frequency    | How often the delivery pipeline deploys to the final target in your delivery pipeline.<br/>One of the four key metrics defined by the DevOps Research and Assessment (DORA) program. | 
| Deployment failure rate | The percentage of failed rollouts to the final target in your delivery pipeline.                                                                                                | 

Review deployed applications in Cloud Run:

![Cloud Build](./images/cloud-run-services.png)

### Congratulations!