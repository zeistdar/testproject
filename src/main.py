from fastapi import FastAPI
import boto3
import time
import os
import boto3
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

# Boto3 CloudWatch client setup
client = boto3.client('logs', region_name='us-west-1')  # Adjust region as needed
LOG_GROUP = 'my-log-group'
LOG_STREAM = 'my-log-stream'
sequence_token = None


import boto3
import base64

def get_secret(secret_key):
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
        if secret_key in get_secret_value_response:
            secret = get_secret_value_response[secret_key]
            return secret
        else:
            # Binary secrets are base64-encoded, so decode them first
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            return decoded_binary_secret


print(secret)


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


# FastAPI app setup
# app = FastAPI()
app.add_middleware(TrustedHostMiddleware, allowed_hosts=["*"])  # Adjust as needed

# Rate limiter setup
limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(HTTPException, _rate_limit_exceeded_handler)

# API key setup
API_KEY_NAME = "secret-api-key"
API_KEY = "my-secret-api-token"  # Store this securely, don't hard-code in production
CHROMA_AUTH = "GOIwEZaN3mLMqG5chII5Z2pGjwUzkb89"
headers = {
    "Authorization": f"Bearer {get_secret('CHROMA_AUTH_TOKEN')}"
}

client = chromadb.HttpClient(host=get_secret("PUBLIC_IP_ADDRESS"), port=8000, headers=headers)
openai_ef = embedding_functions.OpenAIEmbeddingFunction(
                api_key=get_secret("OPENAI_API_KEY")"),
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


@app.post("/index/", tags=["indexing"])
@limiter.limit("5/minute")  # Adjust this as needed
async def index_data(request: Request, data: QA, api_key: str = Depends(get_current_api_key)) -> dict:
    try:
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


@app.post("/search/", tags=["search"])
@limiter.limit("5/minute")  # Adjust this as needed
async def search(request: Request, data: Question, api_key: str = Depends(get_current_api_key)) -> List[float]:
    try:
        result = collection.query(
            query_texts=[data.question],
            n_results=2
        )
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