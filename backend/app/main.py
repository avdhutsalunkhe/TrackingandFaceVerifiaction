from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from app.config import settings
from app.database import engine, Base
from app.api import api_router
from app.security.rate_limiter import limiter
from app.ml.models_manager import models_manager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Ensure DB schema tables exist
    try:
        from app.database import run_auto_migrations
        Base.metadata.create_all(bind=engine)
        run_auto_migrations(engine)
        print("[Lifespan] Database tables and dynamic columns verified.")
        
        # Load persisted settings and seed default policies/shifts
        from app.database import SessionLocal
        from app.services.setting_service import SettingService
        from app.services.seed_service import SeedService
        db = SessionLocal()
        try:
            SettingService.load_all_settings(db)
            SeedService.seed_default_policies_and_shifts(db)
            SeedService.seed_default_users(db)
            print(f"[Lifespan] Persisted settings, default users & rules loaded. Global similarity threshold: {settings.SIMILARITY_THRESHOLD}")
        finally:
            db.close()
    except Exception as e:
        print(f"[Lifespan] Database connection warning: {e}")

    # Initialize / warm up ML models
    _ = models_manager.detector
    _ = models_manager.recognizer
    _ = models_manager.liveness
    print("[Lifespan] Biometric Pipeline loaded.")
    yield
    # Shutdown
    print("[Lifespan] Application shutting down.")

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Enterprise server-side AI biometric attendance system with deep-learning face recognition, anti-spoofing, geofencing hard gating, and configurable shift rule engine.",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
    lifespan=lifespan
)

# Attach rate limiter
app.state.limiter = limiter

@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={"detail": "Rate limit exceeded. Please retry shortly."}
    )

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_origin_regex=r".*",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from fastapi.responses import JSONResponse, RedirectResponse, Response
from starlette.exceptions import HTTPException as StarletteHTTPException

@app.exception_handler(StarletteHTTPException)
async def custom_http_exception_handler(request: Request, exc: StarletteHTTPException):
    if exc.status_code == 404:
        return JSONResponse(
            status_code=404,
            content={
                "error": "404 Not Found",
                "requested_path": request.url.path,
                "message": f"Path '{request.url.path}' does not exist on this server.",
                "valid_endpoints": {
                    "api_documentation": "/api/docs",
                    "health_check": "/api/health",
                    "server_time": "/api/user/server-time",
                    "next_event": "/api/attendance/next-event",
                    "user_routes": "/api/user/*",
                    "admin_routes": "/api/admin/*"
                }
            }
        )
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail}
    )

# Mount all API routes
app.include_router(api_router)

@app.get("/favicon.ico", include_in_schema=False)
def favicon():
    return Response(status_code=204)

@app.get("/", tags=["General"])
def root():
    from app.utils.ip_utils import get_server_network_summary
    network = get_server_network_summary(8084)
    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "environment": settings.ENV,
        "docs_url": "/api/docs",
        "health_check": "/api/health",
        "primary_lan_url": network["primary_lan_url"],
        "public_url": network["public_url"],
        "lan_access_urls": network["all_lan_urls"]
    }

@app.get("/docs", include_in_schema=False)
@app.get("/api/docx", include_in_schema=False)
@app.get("/api/doc", include_in_schema=False)
@app.get("/swagger", include_in_schema=False)
@app.get("/api/swagger", include_in_schema=False)
@app.get("/api", include_in_schema=False)
def docs_redirect():
    return RedirectResponse(url="/api/docs")

@app.get("/redoc", include_in_schema=False)
def redoc_redirect():
    return RedirectResponse(url="/api/redoc")

@app.get("/api/health", tags=["Health"])
def health_check():
    from app.utils.ip_utils import get_server_network_summary
    network = get_server_network_summary(8084)
    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "environment": settings.ENV,
        "primary_lan_url": network["primary_lan_url"],
        "public_url": network["public_url"],
        "docs_url": network["docs_url"]
    }
