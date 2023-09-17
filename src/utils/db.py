import boto3
import uuid
from datetime import datetime
from fastapi import HTTPException, status
from .log import log_to_cloudwatch
from .secrets import get_secret, secret_keys
from config.constants import LOG_GROUP, LOG_STREAM, TABLE_NAME
from boto3.dynamodb.conditions import Key
from models.schemas import QA, Question
import chromadb
from chromadb.utils import embedding_functions

dynamodb = boto3.resource('dynamodb', region_name='us-west-1')
table = dynamodb.Table(TABLE_NAME)

CHROMA_AUTH = secret_keys["CHROMA_AUTH_TOKEN"]
headers = {
    "Authorization": f"Bearer {CHROMA_AUTH}"
}

client = chromadb.HttpClient(host=secret_keys['PUBLIC_IP_ADDRESS'], port=8000, headers=headers)

openai_ef = embedding_functions.OpenAIEmbeddingFunction(
                api_key=secret_keys["OPENAI_API_KEY"],
                model_name="text-embedding-ada-002"
            )

collection = client.get_or_create_collection(name="my_collection", embedding_function=openai_ef)

async def index_data_in_db(data: QA) -> dict:
    try:
        # Check if question-answer pair already exists in DynamoDB
        response = table.query(
            IndexName='QuestionAnswerIndex',
            KeyConditionExpression=Key('question').eq(data.question) & Key('answer').eq(data.answer)
        )

        if response['Count'] > 0:
            return {"message": "Data already indexed", "status": "fail"}

        # If not, add to DynamoDB and index in ChromaDB
        table.put_item(
            Item={
                'question': data.question,
                'answer': data.answer,
                'form_type': data.form_type,
                'id': str(uuid.uuid4()),
                'date': str(datetime.utcnow())
            }
        )

        collection.add(
            documents=[data.question + "\n" + data.answer],
            metadatas=[{"question": data.question}],
            ids=[str(uuid.uuid4())]
        )
        return {"message": "Data indexed successfully", "status": "success"}
    except Exception as e:
        log_to_cloudwatch(f"Error while indexing: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))

async def search_data_in_db(data: Question) -> dict:
    try:
        result = collection.query(
            query_texts=[data.question],
            n_results=2
        )
        return {
            "data": result["documents"][0],
            "status": "success"
        }
    except Exception as e:
        log_to_cloudwatch(f"Error while searching: {str(e)}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))
