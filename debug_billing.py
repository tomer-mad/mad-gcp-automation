import os
from googleapiclient import discovery
from googleapiclient.errors import HttpError

# Configuration
PROJECT_ID = "mad-mmm-poc"
PROJECT_NAME = f"projects/{PROJECT_ID}"


def test_billing_permissions():
    """
    Attempts to read and write billing info to verify permissions.
    """
    print(f"🕵️ Debugging as: {os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')}")

    # 1. Build the Billing Service
    try:
        service = discovery.build('cloudbilling', 'v1')
    except Exception as e:
        print(f"❌ Failed to build service client: {e}")
        return

    # 2. Try to GET Billing Info (Tests Viewer Permissions)
    print(f"\nrunning: billing.projects().getBillingInfo(name='{PROJECT_NAME}')")
    try:
        billing_info = service.projects().getBillingInfo(name=PROJECT_NAME).execute()
        print(f"✅ GET Success! Linked Billing Account: {billing_info.get('billingAccountName', 'None')}")
        print(f"   Billing Enabled: {billing_info.get('billingEnabled')}")
    except HttpError as e:
        print(f"❌ GET Failed: {e}")
        # If we can't read, we definitely can't write, so we stop here.
        return

    # 3. Try to DISABLE Billing (Tests Manager Permissions)
    # WARNING: This will actually disable billing if it works.
    # Since this is a POC, that is likely what you want to test.
    print(f"\nrunning: billing.projects().updateBillingInfo(name='{PROJECT_NAME}', body=...)")
    try:
        # To disable billing, we send an empty billingAccountName
        body = {"billingAccountName": ""}
        response = service.projects().updateBillingInfo(name=PROJECT_NAME, body=body).execute()
        print(f"✅ UPDATE Success! Billing has been disabled for {PROJECT_ID}.")
    except HttpError as e:
        print(f"❌ UPDATE Failed: {e}")
        print("\n🔍 DIAGNOSIS:")
        if e.resp.status == 403:
            print("   You are missing 'roles/billing.projectManager' on the PROJECT.")
            print("   OR you are missing 'roles/billing.user' on the BILLING ACCOUNT.")


if __name__ == "__main__":
    test_billing_permissions()