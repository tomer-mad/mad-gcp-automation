import base64
import json


def budget_alert_handler(event, context):
    """
    Background Cloud Function to be triggered by Pub/Sub.
    """
    try:
        if 'data' in event:
            # 1. Decode the Base64 data
            name_data = base64.b64decode(event['data']).decode('utf-8')
            budget_json = json.loads(name_data)

            # 2. Extract specific logic (Example logic)
            budget_name = budget_json.get('budgetDisplayName')
            cost = budget_json.get('costAmount')

            print(f"Processing alert for: {budget_name}")
            return f"Success: Processed alert for {budget_name} with cost {cost}"
        else:
            raise ValueError("No 'data' field in Pub/Sub message")

    except Exception as e:
        # In a real function, you might log this to Cloud Logging
        print(f"Error: {e}")
        return f"Error: {e}"