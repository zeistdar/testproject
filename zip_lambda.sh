#!/bin/bash

# Create a directory for the Lambda package
mkdir lambda_package
cd lambda_package
ls ./
cp ../event_driven_lambda/index.py .

# Use Docker to simulate the Lambda environment and install dependencies
docker run --rm -v $(pwd):/var/task lambci/lambda:build-python3.8 pip install boto3 requests -t .

# Zip up the package
zip -r9 /tmp/lambda.zip .