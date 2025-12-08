import base64
import json
import os
from googleapiclient import discovery
from googleapiclient.errors import HttpError

def stop_billing(event, context):
    """
    Stops billing for a project by disabling the billing account associated with it.
    This function is triggered by a Pub/Sub message from a budget alert and only
    disables billing if the budget has reached 99% of its limit.
    """
    print(f"Function triggered by event: {context.event_id}")

    try:
        # Decode the Pub/Sub message
        pubsub_data = base64.b64decode(event['data']).decode('utf-8')
        pubsub_json = json.loads(pubsub_data)
        print(f"Decoded Pub/Sub payload: {pubsub_json}")

        # Extract the threshold percentage from the message
        threshold_percent = pubsub_json.get('threshold_percent', 0.0)
        print(f"Budget threshold crossed: {threshold_percent * 100}%")

        # --- Main Logic: Only act on the 99% threshold ---
        if threshold_percent < 0.99:
            print(f"Budget is at {threshold_percent * 100}%. Taking no action. Billing will be disabled at 99%.")
            return "No action taken."

        # Get the project ID from environment variables
        project_id = os.environ.get('TARGET_PROJECT_ID')
        if not project_id:
            raise ValueError("TARGET_PROJECT_ID environment variable not set.")

        print(f"CRITICAL: Budget threshold is >= 99%. Proceeding to disable billing for project: {project_id}")

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
