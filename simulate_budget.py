import json
import time
from google.cloud import pubsub_v1
from google.api_core.exceptions import PermissionDenied  # Added for specific auth error handling

# =================CONFIGURATION=================
PROJECT_ID = "mad-mmm-poc"
TOPIC_ID = "budget-alert-topic"


# ===============================================

def send_budget_alert(current_spend, budget_cap):
    """
    Imitates a Google Cloud Billing alert by publishing
    a formatted JSON message to Pub/Sub.
    """

    # Calculate threshold (just for the mock data)
    ratio = current_spend / budget_cap

    # 1. Construct the Payload
    # This matches the exact schema Google Billing sends
    alert_payload = {
        "budgetDisplayName": "simulation-budget",
        "alertThresholdExceeded": round(ratio, 2),
        "costAmount": float(current_spend),
        "costIntervalStart": "2023-10-01T00:00:00Z",
        "budgetAmount": float(budget_cap),
        "budgetAmountType": "SPECIFIED_AMOUNT",
        "currencyCode": "ILS"  # Israel Shekels
    }

    # 2. Prepare the Publisher
    # This automatically picks up credentials from 'gcloud auth application-default login'
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)

    # 3. Serialize and Encode
    # We send bytes; Pub/Sub handles the Base64 wrapper automatically
    data_str = json.dumps(alert_payload)
    data_bytes = data_str.encode("utf-8")

    print(f"📡 Attempting to publish to: {topic_path}...")

    # 4. Publish
    try:
        publish_future = publisher.publish(topic_path, data=data_bytes)

        # Block until the message is actually published
        message_id = publish_future.result()
        print(f"✅ Sent Alert: Spent ₪{current_spend} / ₪{budget_cap} (Msg ID: {message_id})")

    except PermissionDenied:
        print("\n❌ ERROR: Permission Denied.")
        print("💡 FIX: You need to authenticate your local machine first.")
        print("   Run this command in your terminal:")
        print("   gcloud auth application-default login")

    except Exception as e:
        print(f"❌ Failed to send: {e}")


if __name__ == "__main__":
    print("--- 💰 Starting Budget Simulation (ILS) ---")

    # # SCENARIO 1: Everything is fine (50% spent)
    # send_budget_alert(current_spend=500.00, budget_cap=1000.00)
    # time.sleep(1)
    #
    # # SCENARIO 2: Warning Threshold (85% spent)
    # send_budget_alert(current_spend=850.00, budget_cap=1000.00)
    # time.sleep(1)

    # SCENARIO 3: Over Budget (120% spent)
    send_budget_alert(current_spend=1200.00, budget_cap=1000.00)

    print("--- Simulation Complete ---")