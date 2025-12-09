import base64
import json
import os
from googleapiclient import discovery
from googleapiclient.errors import HttpError
import requests

def stop_billing(event, context):
    """
    Stops billing for a project by disabling the billing account associated with it.
    This function is triggered by a Pub/Sub message from a budget alert and only
    disables billing if the cost has reached 99% or more of the budget.
    """
    print(f"Function triggered by event: {context.event_id}")
    # --- DIAGNOSTIC START ---
    try:
        metadata_url = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
        headers = {"Metadata-Flavor": "Google"}
        identity = requests.get(metadata_url, headers=headers).text
        print(f"🕵️ ACTUAL FUNCTION IDENTITY: {identity}")
    except Exception as e:
        print(f"Could not determine identity: {e}")
    # --- DIAGNOSTIC END ---
    try:
        # Decode the Pub/Sub message
        pubsub_data = base64.b64decode(event['data']).decode('utf-8')
        pubsub_json = json.loads(pubsub_data)
        print(f"Decoded Pub/Sub payload: {pubsub_json}")

        cost_amount = pubsub_json.get('costAmount', 0.0)
        budget_amount = pubsub_json.get('budgetAmount', 0.0)

        # --- Main Logic: Calculate percentage and act only if >= 99% ---
        if budget_amount == 0:
            print("Budget amount is zero. Cannot calculate percentage. Taking no action.")
            return "No action taken, budget is zero."

        current_percentage = cost_amount / budget_amount
        print(f"Current cost is {cost_amount} out of {budget_amount} budget ({current_percentage:.2%}).")

        if current_percentage < 0.99:
            print(f"Budget usage is below 99%. Taking no action.")
            return "No action taken."

        # Get the project ID from environment variables
        project_id = os.environ.get('TARGET_PROJECT_ID')
        if not project_id:
            raise ValueError("TARGET_PROJECT_ID environment variable not set.")

        print(f"CRITICAL: Budget usage is >= 99%. Proceeding to disable billing for project: {project_id}")

        project_name = f'projects/{project_id}'
        billing = discovery.build('cloudbilling', 'v1', cache_discovery=False)

        billing_info = billing.projects().getBillingInfo(name=project_name).execute()

        if not billing_info.get('billingEnabled'):
            print(f"Billing is already disabled for project: {project_id}")
            return "Billing already disabled."

        print(f"Attempting to disable billing for project: {project_id}")
        body = {'billingAccountName': ''}  # Empty string disables billing
        billing.projects().updateBillingInfo(name=project_name, body=body).execute()

        print(f"Successfully disabled billing for project: {project_id}")
        return "Billing disabled."

    except HttpError as e:
        print(f"ERROR: Google API HTTP Error: {e}")
        print(f"Detailed API Error Response: {e.content}")
        raise
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        raise
