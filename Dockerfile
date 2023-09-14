FROM tiangolo/uvicorn-gunicorn-fastapi:python3.11

COPY ./src /app

RUN pip install --upgrade pip

RUN pip install fastapi uvicorn boto3 elasticsearch numpy openai slowapi chromadb

RUN pip freeze > requirements.txt

CMD [ "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "80"]
