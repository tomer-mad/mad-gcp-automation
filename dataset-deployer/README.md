# GCP Dataset Provisioner

This automation script provisions Google Cloud BigQuery datasets based on a powerful and flexible configuration file. It is designed to be run securely via a deployment script that triggers Google Cloud Build.

## How It Works

The script reads a `config.yaml` file that defines dataset requirements. It automatically generates the full list of datasets to create by combining **base names** and **environment suffixes** (e.g., `sales` + `dev` -> `SALES_DEV`).

The process is idempotent: it will only create datasets that do not already exist, ensuring that running it multiple times is safe.

## How to Use

### Prerequisites

1.  **Google Cloud SDK:** Authenticate with `gcloud auth login` and `gcloud auth application-default login`.
2.  **Permissions (One-Time Setup per Project):**
    *   **Your User:** You need the **"Cloud Build Editor"** (`roles/cloudbuild.builds.editor`) role in the target project to submit builds.
    *   **Cloud Build Service Account:** The project's Cloud Build service account (e.g., `[PROJECT_NUMBER]@cloudbuild.gserviceaccount.com`) must have the **"BigQuery Data Editor"** (`roles/bigquery.dataEditor`) role to create the datasets.

### Configuration

Edit the `config.yaml` file to define your desired datasets.

**Example `config.yaml`:**
```yaml
# config.yaml

# Default location for all datasets.
location: "US"

# A list of environment suffixes to append to each base name.
environments:
  - "dev"
  - "prod"

# A list of base names for the datasets to be created.
base_names:
  - "mad_l1"
  - "marketing"
```
This configuration will create `MAD_L1_DEV`, `MAD_L1_PROD`, `MARKETING_DEV`, and `MARKETING_PROD`.

### Deployment (Recommended Method)

The `dataset-deployer.sh` script is the safest way to run this automation. It forces you to specify the target project ID and asks for confirmation before running.

**Step 1: Make the script executable (run once):**
```bash
chmod +x dataset-deployer.sh
```

**Step 2: Run the deployment:**
```bash
./dataset-deployer.sh <your-gcp-project-id>
```
The script will show you the project you are targeting and ask for a final 'y' before submitting the job to Cloud Build.

### Manual Testing (for Development)

You can also run the Python script locally for quick tests.

1.  **Install dependencies:** `pip install -r requirements.txt`
2.  **Set your project:** `gcloud config set project <your-gcp-project-id>`
3.  **Dry Run:** `python3 provision_datasets.py` (shows the target project and exits)
4.  **Execute:** `python3 provision_datasets.py --confirm`
