from pydantic import BaseModel, EmailStr


class NotificationSettings(BaseModel):
    phone: str | None
    phone_verified: bool | None
    email: EmailStr| None


class NotificationSettingsUpdate(BaseModel):
    phone: str | None
