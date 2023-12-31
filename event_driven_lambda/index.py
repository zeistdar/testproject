import boto3
import csv
import os
import requests
import logging
import json


logging.basicConfig(level=logging.INFO)

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

FAST_API_ENDPOINT = f"http://{os.environ['ALB_DNS_NAME']}/index/" # Replace with your actual FastAPI endpoint


def get_secret():
    secret_name = "instance_credentials"
    region_name = "us-west-1"
    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager', region_name=region_name)

    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
        if 'SecretString' in get_secret_value_response:
            return get_secret_value_response['SecretString']
    except Exception as e:
        raise e



def handler(event, context):
    # Extract bucket and file name from the event
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    print(f"Processing {key} from {bucket}")
    logging.info(f"Processing {key} from {bucket}")
    secret_keys = json.loads(get_secret())

    # Read the CSV from S3
    response = s3.get_object(Bucket=bucket, Key=key)
    lines = response['Body'].read().decode('utf-8').splitlines()
    csv_reader = csv.DictReader(lines)
    # Read data and send to FastAPI for indexing
    for row in csv_reader:
        print(row)
        logging.info(row)
        payload = {
            "question": row["question"],
            "answer": row["answer"],
            "form_type": row["form_type"]
        }
        headers = {
            "secret-api-key": secret_keys["SECRET_API_KEY"],
            "Content-Type": "application/json"
        }

        print(FAST_API_ENDPOINT)
        logging.info(FAST_API_ENDPOINT)
        response = requests.post(FAST_API_ENDPOINT, json=payload, headers=headers)
        print(response)
        logging.info(response)
        if response.status_code != 200:
            print(f"Failed to index data: {payload}")
            logging.info(f"Failed to index data: {payload}")

    # Update the DynamoDB table
    table_name = os.environ['DYNAMODB_TABLE_NAME']
    table = dynamodb.Table(table_name)
    table.put_item(Item={
        'filename': key,
        'status': 'Processed',
        'processedRecords': csv_reader.line_num - 1,  # Subtracting header row
    })
    print(f"Processed {csv_reader.line_num - 1} records from {key}")
    logging.info(f"Processed {csv_reader.line_num - 1} records from {key}")

    return {
        'statusCode': 200,
        'body': f"Processed {csv_reader.line_num - 1} records from {key}"
    }
