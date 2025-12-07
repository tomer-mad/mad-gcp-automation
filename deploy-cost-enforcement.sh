#!/bin/bash

# --- Configuration Variables ---
FUNCTION_NAME="billing-disable-function"
TOPIC_NAME="budget-alert-topic"
REGION="us-central1" # IMPORTANT: Choose a region near you or the billing account region
RUNTIME="python311"
ENTRY_POINT="stop_billing"
SOURCE_DIR="./function-source" # Directory containing main.py and requirements.txt

# --- Input Validation ---
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <PROJECT_ID> <BUDGET_AMOUNT_USD>"
    exit 1
fi

PROJECT_ID=$1
BUDGET_AMOUNT=$2
BUDGET_DISPLAY_NAME="${PROJECT_ID}-HARD-STOP-${BUDGET_AMOUNT}"
BILLING_ACCOUNT_ID=$(gcloud projects describe "$PROJECT_ID" --format='value(billingAccountName)')

if [ -z "$BILLING_ACCOUNT_ID" ]; then
    echo "ERROR: Project $PROJECT_ID is not linked to a billing account."
    exit 1
fi
BILLING_ACCOUNT_ID=${BILLING_ACCOUNT_ID##*/} # Extracts the ID from the full resource name

echo "--- Starting Automated Budget Enforcement Setup ---"
echo "Project ID: $PROJECT_ID"
echo "Billing Account ID: $BILLING_ACCOUNT_ID"
echo "Budget Amount: $BUDGET_AMOUNT USD"
echo "------------------------------------------------"

# 1. Enable Required APIs (Cloud Functions, Pub/Sub, Cloud Billing)
echo "1. Enabling required APIs..."
gcloud services enable cloudfunctions.googleapis.com pubsub.googleapis.com cloudbilling.googleapis.com --project="$PROJECT_ID"

# 2. Create Pub/Sub Topic
echo "2. Creating Pub/Sub topic: $TOPIC_NAME..."
gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID"

# 3. Deploy Cloud Function
# The function is deployed to the target project and uses an environment variable
# to know which project to act on.
echo "3. Deploying Cloud Function: $FUNCTION_NAME..."
gcloud functions deploy "$FUNCTION_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --runtime="$RUNTIME" \
  --entry-point="$ENTRY_POINT" \
  --source="$SOURCE_DIR" \
  --trigger-topic="$TOPIC_NAME" \
  --set-env-vars="TARGET_PROJECT_ID=${PROJECT_ID}" \
  --allow-unauthenticated # Note: Pub/Sub triggers are implicitly secure, this is generally safe

# Retrieve the Cloud Function's Service Account
SERVICE_ACCOUNT=$(gcloud functions describe "$FUNCTION_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format='value(serviceAccountEmail)')

echo "Cloud Function Service Account: $SERVICE_ACCOUNT"

# 4. Grant Billing Permissions to the Cloud Function's Service Account
echo "4. Granting Project Billing Manager role to Service Account..."
# IMPORTANT: This permission must be granted on the TARGET project, or ideally,
# on the Billing Account if the function is centralized. For this per-project model,
# granting it on the project is often sufficient, but granting it on the Billing Account
# is more reliable for Billing API calls.
gcloud organizations add-iam-policy-binding "$BILLING_ACCOUNT_ID" \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/billing.projectManager" \
  --account-id="$BILLING_ACCOUNT_ID" # Make sure to specify the billing account for this command

# 5. Create the Budget and link the Pub/Sub Topic
echo "5. Creating Billing Budget and linking Pub/Sub topic..."
gcloud beta billing budgets create \
  --billing-account="$BILLING_ACCOUNT_ID" \
  --display-name="$BUDGET_DISPLAY_NAME" \
  --amount="$BUDGET_AMOUNT" \
  --calendar-period=MONTH \
  --projects="$PROJECT_ID" \
  --threshold-rule=percent=100.0,action=pubsub,topic="$TOPIC_NAME",project="$PROJECT_ID" \
  --all-services # Apply to all services in the project

echo "--- Setup Complete! ---"
echo "Project $PROJECT_ID is now protected with a \$$BUDGET_AMOUNT hard limit."
echo "Remember: You must manually re-link the billing account when the limit is hit."