#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git shared.na.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Set up Jenkins with sufficient resources
# DO NOT FORGET TO PASS '-n ${GUID}-jenkins to ALL commands!!'
# You do not want to set up things in the wrong project.

oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi --param DISABLE_ADMINISTRATIVE_MONITORS=true -n ${GUID}-jenkins
oc set resources dc jenkins --limits=memory=2Gi,cpu=2 --requests=memory=1Gi,cpu=500m -n ${GUID}-jenkins

oc new-build --strategy=docker -D $'FROM registry.access.redhat.com/ubi8/go-toolset:latest as builder\n
ENV SKOPEO_VERSION=v1.0.0\n
RUN git clone -b $SKOPEO_VERSION https://github.com/containers/skopeo.git && cd skopeo/ && make binary-local DISABLE_CGO=1\n
FROM image-registry.openshift-image-registry.svc:5000/openshift/jenkins-agent-maven:v4.0 as final\n
USER root\n
RUN mkdir /etc/containers\n
COPY --from=builder /opt/app-root/src/skopeo/default-policy.json /etc/containers/policy.json\n
COPY --from=builder /opt/app-root/src/skopeo/skopeo /usr/bin\n
USER 1001' --name=jenkins-agent-appdev -n ${GUID}-jenkins

oc create secret generic gitea-secret --from-literal=username=srinivas.sarat.yadavalli-ibm.com --from-literal=password=Adm1n1strat0r -n ${GUID}-jenkins
#oc set build-secret --source bc/tasks gitea-secret -n ${GUID}-jenkins


oc new-app --template=eap72-basic-s2i --param APPLICATION_NAME=tasks --param SOURCE_REPOSITORY_URL=https://homework-gitea.apps.shared-na4.na4.openshift.opentlc.com/SaratOCPHW/openshift-tasks.git --param SOURCE_REPOSITORY_REF=master --param CONTEXT_DIR=openshift-tasks --param MAVEN_MIRROR_URL=https://homework-nexus.apps.shared-na4.na4.openshift.opentlc.com/repository/maven-all-public/ -n ${GUID}-jenkins

#oc create secret generic gitea-secret --from-literal=username=srinivas.sarat.yadavalli-ibm.com --from-literal=password=Adm1n1strat0r -n ${GUID}-jenkins
oc set build-secret --source bc/tasks gitea-secret -n ${GUID}-jenkins
# Create custom agent container image with skopeo.
# Build config must be called 'jenkins-agent-appdev' for the test below to succeed

# TBD


# Create Secret with credentials to access the private repository
# You may hardcode your user id and password here because
# this shell scripts lives in a private repository
# Passing it from Jenkins would show it in the Jenkins Log

# TBD



# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
# Build config has to be called 'tasks-pipeline'.
# Make sure you use your secret to access the repository

# TBD



# Set up ConfigMap with Jenkins Agent definition
oc create -f ./manifests/agent-cm.yaml -n ${GUID}-jenkins
echo ******CREATED CONFIG MAP*******

# ========================================
# No changes are necessary below this line
# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done

oc start-build tasks -n ${GUID}-jenkins

# Make sure that Jenkins Agent Build Pod has finished building
while : ; do
  echo "Checking if Jenkins Agent Build Pod has finished building..."
  AVAILABLE_REPLICAS=$(oc get pod jenkins-agent-appdev-1-build -n ${GUID}-jenkins -o=jsonpath='{.status.phase}')
  if [[ "$AVAILABLE_REPLICAS" == "Succeeded" ]]; then
    echo "...Yes. Jenkins Agent Build Pod has finished."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done

oc policy add-role-to-user admin system:serviceaccount:gpte-jenkins:homework-jenkins -n ${GUID}-jenkins
oc policy add-role-to-user admin system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-tasks-dev
oc policy add-role-to-user admin system:serviceaccount:${GUID}-jenkins:jenkins -n ${GUID}-tasks-prod
#oc create -f ./manifests/tasks-pipeline.yml -n ${GUID}-jenkins
#oc set build-secret --source bc/tasks-pipeline gitea-secret -n ${GUID}-jenkins

echo "******* Done executing the setup_jenkins.sh script**********"