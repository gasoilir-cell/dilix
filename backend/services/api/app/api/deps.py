"""
Dilix — Dependencies مشترک FastAPI
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.user import User
from app.services.auth_service import AuthService

security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> User:
    try:
        auth_service = AuthService(db)
        user = await auth_service.get_user_by_token(credentials.credentials)
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="حساب کاربری غیرفعال یا مسدود شده است",
            )
        return user
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )


async def require_kyc(
    level: int = 1,
    current_user: User = Depends(get_current_user),
) -> User:
    if current_user.kyc_level < level:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"برای این عملیات نیاز به تایید هویت سطح {level} دارید",
        )
    return current_user


async def require_role(*roles: str):
    async def _checker(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="دسترسی کافی ندارید",
            )
        return current_user
    return _checker
