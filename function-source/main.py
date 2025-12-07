import base64
import json
import os
from googleapiclient import discovery

def stop_billing(event, context):
    """
    Stops billing for a project by disabling the billing account associated with it.
    This function is triggered by a Pub/Sub message from a budget alert.
    """
    print(f"Function triggered by event: {context.event_id}")
    print(f"Full Pub/Sub message data: {event}")

    try:
        # Decode the Pub/Sub message
        pubsub_data = base64.b64decode(event['data']).decode('utf-8')
        print(f"Decoded Pub/Sub payload: {pubsub_data}")
        pubsub_json = json.loads(pubsub_data)

        # Get the project ID from environment variables
        project_id = os.environ.get('TARGET_PROJECT_ID')
        if not project_id:
            raise ValueError("TARGET_PROJECT_ID environment variable not set.")

        print(f"Processing budget alert for project: {project_id}")

        # The billing API requires the project name in the format 'projects/PROJECT_ID'
        project_name = f'projects/{project_id}'

        # Build the billing API client
        billing = discovery.build(
            'cloudbilling',
            'v1',
            cache_discovery=False,
        )

        # Get the project's current billing info
        billing_info = billing.projects().getBillingInfo(name=project_name).execute()

        if not billing_info.get('billingEnabled'):
            print(f"Billing is already disabled for project: {project_id}")
            return

        print(f"Attempting to disable billing for project: {project_id}")

        # Disable billing by associating the project with a null billing account
        body = {'billingAccountName': ''}  # Empty string disables billing
        billing.projects().updateBillingInfo(name=project_name, body=body).execute()

        print(f"Successfully disabled billing for project: {project_id}")

    except Exception as e:
        print(f"Error: {e}")
        # Re-raise the exception to ensure the function execution is marked as failed
        raise
