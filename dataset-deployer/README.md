# GCP Dataset Provisioner

This automation script provisions and manages Google Cloud BigQuery datasets. It is designed to be run securely via a deployment script that triggers Google Cloud Build.

## How It Works

The script reads a `config.yaml` file to determine the desired state of datasets. It uses the pure Python client library for all operations.

1.  **Creates if Not Found:** If a dataset does not exist, it is created as a new primary (writable) dataset in the location specified in the config.

2.  **Checks if Found:** If a dataset already exists, its location is checked.
    *   **If Locations Match:** No action is taken.
    *   **If Locations Mismatch:** The script's behavior depends on the `replication` policy.

3.  **Handles Replication (Asynchronous):**
    *   If `replication.enabled` is `false`, the script follows the `on_location_mismatch` policy (`warn` or `fail`).
    *   If `replication.enabled` is `true`, the script sends an **asynchronous request** to the BigQuery API to create a read-only replica in the new target location. The script will then continue immediately without waiting for the replica to be created. This process may take several minutes to complete in the GCP console.

## How to Use

### Prerequisites

1.  **Google Cloud SDK:** Required for authenticating and submitting builds.
2.  **Permissions (One-Time Setup per Project):**
    *   **Your User:** You need the **"Cloud Build Editor"** (`roles/cloudbuild.builds.editor`) role to submit builds.
    *   **Cloud Build Service Account:** The project's Cloud Build service account must have the **"BigQuery Admin"** (`roles/bigquery.admin`) role to manage replication.

### Configuration

Edit the `config.yaml` file to define your desired datasets and policies.

**Example `config.yaml`:**
```yaml
# config.yaml

# The desired primary location for your datasets.
location: "US"

# --- Cross-Region Replication Policy ---
replication:
  # Set to true to enable the replication feature.
  enabled: false # Disabled by default for safety.

# A list of standard base names for the datasets to be created.
base_names:
  - "MAD_L0"
  - "MAD_L2"
  - "MAD_ETL"
```

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
