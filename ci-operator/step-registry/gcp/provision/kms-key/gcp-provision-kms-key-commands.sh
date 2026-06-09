#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# save the exit code for junit xml file generated in step gather-must-gather
# pre configuration steps before running installation, exit code 100 if failed,
# save to install-pre-config-status.txt
EXIT_CODE=100
trap 'if [[ "$?" == 0 ]]; then EXIT_CODE=0; fi; echo "${EXIT_CODE}" > "${SHARED_DIR}/install-pre-config-status.txt"' EXIT TERM

export CLOUDSDK_PYTHON=python3

GOOGLE_PROJECT_ID="$(< "${CLUSTER_PROFILE_DIR}/openshift_gcp_project")"
export GCP_SHARED_CREDENTIALS_FILE="${CLUSTER_PROFILE_DIR}/gce.json"
sa_email=$(jq -r .client_email "${GCP_SHARED_CREDENTIALS_FILE}")
if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -Fxq "${sa_email}"
then
  gcloud auth activate-service-account --key-file="${GCP_SHARED_CREDENTIALS_FILE}"
  gcloud config set project "${GOOGLE_PROJECT_ID}"
fi

LOCATION="global"
KEY_RING_NAME="openshift-ci"
KEY_NAME="openshift-ci-e2e"

echo "$(date -u --rfc-3339=seconds) - Ensuring KMS key ring '${KEY_RING_NAME}' exists in location '${LOCATION}'..."
if ! gcloud kms keyrings describe "${KEY_RING_NAME}" \
  --location="${LOCATION}" \
  --project="${GOOGLE_PROJECT_ID}" &>/dev/null; then
  gcloud kms keyrings create "${KEY_RING_NAME}" \
    --location="${LOCATION}" \
    --project="${GOOGLE_PROJECT_ID}"
  echo "Created key ring '${KEY_RING_NAME}'."
else
  echo "Key ring '${KEY_RING_NAME}' already exists."
fi

echo "$(date -u --rfc-3339=seconds) - Ensuring KMS crypto key '${KEY_NAME}' exists in key ring '${KEY_RING_NAME}'..."
if ! gcloud kms keys describe "${KEY_NAME}" \
  --keyring="${KEY_RING_NAME}" \
  --location="${LOCATION}" \
  --project="${GOOGLE_PROJECT_ID}" &>/dev/null; then
  gcloud kms keys create "${KEY_NAME}" \
    --keyring="${KEY_RING_NAME}" \
    --location="${LOCATION}" \
    --project="${GOOGLE_PROJECT_ID}" \
    --purpose=encryption
  echo "Created crypto key '${KEY_NAME}'."
else
  echo "Crypto key '${KEY_NAME}' already exists, reusing."
fi

echo "${KEY_RING_NAME}" > "${SHARED_DIR}/gcp_kms_key_ring"
echo "${KEY_NAME}" > "${SHARED_DIR}/gcp_kms_key_name"
echo "${LOCATION}" > "${SHARED_DIR}/gcp_kms_key_location"

echo "Saved KMS key details to SHARED_DIR:"
echo "  key_ring=${KEY_RING_NAME}"
echo "  key_name=${KEY_NAME}"
echo "  location=${LOCATION}"
