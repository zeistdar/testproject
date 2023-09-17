from pydantic import BaseModel


class QA(BaseModel):
    question: str
    answer: str
    form_type: str


class Question(BaseModel):
    question: str
