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
    print("================================================================")
    print(f"  Starting Dataset Provisioner for project: '{project_id}'")
    print("================================================================")

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    # --- Load configuration ---
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

    print(f"\nFound {len(datasets_to_process)} datasets to process from config:")
    for d in datasets_to_process:
        print(f"- {d['name']} (Desired Location: {d['location']})")

    # --- Main Provisioning Loop ---
    for i, dataset_config in enumerate(datasets_to_process):
        dataset_name = dataset_config.get("name")
        desired_location = dataset_config.get("location")
        dataset_id = f"{project_id}.{dataset_name}"

        print("\n----------------------------------------------------------------")
        print(f"Processing Dataset {i+1}/{len(datasets_to_process)}: {dataset_name}")
        print("----------------------------------------------------------------")

        try:
            existing_dataset = client.get_dataset(dataset_id)
            print(f"[STATUS]  Dataset '{dataset_id}' already exists in location '{existing_dataset.location}'.")

            if existing_dataset.location == desired_location:
                print("[RESULT]  Location matches. No action needed.")
                continue

            # --- LOCATION MISMATCH ---
            print(f"[INFO]    Location mismatch detected. Desired: '{desired_location}'.")

            if not replication_enabled:
                message = f"[ACTION]  Replication is disabled. Following '{mismatch_policy}' policy."
                if mismatch_policy == 'fail':
                    print(message, file=sys.stderr)
                    print("[RESULT]  Halting deployment.", file=sys.stderr)
                    sys.exit(1)
                else:
                    print(message)
                    print("[RESULT]  Skipping dataset.")
                continue

            # --- REPLICATION LOGIC ---
            print("[ACTION]  Replication is ENABLED. Checking for existing replicas.")
            
            if existing_dataset.replicas:
                for replica in existing_dataset.replicas:
                    if client.get_dataset(replica).location == desired_location:
                        print(f"[INFO]    A replica in '{desired_location}' already exists.")
                        print("[RESULT]  No action needed.")
                        continue

            print(f"[ACTION]  Creating replica in '{desired_location}'...")
            existing_dataset.replicas = [bigquery.DatasetReference.from_string(dataset_id, default_project=project_id)]
            replica_update = {"replica": {"location": desired_location}}
            client.patch_dataset(existing_dataset.dataset_id, replica_update)
            print("[RESULT]  Replica creation initiated. This can take some time.")

            if promote_replica:
                print("[ACTION]  Promotion requested. Waiting 60s for replication to stabilize...")
                time.sleep(60)
                
                print(f"[ACTION]  Promoting '{desired_location}' to primary...")
                client.update_dataset(existing_dataset, ["primary_dataset_id"])
                print("[RESULT]  Promotion complete.")

        except NotFound:
            print(f"[STATUS]  Dataset '{dataset_id}' not found.")
            print(f"[ACTION]  Creating new primary dataset in '{desired_location}'...")
            dataset = bigquery.Dataset(dataset_id)
            dataset.location = desired_location
            client.create_dataset(dataset, timeout=30)
            print(f"[RESULT]  Dataset '{dataset_id}' created successfully.")

    print("\n================================================================")
    print("  All datasets processed. Provisioning complete.")
    print("================================================================")


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
