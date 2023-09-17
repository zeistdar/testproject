from fastapi import HTTPException, status, Depends
from fastapi.security import APIKeyHeader
from utils.secrets import secret_keys
from config.constants import API_KEY_NAME

API_KEY = secret_keys["SECRET_API_KEY"]
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

async def get_current_api_key(api_key_header: str = Depends(api_key_header)):
    if api_key_header != API_KEY:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API Key")
    return api_key_header
