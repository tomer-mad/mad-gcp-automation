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

# The service account for the Cloud Function. This script will create it if it doesn't exist.
FUNCTION_SERVICE_ACCOUNT_NAME="billing-disabler-sa"
FUNCTION_SERVICE_ACCOUNT_EMAIL="${FUNCTION_SERVICE_ACCOUNT_NAME}@${TARGET_PROJECT_ID}.iam.gserviceaccount.com"
# --- End of Configuration ---


# --- Build Service Account Setup (Idempotent) ---
echo "Checking for build service account ${BUILD_SERVICE_ACCOUNT_EMAIL}..."
if ! gcloud iam service-accounts describe "${BUILD_SERVICE_ACCOUNT_EMAIL}" --project="${BUILD_PROJECT_ID}" &> /dev/null; then
  echo "Build service account not found. Creating it now..."
  if ! gcloud iam service-accounts create "${BUILD_SERVICE_ACCOUNT_NAME}" \
    --project="${BUILD_PROJECT_ID}" \
    --display-name="Budget Deployer Service Account"; then
    echo "Error: Failed to create the build service account."
    echo "Please ensure you have permissions to create service accounts in project ${BUILD_PROJECT_ID}."
    exit 1
  fi
  echo "Build service account created successfully."
else
  echo "Build service account already exists."
fi
# --- End of Build Service Account Setup ---


# --- Function Service Account Setup (Idempotent) ---
echo "Checking for function service account ${FUNCTION_SERVICE_ACCOUNT_EMAIL}..."
if ! gcloud iam service-accounts describe "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" --project="${TARGET_PROJECT_ID}" &> /dev/null; then
  echo "Function service account not found. Creating it now..."
  if ! gcloud iam service-accounts create "${FUNCTION_SERVICE_ACCOUNT_NAME}" \
    --project="${TARGET_PROJECT_ID}" \
    --display-name="Billing Disabler Function Service Account"; then
    echo "Error: Failed to create the function service account."
    echo "Please ensure you have permissions to create service accounts in project ${TARGET_PROJECT_ID}."
    exit 1
  fi
  echo "Function service account created successfully."
else
  echo "Function service account already exists."
fi

echo "Granting function service account (${FUNCTION_SERVICE_ACCOUNT_EMAIL}) the Project Billing Manager role..."
# This allows the function to disable billing on the target project.
# The user running this script needs permission to grant this role.
if ! gcloud projects add-iam-policy-binding "${TARGET_PROJECT_ID}" \
  --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/billing.projectManager"; then
  echo "Error: Failed to grant Project Billing Manager role to the function service account."
  echo "Please ensure you have permissions to manage IAM policies on project ${TARGET_PROJECT_ID}."
  exit 1
fi
echo "Required IAM permissions for the function service account have been successfully granted."
# --- End of Function Service Account Setup ---


# --- Main Logic ---
# Retrieve the Billing Account ID associated with the target project.
BILLING_ACCOUNT_ID=$(gcloud billing projects describe "${TARGET_PROJECT_ID}" --format='value(billingAccountName)' | sed 's|billingAccounts/||g')

if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
  echo "Error: Could not retrieve Billing Account ID for project ${TARGET_PROJECT_ID}."
  exit 1
fi

# --- Pre-flight Permission Grant for Build SA ---
echo "Granting the build service account (${BUILD_SERVICE_ACCOUNT_EMAIL}) permission to create budgets on billing account ${BILLING_ACCOUNT_ID}..."
# This allows the build process to create the budget for the target project.
# It requires the user running this script to have 'Billing Account Administrator' role.
if ! gcloud billing accounts add-iam-policy-binding "${BILLING_ACCOUNT_ID}" \
  --member="serviceAccount:${BUILD_SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/billing.admin"; then
  echo "Error: Failed to grant Billing Admin role to the build service account on the billing account."
  echo "Please ensure you have permissions to manage IAM policies on billing account ${BILLING_ACCOUNT_ID}."
  exit 1
fi
echo "Required IAM permissions for the build process have been successfully granted."
# --- End of Pre-flight Grant ---


echo "Submitting Cloud Build job with the following parameters:"
echo "Target Project ID: ${TARGET_PROJECT_ID}"
echo "Budget Amount: ${BUDGET_AMOUNT} (in billing account currency)"
echo "Billing Account ID: ${BILLING_ACCOUNT_ID}"
echo "Function Service Account: ${FUNCTION_SERVICE_ACCOUNT_EMAIL}"

# Submit the Cloud Build job.
gcloud builds submit --config gcp-project-budget/deploy-cost-enforcement.yaml \
  --substitutions=_TARGET_PROJECT_ID="${TARGET_PROJECT_ID}",_BUDGET_AMOUNT="${BUDGET_AMOUNT}",_BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID}",_FUNCTION_SERVICE_ACCOUNT_EMAIL="${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
  --service-account="projects/${BUILD_PROJECT_ID}/serviceAccounts/${BUILD_SERVICE_ACCOUNT_EMAIL}"

echo "Cloud Build job submitted successfully."
