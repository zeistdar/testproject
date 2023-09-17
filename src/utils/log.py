import boto3
import time
from config.constants import LOG_GROUP, LOG_STREAM

log_client = boto3.client('logs', region_name='us-west-1')

def log_to_cloudwatch(message: str):
    try:
        log_client.put_log_events(
            logGroupName=LOG_GROUP,
            logStreamName=LOG_STREAM,
            logEvents=[
                {
                    'timestamp': int(time.time() * 1000),
                    'message': message
                },
            ]
        )
    except Exception as e:
        print(f"Failed to log to CloudWatch: {str(e)}")
