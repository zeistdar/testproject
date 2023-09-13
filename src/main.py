from fastapi import FastAPI
import boto3
import time

app = FastAPI()

client = boto3.client('logs', region_name='us-west-1')  # Adjust region as needed
LOG_GROUP = 'my-log-group'
LOG_STREAM = 'my-log-stream'
sequence_token = None

def log_to_cloudwatch(message):
    global sequence_token
    event_log = {
        'logGroupName': LOG_GROUP,
        'logStreamName': LOG_STREAM,
        'logEvents': [
            {
                'timestamp': int(time.time() * 1000),
                'message': message
            },
        ],
    }
    if sequence_token:
        event_log['sequenceToken'] = sequence_token
    response = client.put_log_events(**event_log)
    sequence_token = response['nextSequenceToken']

@app.get("/index")
def index_data(data: str):
    # Your logic to index data
    log_to_cloudwatch(f"Indexed data: {data}")
    return {"message": "Data indexed"}

@app.get("/search")
def search_data(query: str):
    # Your logic to search data
    log_to_cloudwatch(f"Searched with query: {query}")
    return {"message": "Search results"}
