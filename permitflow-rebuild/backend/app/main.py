from fastapi import FastAPI
from app.api import permits

app = FastAPI()
app.include_router(permits.router)
