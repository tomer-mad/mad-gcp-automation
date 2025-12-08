#!/bin/bash

# --- Configuration ---
# The target project for which the budget will be enforced.
TARGET_PROJECT_ID="mad-mmm-poc"

# The budget amount, in the currency of your billing account.
BUDGET_AMOUNT="27"

# The project where the Cloud Build job runs and where the deployer service account lives.
BUILD_PROJECT_ID="madgrowth-data"
BUILD_SERVICE_ACCOUNT_NAME="budget-deployer-sa"
BUILD_SERVICE_ACCOUNT_EMAIL="${BUILD_SERVICE_ACCOUNT_NAME}@${BUILD_PROJECT_ID}.iam.gserviceaccount.com"
# --- End of Configuration ---


# --- Service Account Creation (Idempotent) ---
echo "Checking for build service account ${BUILD_SERVICE_ACCOUNT_EMAIL}..."
# The 'gcloud iam service-accounts describe' command fails if the SA doesn't exist.
# We suppress output and check the exit code.
if ! gcloud iam service-accounts describe ${BUILD_SERVICE_ACCOUNT_EMAIL} --project=${BUILD_PROJECT_ID} &> /dev/null; then
  echo "Service account not found. Creating it now..."
  gcloud iam service-accounts create ${BUILD_SERVICE_ACCOUNT_NAME} \
    --project=${BUILD_PROJECT_ID} \
    --display-name="Budget Deployer Service Account"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create the build service account."
    echo "Please ensure you have permissions to create service accounts in project ${BUILD_PROJECT_ID}."
    exit 1
  fi
  echo "Service account created successfully."
else
  echo "Service account already exists."
fi
# --- End of Service Account Creation ---


# --- Pre-flight Permission Grant ---
echo "Granting the build service account (${BUILD_SERVICE_ACCOUNT_EMAIL}) permission to manage IAM on ${TARGET_PROJECT_ID}..."
# This allows the build process to grant the required billing role to the Cloud Function's service account.
gcloud projects add-iam-policy-binding ${TARGET_PROJECT_ID} \
  --member="serviceAccount:${BUILD_SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/resourcemanager.projectIamAdmin"

if [ $? -ne 0 ]; then
  echo "Error: Failed to grant Project IAM Admin role to the build service account."
  echo "Please ensure you have permissions to manage IAM policies on project ${TARGET_PROJECT_ID}."
  exit 1
fi
echo "Required IAM permissions for the build process have been successfully granted."
# --- End of Pre-flight Grant ---


# --- Main Logic ---
# Retrieve the Billing Account ID associated with the target project.
BILLING_ACCOUNT_ID=$(gcloud billing projects describe ${TARGET_PROJECT_ID} --format='value(billingAccountName)' | sed 's|billingAccounts/||g')

if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
  echo "Error: Could not retrieve Billing Account ID for project ${TARGET_PROJECT_ID}."
  exit 1
fi

echo "Submitting Cloud Build job with the following parameters:"
echo "Target Project ID: ${TARGET_PROJECT_ID}"
echo "Budget Amount: ${BUDGET_AMOUNT} (in billing account currency)"
echo "Billing Account ID: ${BILLING_ACCOUNT_ID}"

# Submit the Cloud Build job.
gcloud builds submit --config gcp-project-budget/deploy-cost-enforcement.yaml \
  --substitutions=_TARGET_PROJECT_ID="${TARGET_PROJECT_ID}",_BUDGET_AMOUNT="${BUDGET_AMOUNT}",_BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID}" \
  --service-account="projects/${BUILD_PROJECT_ID}/serviceAccounts/${BUILD_SERVICE_ACCOUNT_EMAIL}"

echo "Cloud Build job submitted successfully."
