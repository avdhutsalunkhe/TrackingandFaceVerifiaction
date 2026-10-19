from fastapi import APIRouter
from app.api.auth import router as auth_router
from app.api.admin import router as admin_router
from app.api.shift import router as shift_router
from app.api.user import router as user_router
from app.api.shift_engine import router as shift_engine_router
from app.api.time_office import router as time_office_router
from app.api.roles import router as roles_router
from app.api.tracking import router as tracking_router
from app.api.app_update import router as app_update_router

api_router = APIRouter()
api_router.include_router(auth_router)
api_router.include_router(admin_router)
api_router.include_router(shift_router)
api_router.include_router(user_router)
api_router.include_router(shift_engine_router)
api_router.include_router(time_office_router)
api_router.include_router(roles_router)
api_router.include_router(tracking_router)
api_router.include_router(app_update_router)

__all__ = ["api_router"]
