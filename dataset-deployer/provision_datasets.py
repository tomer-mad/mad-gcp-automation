import os
import sys
import argparse
import yaml
from google.cloud import bigquery
from google.cloud.exceptions import NotFound

def provision_datasets(client, project_id, config_path="config.yaml"):
    """
    Provisions BigQuery datasets based on a YAML configuration file.
    """
    print(f"Starting dataset provisioning for project: '{project_id}'")

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    default_location = config.get("location", "US")
    mismatch_policy = config.get("on_location_mismatch", "warn").lower()
    environments = config.get("environments", [])
    base_names = config.get("base_names", [])

    datasets_to_create = []

    # Generate datasets from base names and environments
    for base_name in base_names:
        for env in environments:
            dataset_name = f"{base_name.upper()}_{env.upper()}"
            datasets_to_create.append({"name": dataset_name, "location": default_location})

    # Process any specifically defined datasets
    for specific_dataset in config.get("specific_datasets", []):
        name = specific_dataset.get("name")
        loc = specific_dataset.get("location", default_location)
        envs = specific_dataset.get("environments")

        if not name:
            continue

        if envs:
             for env in envs:
                 dataset_name = f"{name.upper()}_{env.upper()}"
                 datasets_to_create.append({"name": dataset_name, "location": loc})
        else:
            datasets_to_create.append({"name": name.upper(), "location": loc})

    # --- Main Provisioning Loop ---
    for dataset_config in datasets_to_create:
        dataset_name = dataset_config.get("name")
        desired_location = dataset_config.get("location")
        dataset_id = f"{project_id}.{dataset_name}"

        try:
            existing_dataset = client.get_dataset(dataset_id)
            print(f"Dataset '{dataset_id}' already exists.")

            # --- Location Mismatch Check ---
            if existing_dataset.location != desired_location:
                message = (
                    f"  - WARNING: Location mismatch for '{dataset_id}'.\n"
                    f"    - Configured location: '{desired_location}'\n"
                    f"    - Actual location:     '{existing_dataset.location}'"
                )
                if mismatch_policy == 'fail':
                    print(message, file=sys.stderr)
                    print("  - Halting deployment due to 'fail' policy.", file=sys.stderr)
                    sys.exit(1)
                else: # 'warn' policy
                    print(message)
                    print("  - Skipping dataset due to location mismatch.")
            else:
                print(f"  - Location matches ('{existing_dataset.location}'). No action needed.")

        except NotFound:
            print(f"Dataset '{dataset_id}' not found. Creating in '{desired_location}'...")
            dataset = bigquery.Dataset(dataset_id)
            dataset.location = desired_location
            client.create_dataset(dataset, timeout=30)
            print(f"  - Dataset '{dataset_id}' created successfully.")

def main():
    """
    Main function to handle argument parsing and confirmation.
    """
    parser = argparse.ArgumentParser(description="Provision BigQuery Datasets.")
    parser.add_argument(
        "--confirm",
        action="store_true",
        help="Flag to confirm execution. If not present, the script will only display the target project and exit."
    )
    args = parser.parse_args()

    # Determine the project ID from the environment
    project_id = os.environ.get("GCP_PROJECT") or os.environ.get("DEVSHELL_PROJECT_ID")
    if not project_id:
        try:
            client = bigquery.Client()
            project_id = client.project
        except Exception as e:
            print(f"Error: Could not determine GCP project. Please configure gcloud or set GCP_PROJECT. Details: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        client = bigquery.Client(project=project_id)

    if not args.confirm:
        print("---------------------------------------------------------------")
        print(f"--- DRY RUN MODE ---")
        print(f"--- Target project is: '{project_id}'")
        print(f"--- To execute, re-run with the --confirm flag.")
        print("---------------------------------------------------------------")
        sys.exit(0)

    provision_datasets(client, project_id)

if __name__ == "__main__":
    main()
