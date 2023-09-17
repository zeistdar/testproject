import boto3
import json

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

secret_keys = json.loads(get_secret())
