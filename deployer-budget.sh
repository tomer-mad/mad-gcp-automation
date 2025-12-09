#!/bin/bash

# --- Configuration ---
# The target project for which the budget will be enforced.
TARGET_PROJECT_ID="mad-mmm-poc"

# The budget amount, in the currency of your billing account.
BUDGET_AMOUNT="20"

# The project where the deployer script runs (can be the same as target).
BUILD_PROJECT_ID="madgrowth-data"

# The service account for the Cloud Function. This script will create it if it doesn't exist.
FUNCTION_SERVICE_ACCOUNT_NAME="billing-disabler-sa"
FUNCTION_SERVICE_ACCOUNT_EMAIL="${FUNCTION_SERVICE_ACCOUNT_NAME}@${TARGET_PROJECT_ID}.iam.gserviceaccount.com"
# --- End of Configuration ---

# --- Undeploy Function ---
undeploy() {
    echo "Starting undeployment process..."

    # Delete Cloud Function
    echo "Deleting Cloud Function 'billing-disable-function'..."
    gcloud functions delete billing-disable-function --project="${TARGET_PROJECT_ID}" --region=us-central1 --quiet

    # Delete Pub/Sub Topic
    echo "Deleting Pub/Sub topic 'budget-alert-topic'..."
    gcloud pubsub topics delete budget-alert-topic --project="${TARGET_PROJECT_ID}" --quiet

    # Find and Delete Budget
    BILLING_ACCOUNT_ID=$(gcloud billing projects describe "${TARGET_PROJECT_ID}" --format='value(billingAccountName)' | sed 's|billingAccounts/||g' 2>/dev/null)
    if [[ -n "${BILLING_ACCOUNT_ID}" ]]; then
        BUDGET_DISPLAY_NAME="${TARGET_PROJECT_ID}-HARD-STOP-${BUDGET_AMOUNT}"
        BUDGET_ID=$(gcloud beta billing budgets list --billing-account="${BILLING_ACCOUNT_ID}" --filter="displayName=${BUDGET_DISPLAY_NAME}" --format='value(name)')
        if [[ -n "${BUDGET_ID}" ]]; then
            echo "Deleting budget '${BUDGET_DISPLAY_NAME}'..."
            gcloud beta billing budgets delete "${BUDGET_ID}"
        else
            echo "Budget '${BUDGET_DISPLAY_NAME}' not found."
        fi
    fi

    # Revoke IAM Roles and Delete Function Service Account
    echo "Revoking IAM roles and deleting function service account..."
    gcloud projects remove-iam-policy-binding "${TARGET_PROJECT_ID}" \
        --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
        --role="roles/billing.projectManager" --quiet --condition=None >/dev/null 2>&1

    gcloud iam service-accounts delete "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" --project="${TARGET_PROJECT_ID}" --quiet

    echo "Undeployment complete."
}

# --- Deploy Function ---
deploy() {
    echo "--- Starting Direct Deployment ---"

    # 1. Enable APIs
    echo "Enabling required APIs on target project ${TARGET_PROJECT_ID}..."
    gcloud services enable cloudfunctions.googleapis.com pubsub.googleapis.com cloudbilling.googleapis.com eventarc.googleapis.com --project="${TARGET_PROJECT_ID}"

    echo "Enabling required APIs on billing project ${BUILD_PROJECT_ID}..."
    gcloud services enable billingbudgets.googleapis.com --project="${BUILD_PROJECT_ID}"

    # 2. Create Function Service Account
    echo "Ensuring function service account ${FUNCTION_SERVICE_ACCOUNT_EMAIL} exists..."
    if ! gcloud iam service-accounts describe "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" --project="${TARGET_PROJECT_ID}" &> /dev/null; then
      gcloud iam service-accounts create "${FUNCTION_SERVICE_ACCOUNT_NAME}" \
        --project="${TARGET_PROJECT_ID}" \
        --display-name="Billing Disabler Function Service Account"
    fi
    echo "Granting Project Billing Manager role to function SA..."
    gcloud projects add-iam-policy-binding "${TARGET_PROJECT_ID}" \
      --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
      --role="roles/billing.projectManager" >/dev/null

    # 3. Create Pub/Sub Topic
    echo "Ensuring Pub/Sub topic 'budget-alert-topic' exists..."
    if ! gcloud pubsub topics describe budget-alert-topic --project=${TARGET_PROJECT_ID} &> /dev/null; then
      gcloud pubsub topics create budget-alert-topic --project=${TARGET_PROJECT_ID}
    fi

    # 4. Deploy Cloud Function
    echo "Deploying Cloud Function 'billing-disable-function'..."
    gcloud functions deploy billing-disable-function \
      --project "${TARGET_PROJECT_ID}" \
      --region "us-central1" \
      --runtime "python311" \
      --entry-point "stop_billing" \
      --source "./function-source" \
      --trigger-topic "budget-alert-topic" \
      --set-env-vars "TARGET_PROJECT_ID=${TARGET_PROJECT_ID}" \
      --service-account "${FUNCTION_SERVICE_ACCOUNT_EMAIL}"

    # 5. Create Budget
    echo "Ensuring billing budget exists..."
    BILLING_ACCOUNT_ID=$(gcloud billing projects describe "${TARGET_PROJECT_ID}" --format='value(billingAccountName)' | sed 's|billingAccounts/||g')
    if [[ -z "${BILLING_ACCOUNT_ID}" ]]; then
      echo "Error: Could not retrieve Billing Account ID for project ${TARGET_PROJECT_ID}."
      exit 1
    fi

    BUDGET_DISPLAY_NAME="${TARGET_PROJECT_ID}-HARD-STOP-${BUDGET_AMOUNT}"
    if ! gcloud beta billing budgets list --billing-account=${BILLING_ACCOUNT_ID} --format="value(displayName)" | grep -q "^${BUDGET_DISPLAY_NAME}$"; then
      echo "Creating budget of ${BUDGET_AMOUNT} for project ${TARGET_PROJECT_ID}..."
      gcloud beta billing budgets create \
        --billing-account=${BILLING_ACCOUNT_ID} \
        --display-name="${BUDGET_DISPLAY_NAME}" \
        --budget-amount=${BUDGET_AMOUNT} \
        --filter-projects="projects/${TARGET_PROJECT_ID}" \
        --credit-types-treatment=INCLUDE_ALL_CREDITS \
        --all-updates-rule-pubsub-topic="projects/${TARGET_PROJECT_ID}/topics/budget-alert-topic" \
        --threshold-rule=percent=0.9 \
        --threshold-rule=percent=0.95 \
        --threshold-rule=percent=0.99
    else
      echo "Budget '${BUDGET_DISPLAY_NAME}' already exists. Skipping creation."
    fi

    echo "--- Direct Deployment Finished Successfully ---"
}

# --- Main Execution ---
if [[ "$1" == "undeploy" ]]; then
    undeploy
elif [[ "$1" == "deploy" ]]; then
    deploy
else
    echo "Usage: $0 [deploy|undeploy]"
    exit 1
fi
