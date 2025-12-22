import json
import argparse
from datetime import datetime, timezone, timedelta
from google.cloud import pubsub_v1
from google.api_core.exceptions import PermissionDenied

def send_budget_alert(project_id, topic_id, current_spend, budget_cap):
    """
    Simulates a Google Cloud Billing alert by publishing a formatted JSON message to Pub/Sub.
    """
    # 1. Construct the dynamic payload
    # This matches the schema Google Billing sends
    one_minute_ago = datetime.now(timezone.utc) - timedelta(minutes=1)
    timestamp_str = one_minute_ago.strftime('%Y-%m-%dT%H:%M:%SZ')

    alert_payload = {
        "budgetDisplayName": f"{project_id}-HARD-STOP-{int(budget_cap)}",
        "alertThresholdExceeded": round(current_spend / budget_cap, 2),
        "costAmount": float(current_spend),
        "costIntervalStart": timestamp_str,
        "budgetAmount": float(budget_cap),
        "budgetAmountType": "SPECIFIED_AMOUNT",
        "currencyCode": "ILS"  # Using a standard currency, can be changed if needed
    }

    # 2. Prepare the Publisher
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_id)

    # 3. Serialize and Encode
    data_str = json.dumps(alert_payload)
    data_bytes = data_str.encode("utf-8")

    # Add attributes for filtering on the subscriber side
    attributes = {
        "source": "budget-simulation",
        "project_id": project_id,
    }

    print(f"📡 Attempting to publish to: {topic_path}...")
    print(f"   Payload: {data_str}")
    print(f"   Attributes: {attributes}")

    # 4. Publish
    try:
        publish_future = publisher.publish(topic_path, data=data_bytes, **attributes)
        message_id = publish_future.result()
        print(f"✅ Sent Alert: Spent ${current_spend} / ${budget_cap} (Msg ID: {message_id})")
        print(f"   Published to topic: {topic_path}")

    except PermissionDenied:
        print("\n❌ ERROR: Permission Denied.")
        print("💡 FIX: You need to authenticate your local machine first.")
        print("   Run this command in your terminal:")
        print("   gcloud auth application-default login")
    except Exception as e:
        print(f"❌ Failed to send: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Simulate a Google Cloud Billing budget alert.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--project",
        required=False,
        default="mad-bi",
        help="The Google Cloud project ID where the Pub/Sub topic exists."
    )
    parser.add_argument(
        "--spend",
        required=False,
        type=float,
        default= 300.0 ,
        help="The current cost amount to simulate."
    )
    parser.add_argument(
        "--budget",
        required=False,
        type=float,
        default=200.0,
        help="The total budget amount."
    )
    parser.add_argument(
        "--topic",
        default="budget-alert-topic" ,
        help="The ID of the Pub/Sub topic to publish to (default: budget-alert-topic)."
    )

    args = parser.parse_args()

    print(f"--- 💰 Starting Budget Simulation for project '{args.project}' ---")
    send_budget_alert(
        project_id=args.project,
        topic_id=args.topic,
        current_spend=args.spend,
        budget_cap=args.budget
    )
    print("--- Simulation Complete ---")
