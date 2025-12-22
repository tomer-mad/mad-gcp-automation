# GCP Dataset Provisioner

This automation script provisions and manages Google Cloud BigQuery datasets, including advanced cross-region replication. It is designed to be run securely via a deployment script that triggers Google Cloud Build.

## How It Works

The script reads a `config.yaml` file to determine the desired state of datasets. It uses a combination of the Python client library for basic operations and the `gcloud` command-line tool for advanced replication tasks.

1.  **Creates if Not Found:** If a dataset does not exist, it is created as a new primary dataset.
2.  **Checks if Found:** If a dataset exists, its location is checked against the config.
3.  **Handles Replication:** If locations mismatch and `replication.enabled` is `true`, the script uses `gcloud alpha bq datasets update` to create a read-only replica in the new target location.

## How to Use

### Prerequisites

1.  **Google Cloud SDK:** The `gcloud` and `bq` command-line tools must be installed and authenticated.
2.  **Alpha Components:** The `gcloud alpha` components must be installed. Run this command once:
    ```bash
    gcloud components install alpha
    ```
3.  **Permissions (One-Time Setup per Project):**
    *   **Your User:** You need the **"Cloud Build Editor"** (`roles/cloudbuild.builds.editor`) role to submit builds.
    *   **Cloud Build Service Account:** The project's Cloud Build service account must have the **"BigQuery Admin"** (`roles/bigquery.admin`) role.

### Configuration

Edit the `config.yaml` file to define your desired datasets and policies.

### Deployment (Recommended Method)

The `dataset-deployer.sh` script is the safest way to run this automation.

**Step 1: Make the script executable (run once):**
```bash
chmod +x dataset-deployer.sh
```

**Step 2: Run the deployment:**
```bash
./dataset-deployer.sh <your-gcp-project-id>
```
The script will ask for confirmation before submitting the job to Cloud Build.
