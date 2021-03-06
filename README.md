# Github Actions GCP Deploy Script

This script is used by [Git Hub Actions](https://github.com/features/actions) to continuously deploy artifacts to a GCP bucket.

When Git Hub Actions builds a push to your project (not a pull request), any files matching `target/*.{war,jar,zip}` will be uploaded to your GCP bucket with the prefix `builds/$DEPLOY_BUCKET_PREFIX/deploy/$BRANCH/$BUILD_NUMBER/`. Pull requests will upload the same files with a prefix of `builds/$DEPLOY_BUCKET_PREFIX/pull-request/$PULL_REQUEST_NUMBER/`.

For example, the 36th push to the `master` branch will result in the following files being created in your `exampleco-ops` bucket:

```
builds/exampleco/deploy/master/36/exampleco-1.0-SNAPSHOT.war
builds/exampleco/deploy/master/36/exampleco-1.0-SNAPSHOT.zip
```

When the 15th pull request is created, the following files will be uploaded into your bucket:
```
builds/exampleco/pull-request/15/exampleco-1.0-SNAPSHOT.war
builds/exampleco/pull-request/15/exampleco-1.0-SNAPSHOT.zip
```

## Usage

Your .github/workflows/gradle.yml should look something like this:

```
# This workflow will build a Java project with Gradle
# For more information see: https://help.github.com/actions/language-and-framework-guides/building-and-testing-java-with-gradle

name: Java CI with Gradle

on:
  push:
    branches: 
      - develop
      - release/*
    tags: v*

  pull_request:
    branches: 
      - develop
      - release/*

env:
  GITHUB_ACTIONS_PULL_REQUEST: ${{ github.event.pull_request.number }}
  DEPLOY_SOURCE_DIR: site/build/libs
  BUILD_NUM_OFFSET: 1000

jobs:
  build:

    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v2
    - name: Set up JDK
      uses: actions/setup-java@v2
      with:
        java-version: '8'
        distribution: 'adopt'
    - name: Get Tag Version
      run: echo "GITHUB_ACTIONS_TAG=${GITHUB_REF#refs/*/}" >> $GITHUB_ENV
    - name: Clone Github Actions S3 Deploy
      run: git clone https://github.com/perfectsense/github-actions-gcp-deploy.git
    - name: Build with Gradle
      run: ./github-actions-gcp-deploy/build-gradle.sh
    - name: Deploy to GCP
      env:
        DEPLOY_BUCKET: ${{ secrets.DEPLOY_BUCKET }}
        DEPOLOY_CREDENTIALS: ${{ secrets.GCP_CREDE

```

## Generate a [GCP Service account](https://developers.google.com/identity/protocols/oauth2/service-account)
Encrypt with openssl des3 with a strong password and save to your project in /.github/deploy/gcp-deploy.json.des3
Ex : `openssl des3 -in credentials.json -out gcp-deploy.json.des3 -md sha512`

In Github Actions set DEPLOY_BUCKET and GCP_CREDENTIALS environmental variables
GCP_CREDENTIALS is the encryption password for the GCP Service Account credentials

