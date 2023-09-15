from fastapi import FastAPI
import boto3
import time
import os
import json
import base64
from fastapi import FastAPI, HTTPException, Depends, Request, status
from fastapi.security import APIKeyHeader
from elasticsearch import Elasticsearch
from typing import List
from pydantic import BaseModel
import openai
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from fastapi.middleware.trustedhost import TrustedHostMiddleware
import chromadb
from chromadb.utils import embedding_functions
import os
import uuid
from fastapi import FastAPI, HTTPException
from typing import List
from pydantic import BaseModel
import openai


app = FastAPI()
# os.environ['OPENAI_API_KEY'] = "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"


openai.api_key = ""


# app = FastAPI()
EMBEDDING_MODEL = "text-embedding-ada-002"
# model = SentenceTransformer('distilbert-base-nli-mean-tokens')

# INDEX_NAME = "dev_index"

class QA(BaseModel):
    question: str
    answer: str

class Question(BaseModel):
    question: str


# FastAPI app setup
# app = FastAPI()
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["*"])  # Adjust as needed
# Boto3 CloudWatch client setup
log_client = boto3.client('logs', region_name='us-west-1')  # Adjust region as needed
LOG_GROUP = "custom-search-app-log-group"
LOG_STREAM = "custom-search-app-log-stream"
sequence_token = None



def get_secret():
    secret_name = "example_secret"
    region_name = "us-west-1" # Change to the region you're working with

    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager', region_name=region_name)

    try:
        get_secret_value_response = client.get_secret_value(SecretId=secret_name)
    except Exception as e:
        print(e)
        raise e
    else:
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            return secret
        else:
            # Binary secrets are base64-encoded, so decode them first
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            return decoded_binary_secret


# print(secret)


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
    # global client
    response = log_client.put_log_events(**event_log)
    sequence_token = response['nextSequenceToken']

# Rate limiter setup
# limiter = Limiter(key_func=get_remote_address)
# app.state.limiter = limiter
# app.add_exception_handler(HTTPException, _rate_limit_exceeded_handler)
secret_string = get_secret()
secret_keys = json.loads(secret_string)
# API key setup
API_KEY_NAME = "secret-api-key"
API_KEY = "secret-api-token"  # Store this securely, don't hard-code in production
CHROMA_AUTH = secret_keys["CHROMA_AUTH_TOKEN"]
MAX_RETRIES = 5
RETRY_DELAY = 5  # seconds
headers = {
    "Authorization": f"Bearer {CHROMA_AUTH}"
}
for attempt in range(MAX_RETRIES):
    try:
        client = chromadb.HttpClient(host=secret_keys['PUBLIC_IP_ADDRESS'], port=8000, headers=headers)
        client.list_collections()
        break  # Exit the loop if the connection is successful
    except Exception as e:
        if attempt < MAX_RETRIES - 1:  # i.e. if it's not the last attempt
            print(f"Attempt {attempt + 1} failed. Retrying in {RETRY_DELAY} seconds...")
            time.sleep(RETRY_DELAY)
        else:
            raise e  # Raise the exception on the last attempt
openai_ef = embedding_functions.OpenAIEmbeddingFunction(
                api_key=secret_keys["OPENAI_API_KEY"],
                model_name="text-embedding-ada-002"
            )
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)
collection = client.get_or_create_collection(name="my_collection", embedding_function=openai_ef)
# collection.add(
#     documents=["lorem ipsum...", "doc2", "doc3"],
#     metadatas=[{"chapter": "3", "verse": "16"}, {"chapter": "3", "verse": "5"}, {"chapter": "29", "verse": "11"}],
#     ids=["id1", "id2", "id3"]
# )

async def get_current_api_key(api_key_header: str = Depends(api_key_header)):
    if api_key_header != API_KEY:
        print(api_key_header)
        print(API_KEY)
        # log_to_cloudwatch(f"Invalid API Key attempted: {api_key_header}")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API Key")
    return api_key_header



# @limiter.limit("10000/minute")  # Adjust this as needed
@app.post("/index/", tags=["indexing"])
async def index_data(request: Request, data: QA, api_key: str = Depends(get_current_api_key)) -> dict:
    try:
        log_to_cloudwatch(f"Indexing data: {data}")
        collection.add(
            documents=[data.question + "\n" + data.answer],
            metadatas=[{"question": data.question}],
            ids=[str(uuid.uuid4())]
        )
        return {"message": "Data indexed", "question": data.question, "answer": data.answer, "id": str(uuid.uuid4()), "status": "success"}
    except Exception as e:
        print(e)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal Server Error")
    # log_to_cloudwatch(f"Indexing data: {data}")
    # Your logic for indexing data ...



# @limiter.limit("10000/minute")  # Adjust this as needed
@app.post("/search/", tags=["search"])
async def search(request: Request, data: Question, api_key: str = Depends(get_current_api_key)) -> List[str]:
    try:
        log_to_cloudwatch(f"Searching with query: {data.question}")
        result = collection.query(
            query_texts=[data.question],
            n_results=2
        )
        print(result)
        print(result["documents"][0])
        return result["documents"][0]
    except Exception as e:
        print(e)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Internal Server Error")

    # log_to_cloudwatch(f"Searching with query: {data.question}")
    # Your logic for searching data ...


# @app.exception_handler(Exception)
# async def generic_exception_handler(request: Request, exc: Exception):
#     # log_to_cloudwatch(f"Unhandled error: {exc}")
#     # return {"detail": "Unhandled exception occurred"}


# More FastAPI configurations, error handlers, etc.