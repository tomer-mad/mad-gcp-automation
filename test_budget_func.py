import unittest
import base64
import json
from unittest.mock import patch


# ==========================================
# PART 1: YOUR CLOUD FUNCTION CODE (main.py)
# ==========================================
def process_budget_alert(event, context):
    """
    This is your actual Cloud Function logic.
    It expects 'data' to be base64 encoded.
    """
    if 'data' not in event:
        raise ValueError("No data field provided in the event!")

    # 1. Decode the Base64 data
    decoded_bytes = base64.b64decode(event['data'])
    decoded_str = decoded_bytes.decode('utf-8')
    budget_json = json.loads(decoded_str)

    # 2. Extract specific fields
    cost_amount = budget_json.get('costAmount')
    budget_limit = budget_json.get('budgetAmount')

    # 3. Logic: Check if we are over budget (Simulated logic)
    message = f"ALERT: Spent ${cost_amount} of ${budget_limit} budget!"
    print(message)
    return message


# ==========================================
# PART 2: THE UNIT TEST
# ==========================================
class TestBudgetAlert(unittest.TestCase):

    def setUp(self):
        # This is the plain JSON we *want* to send
        self.plain_payload = {
            "budgetDisplayName": "test-budget",
            "alertThresholdExceeded": 0.8,
            "costAmount": 850.50,
            "budgetAmount": 1000.00,
            "currencyCode": "USD"
        }

    def test_pubsub_decoding_flow(self):
        """
        Tests if the function correctly decodes a base64 Pub/Sub message.
        """
        # 1. PREPARE: Manually encode the payload to Base64 (Simulate Pub/Sub)
        json_str = json.dumps(self.plain_payload)
        b64_encoded = base64.b64encode(json_str.encode('utf-8')).decode('utf-8')

        # 2. CONSTRUCT: The event dictionary Pub/Sub sends
        mock_event = {
            'data': b64_encoded,
            'attributes': {'key': 'value'}
        }
        mock_context = {}  # Context is usually not needed for basic logic

        # 3. ACT: Call the function
        result = process_budget_alert(mock_event, mock_context)

        # 4. ASSERT: Verify the logic worked
        expected_msg = "ALERT: Spent $850.5 of $1000.0 budget!"
        self.assertEqual(result, expected_msg)
        print("\n✅ Test Passed: Function decoded Base64 and extracted cost correctly.")


# ==========================================
# PART 3: RUN THE TEST
# ==========================================
if __name__ == '__main__':
    unittest.main()