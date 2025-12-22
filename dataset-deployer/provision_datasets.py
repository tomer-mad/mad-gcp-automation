import os
import sys
import time
import argparse
import yaml
import subprocess
from google.cloud import bigquery
from google.cloud.exceptions import NotFound

def run_gcloud_command(command):
    """Runs a gcloud command, raising an error if it fails."""
    print(f"[INFO]    Executing: {' '.join(command)}")
    process = subprocess.run(command, capture_output=True, text=True, check=True)
    return process.stdout

def provision_datasets(client, project_id, config_path="config.yaml"):
    """Provisions and replicates BigQuery datasets."""
    print("================================================================")
    print(f"  Starting Dataset Provisioner for project: '{project_id}'")
    print("================================================================")

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    default_location = config.get("location", "US")
    replication_config = config.get("replication", {})
    replication_enabled = replication_config.get("enabled", False)
    promote_replica = replication_config.get("promote_replica_to_primary", False)
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

            print(f"[ACTION]  Creating replica in '{desired_location}'...")
            
            # --- THE FIX ---
            # Directly modify the internal properties dictionary
            new_replica = {"location": desired_location}
            raw_resource.setdefault("replicas", []).append(new_replica)
            
            # Use a field mask to tell the API *only* to update the 'replicas' field
            client.update_dataset(existing_dataset, ["replicas"])
            
            print("[RESULT]  Replica creation initiated.")

            if promote_replica:
                print("[ACTION]  Promotion requested. Waiting 60s for replication to stabilize...")
                time.sleep(60)
                print(f"[ACTION]  Promoting '{desired_location}' to primary...")
                run_gcloud_command(["bq", "update", f"--promote_replica={desired_location}", dataset_id])
                print("[RESULT]  Promotion complete.")

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
    parser = argparse.ArgumentParser(description="Provision BigQuery Datasets with Replication.")
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
