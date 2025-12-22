#!/bin/bash

# This script provides a safe wrapper for submitting the dataset provisioning job to Google Cloud Build.
# It requires the user to explicitly specify a target project ID and confirm before proceeding.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- 1. Check for Project ID ---
if [ -z "$1" ]; then
  echo "Error: No project ID provided."
  echo "Usage: ./dataset-deployer.sh <your-gcp-project-id>"
  exit 1
fi

PROJECT_ID=$1

# --- 2. Safety Confirmation ---
echo "================================================================"
echo "  WARNING: You are about to deploy resources to the GCP project:"
echo
echo "    Project ID: $PROJECT_ID"
echo
echo "  This will trigger a Cloud Build job to provision BigQuery"
echo "  datasets as defined in 'config.yaml'."
echo "================================================================"
read -p "Are you sure you want to proceed? (y/n) " -n 1 -r
echo # Move to a new line

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled by user."
  exit 1
fi

# --- 3. Submit to Cloud Build ---
echo
echo "Proceeding with deployment to project '$PROJECT_ID'..."

# The '--project' flag tells gcloud which project to run the build in.
gcloud builds submit --config cloudbuild.yaml --project "$PROJECT_ID" .

echo
echo "Cloud Build job submitted successfully for project '$PROJECT_ID'."
