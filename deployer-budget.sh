#!/bin/bash

# The target project for which the budget will be enforced.
TARGET_PROJECT_ID="mad-mmm-poc"

# The budget amount in USD.
BUDGET_AMOUNT="276"

# Retrieve the Billing Account ID associated with the target project.
# The 'sed' command strips the 'billingAccounts/' prefix to get the raw ID.
BILLING_ACCOUNT_ID=$(gcloud projects describe ${TARGET_PROJECT_ID} --format='value(billingAccountName)' | sed 's|billingAccounts/||g')

# Check if the billing account ID was retrieved successfully.
if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
  echo "Error: Could not retrieve Billing Account ID for project ${TARGET_PROJECT_ID}."
  echo "Please ensure the project exists and you have permissions to view its billing information."
  exit 1
fi

echo "Submitting Cloud Build job with the following parameters:"
echo "Target Project ID: ${TARGET_PROJECT_ID}"
echo "Budget Amount: ${BUDGET_AMOUNT}"
echo "Billing Account ID: ${BILLING_ACCOUNT_ID}"

# Submit the Cloud Build job with all required parameters as substitutions.
gcloud builds submit --config gcp-project-budget/deploy-cost-enforcement.yaml \
  --substitutions=_TARGET_PROJECT_ID="${TARGET_PROJECT_ID}",_BUDGET_AMOUNT="${BUDGET_AMOUNT}",_BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID}" \
  --service-account="budget-deployer-sa@madgrowth-data.iam.gserviceaccount.com" \
  --logging=CLOUD_LOGGING_ONLY

echo "Cloud Build job submitted successfully."
