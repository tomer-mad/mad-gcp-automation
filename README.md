# GCP Project Budget Enforcement Automation

This repository provides a robust and automated solution to enforce a hard budget limit on Google Cloud Platform (GCP) projects. It prevents unexpected costs by automatically disabling billing for a project when its spending exceeds a predefined budget.

## How It Works

The solution is built around a serverless architecture using GCP's native services:

1.  **GCP Budget:** A standard GCP budget is created for the target project. This budget is configured to send notifications to a Pub/Sub topic when spending reaches certain percentages (90%, 95%, and 99%) of the total budget amount.

2.  **Pub/Sub Topic:** A Pub/Sub topic (`budget-alert-topic`) acts as the central messaging hub, receiving all budget notifications.

3.  **Cloud Function:** A Gen2 Cloud Function (`billing-disable-function`) written in Python is subscribed to the Pub/Sub topic. This function is the core of the enforcement logic.

4.  **Enforcement Logic:** When a budget notification is published to the topic, the Cloud Function is triggered. It inspects the message payload to determine the current cost versus the budgeted amount. **If the cost has reached 99% or more of the budget, the function will automatically disable billing for the project.**

5.  **Service Account:** A dedicated Identity and Access Management (IAM) service account (`billing-disabler-sa`) is created with the minimum necessary permissions (`roles/billing.projectManager`) to disable billing. The Cloud Function executes under this service account to ensure a secure and auditable process.

This entire infrastructure is deployed and managed by a single shell script, `deployer-budget.sh`, which handles resource creation, IAM permissions, and cleanup.

## Features

*   **Hard Budget Enforcement:** Automatically disables billing to prevent cost overruns.
*   **Serverless & Scalable:** Built on GCP's managed services (Cloud Functions, Pub/Sub) for high availability and low maintenance.
*   **Secure:** Uses a dedicated service account with least-privilege permissions.
*   **Easy Deployment:** A single script to deploy, undeploy, or redeploy the entire solution.
*   **Testable:** Includes a simulation script to test the enforcement logic without waiting for actual spending.
*   **Dynamic Project Targeting:** The Cloud Function intelligently extracts the project ID from the budget's display name, making the core logic reusable and project-agnostic.

## How to Use

### Prerequisites

1.  **Google Cloud SDK:** Ensure you have `gcloud` installed and authenticated on your local machine.
2.  **Permissions:** Your user account must have sufficient permissions in the target GCP project to enable APIs, create service accounts, IAM policies, Pub/Sub topics, Cloud Functions, and budgets. The `Owner` or `Editor` role is typically sufficient.

### Deployment

The `deployer-budget.sh` script is the primary tool for managing the solution.

**To deploy the budget enforcement system:**

```bash
./deployer-budget.sh deploy --project <YOUR_PROJECT_ID> --amount <BUDGET_AMOUNT>
```

*   `<YOUR_PROJECT_ID>`: The ID of the GCP project you want to protect.
*   `<BUDGET_AMOUNT>`: The total budget amount in your currency (e.g., `500`).

This command will:
1.  Enable all required APIs.
2.  Create the dedicated service account and grant it the `billing.projectManager` role.
3.  Grant necessary permissions to the Cloud Build and Pub/Sub service accounts.
4.  Create the `budget-alert-topic` Pub/Sub topic.
5.  Deploy the `billing-disable-function` Cloud Function.
6.  Create the GCP budget with rules to notify the Pub/Sub topic at 90%, 95%, and 99% thresholds.

### Undeployment

**To remove the budget enforcement system:**

```bash
./deployer-budget.sh undeploy --project <YOUR_PROJECT_ID> --amount <BUDGET_AMOUNT>
```

This command will safely delete all the resources created during deployment, including the Cloud Function, Pub/Sub topic, budget, and service account.

**Important:** The script will prompt you to manually re-enable billing in the GCP Console before it proceeds with the undeployment. This is a safety measure to prevent resources from being left in a non-deletable state.

### Redeployment

**To update or redeploy the system:**

```bash
./deployer-budget.sh redeploy --project <YOUR_PROJECT_ID> --amount <BUDGET_AMOUNT>
```

This command is a convenient shortcut that first runs the `undeploy` process and then immediately runs the `deploy` process.

## Simulating a Budget Alert

You don't have to wait for your project to spend money to test if the system works. The `simulate_budget.py` script allows you to manually trigger the Cloud Function.

**To simulate an alert that will disable billing (spend >= 99% of budget):**

```bash
python3 simulate_budget.py --project <YOUR_PROJECT_ID> --spend 99 --budget 100
```

**To simulate an alert that will *not* disable billing (spend < 99% of budget):**

```bash
python3 simulate_budget.py --project <YOUR_PROJECT_ID> --spend 50 --budget 100
```

This script publishes a message to the `budget-alert-topic` with a payload that mimics a real GCP budget notification, allowing you to verify the end-to-end functionality in a controlled way.

## What Can Be Achieved with This Repo

*   **Financial Governance:** Implement strict cost control for development, sandbox, or any project where budget adherence is critical.
*   **Educational Safety:** Provide students or trainees with GCP access without the risk of incurring large, unexpected bills.
*   **Prevent Runaway Costs:** Protect against accidental resource provisioning or misconfigurations that could lead to rapid spending.
*   **Automated Peace of Mind:** Set a budget and trust that the automated system will act as a final safety net, even when no one is actively monitoring the costs.
