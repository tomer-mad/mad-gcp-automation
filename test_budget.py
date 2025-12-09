import json
import base64

# 1. Define the plain JSON (The actual data you want to test)
plain_payload = {
    "budgetDisplayName": "production-budget-2025",
    "alertThresholdExceeded": 1.01,
    "costAmount": 1250.00,
    "budgetAmount": 1000.00,
    "budgetAmountType": "SPECIFIED_AMOUNT",
    "currencyCode": "USD"
}

# 2. Convert to JSON string, then encode to Base64
json_str = json.dumps(plain_payload)
encoded_data = base64.b64encode(json_str.encode("utf-8")).decode("utf-8")

# 3. Wrap it in the Pub/Sub envelope structure
test_event = {
    "data": encoded_data
}
print(test_event)
# 4. Print the result
print("--- COPY THE JSON BELOW INTO THE GCP TESTING TAB ---")
print(json.dumps(test_event, indent=2))