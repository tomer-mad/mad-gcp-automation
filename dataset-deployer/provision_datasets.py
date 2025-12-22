import os
import sys
import time
import argparse
import yaml
from google.cloud import bigquery
from google.cloud.exceptions import NotFound

def provision_datasets(client, project_id, config_path="config.yaml"):
    """
    Provisions and replicates BigQuery datasets using the Python client library.
    """
    print("================================================================")
    print(f"  Starting Dataset Provisioner for project: '{project_id}'")
    print("================================================================")

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    default_location = config.get("location", "US")
    replication_config = config.get("replication", {})
    replication_enabled = replication_config.get("enabled", False)
    mismatch_policy = config.get("on_location_mismatch", "warn").lower()
    
    environments = config.get("environments", [])
    base_names = config.get("base_names", [])

    datasets_to_process = [{"name": f"{bn.upper()}_{env.upper()}", "location": default_location} for bn in base_names for env in environments]

    print(f"\nFound {len(datasets_to_process)} datasets to process from config:")
    for d in datasets_to_process:
        print(f"- {d['name']} (Desired Location: {d['location']})")

    for i, dataset_config in enumerate(datasets_to_process):
        dataset_name = dataset_config["name"]
        desired_location = dataset_config["location"]
        dataset_id = f"{project_id}.{dataset_name}"

        print("\n" + "-"*64)
        print(f"Processing Dataset {i+1}/{len(datasets_to_process)}: {dataset_name}")
        print("-"*64)

        try:
            existing_dataset = client.get_dataset(dataset_id)
            actual_location = existing_dataset.location
            print(f"[STATUS]  Dataset '{dataset_id}' already exists in location '{actual_location}'.")

            if actual_location == desired_location:
                print("[RESULT]  Location matches. No action needed.")
                continue

            print(f"[INFO]    Location mismatch detected. Desired: '{desired_location}'.")

            if not replication_enabled:
                message = f"[ACTION]  Replication is disabled. Following '{mismatch_policy}' policy."
                if mismatch_policy == 'fail':
                    print(message, file=sys.stderr); sys.exit(1)
                else:
                    print(message + " (warn). Skipping.")
                continue

            print("[ACTION]  Replication is ENABLED. Checking for existing replicas.")
            
            raw_resource = existing_dataset._properties
            replicas = raw_resource.get("replicas", [])
            
            if any(r["location"] == desired_location for r in replicas):
                print(f"[INFO]    A replica in '{desired_location}' already exists.")
                print("[RESULT]  No action needed.")
                continue

            print(f"[ACTION]  Attempting to create replica in '{desired_location}'...")
            
            # --- Reverted Logic ---
            # Modify the internal properties dictionary and use update_dataset with a field mask.
            # This sends the request and continues without waiting.
            dataset_properties = existing_dataset._properties
            dataset_properties.setdefault("replicas", []).append({"location": desired_location})
            
            client.update_dataset(existing_dataset, ["replicas"])
            
            print("[RESULT]  Replica creation request sent. The operation is asynchronous and may take several minutes to complete in the GCP console.")

        except NotFound:
            print(f"[STATUS]  Dataset '{dataset_id}' not found.")
            print(f"[ACTION]  Creating new primary dataset in '{desired_location}'...")
            new_dataset = bigquery.Dataset(dataset_id)
            new_dataset.location = desired_location
            client.create_dataset(new_dataset, timeout=30)
            print(f"[RESULT]  Dataset '{dataset_id}' created successfully.")
        except Exception as e:
            print(f"[ERROR]   An unexpected error occurred: {e}", file=sys.stderr)
            print("[RESULT]  Skipping dataset due to error.", file=sys.stderr)


    print("\n" + "="*64)
    print("  All datasets processed. Provisioning complete.")
    print("="*64)

def main():
    parser = argparse.ArgumentParser(description="Provision BigQuery Datasets.")
    parser.add_argument("--confirm", action="store_true", help="Flag to confirm execution.")
    args = parser.parse_args()

    project_id = os.environ.get("GCP_PROJECT") or os.environ.get("DEVSHELL_PROJECT_ID")
    if not project_id:
        try:
            client = bigquery.Client()
            project_id = client.project
        except Exception as e:
            print(f"Error: Could not determine GCP project. Details: {e}", file=sys.stderr); sys.exit(1)
    else:
        client = bigquery.Client(project=project_id)

    if not args.confirm:
        print("--- DRY RUN MODE ---")
        print(f"--- Target project is: '{project_id}'")
        print(f"--- To execute, re-run with the --confirm flag.")
        sys.exit(0)

    provision_datasets(client, project_id)

if __name__ == "__main__":
    main()
