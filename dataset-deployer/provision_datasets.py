import os
import sys
import time
import argparse
import yaml
from google.cloud import bigquery
from google.cloud.exceptions import NotFound

def provision_datasets(client, project_id, config_path="config.yaml"):
    """
    Provisions and replicates BigQuery datasets based on a YAML configuration file.
    """
    print(f"Starting dataset provisioning for project: '{project_id}'")

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    # Load configuration with defaults
    default_location = config.get("location", "US")
    replication_config = config.get("replication", {})
    replication_enabled = replication_config.get("enabled", False)
    promote_replica = replication_config.get("promote_replica_to_primary", False)
    mismatch_policy = config.get("on_location_mismatch", "warn").lower()
    
    environments = config.get("environments", [])
    base_names = config.get("base_names", [])

    datasets_to_process = []
    for base_name in base_names:
        for env in environments:
            dataset_name = f"{base_name.upper()}_{env.upper()}"
            datasets_to_process.append({"name": dataset_name, "location": default_location})

    for specific_dataset in config.get("specific_datasets", []):
        # This part remains for one-off creations, but replication logic focuses on the main list
        pass

    # --- Main Provisioning Loop ---
    for dataset_config in datasets_to_process:
        dataset_name = dataset_config.get("name")
        desired_location = dataset_config.get("location")
        dataset_id = f"{project_id}.{dataset_name}"

        try:
            existing_dataset = client.get_dataset(dataset_id)
            print(f"Dataset '{dataset_id}' already exists.")

            if existing_dataset.location == desired_location:
                print(f"  - Location matches ('{existing_dataset.location}'). No action needed.")
                continue

            # --- LOCATION MISMATCH ---
            print(f"  - Location mismatch detected. Config: '{desired_location}', Actual: '{existing_dataset.location}'.")

            if not replication_enabled:
                message = "  - Replication is disabled. Following 'on_location_mismatch' policy."
                if mismatch_policy == 'fail':
                    print(message, file=sys.stderr)
                    sys.exit(1)
                else:
                    print(message + " (warn). Skipping.")
                continue

            # --- REPLICATION LOGIC ---
            print("  - Replication is ENABLED. Proceeding with replication logic.")
            
            # Check if the desired location is already a replica
            if existing_dataset.replicas:
                for replica in existing_dataset.replicas:
                    if client.get_dataset(replica).location == desired_location:
                        print(f"  - A replica in '{desired_location}' already exists. No action needed.")
                        # Optional: Add promotion logic here if needed in the future
                        continue

            print(f"  - Creating replica in '{desired_location}'...")
            existing_dataset.replicas = [bigquery.DatasetReference.from_string(f"{project_id}.{dataset_name}", default_project=project_id)]
            
            # The API needs a special format for the replica
            replica_update = {"replica": {"location": desired_location}}
            
            # This is an API quirk; we patch the dataset to add the replica
            client.patch_dataset(existing_dataset.dataset_id, replica_update)
            print("  - Replica creation initiated. This can take some time.")

            if promote_replica:
                print("  - Promotion requested. Waiting before promoting...")
                # It's crucial to wait for replication to be established before promoting
                time.sleep(60) # Wait 60 seconds as a precaution
                
                print(f"  - Promoting '{desired_location}' to primary...")
                client.update_dataset(existing_dataset, ["primary_dataset_id"])
                print("  - Promotion complete.")

        except NotFound:
            print(f"Dataset '{dataset_id}' not found. Creating primary in '{desired_location}'...")
            dataset = bigquery.Dataset(dataset_id)
            dataset.location = desired_location
            client.create_dataset(dataset, timeout=30)
            print(f"  - Dataset '{dataset_id}' created successfully.")

def main():
    parser = argparse.ArgumentParser(description="Provision BigQuery Datasets with Replication.")
    parser.add_argument("--confirm", action="store_true", help="Flag to confirm execution.")
    args = parser.parse_args()

    project_id = os.environ.get("GCP_PROJECT") or os.environ.get("DEVSHELL_PROJECT_ID")
    if not project_id:
        try:
            client = bigquery.Client()
            project_id = client.project
        except Exception as e:
            print(f"Error: Could not determine GCP project. Details: {e}", file=sys.stderr)
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
