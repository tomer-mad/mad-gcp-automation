# GCP Dataset Provisioner

This automation script provisions and manages Google Cloud BigQuery datasets, including advanced cross-region replication. It is designed to be run securely via a deployment script that triggers Google Cloud Build.

## How It Works

The script reads a `config.yaml` file to determine the desired state of datasets.

1.  **Creates if Not Found:** If a dataset does not exist, it is created as a new primary (writable) dataset in the location specified in the config.

2.  **Checks if Found:** If a dataset already exists, its location is checked.
    *   **If Locations Match:** No action is taken.
    *   **If Locations Mismatch:** The script's behavior depends on the `replication` policy.

3.  **Handles Replication:**
    *   If `replication.enabled` is `false`, the script follows the `on_location_mismatch` policy (`warn` or `fail`).
    *   If `replication.enabled` is `true`, the script will create a read-only replica of the existing dataset in the new target location.
    *   If `replication.promote_replica_to_primary` is `true`, the script will then promote the new replica to be the new writable primary, demoting the old one.

## How to Use

### Prerequisites

1.  **Google Cloud SDK:** The `gcloud` and `bq` command-line tools must be installed and authenticated. This is pre-installed in Cloud Build and Cloud Shell.
2.  **Permissions (One-Time Setup per Project):**
    *   **Your User:** You need the **"Cloud Build Editor"** (`roles/cloudbuild.builds.editor`) role to submit builds.
    *   **Cloud Build Service Account:** The project's Cloud Build service account must have the **"BigQuery Admin"** (`roles/bigquery.admin`) role. *(Note: This is a higher permission level required for replication and promotion.)*

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
  enabled: true

  # If true, the script will promote the new replica to be the new primary.
  promote_replica_to_primary: false

# A list of standard base names for the datasets to be created.
base_names:
  - "MAD_L0"
  - "MAD_L2"
  - "MAD_ETL"
```
**Scenario:** Imagine `MAD_L0_PROD` already exists in `EU`. With the config above, running the script against the `US` location will:
1.  Detect the location mismatch for `MAD_L0_PROD`.
2.  Create a read-only replica of `MAD_L0_PROD` in the `US`.
3.  If `promote_replica_to_primary` were `true`, it would then make the `US` dataset the new writable primary.

### Deployment

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
