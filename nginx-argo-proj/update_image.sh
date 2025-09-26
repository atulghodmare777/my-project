#!/bin/bash

# Set variables
REPO_NAME="n7-playground-nginx"
DEPLOYMENT_FILE="apps/nginx/k8s/deployment.yaml"
NEW_IMAGE="gcr.io/nviz-playground/nginx-app:$1"

# Check if the repository already exists
if [ ! -d "$REPO_NAME" ]; then
    # Clone the repository if it doesn't exist
    git clone https://maheshrangisetty:ATBBmJpggxa8S5dsz9WyLuzpAbxp52F7DB9B@bitbucket.org/NvizionSolutions/n7-playground-nginx.git
fi

# Change to the repository directory
cd $REPO_NAME

# Fetch the latest changes from the remote repository
git fetch origin

# Reset to the latest commit on the master branch (or your target branch)
git reset --hard origin/main  # Replace 'master' with your branch if necessary

# Update the image in deployment.yaml
sed -i "s|image: gcr.io/nviz-playground/nginx-app:.*|image: $NEW_IMAGE|" $DEPLOYMENT_FILE

# Commit the changes if there are any
git config --global user.email "mahesh.rangisetty@nviz.com"  # Replace with your email
git config --global user.name "mahesh"  # Replace with your name
git add $DEPLOYMENT_FILE
git commit -m "Update image to $1" || echo "No changes to commit"

# Push changes back to Bitbucket
git push origin main  # Replace 'master' with your branch if necessary
