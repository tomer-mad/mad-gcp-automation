#!/bin/bash

# The target project for which the budget will be enforced.
TARGET_PROJECT_ID="mad-mmm-poc"

# The budget amount, in the currency of your billing account.
# CHANGE THIS VALUE to your desired budget amount.
BUDGET_AMOUNT="56"

# The service account that will run the Cloud Build job.
BUILD_SERVICE_ACCOUNT="budget-deployer-sa@madgrowth-data.iam.gserviceaccount.com"

# --- Pre-flight Permission Grant ---
echo "Granting the build service account (${BUILD_SERVICE_ACCOUNT}) permission to manage IAM on ${TARGET_PROJECT_ID}..."
# This command allows the build process to grant the required billing role to the Cloud Function's service account.
# It is run by the user executing this script, who is expected to have the necessary privileges.
gcloud projects add-iam-policy-binding ${TARGET_PROJECT_ID} \
  --member="serviceAccount:${BUILD_SERVICE_ACCOUNT}" \
  --role="roles/resourcemanager.projectIamAdmin"

if [ $? -ne 0 ]; then
  echo "Error: Failed to grant Project IAM Admin role to the build service account."
  echo "Please ensure you have permissions to manage IAM policies on project ${TARGET_PROJECT_ID} and try again."
  exit 1
fi
echo "Required IAM permissions for the build process have been successfully granted."
# --- End of Pre-flight Grant ---

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

# Submit the Cloud Build job. The service account for the build now has the necessary
# permissions to complete all steps in the YAML file.
gcloud builds submit --config gcp-project-budget/deploy-cost-enforcement.yaml \
#  --logging=CLOUD_LOGGING_ONLY \
  --substitutions=_TARGET_PROJECT_ID="${TARGET_PROJECT_ID}",_BUDGET_AMOUNT="${BUDGET_AMOUNT}",_BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID}" \
  --service-account="${BUILD_SERVICE_ACCOUNT}"

echo "Cloud Build job submitted successfully."
