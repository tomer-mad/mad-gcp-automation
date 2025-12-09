#!/bin/bash

# This script deploys or removes a budget enforcement mechanism for a Google Cloud project.
# It creates a Cloud Function that is triggered by budget alerts and disables billing.

# --- Usage function ---
usage() {
    echo "Usage: $0 <deploy|undeploy|redeploy> --project <PROJECT_ID> --amount <AMOUNT>"
    echo ""
    echo "Commands:"
    echo "  deploy    Deploys the budget enforcement resources."
    echo "  undeploy  Removes the budget enforcement resources."
    echo "  redeploy  Removes the old system, prompts for manual billing re-enablement, then deploys the new system."
    echo ""
    echo "Arguments:"
    echo "  --project   The target Google Cloud project ID."
    echo "  --amount    The budget amount (required for all commands)."
    exit 1
}

# --- Parse Arguments ---
if [[ $# -lt 1 ]]; then
    usage
fi

COMMAND=$1
shift # consume command

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --project)
        TARGET_PROJECT_ID="$2"
        shift 2
        ;;
        --amount)
        BUDGET_AMOUNT="$2"
        shift 2
        ;;
        *)    # unknown option
        usage
        ;;
    esac
done

# --- Validate Arguments ---
if [[ -z "${TARGET_PROJECT_ID}" || -z "${BUDGET_AMOUNT}" ]]; then
    echo "Error: Both --project and --amount are required."
    usage
fi
if [[ "${COMMAND}" != "deploy" && "${COMMAND}" != "undeploy" && "${COMMAND}" != "redeploy" ]]; then
    usage
fi

# --- Dynamic Configuration ---
FUNCTION_SERVICE_ACCOUNT_NAME="billing-disabler-sa"
FUNCTION_SERVICE_ACCOUNT_EMAIL="${FUNCTION_SERVICE_ACCOUNT_NAME}@${TARGET_PROJECT_ID}.iam.gserviceaccount.com"
TOPIC_ID="budget-alert-topic" # Reverted to generic name

# --- Undeploy Function ---
undeploy() {
    echo "--- Starting Undeployment for project: ${TARGET_PROJECT_ID} ---"

    echo ""
    echo "============================== ACTION REQUIRED =============================="
    echo "To prevent errors, billing must be enabled for project '${TARGET_PROJECT_ID}'"
    echo "before undeployment can proceed. Please re-enable it in the Google Cloud Console."
    echo "1. Go to: https://console.cloud.google.com/billing"
    echo "2. Select the project '${TARGET_PROJECT_ID}'."
    echo "3. Link your billing account."
    echo "==========================================================================="
    echo ""
    read -p "Once billing is re-enabled, press [Enter] to continue..."

    # Delete Cloud Function if it exists
    echo "Checking for Cloud Function 'billing-disable-function'..."
    if gcloud functions describe billing-disable-function --project="${TARGET_PROJECT_ID}" --region=us-central1 &> /dev/null; then
        echo "Deleting Cloud Function 'billing-disable-function'..."
        gcloud functions delete billing-disable-function --project="${TARGET_PROJECT_ID}" --region=us-central1 --quiet
    else
        echo "Cloud Function 'billing-disable-function' not found. Skipping."
    fi

    # Delete Pub/Sub Topic if it exists
    echo "Checking for Pub/Sub topic '${TOPIC_ID}'..."
    if gcloud pubsub topics describe "${TOPIC_ID}" --project="${TARGET_PROJECT_ID}" &> /dev/null; then
        echo "Deleting Pub/Sub topic '${TOPIC_ID}'..."
        gcloud pubsub topics delete "${TOPIC_ID}" --project="${TARGET_PROJECT_ID}" --quiet
    else
        echo "Pub/Sub topic '${TOPIC_ID}' not found. Skipping."
    fi

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

    # Revoke IAM Roles and Delete Function Service Account if it exists
    echo "Checking for service account ${FUNCTION_SERVICE_ACCOUNT_EMAIL}..."
    if gcloud iam service-accounts describe "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" --project="${TARGET_PROJECT_ID}" &> /dev/null; then
        echo "Service account found. Revoking roles and deleting..."
        TARGET_PROJECT_NUMBER=$(gcloud projects describe "${TARGET_PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)
        DEFAULT_CLOUDBUILD_SA="${TARGET_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
        PUBSUB_SERVICE_ACCOUNT="service-${TARGET_PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"

        # Revoke permissions on the function SA
        gcloud iam service-accounts remove-iam-policy-binding "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
            --project="${TARGET_PROJECT_ID}" \
            --member="serviceAccount:${DEFAULT_CLOUDBUILD_SA}" \
            --role="roles/iam.serviceAccountUser" --quiet >/dev/null 2>&1
        gcloud iam service-accounts remove-iam-policy-binding "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
            --project="${TARGET_PROJECT_ID}" \
            --member="serviceAccount:${PUBSUB_SERVICE_ACCOUNT}" \
            --role="roles/iam.serviceAccountUser" --quiet >/dev/null 2>&1

        # Revoke permissions from the function SA
        gcloud projects remove-iam-policy-binding "${TARGET_PROJECT_ID}" \
            --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
            --role="roles/billing.projectManager" --quiet --condition=None >/dev/null 2>&1
        gcloud projects remove-iam-policy-binding "${TARGET_PROJECT_ID}" \
            --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
            --role="roles/cloudfunctions.invoker" --quiet --condition=None >/dev/null 2>&1
        gcloud projects remove-iam-policy-binding "${TARGET_PROJECT_ID}" \
            --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
            --role="roles/run.invoker" --quiet --condition=None >/dev/null 2>&1
        gcloud projects remove-iam-policy-binding "${TARGET_PROJECT_ID}" \
            --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
            --role="roles/pubsub.serviceAgent" --quiet --condition=None >/dev/null 2>&1

        # Delete Function Service Account
        if ! gcloud iam service-accounts delete "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" --project="${TARGET_PROJECT_ID}" --quiet; then
            echo "Warning: Failed to delete service account ${FUNCTION_SERVICE_ACCOUNT_EMAIL}."
            echo "Please manually delete it from the Google Cloud Console."
        fi
    else
        echo "Service account ${FUNCTION_SERVICE_ACCOUNT_EMAIL} not found or already deleted. Skipping."
    fi

    # Revoke permissions for Pub/Sub SA
    TARGET_PROJECT_NUMBER=$(gcloud projects describe "${TARGET_PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)
    if [[ -n "${TARGET_PROJECT_NUMBER}" ]]; then
        PUBSUB_SERVICE_ACCOUNT="service-${TARGET_PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
        gcloud projects remove-iam-policy-binding "${TARGET_PROJECT_ID}" \
            --member="serviceAccount:${PUBSUB_SERVICE_ACCOUNT}" \
            --role="roles/run.invoker" --quiet --condition=None >/dev/null 2>&1
        gcloud projects remove-iam-policy-binding "${TARGET_PROJECT_ID}" \
            --member="serviceAccount:${PUBSUB_SERVICE_ACCOUNT}" \
            --role="roles/cloudfunctions.invoker" --quiet --condition=None >/dev/null 2>&1
    fi

    echo "--- Undeployment for project ${TARGET_PROJECT_ID} complete. ---"
}

# --- Deploy Function ---
deploy() {
    echo "--- Starting Deployment for project: ${TARGET_PROJECT_ID} with budget: ${BUDGET_AMOUNT} ---"

    # 1. Enable APIs
    echo "Enabling required APIs on target project ${TARGET_PROJECT_ID}..."
    gcloud services enable cloudfunctions.googleapis.com pubsub.googleapis.com cloudbilling.googleapis.com eventarc.googleapis.com cloudbuild.googleapis.com run.googleapis.com --project="${TARGET_PROJECT_ID}"

    # 2. Create Function Service Account
    echo "Ensuring function service account ${FUNCTION_SERVICE_ACCOUNT_EMAIL} exists..."
    if ! gcloud iam service-accounts describe "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" --project="${TARGET_PROJECT_ID}" &> /dev/null; then
      gcloud iam service-accounts create "${FUNCTION_SERVICE_ACCOUNT_NAME}" \
        --project="${TARGET_PROJECT_ID}" \
        --display-name="Billing Disabler Function Service Account"
      echo "Waiting 30 seconds for service account to propagate before granting permissions..."
      sleep 30
    fi
    echo "Granting Project Billing Manager role to function SA..."
    gcloud projects add-iam-policy-binding "${TARGET_PROJECT_ID}" \
      --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
      --role="roles/billing.projectManager" >/dev/null
    echo "Granting Cloud Function Invoker role to function SA..."
    gcloud projects add-iam-policy-binding "${TARGET_PROJECT_ID}" \
      --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
      --role="roles/cloudfunctions.invoker" >/dev/null
    echo "Granting Cloud Run Invoker role to function SA..."
    gcloud projects add-iam-policy-binding "${TARGET_PROJECT_ID}" \
      --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
      --role="roles/run.invoker" >/dev/null
    echo "Granting Pub/Sub Service Agent role to function SA..."
    gcloud projects add-iam-policy-binding "${TARGET_PROJECT_ID}" \
      --member="serviceAccount:${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
      --role="roles/pubsub.serviceAgent" >/dev/null

    # 3. Grant Build SA permission to use Function SA
    echo "Granting Cloud Build SA permission to use the function's service account..."
    TARGET_PROJECT_NUMBER=$(gcloud projects describe "${TARGET_PROJECT_ID}" --format="value(projectNumber)")
    DEFAULT_CLOUDBUILD_SA="${TARGET_PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"
    gcloud iam service-accounts add-iam-policy-binding "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
        --project="${TARGET_PROJECT_ID}" \
        --member="serviceAccount:${DEFAULT_CLOUDBUILD_SA}" \
        --role="roles/iam.serviceAccountUser"

    # 4. Grant Pub/Sub SA permissions
    PUBSUB_SERVICE_ACCOUNT="service-${TARGET_PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
    echo "Granting Pub/Sub SA permission to invoke the Cloud Function..."
    gcloud projects add-iam-policy-binding "${TARGET_PROJECT_ID}" \
        --member="serviceAccount:${PUBSUB_SERVICE_ACCOUNT}" \
        --role="roles/run.invoker"
    gcloud projects add-iam-policy-binding "${TARGET_PROJECT_ID}" \
        --member="serviceAccount:${PUBSUB_SERVICE_ACCOUNT}" \
        --role="roles/cloudfunctions.invoker"
    echo "Granting Pub/Sub SA permission to use the function's service account..."
    gcloud iam service-accounts add-iam-policy-binding "${FUNCTION_SERVICE_ACCOUNT_EMAIL}" \
        --project="${TARGET_PROJECT_ID}" \
        --member="serviceAccount:${PUBSUB_SERVICE_ACCOUNT}" \
        --role="roles/iam.serviceAccountUser"

    echo "Waiting 30 seconds for IAM permissions to propagate..."
    sleep 30

    # 5. Create Pub/Sub Topic
    echo "Ensuring Pub/Sub topic '${TOPIC_ID}' exists..."
    if ! gcloud pubsub topics describe "${TOPIC_ID}" --project=${TARGET_PROJECT_ID} &> /dev/null; then
      gcloud pubsub topics create "${TOPIC_ID}" --project=${TARGET_PROJECT_ID}
    fi

    # 6. Deploy Cloud Function
    echo "Deploying Cloud Function 'billing-disable-function'..."
    gcloud functions deploy billing-disable-function \
      --project "${TARGET_PROJECT_ID}" \
      --region "us-central1" \
      --runtime "python311" \
      --entry-point "stop_billing" \
      --source "./function-source" \
      --trigger-topic "${TOPIC_ID}" \
      --service-account "${FUNCTION_SERVICE_ACCOUNT_EMAIL}"

    # 7. Create Budget
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
        --all-updates-rule-pubsub-topic="projects/${TARGET_PROJECT_ID}/topics/${TOPIC_ID}" \
        --threshold-rule=percent=0.9 \
        --threshold-rule=percent=0.95 \
        --threshold-rule=percent=0.99
    else
      echo "Budget '${BUDGET_DISPLAY_NAME}' already exists. Skipping creation."
    fi

    echo "--- Deployment for project ${TARGET_PROJECT_ID} finished successfully. ---"
}

# --- Redeploy Function ---
redeploy() {
    echo "--- Starting Redeployment Process ---"

    # 1. Undeploy the existing system
    undeploy

    # 2. Deploy the new system
    deploy
}


# --- Main Execution ---
if [[ "${COMMAND}" == "deploy" ]]; then
    deploy
elif [[ "${COMMAND}" == "undeploy" ]]; then
    undeploy
elif [[ "${COMMAND}" == "redeploy" ]]; then
    redeploy
fi
